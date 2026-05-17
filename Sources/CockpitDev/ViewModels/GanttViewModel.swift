import Foundation
import SwiftData
import SwiftUI

/// Zoom level for the Gantt chart timeline.
enum GanttZoomLevel: Int, CaseIterable {
    case day = 0
    case week = 1
    case month = 2
    case quarter = 3

    /// The width in points per day at this zoom level.
    var pointsPerDay: CGFloat {
        switch self {
        case .day: return 60
        case .week: return 20
        case .month: return 6
        case .quarter: return 2
        }
    }

    /// Display label for the zoom level.
    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        }
    }
}

/// ViewModel managing the Gantt chart state including zoom, scroll, ticket data,
/// conflict detection, and drag-to-reschedule operations.
@Observable
class GanttViewModel {

    // MARK: - State

    /// The current workspace being displayed.
    var workspace: Workspace?

    /// Current zoom level.
    var zoomLevel: GanttZoomLevel = .week

    /// Scroll offset (x, y) for pan navigation.
    var scrollOffset: CGPoint = .zero

    /// Whether the chart has auto-scrolled to today on first open.
    var hasAutoScrolledToToday: Bool = false

    /// Tickets that have both start and end dates (scheduled).
    var scheduledTickets: [Ticket] = []

    /// Tickets without start or end dates (unscheduled).
    var unscheduledTickets: [Ticket] = []

    /// Set of ticket IDs that have active dependency conflicts.
    var conflictedTicketIds: Set<UUID> = []

    /// The ticket currently being dragged for rescheduling.
    var draggingTicket: Ticket?

    /// The drag offset in points during a reschedule drag.
    var dragOffset: CGFloat = 0

    /// Whether a sync operation is in progress.
    var isSyncing: Bool = false

    /// Error message to display.
    var errorMessage: String?

    /// Whether the error alert is shown.
    var showError: Bool = false

    /// The row height for each ticket bar.
    let rowHeight: CGFloat = 36

    /// Vertical spacing between rows.
    let rowSpacing: CGFloat = 4

    /// Height of the timeline header.
    let headerHeight: CGFloat = 50

    /// Left margin for ticket labels.
    let labelWidth: CGFloat = 200

    // MARK: - Dependencies

    private let syncEngine: SyncEngine?
    private let conflictEngine: DependencyConflictEngine
    private let modelContext: ModelContext?

    // MARK: - Initialization

    init(
        workspace: Workspace? = nil,
        syncEngine: SyncEngine? = nil,
        conflictEngine: DependencyConflictEngine = DependencyConflictEngine(),
        modelContext: ModelContext? = nil
    ) {
        self.workspace = workspace
        self.syncEngine = syncEngine
        self.conflictEngine = conflictEngine
        self.modelContext = modelContext
        if workspace != nil {
            refreshData()
        }
    }

    // MARK: - Computed Properties

    /// The earliest start date across all scheduled tickets.
    var chartStartDate: Date {
        let earliest = scheduledTickets.compactMap { $0.startDate }.min()
        // Pad 7 days before the earliest ticket
        return Calendar.current.date(byAdding: .day, value: -7, to: earliest ?? Date()) ?? Date()
    }

    /// The latest end date across all scheduled tickets.
    var chartEndDate: Date {
        let latest = scheduledTickets.compactMap { $0.endDate }.max()
        // Pad 7 days after the latest ticket
        return Calendar.current.date(byAdding: .day, value: 7, to: latest ?? Date()) ?? Date()
    }

    /// Total number of days the chart spans.
    var totalDays: Int {
        let days = Calendar.current.dateComponents([.day], from: chartStartDate, to: chartEndDate).day ?? 30
        return max(days, 30)
    }

    /// Total width of the chart content area.
    var totalContentWidth: CGFloat {
        CGFloat(totalDays) * zoomLevel.pointsPerDay
    }

    /// Total height of the scheduled section.
    var scheduledSectionHeight: CGFloat {
        CGFloat(scheduledTickets.count) * (rowHeight + rowSpacing)
    }

    /// The x-offset for today's date line.
    var todayXOffset: CGFloat {
        xPosition(for: Date())
    }

    // MARK: - Data Refresh

    /// Refreshes ticket data from the workspace and evaluates conflicts.
    func refreshData() {
        guard let workspace = workspace else {
            scheduledTickets = []
            unscheduledTickets = []
            conflictedTicketIds = []
            return
        }

        let allTickets = workspace.tickets

        scheduledTickets = allTickets
            .filter { $0.startDate != nil && $0.endDate != nil }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        unscheduledTickets = allTickets
            .filter { $0.startDate == nil || $0.endDate == nil }
            .sorted { $0.title < $1.title }

        evaluateConflicts()
    }

    /// Evaluates dependency conflicts for all tickets in the workspace.
    func evaluateConflicts() {
        guard let workspace = workspace else {
            conflictedTicketIds = []
            return
        }

        let conflicts = conflictEngine.evaluateConflicts(workspace: workspace)
        var ids = Set<UUID>()
        for conflict in conflicts {
            ids.insert(conflict.dependentTicket.id)
            ids.insert(conflict.blockerTicket.id)
        }
        conflictedTicketIds = ids
    }

    // MARK: - Coordinate Calculations

    /// Converts a date to an x-position on the chart.
    func xPosition(for date: Date) -> CGFloat {
        let days = Calendar.current.dateComponents([.day], from: chartStartDate, to: date).day ?? 0
        return CGFloat(days) * zoomLevel.pointsPerDay
    }

    /// Converts an x-position to a date on the chart.
    func date(forXPosition x: CGFloat) -> Date {
        let days = Int(x / zoomLevel.pointsPerDay)
        return Calendar.current.date(byAdding: .day, value: days, to: chartStartDate) ?? chartStartDate
    }

    /// Returns the width in points for a ticket bar.
    func barWidth(for ticket: Ticket) -> CGFloat {
        guard let start = ticket.startDate, let end = ticket.endDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
        return CGFloat(max(days, 1)) * zoomLevel.pointsPerDay
    }

    /// Returns the x-position for a ticket bar.
    func barXPosition(for ticket: Ticket) -> CGFloat {
        guard let start = ticket.startDate else { return 0 }
        return xPosition(for: start)
    }

    /// Returns the y-position for a ticket bar at the given row index.
    func barYPosition(forRow row: Int) -> CGFloat {
        headerHeight + CGFloat(row) * (rowHeight + rowSpacing)
    }

    /// Returns the duration in days for a ticket.
    func ticketDuration(for ticket: Ticket) -> Int {
        guard let start = ticket.startDate, let end = ticket.endDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    // MARK: - Zoom

    /// Zooms in one level.
    func zoomIn() {
        guard let currentIndex = GanttZoomLevel.allCases.firstIndex(of: zoomLevel),
              currentIndex > 0 else { return }
        zoomLevel = GanttZoomLevel.allCases[currentIndex - 1]
    }

    /// Zooms out one level.
    func zoomOut() {
        guard let currentIndex = GanttZoomLevel.allCases.firstIndex(of: zoomLevel),
              currentIndex < GanttZoomLevel.allCases.count - 1 else { return }
        zoomLevel = GanttZoomLevel.allCases[currentIndex + 1]
    }

    /// Handles scroll/pinch zoom gesture magnitude.
    func handleZoomGesture(delta: CGFloat) {
        if delta > 0 {
            zoomIn()
        } else if delta < 0 {
            zoomOut()
        }
    }

    // MARK: - Pan Navigation

    /// Updates scroll offset during drag-to-pan.
    func pan(by translation: CGSize) {
        scrollOffset.x += translation.width
        scrollOffset.y += translation.height

        // Clamp horizontal scroll
        let maxScrollX: CGFloat = 0
        let minScrollX = -(totalContentWidth - 800) // approximate visible width
        scrollOffset.x = min(maxScrollX, max(minScrollX, scrollOffset.x))

        // Clamp vertical scroll
        let maxScrollY: CGFloat = 0
        let minScrollY = -(scheduledSectionHeight - 400) // approximate visible height
        scrollOffset.y = min(maxScrollY, max(minScrollY, scrollOffset.y))
    }

    // MARK: - Auto-Scroll to Today

    /// Scrolls the chart to center on today's date.
    func scrollToToday(viewWidth: CGFloat) {
        let todayX = todayXOffset
        scrollOffset.x = -(todayX - viewWidth / 2 + labelWidth)
        hasAutoScrolledToToday = true
    }

    // MARK: - Drag-to-Reschedule

    /// Begins a drag-to-reschedule operation.
    func beginDrag(ticket: Ticket) {
        draggingTicket = ticket
        dragOffset = 0
    }

    /// Updates the drag offset during reschedule.
    func updateDrag(offset: CGFloat) {
        dragOffset = offset
    }

    /// Completes the drag-to-reschedule, updating the ticket's dates.
    func endDrag() async {
        guard let ticket = draggingTicket,
              let startDate = ticket.startDate,
              let endDate = ticket.endDate else {
            resetDragState()
            return
        }

        // Calculate the number of days to shift
        let dayShift = Int(round(dragOffset / zoomLevel.pointsPerDay))

        guard dayShift != 0 else {
            resetDragState()
            return
        }

        let calendar = Calendar.current

        // Preserve duration: update both start and end
        guard let newStart = calendar.date(byAdding: .day, value: dayShift, to: startDate),
              let newEnd = calendar.date(byAdding: .day, value: dayShift, to: endDate) else {
            resetDragState()
            return
        }

        // Update ticket dates
        ticket.startDate = newStart
        ticket.endDate = newEnd
        ticket.updatedAt = Date()

        resetDragState()
        refreshData()

        // Sync to GitLab
        await syncReschedule(ticket: ticket)
    }

    /// Resets drag state.
    private func resetDragState() {
        draggingTicket = nil
        dragOffset = 0
    }

    /// Syncs a rescheduled ticket to GitLab.
    private func syncReschedule(ticket: Ticket) async {
        guard let syncEngine = syncEngine else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await syncEngine.pushTicketToGitLab(ticket)
        } catch {
            errorMessage = "Failed to sync schedule change: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Conflict Checking

    /// Returns whether a ticket has an active conflict.
    func hasConflict(_ ticket: Ticket) -> Bool {
        conflictedTicketIds.contains(ticket.id)
    }

    // MARK: - Assignee Color

    /// Returns a soft pastel color for a ticket based on its assignee.
    func barColor(for ticket: Ticket) -> Color {
        if hasConflict(ticket) {
            return DesignSystem.Colors.dangerSoft
        }

        guard let assignee = ticket.assignee else {
            return DesignSystem.Colors.accentSoft
        }

        // Generate a consistent pastel color from the assignee's ID
        let hash = assignee.id.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.3, brightness: 0.95)
    }

    /// Returns the border color for a ticket bar.
    func barBorderColor(for ticket: Ticket) -> Color {
        if hasConflict(ticket) {
            return DesignSystem.Colors.danger
        }

        guard let assignee = ticket.assignee else {
            return DesignSystem.Colors.accent.opacity(0.4)
        }

        let hash = assignee.id.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.7)
    }

    // MARK: - Timeline Header Labels

    /// Returns date labels for the timeline header based on the current zoom level.
    func timelineLabels() -> [(date: Date, label: String)] {
        var labels: [(Date, String)] = []
        let calendar = Calendar.current
        let formatter = DateFormatter()

        switch zoomLevel {
        case .day:
            formatter.dateFormat = "MMM d"
            var current = chartStartDate
            while current <= chartEndDate {
                labels.append((current, formatter.string(from: current)))
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }

        case .week:
            formatter.dateFormat = "MMM d"
            var current = chartStartDate
            // Align to start of week
            let weekday = calendar.component(.weekday, from: current)
            if let aligned = calendar.date(byAdding: .day, value: -(weekday - calendar.firstWeekday), to: current) {
                current = aligned
            }
            while current <= chartEndDate {
                labels.append((current, formatter.string(from: current)))
                current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
            }

        case .month:
            formatter.dateFormat = "MMM yyyy"
            var components = calendar.dateComponents([.year, .month], from: chartStartDate)
            components.day = 1
            var current = calendar.date(from: components) ?? chartStartDate
            while current <= chartEndDate {
                labels.append((current, formatter.string(from: current)))
                current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            }

        case .quarter:
            formatter.dateFormat = "QQQ yyyy"
            var components = calendar.dateComponents([.year, .month], from: chartStartDate)
            let month = components.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            components.month = quarterStartMonth
            components.day = 1
            var current = calendar.date(from: components) ?? chartStartDate
            while current <= chartEndDate {
                labels.append((current, formatter.string(from: current)))
                current = calendar.date(byAdding: .month, value: 3, to: current) ?? current
            }
        }

        return labels
    }
}
