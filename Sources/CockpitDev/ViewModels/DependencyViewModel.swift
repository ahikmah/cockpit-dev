import Foundation
import SwiftData
import SwiftUI

/// ViewModel managing dependency creation, removal, conflict detection, and resolution.
@Observable
@MainActor
class DependencyViewModel {

    // MARK: - State

    /// Active conflicts for the current workspace.
    private(set) var activeConflicts: [DependencyConflict] = []

    /// Conflicts for the currently selected ticket.
    private(set) var ticketConflicts: [DependencyConflict] = []

    /// Search results for dependency linking.
    var searchResults: [Ticket] = []

    /// Whether a search is in progress.
    var isSearching: Bool = false

    /// The current search query for finding tickets to link.
    var searchQuery: String = ""

    /// Error message to display.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    /// Whether the cycle error alert is shown.
    var showCycleError: Bool = false

    /// The cycle path description for display.
    var cyclePathDescription: String = ""

    /// Whether the status conflict warning dialog is shown.
    var showStatusConflictWarning: Bool = false

    /// The pending status change that triggered the warning.
    var pendingStatusChange: PendingStatusChange?

    /// Whether the conflicts panel is shown.
    var showConflictsPanel: Bool = false

    // MARK: - Dependencies

    private let conflictEngine = DependencyConflictEngine()
    private var modelContext: ModelContext?
    private var workspace: Workspace?

    // MARK: - Initialization

    init() {}

    /// Configures the view model with dependencies.
    func configure(modelContext: ModelContext, workspace: Workspace?) {
        self.modelContext = modelContext
        self.workspace = workspace
        if let workspace {
            refreshConflicts(for: workspace)
        }
    }

    // MARK: - Dependency Search

    /// Searches for tickets that can be linked as dependencies.
    /// Excludes the current ticket and tickets already linked.
    func searchTickets(query: String, excluding ticket: Ticket) {
        guard let modelContext, let workspace else {
            searchResults = []
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true

        let workspaceId = workspace.id
        let descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.workspace?.id == workspaceId }
        )

        do {
            let allTickets = try modelContext.fetch(descriptor)
            let existingBlockerIds = Set(ticket.blockedBy.map(\.id))
            let existingBlockIds = Set(ticket.blocks.map(\.id))

            searchResults = allTickets.filter { candidate in
                // Exclude self
                guard candidate.id != ticket.id else { return false }
                // Exclude already linked
                guard !existingBlockerIds.contains(candidate.id) else { return false }
                guard !existingBlockIds.contains(candidate.id) else { return false }
                // Match query
                return candidate.title.localizedCaseInsensitiveContains(trimmed)
            }
        } catch {
            searchResults = []
        }

        isSearching = false
    }

    // MARK: - Add Dependency

    /// Adds a dependency where `blocker` blocks `dependent`.
    /// Validates for circular dependencies before adding.
    ///
    /// - Parameters:
    ///   - dependent: The ticket that will be blocked.
    ///   - blocker: The ticket that blocks.
    /// - Returns: `true` if the dependency was added successfully.
    @discardableResult
    func addDependency(dependent: Ticket, blocker: Ticket) -> Bool {
        guard let modelContext else { return false }

        // Build existing dependency graph
        let existingDeps = buildDependencyGraph()

        // Validate no cycle
        if !conflictEngine.validateNoCycle(from: dependent, to: blocker, existingDeps: existingDeps) {
            // Detect and show cycle path
            if let cyclePath = conflictEngine.detectCyclePath(from: dependent, to: blocker, existingDeps: existingDeps) {
                cyclePathDescription = cyclePath.joined(separator: " → ")
            } else {
                cyclePathDescription = "\(dependent.title) → \(blocker.title) → ... → \(dependent.title)"
            }
            showCycleError = true
            return false
        }

        // Add the dependency
        dependent.blockedBy.append(blocker)
        blocker.blocks.append(dependent)
        dependent.updatedAt = Date()
        blocker.updatedAt = Date()

        do {
            try modelContext.save()
            // Re-evaluate conflicts
            evaluateConflictsForTicket(dependent)
            if let workspace {
                refreshConflicts(for: workspace)
            }
            return true
        } catch {
            showErrorMessage("Failed to save dependency: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Remove Dependency

    /// Removes a dependency between two tickets and cleans up related conflicts.
    ///
    /// - Parameters:
    ///   - dependent: The ticket that was blocked.
    ///   - blocker: The ticket that was blocking.
    func removeDependency(dependent: Ticket, blocker: Ticket) {
        guard let modelContext else { return }

        // Remove from both sides
        dependent.blockedBy.removeAll { $0.id == blocker.id }
        blocker.blocks.removeAll { $0.id == dependent.id }
        dependent.updatedAt = Date()
        blocker.updatedAt = Date()

        do {
            try modelContext.save()
            // Re-evaluate conflicts (auto-resolution: conflicts caused by this dependency are gone)
            evaluateConflictsForTicket(dependent)
            if let workspace {
                refreshConflicts(for: workspace)
            }
        } catch {
            showErrorMessage("Failed to remove dependency: \(error.localizedDescription)")
        }
    }

    // MARK: - Conflict Evaluation

    /// Evaluates conflicts for a specific ticket.
    func evaluateConflictsForTicket(_ ticket: Ticket) {
        ticketConflicts = conflictEngine.evaluateForTicket(ticket)
    }

    /// Refreshes all active conflicts for the workspace.
    func refreshConflicts(for workspace: Workspace) {
        activeConflicts = conflictEngine.evaluateConflicts(workspace: workspace)
    }

    // MARK: - Status Change with Conflict Check

    /// Checks if a status change would create a status conflict.
    /// If so, shows a warning dialog. Otherwise, proceeds.
    ///
    /// - Parameters:
    ///   - ticket: The ticket whose status is changing.
    ///   - newStatus: The proposed new status.
    ///   - onProceed: Closure to execute if the user proceeds.
    func checkStatusChangeConflict(ticket: Ticket, newStatus: TicketStatus, onProceed: @escaping () -> Void) {
        // Only check when moving to inProgress
        guard newStatus == .inProgress else {
            onProceed()
            return
        }

        // Check if any blocker is not done
        let undoneBlockers = ticket.blockedBy.filter { $0.status != .done }
        if !undoneBlockers.isEmpty {
            let blockerNames = undoneBlockers.map { "\"\($0.title)\"" }.joined(separator: ", ")
            pendingStatusChange = PendingStatusChange(
                ticket: ticket,
                newStatus: newStatus,
                conflictDescription: "Moving \"\(ticket.title)\" to In Progress while blocker(s) \(blockerNames) are not done.",
                onProceed: onProceed
            )
            showStatusConflictWarning = true
        } else {
            onProceed()
        }
    }

    /// Proceeds with the pending status change despite the conflict.
    func proceedWithStatusChange() {
        pendingStatusChange?.onProceed()
        pendingStatusChange = nil
        showStatusConflictWarning = false
        // Refresh conflicts after the change
        if let workspace {
            refreshConflicts(for: workspace)
        }
    }

    /// Cancels the pending status change.
    func cancelStatusChange() {
        pendingStatusChange = nil
        showStatusConflictWarning = false
    }

    // MARK: - Auto-Resolution

    /// Re-evaluates and removes conflicts that are no longer valid.
    /// Called when ticket schedules or statuses change.
    func autoResolveConflicts() {
        guard let workspace else { return }
        refreshConflicts(for: workspace)
    }

    // MARK: - Private Helpers

    /// Builds the dependency graph from the workspace tickets.
    private func buildDependencyGraph() -> [UUID: [Ticket]] {
        guard let workspace else { return [:] }

        var graph: [UUID: [Ticket]] = [:]
        for ticket in workspace.tickets {
            if !ticket.blockedBy.isEmpty {
                graph[ticket.id] = ticket.blockedBy
            }
        }
        return graph
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Pending Status Change

/// Represents a status change that triggered a conflict warning.
struct PendingStatusChange {
    let ticket: Ticket
    let newStatus: TicketStatus
    let conflictDescription: String
    let onProceed: () -> Void
}
