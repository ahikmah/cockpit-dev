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

    // MARK: - Story Points to Weight

    /// Maps story points to GitLab weight (direct 1:1 mapping).
    static func storyPointsToWeight(_ storyPoints: Int?) -> Int? {
        return storyPoints
    }

    /// Maps GitLab weight to story points (direct 1:1 mapping).
    static func weightToStoryPoints(_ weight: Int?) -> Int? {
        return weight
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
    init(apiClient: GitLabAPIClient, modelContext: ModelContext, pollingInterval: TimeInterval = AppConstants.defaultPollInterval) {
        self.apiClient = apiClient
        self.modelContext = modelContext
        self.pollingInterval = pollingInterval
    }

    deinit {
        pollingTask?.cancel()
        offlineRetryTask?.cancel()
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
                fields.weight = FieldMapping.storyPointsToWeight(ticket.storyPoints)
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
                    weight: FieldMapping.storyPointsToWeight(ticket.storyPoints),
                    assigneeId: ticket.assignee?.gitlabUserId
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
            storyPoints: FieldMapping.weightToStoryPoints(remote.weight),
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

        guard let repository = workspace.repositories.first else {
            throw SyncError.noProjectId
        }

        let projectId = repository.gitlabProjectId
        var results: [SyncResult] = []

        do {
            // Fetch all issues from GitLab
            let remoteIssues = try await apiClient.fetchIssues(projectId: projectId)
            let localTickets = workspace.tickets

            // Build lookup maps
            let remoteByIid = Dictionary(uniqueKeysWithValues: remoteIssues.map { ($0.iid, $0) })
            let localByIid = Dictionary(uniqueKeysWithValues:
                localTickets.compactMap { ticket -> (Int, Ticket)? in
                    guard let iid = ticket.gitlabIssueIid else { return nil }
                    return (iid, ticket)
                }
            )

            // Reconcile tickets that exist on both sides
            for (iid, localTicket) in localByIid {
                if let remoteIssue = remoteByIid[iid] {
                    let result = reconcile(local: localTicket, remote: remoteIssue)
                    results.append(result)

                    // Auto-apply non-conflict results
                    if case .noConflict(let merged) = result {
                        applySnapshot(merged, to: localTicket)
                        localTicket.lastSyncedAt = Date()
                    }
                } else {
                    // Local ticket exists but not on remote (may have been deleted)
                    results.append(.localOnly(TicketSnapshot(from: localTicket)))
                }
            }

            // Find remote-only issues (exist on GitLab but not locally)
            let localIids = Set(localByIid.keys)
            for (iid, remoteIssue) in remoteByIid where !localIids.contains(iid) {
                let remoteStatus = FieldMapping.gitLabToStatus(state: remoteIssue.state, labels: remoteIssue.labels)
                let snapshot = TicketSnapshot(
                    gitlabIssueId: remoteIssue.id,
                    gitlabIssueIid: remoteIssue.iid,
                    title: remoteIssue.title,
                    descriptionText: remoteIssue.description,
                    status: remoteStatus,
                    storyPoints: FieldMapping.weightToStoryPoints(remoteIssue.weight),
                    labels: FieldMapping.nonWorkflowLabels(remoteIssue.labels),
                    updatedAt: remoteIssue.updatedAt
                )
                results.append(.remoteOnly(snapshot))
            }

            try modelContext.save()

        } catch {
            throw SyncError.reconcileFailed(error)
        }

        return results
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
        ticket.storyPoints = FieldMapping.weightToStoryPoints(issue.weight)
        ticket.labels = FieldMapping.nonWorkflowLabels(issue.labels)
        ticket.updatedAt = issue.updatedAt
        ticket.localVersion += 1
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
            ticket.storyPoints = FieldMapping.weightToStoryPoints(payload.objectAttributes.weight)
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
            storyPoints: FieldMapping.weightToStoryPoints(payload.objectAttributes.weight),
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
