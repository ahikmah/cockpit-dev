import Foundation
import SwiftData
import SwiftUI

/// ViewModel managing the Kanban board state, filtering, column configuration,
/// drag-and-drop operations, and GitLab synchronization.
@Observable
class KanbanViewModel {

    // MARK: - Published State

    /// The current workspace being displayed.
    var workspace: Workspace?

    /// Filtered tickets organized by column name.
    var columnTickets: [String: [Ticket]] = [:]

    /// Whether a sync operation is in progress.
    var isSyncing: Bool = false

    /// Error message to display to the user.
    var errorMessage: String?

    /// Whether the error alert is shown.
    var showError: Bool = false

    /// Whether the column configuration sheet is shown.
    var showColumnConfig: Bool = false

    // MARK: - Filter State

    /// Filter by assignee member.
    var filterAssignee: Member?

    /// Filter by label.
    var filterLabel: String?

    /// Filter by sprint.
    var filterSprint: Sprint?

    // MARK: - Column Configuration State

    /// New column name for adding.
    var newColumnName: String = ""

    /// Column being renamed.
    var renamingColumn: String?

    /// New name for the column being renamed.
    var renameColumnText: String = ""

    // MARK: - Drag State

    /// The ticket currently being dragged.
    var draggingTicket: Ticket?

    /// The column the dragged ticket originated from.
    var dragSourceColumn: String?

    /// The column currently being hovered over during drag.
    var dropTargetColumn: String?

    // MARK: - Dependencies

    private let syncEngine: SyncEngine?
    private let modelContext: ModelContext?

    // MARK: - Initialization

    init(workspace: Workspace? = nil, syncEngine: SyncEngine? = nil, modelContext: ModelContext? = nil) {
        self.workspace = workspace
        self.syncEngine = syncEngine
        self.modelContext = modelContext
        if workspace != nil {
            refreshBoard()
        }
    }

    // MARK: - Computed Properties

    /// Ordered column names from the workspace configuration.
    var columns: [String] {
        workspace?.kanbanColumns ?? AppConstants.defaultKanbanColumns
    }

    /// All unique labels across tickets in the workspace.
    var availableLabels: [String] {
        guard let workspace = workspace else { return [] }
        let allLabels = workspace.tickets.flatMap { $0.labels }
        return Array(Set(allLabels)).sorted()
    }

    /// All members in the workspace for filter options.
    var availableMembers: [Member] {
        workspace?.members ?? []
    }

    /// All sprints in the workspace for filter options.
    var availableSprints: [Sprint] {
        workspace?.sprints ?? []
    }

    /// Whether the current user can configure columns (Owner/Admin).
    func canConfigureColumns(currentUserRole: MemberRole) -> Bool {
        currentUserRole == .owner || currentUserRole == .admin
    }

    // MARK: - Board Refresh

    /// Refreshes the board by re-computing column tickets from workspace data.
    func refreshBoard() {
        guard let workspace = workspace else {
            columnTickets = [:]
            return
        }

        let filteredTickets = applyFilters(to: workspace.tickets)
        var newColumnTickets: [String: [Ticket]] = [:]

        for column in columns {
            newColumnTickets[column] = []
        }

        for ticket in filteredTickets {
            let columnName = mapStatusToColumn(ticket.status)
            if newColumnTickets[columnName] != nil {
                newColumnTickets[columnName]?.append(ticket)
            } else {
                // Unmapped status: place in first column
                let firstColumn = columns.first ?? "Backlog"
                newColumnTickets[firstColumn, default: []].append(ticket)
            }
        }

        // Sort tickets within each column: SP descending, no-SP at bottom
        for column in columns {
            newColumnTickets[column] = sortTickets(newColumnTickets[column] ?? [])
        }

        columnTickets = newColumnTickets
    }

    // MARK: - Filtering

    /// Applies active filters to the ticket list.
    private func applyFilters(to tickets: [Ticket]) -> [Ticket] {
        var result = tickets

        if let assignee = filterAssignee {
            result = result.filter { $0.assignee?.id == assignee.id }
        }

        if let label = filterLabel, !label.isEmpty {
            result = result.filter { $0.labels.contains(label) }
        }

        if let sprint = filterSprint {
            result = result.filter { $0.sprint?.id == sprint.id }
        }

        return result
    }

    /// Clears all active filters.
    func clearFilters() {
        filterAssignee = nil
        filterLabel = nil
        filterSprint = nil
        refreshBoard()
    }

    // MARK: - Card Ordering

    /// Sorts tickets by story points descending, with no-SP tickets at the bottom.
    private func sortTickets(_ tickets: [Ticket]) -> [Ticket] {
        tickets.sorted { lhs, rhs in
            switch (lhs.storyPoints, rhs.storyPoints) {
            case (nil, nil):
                return lhs.title < rhs.title
            case (nil, _):
                return false
            case (_, nil):
                return true
            case (let lhsSP?, let rhsSP?):
                if lhsSP == rhsSP {
                    return lhs.title < rhs.title
                }
                return lhsSP > rhsSP
            }
        }
    }

    // MARK: - Status ↔ Column Mapping

    /// Maps a TicketStatus to the corresponding column name.
    func mapStatusToColumn(_ status: TicketStatus) -> String {
        let columns = self.columns
        switch status {
        case .backlog:
            return columns.first(where: { $0.lowercased().contains("backlog") }) ?? columns.first ?? "Backlog"
        case .todo:
            return columns.first(where: { $0.lowercased().contains("to do") || $0.lowercased() == "todo" }) ?? columns.first ?? "To Do"
        case .inProgress:
            return columns.first(where: { $0.lowercased().contains("in progress") || $0.lowercased().contains("progress") }) ?? columns.first ?? "In Progress"
        case .inReview:
            return columns.first(where: { $0.lowercased().contains("review") }) ?? columns.first ?? "In Review"
        case .done:
            return columns.first(where: { $0.lowercased().contains("done") || $0.lowercased().contains("complete") }) ?? columns.first ?? "Done"
        }
    }

    /// Maps a column name to the corresponding TicketStatus.
    func mapColumnToStatus(_ columnName: String) -> TicketStatus {
        let lower = columnName.lowercased()
        if lower.contains("done") || lower.contains("complete") {
            return .done
        } else if lower.contains("review") {
            return .inReview
        } else if lower.contains("progress") {
            return .inProgress
        } else if lower.contains("to do") || lower == "todo" {
            return .todo
        } else {
            return .backlog
        }
    }

    /// Checks if a ticket has an unmapped status (doesn't match any column).
    func isUnmappedStatus(_ ticket: Ticket) -> Bool {
        let expectedColumn = mapStatusToColumn(ticket.status)
        return !columns.contains(expectedColumn)
    }

    // MARK: - Drag and Drop

    /// Begins a drag operation for a ticket.
    func beginDrag(ticket: Ticket, fromColumn: String) {
        draggingTicket = ticket
        dragSourceColumn = fromColumn
    }

    /// Updates the drop target column during drag.
    func updateDropTarget(_ column: String?) {
        dropTargetColumn = column
    }

    /// Handles dropping a ticket on a column.
    func dropTicket(on targetColumn: String) async {
        guard let ticket = draggingTicket,
              let sourceColumn = dragSourceColumn,
              sourceColumn != targetColumn else {
            resetDragState()
            return
        }

        let previousStatus = ticket.status
        let newStatus = mapColumnToStatus(targetColumn)

        // Optimistically update the UI
        ticket.status = newStatus
        ticket.updatedAt = Date()
        refreshBoard()
        resetDragState()

        // Sync to GitLab
        await syncStatusChange(ticket: ticket, previousStatus: previousStatus, targetColumn: targetColumn)
    }

    /// Resets all drag state.
    private func resetDragState() {
        draggingTicket = nil
        dragSourceColumn = nil
        dropTargetColumn = nil
    }

    // MARK: - Sync Operations

    /// Syncs a status change to GitLab, rolling back on failure.
    private func syncStatusChange(ticket: Ticket, previousStatus: TicketStatus, targetColumn: String) async {
        guard let syncEngine = syncEngine else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await syncEngine.pushTicketToGitLab(ticket)
        } catch {
            // Rollback on failure
            ticket.status = previousStatus
            ticket.updatedAt = Date()
            refreshBoard()

            errorMessage = "Failed to sync status change: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Handles a webhook-driven status update for a ticket.
    func handleWebhookStatusUpdate(ticketId: UUID, newStatus: TicketStatus) {
        guard let workspace = workspace else { return }

        if let ticket = workspace.tickets.first(where: { $0.id == ticketId }) {
            ticket.status = newStatus
            ticket.updatedAt = Date()
            ticket.lastSyncedAt = Date()
            refreshBoard()
        }
    }

    // MARK: - Column Configuration

    /// Adds a new column to the workspace.
    func addColumn(name: String, currentUserRole: MemberRole) -> Bool {
        guard canConfigureColumns(currentUserRole: currentUserRole) else {
            errorMessage = "Only Owner or Admin can configure columns."
            showError = true
            return false
        }

        guard let workspace = workspace else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Column name cannot be empty."
            showError = true
            return false
        }

        guard workspace.kanbanColumns.count < AppConstants.maxKanbanColumns else {
            errorMessage = "Maximum of \(AppConstants.maxKanbanColumns) columns allowed."
            showError = true
            return false
        }

        guard !workspace.kanbanColumns.contains(trimmedName) else {
            errorMessage = "A column with this name already exists."
            showError = true
            return false
        }

        workspace.kanbanColumns.append(trimmedName)
        workspace.updatedAt = Date()
        refreshBoard()
        return true
    }

    /// Removes a column from the workspace.
    func removeColumn(name: String, currentUserRole: MemberRole) -> Bool {
        guard canConfigureColumns(currentUserRole: currentUserRole) else {
            errorMessage = "Only Owner or Admin can configure columns."
            showError = true
            return false
        }

        guard let workspace = workspace else { return false }

        guard workspace.kanbanColumns.count > 1 else {
            errorMessage = "Cannot remove the last column."
            showError = true
            return false
        }

        workspace.kanbanColumns.removeAll { $0 == name }
        workspace.updatedAt = Date()
        refreshBoard()
        return true
    }

    /// Renames a column in the workspace.
    func renameColumn(oldName: String, newName: String, currentUserRole: MemberRole) -> Bool {
        guard canConfigureColumns(currentUserRole: currentUserRole) else {
            errorMessage = "Only Owner or Admin can configure columns."
            showError = true
            return false
        }

        guard let workspace = workspace else { return false }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Column name cannot be empty."
            showError = true
            return false
        }

        guard !workspace.kanbanColumns.contains(trimmedName) else {
            errorMessage = "A column with this name already exists."
            showError = true
            return false
        }

        if let index = workspace.kanbanColumns.firstIndex(of: oldName) {
            workspace.kanbanColumns[index] = trimmedName
            workspace.updatedAt = Date()
            refreshBoard()
            return true
        }

        return false
    }

    /// Reorders columns by moving a column from one index to another.
    func reorderColumn(from source: IndexSet, to destination: Int, currentUserRole: MemberRole) -> Bool {
        guard canConfigureColumns(currentUserRole: currentUserRole) else {
            errorMessage = "Only Owner or Admin can configure columns."
            showError = true
            return false
        }

        guard let workspace = workspace else { return false }

        workspace.kanbanColumns.move(fromOffsets: source, toOffset: destination)
        workspace.updatedAt = Date()
        refreshBoard()
        return true
    }
}
