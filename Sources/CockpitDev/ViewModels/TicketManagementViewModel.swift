import Foundation
import SwiftData
import SwiftUI

/// ViewModel managing ticket CRUD operations, sync flows, and conflict resolution.
@Observable
@MainActor
class TicketManagementViewModel {

    // MARK: - State

    /// All tickets in the current workspace.
    private(set) var tickets: [Ticket] = []

    /// Whether the create ticket sheet is shown.
    var showCreateSheet: Bool = false

    /// Whether the detail sheet is shown.
    var showDetailSheet: Bool = false

    /// Whether the conflict resolution sheet is shown.
    var showConflictSheet: Bool = false

    /// The ticket currently being viewed/edited.
    var selectedTicket: Ticket?

    /// Error message to display to the user.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    /// Whether a sync operation is in progress.
    var isSyncing: Bool = false

    /// Whether a retry action is available.
    var canRetry: Bool = false

    /// The conflict data for resolution.
    var conflictLocal: TicketSnapshot?
    var conflictRemote: TicketSnapshot?
    var conflictTicket: Ticket?

    /// Whether the delete confirmation dialog is shown.
    var showDeleteConfirmation: Bool = false

    /// Whether to also close the GitLab issue on deletion.
    var showCloseGitLabPrompt: Bool = false

    /// The ticket pending deletion.
    var ticketPendingDeletion: Ticket?

    /// Debounce task for update pushes.
    private var updateDebounceTask: Task<Void, Never>?

    /// The last failed operation for retry.
    private var lastFailedOperation: (() async -> Void)?

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private var syncEngine: SyncEngine?
    private var workspace: Workspace?

    // MARK: - Initialization

    init() {}

    /// Configures the view model with dependencies.
    func configure(modelContext: ModelContext, syncEngine: SyncEngine?, workspace: Workspace?) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
        self.workspace = workspace
        fetchTickets()
    }

    // MARK: - Fetch

    /// Fetches all tickets for the current workspace.
    func fetchTickets() {
        guard let modelContext, let workspace else { return }

        let workspaceId = workspace.id
        let descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.workspace?.id == workspaceId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        do {
            tickets = try modelContext.fetch(descriptor)
        } catch {
            showErrorMessage("Failed to load tickets: \(error.localizedDescription)")
        }
    }

    // MARK: - Create

    /// Creates a new ticket with the given parameters.
    /// Saves locally first, then pushes to GitLab asynchronously.
    /// - Returns: `true` if local creation succeeded.
    @discardableResult
    func createTicket(
        title: String,
        description: String?,
        priority: TicketPriority?,
        storyPoints: Int?,
        labels: [String],
        assignee: Member?,
        sprint: Sprint? = nil,
        startDate: Date?,
        endDate: Date?
    ) -> Bool {
        guard let modelContext, let workspace else {
            showErrorMessage("Unable to save ticket.")
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        // Validate title
        guard !trimmedTitle.isEmpty else {
            showErrorMessage("Ticket title is required.")
            return false
        }

        // Validate story points if provided
        if let sp = storyPoints {
            if let error = validateStoryPoints(sp) {
                showErrorMessage(error)
                return false
            }
        }

        // Create ticket locally
        let ticket = Ticket(
            title: trimmedTitle,
            descriptionText: description?.trimmingCharacters(in: .whitespaces),
            status: .backlog,
            priority: priority,
            storyPoints: storyPoints,
            startDate: startDate,
            endDate: endDate,
            labels: labels,
            localVersion: 1
        )
        ticket.assignee = assignee
        ticket.sprint = sprint
        ticket.workspace = workspace
        sprint?.tickets.append(ticket)

        modelContext.insert(ticket)

        do {
            try modelContext.save()
            fetchTickets()
        } catch {
            showErrorMessage("Failed to save ticket: \(error.localizedDescription)")
            return false
        }

        // Push to GitLab asynchronously
        pushTicketToGitLab(ticket)

        return true
    }

    // MARK: - Update

    /// Updates an existing ticket and schedules a debounced push to GitLab.
    func updateTicket(
        _ ticket: Ticket,
        title: String? = nil,
        description: String? = nil,
        priority: TicketPriority? = nil,
        storyPoints: Int? = nil,
        clearStoryPoints: Bool = false,
        labels: [String]? = nil,
        assignee: Member? = nil,
        clearAssignee: Bool = false,
        startDate: Date? = nil,
        clearStartDate: Bool = false,
        endDate: Date? = nil,
        clearEndDate: Bool = false,
        status: TicketStatus? = nil
    ) {
        guard let modelContext else { return }

        // Validate story points if being set
        if let sp = storyPoints {
            if let error = validateStoryPoints(sp) {
                showErrorMessage(error)
                return
            }
        }

        // Apply changes
        if let title = title {
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                showErrorMessage("Ticket title cannot be empty.")
                return
            }
            ticket.title = trimmed
        }

        if let description = description {
            ticket.descriptionText = description.trimmingCharacters(in: .whitespaces)
        }

        if let priority = priority {
            ticket.priority = priority
        }

        if let sp = storyPoints {
            ticket.storyPoints = sp
        } else if clearStoryPoints {
            ticket.storyPoints = nil
        }

        if let labels = labels {
            ticket.labels = labels
        }

        if let assignee = assignee {
            ticket.assignee = assignee
        } else if clearAssignee {
            ticket.assignee = nil
        }

        if let startDate = startDate {
            ticket.startDate = startDate
        } else if clearStartDate {
            ticket.startDate = nil
        }

        if let endDate = endDate {
            ticket.endDate = endDate
        } else if clearEndDate {
            ticket.endDate = nil
        }

        if let status = status {
            ticket.status = status
        }

        ticket.updatedAt = Date()
        ticket.localVersion += 1

        do {
            try modelContext.save()
            fetchTickets()
        } catch {
            showErrorMessage("Failed to update ticket: \(error.localizedDescription)")
            return
        }

        // Debounced push to GitLab (within 10 seconds)
        scheduleDebouncedPush(for: ticket)
    }

    // MARK: - Delete

    /// Initiates the deletion flow for a ticket.
    func confirmDeletion(of ticket: Ticket) {
        ticketPendingDeletion = ticket
        if ticket.gitlabIssueId != nil {
            // Has GitLab association - ask about closing
            showCloseGitLabPrompt = true
        } else {
            // Local only - just confirm deletion
            showDeleteConfirmation = true
        }
    }

    /// Executes the pending deletion.
    /// - Parameter closeOnGitLab: Whether to also close the issue on GitLab.
    func executeDeletion(closeOnGitLab: Bool = false) {
        guard let modelContext, let ticket = ticketPendingDeletion else { return }

        if closeOnGitLab, let syncEngine, ticket.gitlabIssueIid != nil {
            Task {
                do {
                    try await syncEngine.pushTicketToGitLab(ticket)
                    // Close the issue by updating status to done first
                    ticket.status = .done
                    try await syncEngine.pushTicketToGitLab(ticket)
                } catch {
                    // Continue with local deletion even if GitLab close fails
                    showErrorMessage("Failed to close GitLab issue, but ticket was removed locally.")
                }
            }
        }

        modelContext.delete(ticket)

        do {
            try modelContext.save()
            if selectedTicket?.id == ticket.id {
                selectedTicket = nil
                showDetailSheet = false
            }
            fetchTickets()
        } catch {
            showErrorMessage("Failed to delete ticket: \(error.localizedDescription)")
        }

        ticketPendingDeletion = nil
    }

    // MARK: - Conflict Resolution

    /// Resolves a conflict by choosing either local or remote version.
    /// - Parameter keepLocal: If `true`, keeps local version; otherwise applies remote.
    func resolveConflict(keepLocal: Bool) {
        guard let modelContext, let ticket = conflictTicket else { return }

        if keepLocal {
            // Keep local - push to GitLab to overwrite remote
            pushTicketToGitLab(ticket)
        } else if let remote = conflictRemote {
            // Apply remote version
            ticket.title = remote.title
            ticket.descriptionText = remote.descriptionText
            ticket.status = remote.status
            ticket.storyPoints = remote.storyPoints
            ticket.labels = remote.labels
            ticket.updatedAt = Date()
            ticket.lastSyncedAt = Date()
            ticket.localVersion += 1

            do {
                try modelContext.save()
                fetchTickets()
            } catch {
                showErrorMessage("Failed to apply remote changes: \(error.localizedDescription)")
            }
        }

        // Clear conflict state
        conflictLocal = nil
        conflictRemote = nil
        conflictTicket = nil
        showConflictSheet = false
    }

    // MARK: - Retry

    /// Retries the last failed operation.
    func retryLastOperation() {
        guard let operation = lastFailedOperation else { return }
        canRetry = false
        Task {
            await operation()
        }
    }

    // MARK: - Validation

    /// Validates that a story points value is positive.
    /// - Parameter value: The story points value to validate.
    /// - Returns: An error message if invalid, or `nil` if valid.
    func validateStoryPoints(_ value: Int) -> String? {
        guard value > 0 else {
            return "Story points must be a positive value."
        }
        return nil
    }

    /// Checks if a story points value is non-standard (not in Fibonacci set).
    /// Used for external values from GitLab that may not conform.
    /// - Parameter value: The story points value to check.
    /// - Returns: `true` if the value is non-standard.
    func isNonStandardStoryPoints(_ value: Int) -> Bool {
        return !AppConstants.fibonacciSequence.contains(value)
    }

    // MARK: - Private Helpers

    /// Pushes a ticket to GitLab asynchronously, handling errors.
    private func pushTicketToGitLab(_ ticket: Ticket) {
        guard let syncEngine else { return }

        isSyncing = true

        Task {
            do {
                try await syncEngine.pushTicketToGitLab(ticket)
                await MainActor.run {
                    self.isSyncing = false
                    self.fetchTickets()
                }
            } catch let error as SyncError {
                await MainActor.run {
                    self.isSyncing = false
                    self.handleSyncError(error, for: ticket)
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.showErrorMessage("Sync failed: \(error.localizedDescription)")
                    self.canRetry = true
                    self.lastFailedOperation = { [weak self] in
                        self?.pushTicketToGitLab(ticket)
                    }
                }
            }
        }
    }

    /// Schedules a debounced push to GitLab (within 10 seconds).
    private func scheduleDebouncedPush(for ticket: Ticket) {
        updateDebounceTask?.cancel()
        updateDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.pushTicketToGitLab(ticket)
            }
        }
    }

    /// Handles sync errors with appropriate user feedback.
    private func handleSyncError(_ error: SyncError, for ticket: Ticket) {
        switch error {
        case .offlineQueued:
            // Silently queued - no error to show
            break
        case .noProjectId:
            showErrorMessage("No GitLab project configured. Ticket saved locally.")
        case .pushFailed(let underlying):
            showErrorMessage("Failed to sync with GitLab: \(underlying.localizedDescription)")
            canRetry = true
            lastFailedOperation = { [weak self] in
                self?.pushTicketToGitLab(ticket)
            }
        default:
            showErrorMessage(error.localizedDescription)
            canRetry = true
            lastFailedOperation = { [weak self] in
                self?.pushTicketToGitLab(ticket)
            }
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
