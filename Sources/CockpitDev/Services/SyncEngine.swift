import Foundation
import SwiftData

// MARK: - Sync Result

/// Represents the outcome of reconciling a local ticket with a remote GitLab issue.
enum SyncResult: Equatable {
    case noConflict(merged: TicketSnapshot)
    case conflict(local: TicketSnapshot, remote: TicketSnapshot)
    case remoteOnly(TicketSnapshot)
    case localOnly(TicketSnapshot)

    static func == (lhs: SyncResult, rhs: SyncResult) -> Bool {
        switch (lhs, rhs) {
        case (.noConflict(let a), .noConflict(let b)):
            return a == b
        case (.conflict(let la, let ra), .conflict(let lb, let rb)):
            return la == lb && ra == rb
        case (.remoteOnly(let a), .remoteOnly(let b)):
            return a == b
        case (.localOnly(let a), .localOnly(let b)):
            return a == b
        default:
            return false
        }
    }
}

private extension Ticket {
    func matchesGitLabIssue(id remoteId: Int, iid remoteIid: Int) -> Bool {
        if let gitlabIssueIid {
            return gitlabIssueIid == remoteIid
        }

        guard let gitlabIssueId else {
            return false
        }

        return gitlabIssueId == remoteId || gitlabIssueId == remoteIid
    }
}

// MARK: - Ticket Snapshot

/// An immutable snapshot of a ticket's state for conflict resolution.
struct TicketSnapshot: Equatable, Sendable {
    let id: UUID
    let gitlabIssueId: Int?
    let gitlabIssueIid: Int?
    let title: String
    let descriptionText: String?
    let status: TicketStatus
    let storyPoints: Int?
    let labels: [String]
    let updatedAt: Date
    let localVersion: Int

    init(from ticket: Ticket) {
        self.id = ticket.id
        self.gitlabIssueId = ticket.gitlabIssueId
        self.gitlabIssueIid = ticket.gitlabIssueIid
        self.title = ticket.title
        self.descriptionText = ticket.descriptionText
        self.status = ticket.status
        self.storyPoints = ticket.storyPoints
        self.labels = ticket.labels
        self.updatedAt = ticket.updatedAt
        self.localVersion = ticket.localVersion
    }

    init(
        id: UUID = UUID(),
        gitlabIssueId: Int? = nil,
        gitlabIssueIid: Int? = nil,
        title: String,
        descriptionText: String? = nil,
        status: TicketStatus = .backlog,
        storyPoints: Int? = nil,
        labels: [String] = [],
        updatedAt: Date = Date(),
        localVersion: Int = 0
    ) {
        self.id = id
        self.gitlabIssueId = gitlabIssueId
        self.gitlabIssueIid = gitlabIssueIid
        self.title = title
        self.descriptionText = descriptionText
        self.status = status
        self.storyPoints = storyPoints
        self.labels = labels
        self.updatedAt = updatedAt
        self.localVersion = localVersion
    }
}

// MARK: - Sync Errors

/// Errors that can occur during sync operations.
enum SyncError: Error, LocalizedError {
    case noGitLabIssueId
    case noProjectId
    case ticketNotFound
    case offlineQueued
    case pushFailed(Error)
    case pullFailed(Error)
    case reconcileFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noGitLabIssueId:
            return "Ticket has no associated GitLab issue ID."
        case .noProjectId:
            return "No GitLab project ID available for this workspace."
        case .ticketNotFound:
            return "Ticket not found in local store."
        case .offlineQueued:
            return "Operation queued for retry when connectivity returns."
        case .pushFailed(let error):
            return "Push to GitLab failed: \(error.localizedDescription)"
        case .pullFailed(let error):
            return "Pull from GitLab failed: \(error.localizedDescription)"
        case .reconcileFailed(let error):
            return "Reconciliation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Queued Operation

/// Represents a sync operation queued for offline retry.
struct QueuedSyncOperation: Identifiable, Equatable {
    let id: UUID
    let ticketId: UUID
    let operationType: OperationType
    let queuedAt: Date

    enum OperationType: String, Equatable {
        case push
        case pull
    }

    init(id: UUID = UUID(), ticketId: UUID, operationType: OperationType, queuedAt: Date = Date()) {
        self.id = id
        self.ticketId = ticketId
        self.operationType = operationType
        self.queuedAt = queuedAt
    }
}

// MARK: - Field Mapping

/// Handles mapping between local ticket fields and GitLab issue fields.
enum FieldMapping {

    // MARK: - Status to GitLab State + Labels

    /// Maps a local TicketStatus to GitLab issue state and workflow labels.
    /// - Parameter status: The local ticket status.
    /// - Returns: A tuple of (state: "opened"/"closed", workflowLabel: optional label string).
    static func statusToGitLab(_ status: TicketStatus) -> (state: String, workflowLabel: String?) {
        switch status {
        case .backlog:
            return ("opened", "workflow::backlog")
        case .todo:
            return ("opened", "workflow::todo")
        case .inProgress:
            return ("opened", "workflow::in-progress")
        case .inReview:
            return ("opened", "workflow::in-review")
        case .done:
            return ("closed", "workflow::done")
        }
    }

    /// Maps GitLab issue state and labels to a local TicketStatus.
    /// - Parameters:
    ///   - state: The GitLab issue state ("opened" or "closed").
    ///   - labels: The GitLab issue labels.
    /// - Returns: The corresponding local TicketStatus.
    static func gitLabToStatus(state: String, labels: [String]) -> TicketStatus {
        if state == "closed" {
            return .done
        }

        // Check workflow labels (priority order)
        let workflowLabels = labels.filter { $0.hasPrefix("workflow::") }
        for label in workflowLabels {
            switch label {
            case "workflow::in-review":
                return .inReview
            case "workflow::in-progress":
                return .inProgress
            case "workflow::todo":
                return .todo
            case "workflow::backlog":
                return .backlog
            case "workflow::done":
                return .done
            default:
                continue
            }
        }

        // Default to backlog if no workflow label found
        return .backlog
    }

    /// Filters out workflow labels from a label array, returning only non-workflow labels.
    /// - Parameter labels: The full label array.
    /// - Returns: Labels without workflow:: prefix.
    static func nonWorkflowLabels(_ labels: [String]) -> [String] {
        labels.filter { !$0.hasPrefix("workflow::") }
    }

    /// Builds the complete label set for a GitLab issue from local ticket data.
    /// - Parameters:
    ///   - ticketLabels: The ticket's non-workflow labels.
    ///   - status: The ticket's current status.
    /// - Returns: Combined labels including the workflow label.
    static func buildGitLabLabels(ticketLabels: [String], status: TicketStatus) -> [String] {
        let (_, workflowLabel) = statusToGitLab(status)
        var labels = nonWorkflowLabels(ticketLabels)
        if let workflowLabel = workflowLabel {
            labels.append(workflowLabel)
        }
        return labels
    }
}

// MARK: - SyncEngine

/// Manages bidirectional synchronization between local SwiftData tickets and GitLab issues.
///
/// The SyncEngine handles:
/// - Pushing local changes to GitLab within 10 seconds
/// - Pulling remote changes from GitLab
/// - Processing webhook events
/// - Periodic polling for missed events (configurable, default 5 minutes)
/// - Conflict detection using localVersion counter and lastSyncedAt timestamp
/// - Offline queue with retry on connectivity return
@Observable
@MainActor
class SyncEngine {

    // MARK: - Properties

    /// Whether the engine is currently online and able to reach GitLab.
    var isOnline: Bool = true

    /// Whether periodic polling is active.
    var isPolling: Bool = false

    /// The current polling interval in seconds.
    var pollingInterval: TimeInterval

    /// Queued operations waiting for connectivity.
    var offlineQueue: [QueuedSyncOperation] = []

    /// The GitLab API client for making requests.
    private let apiClient: GitLabAPIClient

    /// The OpenSpec PM metadata source for DB-owned planning fields.
    private let planningMetadataProvider: OpenSpecPMMetadataProviding?

    /// The SwiftData model context for persistence.
    private let modelContext: ModelContext

    /// Timer for periodic polling.
    private var pollingTask: Task<Void, Never>?

    /// Task for processing the offline queue.
    private var offlineRetryTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a SyncEngine with the specified API client and model context.
    /// - Parameters:
    ///   - apiClient: The GitLab API client for remote operations.
    ///   - modelContext: The SwiftData model context for local persistence.
    ///   - pollingInterval: The interval between polling cycles (default: 5 minutes).
    init(
        apiClient: GitLabAPIClient,
        planningMetadataProvider: OpenSpecPMMetadataProviding? = nil,
        modelContext: ModelContext,
        pollingInterval: TimeInterval = AppConstants.defaultPollInterval
    ) {
        self.apiClient = apiClient
        self.planningMetadataProvider = planningMetadataProvider
        self.modelContext = modelContext
        self.pollingInterval = pollingInterval
    }

    // MARK: - Push Operations

    /// Pushes a local ticket to GitLab, creating or updating the corresponding issue.
    ///
    /// If the ticket has no GitLab issue ID, a new issue is created.
    /// If it already has an ID, the existing issue is updated.
    /// Operations are queued if the engine is offline.
    ///
    /// - Parameter ticket: The ticket to push to GitLab.
    /// - Throws: `SyncError` if the operation fails.
    func pushTicketToGitLab(_ ticket: Ticket) async throws {
        guard isOnline else {
            enqueueOperation(ticketId: ticket.id, type: .push)
            throw SyncError.offlineQueued
        }

        guard let workspace = ticket.workspace,
              let repository = workspace.repositories.first else {
            throw SyncError.noProjectId
        }

        let projectId = repository.gitlabProjectId

        do {
            if let issueIid = ticket.gitlabIssueIid {
                // Update existing issue
                let labels = FieldMapping.buildGitLabLabels(ticketLabels: ticket.labels, status: ticket.status)
                let (stateEvent, _) = statusToStateEvent(ticket.status, currentGitLabState: nil)

                var fields = IssueUpdateFields()
                fields.title = ticket.title
                fields.description = ticket.descriptionText
                fields.labels = labels
                fields.assigneeIds = ticket.assignee.map { [$0.gitlabUserId] }
                fields.milestoneId = ticket.sprint?.gitlabMilestoneId
                if let stateEvent = stateEvent {
                    fields.stateEvent = stateEvent
                }

                let _ = try await apiClient.updateIssue(projectId: projectId, issueIid: issueIid, fields: fields)
            } else {
                // Create new issue
                let labels = FieldMapping.buildGitLabLabels(ticketLabels: ticket.labels, status: ticket.status)

                let gitlabIssue = try await apiClient.createIssue(
                    projectId: projectId,
                    title: ticket.title,
                    description: ticket.descriptionText,
                    labels: labels,
                    assigneeId: ticket.assignee?.gitlabUserId,
                    milestoneId: ticket.sprint?.gitlabMilestoneId
                )

                // Associate the GitLab issue ID with the local ticket
                ticket.gitlabIssueId = gitlabIssue.id
                ticket.gitlabIssueIid = gitlabIssue.iid
            }

            // Update sync metadata
            ticket.lastSyncedAt = Date()
            ticket.localVersion += 1
            try modelContext.save()

        } catch {
            throw SyncError.pushFailed(error)
        }
    }

    // MARK: - Pull Operations

    /// Pulls the latest state of a ticket from GitLab and updates the local copy.
    ///
    /// - Parameter ticket: The ticket to pull updates for.
    /// - Throws: `SyncError` if the operation fails.
    func pullFromGitLab(_ ticket: Ticket) async throws {
        guard isOnline else {
            enqueueOperation(ticketId: ticket.id, type: .pull)
            throw SyncError.offlineQueued
        }

        guard let issueIid = ticket.gitlabIssueIid else {
            throw SyncError.noGitLabIssueId
        }

        guard let workspace = ticket.workspace,
              let repository = workspace.repositories.first else {
            throw SyncError.noProjectId
        }

        let projectId = repository.gitlabProjectId

        do {
            let issues = try await apiClient.fetchIssues(projectId: projectId, updatedAfter: ticket.lastSyncedAt)
            guard let remoteIssue = issues.first(where: { $0.iid == issueIid }) else {
                // Issue not in updated list, nothing to pull
                return
            }

            // Apply remote changes to local ticket
            applyRemoteChanges(to: ticket, from: remoteIssue)
            ticket.lastSyncedAt = Date()
            try modelContext.save()

        } catch {
            throw SyncError.pullFailed(error)
        }
    }

    // MARK: - Webhook Event Handling

    /// Routes a webhook event to the appropriate handler.
    ///
    /// - Parameter event: The webhook event to process.
    /// - Throws: If event processing fails.
    func handleWebhookEvent(_ event: WebhookEvent) async throws {
        switch event {
        case .issueHook(let payload):
            try await handleIssueHook(payload)
        case .mergeRequestHook(let payload):
            try await handleMergeRequestHook(payload)
        case .pushHook(let payload):
            try await handlePushHook(payload)
        case .pipelineHook(let payload):
            try await handlePipelineHook(payload)
        }
    }

    // MARK: - Reconciliation

    /// Compares a local ticket with a remote GitLab issue and determines the sync result.
    ///
    /// Conflict detection uses:
    /// - `localVersion` counter: incremented on each local save
    /// - `lastSyncedAt` timestamp: compared against remote `updatedAt`
    ///
    /// A conflict is detected when both sides have been modified since the last sync.
    ///
    /// - Parameters:
    ///   - local: The local ticket to compare.
    ///   - remote: The remote GitLab issue to compare against.
    /// - Returns: A `SyncResult` indicating the reconciliation outcome.
    func reconcile(local: Ticket, remote: GitLabIssue) -> SyncResult {
        let localSnapshot = TicketSnapshot(from: local)

        let remoteStatus = FieldMapping.gitLabToStatus(state: remote.state, labels: remote.labels)
        let remoteSnapshot = TicketSnapshot(
            id: local.id,
            gitlabIssueId: remote.id,
            gitlabIssueIid: remote.iid,
            title: remote.title,
            descriptionText: remote.description,
            status: remoteStatus,
            storyPoints: local.storyPoints,
            labels: FieldMapping.nonWorkflowLabels(remote.labels),
            updatedAt: remote.updatedAt,
            localVersion: local.localVersion
        )

        // Determine if there's a conflict
        let hasLocalChanges = hasLocalModifications(local)
        let hasRemoteChanges = hasRemoteModifications(local: local, remote: remote)

        if hasLocalChanges && hasRemoteChanges {
            // Both sides modified since last sync - conflict
            return .conflict(local: localSnapshot, remote: remoteSnapshot)
        } else if hasRemoteChanges {
            // Only remote changed - apply remote
            return .noConflict(merged: remoteSnapshot)
        } else {
            // No changes or only local changes - keep local
            return .noConflict(merged: localSnapshot)
        }
    }

    // MARK: - Polling

    /// Starts periodic polling at the configured interval.
    ///
    /// - Parameter interval: The polling interval in seconds. Defaults to the engine's configured interval.
    func startPolling(interval: TimeInterval? = nil) {
        let pollInterval = interval ?? pollingInterval
        if let interval = interval {
            pollingInterval = interval
        }

        stopPolling()
        isPolling = true

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                guard let self = self else { break }
                await self.pollAllWorkspaces()
            }
        }
    }

    /// Stops periodic polling.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    // MARK: - Full Reconcile

    /// Performs a workspace-wide reconciliation comparing all local tickets with their remote counterparts.
    ///
    /// - Parameter workspace: The workspace to reconcile.
    /// - Throws: `SyncError` if reconciliation fails.
    /// - Returns: An array of sync results for tickets that need attention.
    @discardableResult
    func fullReconcile(workspace: Workspace) async throws -> [SyncResult] {
        guard isOnline else {
            throw SyncError.offlineQueued
        }

        guard !workspace.repositories.isEmpty else {
            throw SyncError.noProjectId
        }

        var results: [SyncResult] = []

        do {
            for repository in workspace.repositories {
                let projectId = repository.gitlabProjectId
                let milestoneLookup = try await upsertMilestones(projectId: projectId, workspace: workspace)
                var ticketsByIssueIid: [Int: [Ticket]] = [:]

                // Fetch all issues from GitLab
                let remoteIssues = try await apiClient.fetchIssues(projectId: projectId)

                var matchedRemoteIids = Set<Int>()

                // Reconcile tickets that exist on both sides. Match primarily by IID because
                // older local data may have stored GitLab IID in `gitlabIssueId`.
                for remoteIssue in remoteIssues {
                    let localTickets = workspace.tickets.filter { ticket in
                        ticket.matchesGitLabIssue(id: remoteIssue.id, iid: remoteIssue.iid)
                    }

                    guard !localTickets.isEmpty else { continue }
                    matchedRemoteIids.insert(remoteIssue.iid)

                    for localTicket in localTickets {
                        let result = reconcile(local: localTicket, remote: remoteIssue)
                        results.append(result)

                        // GitLab owns issue identity and collaboration state. Planning metadata
                        // such as dates, estimates, and priority is owned by OpenSpec PM data.
                        applyRemoteIssueMetadata(to: localTicket, from: remoteIssue, workspace: workspace, milestoneLookup: milestoneLookup)
                        ticketsByIssueIid[remoteIssue.iid, default: []].append(localTicket)

                        // Auto-apply non-conflict content fields.
                        if case .noConflict(let merged) = result {
                            applySnapshot(merged, to: localTicket)
                            localTicket.lastSyncedAt = Date()
                        }
                    }
                }

                // Find remote-only issues, persist them locally, and still report them.
                for remoteIssue in remoteIssues where !matchedRemoteIids.contains(remoteIssue.iid) {
                    let ticket = createTicket(from: remoteIssue, workspace: workspace, milestoneLookup: milestoneLookup)
                    ticketsByIssueIid[remoteIssue.iid, default: []].append(ticket)
                    let snapshot = TicketSnapshot(from: ticket)
                    results.append(.remoteOnly(snapshot))
                }

                try await refreshRealizationDates(
                    projectId: projectId,
                    remoteIssues: remoteIssues,
                    ticketsByIssueIid: ticketsByIssueIid
                )
            }

            try modelContext.save()

        } catch {
            throw SyncError.reconcileFailed(error)
        }

        return results
    }

    /// Refreshes timeline planning metadata directly from the OpenSpec PM database API.
    func refreshPlanningMetadata(workspace: Workspace) async throws {
        guard !workspace.repositories.isEmpty else {
            throw SyncError.noProjectId
        }

        for repository in workspace.repositories {
            try await applyPlanningMetadata(for: repository, workspace: workspace)
        }
        try modelContext.save()
    }

    // MARK: - Offline Queue

    /// Enqueues an operation for retry when connectivity returns.
    func enqueueOperation(ticketId: UUID, type: QueuedSyncOperation.OperationType) {
        // Avoid duplicate entries for the same ticket and operation type
        guard !offlineQueue.contains(where: { $0.ticketId == ticketId && $0.operationType == type }) else {
            return
        }
        let operation = QueuedSyncOperation(ticketId: ticketId, operationType: type)
        offlineQueue.append(operation)
    }

    /// Processes the offline queue, retrying all queued operations.
    /// Called when connectivity is restored.
    func processOfflineQueue() async {
        guard isOnline else { return }

        var remainingQueue: [QueuedSyncOperation] = []

        for operation in offlineQueue {
            do {
                let ticket = try fetchTicket(by: operation.ticketId)
                switch operation.operationType {
                case .push:
                    try await pushTicketToGitLab(ticket)
                case .pull:
                    try await pullFromGitLab(ticket)
                }
            } catch {
                // If still failing, keep in queue
                remainingQueue.append(operation)
            }
        }

        offlineQueue = remainingQueue
    }

    /// Sets the online status and triggers queue processing if coming back online.
    func setOnlineStatus(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online

        if online && wasOffline && !offlineQueue.isEmpty {
            offlineRetryTask?.cancel()
            offlineRetryTask = Task { [weak self] in
                await self?.processOfflineQueue()
            }
        }
    }

    // MARK: - Private Helpers

    /// Determines the state event needed to transition a GitLab issue.
    private func statusToStateEvent(_ status: TicketStatus, currentGitLabState: String?) -> (stateEvent: String?, workflowLabel: String?) {
        let (targetState, workflowLabel) = FieldMapping.statusToGitLab(status)

        if let currentState = currentGitLabState {
            if currentState == "opened" && targetState == "closed" {
                return ("close", workflowLabel)
            } else if currentState == "closed" && targetState == "opened" {
                return ("reopen", workflowLabel)
            }
        } else {
            // No current state known, set based on target
            if targetState == "closed" {
                return ("close", workflowLabel)
            }
        }

        return (nil, workflowLabel)
    }

    /// Checks if a local ticket has been modified since the last sync.
    private func hasLocalModifications(_ ticket: Ticket) -> Bool {
        guard let lastSyncedAt = ticket.lastSyncedAt else {
            // Never synced - consider as modified if it has a GitLab ID
            return ticket.gitlabIssueId != nil
        }
        return ticket.updatedAt > lastSyncedAt
    }

    /// Checks if a remote issue has been modified since the last sync of the local ticket.
    private func hasRemoteModifications(local: Ticket, remote: GitLabIssue) -> Bool {
        guard let lastSyncedAt = local.lastSyncedAt else {
            // Never synced - remote is always "new"
            return true
        }
        return remote.updatedAt > lastSyncedAt
    }

    /// Applies remote GitLab issue changes to a local ticket.
    private func applyRemoteChanges(to ticket: Ticket, from issue: GitLabIssue) {
        ticket.title = issue.title
        ticket.descriptionText = issue.description
        ticket.status = FieldMapping.gitLabToStatus(state: issue.state, labels: issue.labels)
        ticket.labels = FieldMapping.nonWorkflowLabels(issue.labels)
        ticket.updatedAt = issue.updatedAt
        ticket.localVersion += 1
    }

    /// Resolves actual ticket completion from the latest commit in merge requests that mention the issue.
    private func refreshRealizationDates(
        projectId: Int,
        remoteIssues: [GitLabIssue],
        ticketsByIssueIid: [Int: [Ticket]]
    ) async throws {
        guard !ticketsByIssueIid.isEmpty else { return }

        let projectMergeRequests = (try? await apiClient.fetchMergeRequests(projectId: projectId, state: "all")) ?? []

        let issueByIid = Dictionary(uniqueKeysWithValues: remoteIssues.map { ($0.iid, $0) })

        for (issueIid, tickets) in ticketsByIssueIid {
            let issueNotes = (try? await apiClient.fetchIssueNotes(projectId: projectId, issueIid: issueIid)) ?? []
            let relatedMergeRequests = (try? await apiClient.fetchIssueRelatedMergeRequests(projectId: projectId, issueIid: issueIid)) ?? []
            let mergeRequests = mergeRequestsForIssue(
                issueIid: issueIid,
                tickets: tickets,
                relatedMergeRequests: relatedMergeRequests,
                projectMergeRequests: projectMergeRequests
            )
            let latestMention = latestMergeRequestMention(in: issueNotes)

            var latestCommit: GitLabCommit?
            var latestCommitMRIid: Int?
            var latestDate: Date?

            for mr in mergeRequests {
                let mrMentionsIssue = tickets.contains { ticket in
                    mergeRequest(mr, mentions: ticket, issueIid: issueIid)
                }
                let mrMentionedInIssueTimeline = latestMention?.mrIid == mr.iid

                let commits: [GitLabCommit]
                do {
                    commits = try await apiClient.fetchMRCommits(projectId: projectId, mrIid: mr.iid)
                } catch {
                    continue
                }

                let matchingCommits = commits.filter { commit in
                    tickets.contains { ticket in
                        commitMentions(ticket, issueIid: issueIid, commit: commit)
                    }
                }

                let candidateCommits = matchingCommits.isEmpty && (mrMentionsIssue || mrMentionedInIssueTimeline) ? commits : matchingCommits
                guard !candidateCommits.isEmpty else { continue }

                for commit in candidateCommits {
                    guard let commitDate = realizationDate(for: commit) else { continue }
                    if latestDate.map({ commitDate > $0 }) ?? true {
                        latestDate = commitDate
                        latestCommit = commit
                        latestCommitMRIid = mr.iid
                    }
                }
            }

            if let latestMention,
               !mergeRequests.contains(where: { $0.iid == latestMention.mrIid }),
               let commits = try? await apiClient.fetchMRCommits(projectId: projectId, mrIid: latestMention.mrIid) {
                for commit in commits {
                    guard let commitDate = realizationDate(for: commit) else { continue }
                    if latestDate.map({ commitDate > $0 }) ?? true {
                        latestDate = commitDate
                        latestCommit = commit
                        latestCommitMRIid = latestMention.mrIid
                    }
                }
            }

            for ticket in tickets {
                if let latestDate, let latestCommit, let latestCommitMRIid {
                    ticket.realizedAt = latestDate
                    ticket.realizationSource = .mrCommit
                    ticket.realizationReference = "!\(latestCommitMRIid) \(latestCommit.shortId)"
                } else if let latestMention {
                    ticket.realizedAt = latestMention.createdAt
                    ticket.realizationSource = .mrMention
                    ticket.realizationReference = "!\(latestMention.mrIid)"
                } else if ticket.status == .done, let closedAt = issueByIid[issueIid]?.closedAt {
                    ticket.realizedAt = closedAt
                    ticket.realizationSource = .issueClosed
                    ticket.realizationReference = "#\(issueIid)"
                }
            }
        }
    }

    private struct MergeRequestMention {
        let mrIid: Int
        let createdAt: Date
    }

    private func latestMergeRequestMention(in notes: [GitLabNote]) -> MergeRequestMention? {
        let pattern = #"\bmerge request !([0-9]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        return notes.compactMap { note in
            let range = NSRange(note.body.startIndex..<note.body.endIndex, in: note.body)
            guard let match = regex.firstMatch(in: note.body, range: range),
                  let iidRange = Range(match.range(at: 1), in: note.body),
                  let mrIid = Int(note.body[iidRange]) else {
                return nil
            }

            return MergeRequestMention(mrIid: mrIid, createdAt: note.createdAt)
        }.max { $0.createdAt < $1.createdAt }
    }

    private func mergeRequestsForIssue(
        issueIid: Int,
        tickets: [Ticket],
        relatedMergeRequests: [GitLabMR],
        projectMergeRequests: [GitLabMR]
    ) -> [GitLabMR] {
        var keyed: [Int: GitLabMR] = [:]
        for mr in relatedMergeRequests {
            keyed[mr.iid] = mr
        }

        for mr in projectMergeRequests where tickets.contains(where: { mergeRequest(mr, mentions: $0, issueIid: issueIid) }) {
            keyed[mr.iid] = mr
        }

        return keyed.values.sorted { $0.iid < $1.iid }
    }

    private func mergeRequest(_ mr: GitLabMR, mentions ticket: Ticket, issueIid: Int) -> Bool {
        let text = [
            mr.title,
            mr.description ?? "",
            mr.sourceBranch,
            mr.targetBranch
        ].joined(separator: " ")

        return textMentions(ticket, issueIid: issueIid, text: text)
    }

    private func commitMentions(_ ticket: Ticket, issueIid: Int, commit: GitLabCommit) -> Bool {
        textMentions(ticket, issueIid: issueIid, text: "\(commit.title) \(commit.message)")
    }

    private func textMentions(_ ticket: Ticket, issueIid: Int, text: String) -> Bool {
        let haystack = text.lowercased()
        let directIssueTokens = [
            "#\(issueIid)",
            "issues/\(issueIid)",
            "/-/issues/\(issueIid)"
        ]

        if directIssueTokens.contains(where: { haystack.contains($0.lowercased()) }) {
            return true
        }

        return issueReferenceTokens(for: ticket).contains { token in
            haystack.contains(token.lowercased())
        }
    }

    private func issueReferenceTokens(for ticket: Ticket) -> [String] {
        var tokens: [String] = []
        if let branchName = ticket.branchName, !branchName.isEmpty {
            tokens.append(branchName)
        }

        let pattern = #"\b[A-Z][A-Z0-9]+-\d+\b"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(ticket.title.startIndex..<ticket.title.endIndex, in: ticket.title)
            for match in regex.matches(in: ticket.title, range: range) {
                if let tokenRange = Range(match.range, in: ticket.title) {
                    tokens.append(String(ticket.title[tokenRange]))
                }
            }
        }

        return Array(Set(tokens))
    }

    private func realizationDate(for commit: GitLabCommit) -> Date? {
        commit.committedDate ?? commit.createdAt
    }

    /// Fetches GitLab milestones for a repository and upserts matching local sprints.
    private func upsertMilestones(projectId: Int, workspace: Workspace) async throws -> [Int: Sprint] {
        let milestones = try await apiClient.fetchMilestones(projectId: projectId)
        var lookup: [Int: Sprint] = [:]

        for milestone in milestones {
            let sprint = workspace.sprints.first { $0.gitlabMilestoneId == milestone.id } ?? {
                let dates = milestoneDateRange(for: milestone)
                let sprint = Sprint(
                    name: milestone.title,
                    startDate: dates.start,
                    endDate: dates.end,
                    gitlabMilestoneId: milestone.id
                )
                sprint.workspace = workspace
                workspace.sprints.append(sprint)
                modelContext.insert(sprint)
                return sprint
            }()

            let dates = milestoneDateRange(for: milestone)
            sprint.name = milestone.title
            sprint.startDate = dates.start
            sprint.endDate = dates.end
            sprint.gitlabMilestoneId = milestone.id
            sprint.workspace = workspace
            if !workspace.sprints.contains(where: { $0.id == sprint.id }) {
                workspace.sprints.append(sprint)
            }
            lookup[milestone.id] = sprint
        }

        return lookup
    }

    /// Creates a local ticket from a GitLab issue and links collaboration metadata.
    private func createTicket(from issue: GitLabIssue, workspace: Workspace, milestoneLookup: [Int: Sprint]) -> Ticket {
        let ticket = Ticket(
            gitlabIssueId: issue.id,
            gitlabIssueIid: issue.iid,
            title: issue.title,
            descriptionText: issue.description,
            status: FieldMapping.gitLabToStatus(state: issue.state, labels: issue.labels),
            storyPoints: nil,
            labels: FieldMapping.nonWorkflowLabels(issue.labels),
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            lastSyncedAt: Date(),
            localVersion: 1
        )

        applyRemoteIssueMetadata(to: ticket, from: issue, workspace: workspace, milestoneLookup: milestoneLookup)
        workspace.tickets.append(ticket)
        modelContext.insert(ticket)
        return ticket
    }

    /// Applies planning fields whose source of truth is the OpenSpec PM Feature database.
    private func applyPlanningMetadata(for repository: Repository, workspace: Workspace) async throws {
        guard let planningMetadataProvider else { return }

        let features = try await planningMetadataProvider.fetchFeatures(repositoryURL: repository.url)
        var ticketByFeatureId: [String: Ticket] = [:]

        for feature in features {
            guard let externalIssueId = feature.externalIssueId,
                  let ticket = workspace.tickets.first(where: {
                      $0.matchesGitLabIssue(id: externalIssueId, iid: externalIssueId)
                  }) else {
                continue
            }
            ticketByFeatureId[feature.id] = ticket

            ticket.title = feature.title
            ticket.status = feature.status.ticketStatus
            ticket.priority = feature.priority.ticketPriority
            ticket.storyPoints = feature.storyPoints
            ticket.startDate = feature.startDate
            ticket.endDate = feature.dueDate
            ticket.branchName = feature.branchName

            if let assignee = feature.assignee,
               let member = workspace.members.first(where: { $0.username == assignee.username }) {
                ticket.assignee = member
            }

            if let milestone = feature.milestone, !milestone.isEmpty {
                let sprint = workspace.sprints.first(where: { $0.name == milestone }) ?? {
                    let startDate = feature.startDate ?? Date()
                    let endDate = feature.dueDate ?? startDate
                    let sprint = Sprint(name: milestone, startDate: startDate, endDate: endDate)
                    sprint.workspace = workspace
                    workspace.sprints.append(sprint)
                    modelContext.insert(sprint)
                    return sprint
                }()
                if ticket.sprint?.id != sprint.id {
                    ticket.sprint?.tickets.removeAll { $0.id == ticket.id }
                    ticket.sprint = sprint
                }
                if !sprint.tickets.contains(where: { $0.id == ticket.id }) {
                    sprint.tickets.append(ticket)
                }
            }
        }

        applyFeatureDependencies(features: features, ticketByFeatureId: ticketByFeatureId, workspace: workspace)
    }

    /// Applies dependency edges whose source of truth is the OpenSpec PM Feature database.
    private func applyFeatureDependencies(
        features: [OpenSpecPMFeature],
        ticketByFeatureId: [String: Ticket],
        workspace: Workspace
    ) {
        guard !ticketByFeatureId.isEmpty else { return }

        var ticketByIssueId: [Int: Ticket] = [:]
        var ticketByIssueIid: [Int: Ticket] = [:]
        var ticketByKey: [String: Ticket] = [:]
        for ticket in workspace.tickets {
            if let issueId = ticket.gitlabIssueId {
                ticketByIssueId[issueId] = ticket
            }
            if let issueIid = ticket.gitlabIssueIid {
                ticketByIssueIid[issueIid] = ticket
            }
            if let key = ticketKey(from: ticket.title) {
                ticketByKey[key] = ticket
            }
        }

        for feature in features {
            guard let ticket = ticketByFeatureId[feature.id] else { continue }

            for blocker in ticket.blockedBy {
                blocker.blocks.removeAll { $0.id == ticket.id }
            }
            ticket.blockedBy.removeAll()

            let blockers = feature.dependencyReferences.compactMap { reference in
                resolveFeatureDependency(
                    reference,
                    ticketByFeatureId: ticketByFeatureId,
                    ticketByIssueId: ticketByIssueId,
                    ticketByIssueIid: ticketByIssueIid,
                    ticketByKey: ticketByKey
                )
            }

            for blocker in blockers where blocker.id != ticket.id {
                if !ticket.blockedBy.contains(where: { $0.id == blocker.id }) {
                    ticket.blockedBy.append(blocker)
                }
                if !blocker.blocks.contains(where: { $0.id == ticket.id }) {
                    blocker.blocks.append(ticket)
                }
            }
        }
    }

    private func resolveFeatureDependency(
        _ reference: String,
        ticketByFeatureId: [String: Ticket],
        ticketByIssueId: [Int: Ticket],
        ticketByIssueIid: [Int: Ticket],
        ticketByKey: [String: Ticket]
    ) -> Ticket? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ticket = ticketByFeatureId[trimmed] {
            return ticket
        }
        if let issueNumber = Int(trimmed) {
            return ticketByIssueIid[issueNumber] ?? ticketByIssueId[issueNumber]
        }
        if let key = ticketKey(from: trimmed) {
            return ticketByKey[key]
        }
        return nil
    }

    private func ticketKey(from value: String) -> String? {
        let pattern = #"\b[A-Z][A-Z0-9]+-\d+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else {
            return nil
        }
        return String(value[range])
    }

    /// Applies collaboration metadata derived from a GitLab issue.
    private func applyRemoteIssueMetadata(
        to ticket: Ticket,
        from issue: GitLabIssue,
        workspace: Workspace,
        milestoneLookup: [Int: Sprint]
    ) {
        ticket.gitlabIssueId = issue.id
        ticket.gitlabIssueIid = issue.iid
        ticket.workspace = workspace
        ticket.labels = FieldMapping.nonWorkflowLabels(issue.labels)

        if !workspace.tickets.contains(where: { $0.id == ticket.id }) {
            workspace.tickets.append(ticket)
        }

        let assignee = issue.assignee ?? issue.assignees?.first
        if let assignee {
            ticket.assignee = workspace.members.first { $0.gitlabUserId == assignee.id }
        } else {
            ticket.assignee = nil
        }

        let sprint = issue.milestone.flatMap { milestoneLookup[$0.id] }
        if ticket.sprint?.id != sprint?.id {
            ticket.sprint?.tickets.removeAll { $0.id == ticket.id }
            ticket.sprint = sprint
        }
        if let sprint, !sprint.tickets.contains(where: { $0.id == ticket.id }) {
            sprint.tickets.append(ticket)
        }
    }

    /// Returns a stable sprint date range even when GitLab milestone dates are partially missing.
    private func milestoneDateRange(for milestone: GitLabMilestone) -> (start: Date, end: Date) {
        let startDate = parseGitLabDate(milestone.startDate)
        let dueDate = parseGitLabDate(milestone.dueDate)

        if let startDate, let dueDate {
            return (startDate, dueDate)
        }

        if let startDate {
            let endDate = Calendar.current.date(byAdding: .day, value: 14, to: startDate) ?? startDate
            return (startDate, endDate)
        }

        if let dueDate {
            let startDate = Calendar.current.date(byAdding: .day, value: -14, to: dueDate) ?? dueDate
            return (startDate, dueDate)
        }

        let fallbackStart = milestone.createdAt ?? Date()
        let fallbackEnd = Calendar.current.date(byAdding: .day, value: 14, to: fallbackStart) ?? fallbackStart
        return (fallbackStart, fallbackEnd)
    }

    /// Parses GitLab date-only strings such as `2024-03-15`.
    private func parseGitLabDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        var components = DateComponents()
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date
    }

    /// Applies a snapshot's values to a ticket.
    private func applySnapshot(_ snapshot: TicketSnapshot, to ticket: Ticket) {
        ticket.title = snapshot.title
        ticket.descriptionText = snapshot.descriptionText
        ticket.status = snapshot.status
        ticket.storyPoints = snapshot.storyPoints
        ticket.labels = snapshot.labels
        ticket.updatedAt = snapshot.updatedAt
    }

    /// Fetches a ticket by its UUID from the model context.
    private func fetchTicket(by id: UUID) throws -> Ticket {
        let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == id })
        guard let ticket = try modelContext.fetch(descriptor).first else {
            throw SyncError.ticketNotFound
        }
        return ticket
    }

    /// Polls all workspaces for updates.
    private func pollAllWorkspaces() async {
        do {
            let descriptor = FetchDescriptor<Workspace>()
            let workspaces = try modelContext.fetch(descriptor)
            for workspace in workspaces {
                _ = try? await fullReconcile(workspace: workspace)
            }
        } catch {
            // Polling errors are non-fatal; will retry next cycle
        }
    }

    // MARK: - Webhook Handlers

    /// Handles an issue webhook event by updating the corresponding local ticket.
    private func handleIssueHook(_ payload: IssueWebhookPayload) async throws {
        let issueIid = payload.objectAttributes.iid
        let projectId = payload.project.id

        // Find the local ticket matching this issue
        let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.gitlabIssueIid == issueIid })
        let tickets = try modelContext.fetch(descriptor)

        guard let ticket = tickets.first else {
            // Issue not tracked locally - could be a new issue from GitLab
            // Create a new local ticket if it belongs to a tracked workspace
            try await createTicketFromWebhook(payload: payload, projectId: projectId)
            return
        }

        switch payload.objectAttributes.action {
        case "update", "open", "reopen":
            ticket.title = payload.objectAttributes.title
            ticket.descriptionText = payload.objectAttributes.description
            let labels = payload.objectAttributes.labels?.map { $0.title } ?? []
            ticket.status = FieldMapping.gitLabToStatus(state: payload.objectAttributes.state, labels: labels)
            ticket.labels = FieldMapping.nonWorkflowLabels(labels)
            ticket.updatedAt = Date()
            ticket.lastSyncedAt = Date()
            ticket.localVersion += 1

        case "close":
            ticket.status = .done
            ticket.updatedAt = Date()
            ticket.lastSyncedAt = Date()
            ticket.localVersion += 1

        default:
            break
        }

        try modelContext.save()
    }

    /// Creates a new local ticket from a webhook payload if the project is tracked.
    private func createTicketFromWebhook(payload: IssueWebhookPayload, projectId: Int) async throws {
        // Find workspace that tracks this project
        let descriptor = FetchDescriptor<Repository>(predicate: #Predicate { $0.gitlabProjectId == projectId })
        let repositories = try modelContext.fetch(descriptor)

        guard let repository = repositories.first, let workspace = repository.workspace else {
            return // Not a tracked project
        }

        let labels = payload.objectAttributes.labels?.map { $0.title } ?? []
        let status = FieldMapping.gitLabToStatus(state: payload.objectAttributes.state, labels: labels)

        let ticket = Ticket(
            gitlabIssueId: payload.objectAttributes.id,
            gitlabIssueIid: payload.objectAttributes.iid,
            title: payload.objectAttributes.title,
            descriptionText: payload.objectAttributes.description,
            status: status,
            storyPoints: nil,
            labels: FieldMapping.nonWorkflowLabels(labels),
            lastSyncedAt: Date(),
            localVersion: 1
        )
        ticket.workspace = workspace

        modelContext.insert(ticket)
        try modelContext.save()
    }

    /// Handles a merge request webhook event by updating local MR entries.
    private func handleMergeRequestHook(_ payload: MRWebhookPayload) async throws {
        let mrId = payload.objectAttributes.id
        let mrIid = payload.objectAttributes.iid
        let projectId = payload.project.id
        let action = payload.objectAttributes.action

        // Find the repository for this project
        let repoDescriptor = FetchDescriptor<Repository>(
            predicate: #Predicate { $0.gitlabProjectId == projectId }
        )
        let repositories = try modelContext.fetch(repoDescriptor)
        guard let repository = repositories.first else { return }

        // Find existing MR entry
        let mrDescriptor = FetchDescriptor<MergeRequestEntry>(
            predicate: #Predicate { $0.gitlabMrId == mrId }
        )
        let existingMRs = try modelContext.fetch(mrDescriptor)

        switch action {
        case "open":
            // Create new MR entry if not already tracked
            if existingMRs.isEmpty {
                let entry = MergeRequestEntry(
                    gitlabMrId: mrId,
                    gitlabMrIid: mrIid,
                    title: payload.objectAttributes.title,
                    authorUsername: "user_\(payload.objectAttributes.authorId)",
                    sourceBranch: payload.objectAttributes.sourceBranch,
                    targetBranch: payload.objectAttributes.targetBranch,
                    state: .opened
                )
                entry.repository = repository
                modelContext.insert(entry)
            }

        case "merge":
            if let existingMR = existingMRs.first {
                existingMR.state = .merged
                existingMR.updatedAt = Date()
            }

        case "close":
            if let existingMR = existingMRs.first {
                existingMR.state = .closed
                existingMR.updatedAt = Date()
            }

        case "update":
            if let existingMR = existingMRs.first {
                existingMR.title = payload.objectAttributes.title
                existingMR.sourceBranch = payload.objectAttributes.sourceBranch
                existingMR.targetBranch = payload.objectAttributes.targetBranch
                existingMR.updatedAt = Date()
            }

        default:
            break
        }

        try modelContext.save()
    }

    /// Handles a push webhook event.
    /// Delegates to SpecTrackingService for OpenSpec spec file detection.
    private func handlePushHook(_ payload: PushWebhookPayload) async throws {
        let projectId = payload.projectId

        // Find workspace that tracks this project
        let descriptor = FetchDescriptor<Repository>(
            predicate: #Predicate { $0.gitlabProjectId == projectId }
        )
        let repositories = try modelContext.fetch(descriptor)

        guard let repository = repositories.first, let workspace = repository.workspace else {
            return // Not a tracked project
        }

        // Delegate to SpecTrackingService for spec file detection
        let specTrackingService = SpecTrackingService(apiClient: apiClient, modelContext: modelContext)
        try await specTrackingService.handlePushEvent(payload, workspace: workspace)
    }

    /// Handles a pipeline webhook event by updating the associated MR's pipeline status.
    private func handlePipelineHook(_ payload: PipelineWebhookPayload) async throws {
        guard let mrInfo = payload.mergeRequest else { return }

        let mrId = mrInfo.id
        let descriptor = FetchDescriptor<MergeRequestEntry>(
            predicate: #Predicate { $0.gitlabMrId == mrId }
        )

        if let existingMR = try modelContext.fetch(descriptor).first {
            let status = payload.objectAttributes.status
            switch status {
            case "running": existingMR.pipelineStatus = .running
            case "success": existingMR.pipelineStatus = .success
            case "failed": existingMR.pipelineStatus = .failed
            case "canceled": existingMR.pipelineStatus = .canceled
            case "pending": existingMR.pipelineStatus = .pending
            default: break
            }
            existingMR.updatedAt = Date()
            try modelContext.save()
        }
    }
}
