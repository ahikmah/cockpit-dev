import Foundation
import SwiftData

// MARK: - Draft Comment

/// Represents a draft comment retained locally for retry on API failure.
struct DraftComment: Identifiable, Equatable {
    let id: UUID
    let body: String
    let position: DiffPosition?
    let createdAt: Date
    var retryCount: Int

    init(id: UUID = UUID(), body: String, position: DiffPosition? = nil, createdAt: Date = Date(), retryCount: Int = 0) {
        self.id = id
        self.body = body
        self.position = position
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}

// MARK: - MR Detail Tab

/// Tabs available in the MR detail view.
enum MRDetailTab: String, CaseIterable, Identifiable {
    case diff = "Diff"
    case discussion = "Discussion"
    case pipeline = "Pipeline"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .diff: return "doc.text"
        case .discussion: return "bubble.left.and.bubble.right"
        case .pipeline: return "arrow.triangle.branch"
        }
    }
}

// MARK: - MergeRequestViewModel

/// ViewModel managing merge request list and detail state for a workspace.
///
/// Handles:
/// - Fetching all open MRs across workspace repositories
/// - Loading MR details (diff, discussions, pipeline)
/// - Posting inline and general comments
/// - Draft comment retention on API failure with retry
/// - Approve + Merge actions
/// - Merge failure handling
/// - Pipeline failure warning with explicit confirmation
/// - Webhook-driven MR notifications
@Observable
class MergeRequestViewModel {

    // MARK: - List State

    /// All merge request entries for the workspace.
    var mergeRequests: [MergeRequestEntry] = []

    /// Whether the MR list is currently loading.
    var isLoadingList: Bool = false

    /// Error message from the last list fetch operation.
    var listError: String?

    // MARK: - Detail State

    /// The currently selected merge request.
    var selectedMR: MergeRequestEntry?

    /// The currently active detail tab.
    var selectedDetailTab: MRDetailTab = .diff

    /// Diff files for the selected MR.
    var diffFiles: [GitLabDiffFile] = []

    /// Discussions for the selected MR.
    var discussions: [GitLabDiscussion] = []

    /// Pipeline info for the selected MR.
    var pipeline: GitLabPipeline?

    /// Whether detail data is loading.
    var isLoadingDetail: Bool = false

    /// Error message from the last detail fetch operation.
    var detailError: String?

    // MARK: - Comment State

    /// The current general comment text being composed.
    var commentText: String = ""

    /// Draft comments retained after API failure.
    var draftComments: [DraftComment] = []

    /// Whether a comment is being submitted.
    var isSubmittingComment: Bool = false

    /// Error from the last comment submission.
    var commentError: String?

    // MARK: - Merge State

    /// Whether a merge operation is in progress.
    var isMerging: Bool = false

    /// Error from the last merge operation.
    var mergeError: String?

    /// Whether the pipeline failure confirmation dialog should be shown.
    var showPipelineWarning: Bool = false

    /// Whether the merge was successful (for transient success display).
    var mergeSuccess: Bool = false

    // MARK: - Dependencies

    private var apiClient: GitLabAPIClient?
    private var modelContext: ModelContext?
    private var workspace: Workspace?

    // MARK: - Configuration

    /// Configures the view model with required dependencies.
    /// - Parameters:
    ///   - apiClient: The GitLab API client.
    ///   - modelContext: The SwiftData model context.
    ///   - workspace: The current workspace.
    func configure(apiClient: GitLabAPIClient, modelContext: ModelContext, workspace: Workspace) {
        self.apiClient = apiClient
        self.modelContext = modelContext
        self.workspace = workspace
    }

    // MARK: - List Operations

    /// Fetches all open merge requests across all repositories in the workspace.
    func fetchMergeRequests() async {
        guard let workspace = workspace, let apiClient = apiClient, let modelContext = modelContext else { return }

        isLoadingList = true
        listError = nil

        do {
            var allMRs: [MergeRequestEntry] = []

            for repository in workspace.repositories {
                let projectId = repository.gitlabProjectId
                let remoteMRs = try await apiClient.fetchMergeRequests(projectId: projectId, state: "opened")

                for remoteMR in remoteMRs {
                    // Check if we already have this MR locally
                    let existingDescriptor = FetchDescriptor<MergeRequestEntry>(
                        predicate: #Predicate { $0.gitlabMrId == remoteMR.id }
                    )
                    let existing = try modelContext.fetch(existingDescriptor)

                    if let existingMR = existing.first {
                        // Update existing entry
                        existingMR.title = remoteMR.title
                        existingMR.sourceBranch = remoteMR.sourceBranch
                        existingMR.targetBranch = remoteMR.targetBranch
                        existingMR.authorUsername = remoteMR.author.username
                        existingMR.state = mapMRState(remoteMR.state)
                        existingMR.pipelineStatus = mapPipelineStatus(remoteMR.pipeline?.status)
                        existingMR.updatedAt = remoteMR.updatedAt
                        allMRs.append(existingMR)
                    } else {
                        // Create new entry
                        let entry = MergeRequestEntry(
                            gitlabMrId: remoteMR.id,
                            gitlabMrIid: remoteMR.iid,
                            title: remoteMR.title,
                            authorUsername: remoteMR.author.username,
                            sourceBranch: remoteMR.sourceBranch,
                            targetBranch: remoteMR.targetBranch,
                            pipelineStatus: mapPipelineStatus(remoteMR.pipeline?.status),
                            state: mapMRState(remoteMR.state),
                            createdAt: remoteMR.createdAt,
                            updatedAt: remoteMR.updatedAt
                        )
                        entry.repository = repository
                        modelContext.insert(entry)
                        allMRs.append(entry)
                    }
                }
            }

            try modelContext.save()
            mergeRequests = allMRs.sorted { $0.updatedAt > $1.updatedAt }

        } catch {
            listError = error.localizedDescription
        }

        isLoadingList = false
    }

    // MARK: - Detail Operations

    /// Loads the detail data (diff, discussions, pipeline) for the selected MR.
    /// - Parameter mr: The merge request to load details for.
    func loadMRDetail(_ mr: MergeRequestEntry) async {
        guard let apiClient = apiClient, let repository = mr.repository else { return }

        selectedMR = mr
        isLoadingDetail = true
        detailError = nil

        let projectId = repository.gitlabProjectId
        let mrIid = mr.gitlabMrIid

        do {
            // Fetch diff, discussions in parallel
            async let fetchedDiff = apiClient.fetchMRDiff(projectId: projectId, mrIid: mrIid)
            async let fetchedDiscussions = apiClient.fetchMRDiscussions(projectId: projectId, mrIid: mrIid)

            diffFiles = try await fetchedDiff
            discussions = try await fetchedDiscussions

            // Pipeline info is already on the MR entry; we use what we have
            // For more detail, we could fetch pipeline stages here
            pipeline = nil // Pipeline detail from the MR's pipeline field

        } catch {
            detailError = error.localizedDescription
        }

        isLoadingDetail = false
    }

    // MARK: - Comment Operations

    /// Submits a general comment on the selected MR.
    func submitGeneralComment() async {
        guard let apiClient = apiClient,
              let mr = selectedMR,
              let repository = mr.repository,
              !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let projectId = repository.gitlabProjectId
        let mrIid = mr.gitlabMrIid
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)

        isSubmittingComment = true
        commentError = nil

        do {
            try await apiClient.createMRNote(projectId: projectId, mrIid: mrIid, body: body)
            commentText = ""
            // Refresh discussions to show the new comment
            discussions = try await apiClient.fetchMRDiscussions(projectId: projectId, mrIid: mrIid)
        } catch {
            // Retain as draft comment for retry
            let draft = DraftComment(body: body, position: nil)
            draftComments.append(draft)
            commentError = "Failed to post comment: \(error.localizedDescription). Comment saved as draft."
        }

        isSubmittingComment = false
    }

    /// Submits an inline comment on a specific diff line.
    /// - Parameters:
    ///   - body: The comment text.
    ///   - position: The diff position for the inline comment.
    func submitInlineComment(body: String, position: DiffPosition) async {
        guard let apiClient = apiClient,
              let mr = selectedMR,
              let repository = mr.repository else { return }

        let projectId = repository.gitlabProjectId
        let mrIid = mr.gitlabMrIid

        isSubmittingComment = true
        commentError = nil

        do {
            try await apiClient.createMRNote(projectId: projectId, mrIid: mrIid, body: body, position: position)
            // Refresh discussions
            discussions = try await apiClient.fetchMRDiscussions(projectId: projectId, mrIid: mrIid)
        } catch {
            // Retain as draft comment for retry
            let draft = DraftComment(body: body, position: position)
            draftComments.append(draft)
            commentError = "Failed to post inline comment: \(error.localizedDescription). Comment saved as draft."
        }

        isSubmittingComment = false
    }

    /// Retries submitting a draft comment.
    /// - Parameter draft: The draft comment to retry.
    func retryDraftComment(_ draft: DraftComment) async {
        guard let apiClient = apiClient,
              let mr = selectedMR,
              let repository = mr.repository else { return }

        let projectId = repository.gitlabProjectId
        let mrIid = mr.gitlabMrIid

        do {
            try await apiClient.createMRNote(projectId: projectId, mrIid: mrIid, body: draft.body, position: draft.position)
            // Remove from drafts on success
            draftComments.removeAll { $0.id == draft.id }
            // Refresh discussions
            discussions = try await apiClient.fetchMRDiscussions(projectId: projectId, mrIid: mrIid)
        } catch {
            // Increment retry count
            if let index = draftComments.firstIndex(where: { $0.id == draft.id }) {
                draftComments[index].retryCount += 1
            }
            commentError = "Retry failed: \(error.localizedDescription)"
        }
    }

    /// Discards a draft comment.
    /// - Parameter draft: The draft comment to discard.
    func discardDraftComment(_ draft: DraftComment) {
        draftComments.removeAll { $0.id == draft.id }
    }

    // MARK: - Merge Operations

    /// Approves and merges the selected MR.
    /// If the pipeline has failures, shows a warning requiring explicit confirmation.
    func approveAndMerge() async {
        guard let apiClient = apiClient,
              let mr = selectedMR,
              let repository = mr.repository else { return }

        // Check for pipeline failures
        if mr.pipelineStatus == .failed {
            showPipelineWarning = true
            return
        }

        await performMerge(apiClient: apiClient, projectId: repository.gitlabProjectId, mrIid: mr.gitlabMrIid)
    }

    /// Performs the merge after pipeline warning confirmation.
    func confirmMergeWithPipelineFailure() async {
        guard let apiClient = apiClient,
              let mr = selectedMR,
              let repository = mr.repository else { return }

        showPipelineWarning = false
        await performMerge(apiClient: apiClient, projectId: repository.gitlabProjectId, mrIid: mr.gitlabMrIid)
    }

    /// Cancels the merge after pipeline warning.
    func cancelMerge() {
        showPipelineWarning = false
    }

    /// Performs the actual approve + merge operation.
    private func performMerge(apiClient: GitLabAPIClient, projectId: Int, mrIid: Int) async {
        isMerging = true
        mergeError = nil
        mergeSuccess = false

        do {
            // Approve first
            try await apiClient.approveMR(projectId: projectId, mrIid: mrIid)

            // Then merge
            let mergedMR = try await apiClient.mergeMR(projectId: projectId, mrIid: mrIid)

            // Update local state
            if let mr = selectedMR {
                mr.state = .merged
                mr.updatedAt = mergedMR.updatedAt
                try? modelContext?.save()
            }

            mergeSuccess = true

            // Remove from open MR list
            mergeRequests.removeAll { $0.id == selectedMR?.id }

        } catch {
            // Leave MR in current state, show error
            mergeError = "Merge failed: \(error.localizedDescription)"
        }

        isMerging = false
    }

    // MARK: - Webhook Handling

    /// Handles a merge request webhook event, updating local state.
    /// - Parameter payload: The MR webhook payload.
    func handleMRWebhook(_ payload: MRWebhookPayload) async {
        guard let modelContext = modelContext else { return }

        let mrId = payload.objectAttributes.id
        let action = payload.objectAttributes.action

        switch action {
        case "open":
            // New MR created - add to list
            let entry = MergeRequestEntry(
                gitlabMrId: mrId,
                gitlabMrIid: payload.objectAttributes.iid,
                title: payload.objectAttributes.title,
                authorUsername: "user_\(payload.objectAttributes.authorId)",
                sourceBranch: payload.objectAttributes.sourceBranch,
                targetBranch: payload.objectAttributes.targetBranch,
                state: .opened
            )

            // Find the repository for this project
            let projectId = payload.project.id
            let repoDescriptor = FetchDescriptor<Repository>(
                predicate: #Predicate { $0.gitlabProjectId == projectId }
            )
            if let repository = try? modelContext.fetch(repoDescriptor).first {
                entry.repository = repository
            }

            modelContext.insert(entry)
            try? modelContext.save()
            mergeRequests.insert(entry, at: 0)

        case "merge":
            // MR merged - update state and remove from open list
            let descriptor = FetchDescriptor<MergeRequestEntry>(
                predicate: #Predicate { $0.gitlabMrId == mrId }
            )
            if let existingMR = try? modelContext.fetch(descriptor).first {
                existingMR.state = .merged
                existingMR.updatedAt = Date()
                try? modelContext.save()
                mergeRequests.removeAll { $0.gitlabMrId == mrId }
            }

        case "close":
            // MR closed - update state and remove from open list
            let descriptor = FetchDescriptor<MergeRequestEntry>(
                predicate: #Predicate { $0.gitlabMrId == mrId }
            )
            if let existingMR = try? modelContext.fetch(descriptor).first {
                existingMR.state = .closed
                existingMR.updatedAt = Date()
                try? modelContext.save()
                mergeRequests.removeAll { $0.gitlabMrId == mrId }
            }

        case "update":
            // MR updated - refresh details
            let descriptor = FetchDescriptor<MergeRequestEntry>(
                predicate: #Predicate { $0.gitlabMrId == mrId }
            )
            if let existingMR = try? modelContext.fetch(descriptor).first {
                existingMR.title = payload.objectAttributes.title
                existingMR.sourceBranch = payload.objectAttributes.sourceBranch
                existingMR.targetBranch = payload.objectAttributes.targetBranch
                existingMR.updatedAt = Date()
                try? modelContext.save()
            }

        default:
            break
        }
    }

    /// Handles a pipeline webhook event, updating the MR's pipeline status.
    /// - Parameter payload: The pipeline webhook payload.
    func handlePipelineWebhook(_ payload: PipelineWebhookPayload) async {
        guard let modelContext = modelContext,
              let mrInfo = payload.mergeRequest else { return }

        let mrId = mrInfo.id
        let descriptor = FetchDescriptor<MergeRequestEntry>(
            predicate: #Predicate { $0.gitlabMrId == mrId }
        )

        if let existingMR = try? modelContext.fetch(descriptor).first {
            existingMR.pipelineStatus = mapPipelineStatus(payload.objectAttributes.status)
            existingMR.updatedAt = Date()
            try? modelContext.save()

            // Update in-memory list
            if let index = mergeRequests.firstIndex(where: { $0.gitlabMrId == mrId }) {
                mergeRequests[index].pipelineStatus = existingMR.pipelineStatus
            }
        }
    }

    // MARK: - Helpers

    /// Maps a GitLab MR state string to the local MRState enum.
    private func mapMRState(_ state: String) -> MRState {
        switch state {
        case "opened": return .opened
        case "merged": return .merged
        case "closed": return .closed
        default: return .opened
        }
    }

    /// Maps a GitLab pipeline status string to the local PipelineStatus enum.
    private func mapPipelineStatus(_ status: String?) -> PipelineStatus? {
        guard let status = status else { return nil }
        switch status {
        case "running": return .running
        case "success": return .success
        case "failed": return .failed
        case "canceled": return .canceled
        case "pending": return .pending
        default: return nil
        }
    }

    /// Calculates the time since creation as a human-readable string.
    static func timeSinceCreation(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "just now"
        }
    }
}
