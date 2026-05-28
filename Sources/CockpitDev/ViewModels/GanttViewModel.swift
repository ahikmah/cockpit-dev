import Foundation
import SwiftData
import SwiftUI

/// A developer row in the timeline.
struct GanttTimelineRow: Identifiable {
    let id: String
    let member: Member?
    let title: String
    let subtitle: String
    let initials: String
    let tickets: [Ticket]
}

/// ViewModel managing the Gantt chart state including zoom, scroll, ticket data,
/// conflict detection, and drag-to-reschedule operations.
@Observable
class GanttViewModel {

    // MARK: - State

    /// The current workspace being displayed.
    var workspace: Workspace?

    /// Continuous timeline scale in points per day.
    var pointsPerDay: CGFloat = 20

    /// Smallest readable timeline scale.
    let minimumPointsPerDay: CGFloat = 1.5

    /// Largest useful review scale.
    let maximumPointsPerDay: CGFloat = 120

    /// Selected milestone/sprint filter. Nil means all milestones.
    var selectedSprint: Sprint?

    /// Scroll offset (x, y) for pan navigation.
    var scrollOffset: CGPoint = .zero

    /// Whether the chart has auto-scrolled to today on first open.
    var hasAutoScrolledToToday: Bool = false

    /// Tickets that have both start and end dates (scheduled).
    var scheduledTickets: [Ticket] = []

    /// Tickets without start or end dates (unscheduled).
    var unscheduledTickets: [Ticket] = []

    /// Scheduled tickets grouped by assignee/developer.
    var timelineRows: [GanttTimelineRow] = []

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

    /// Left lane for developer labels.
    let labelWidth: CGFloat = 256

    /// Breathing room below the last developer row so bars and hover cards are not clipped at the viewport edge.
    let bottomContentPadding: CGFloat = 72

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
        CGFloat(totalDays) * pointsPerDay
    }

    /// Total height of the scheduled section.
    var scheduledSectionHeight: CGFloat {
        let rowsHeight = timelineRows.reduce(CGFloat(0)) { total, row in
            total + rowHeight(for: row)
        }
        return rowsHeight + bottomContentPadding
    }

    /// The x-offset for today's date line.
    var todayXOffset: CGFloat {
        xPosition(for: Date())
    }

    /// Workspace milestones available for filtering.
    var availableSprints: [Sprint] {
        guard let workspace else { return [] }
        return workspace.sprints.sorted {
            if $0.startDate == $1.startDate {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.startDate < $1.startDate
        }
    }

    /// Human-readable continuous zoom label.
    var zoomLabel: String {
        if pointsPerDay >= 80 {
            return "Fine"
        } else if pointsPerDay >= 28 {
            return "Daily"
        } else if pointsPerDay >= 8 {
            return "Weekly"
        } else if pointsPerDay >= 3 {
            return "Monthly"
        }
        return "Overview"
    }

    // MARK: - Data Refresh

    /// Refreshes ticket data from the workspace and evaluates conflicts.
    func refreshData() {
        guard let workspace = workspace else {
            scheduledTickets = []
            unscheduledTickets = []
            timelineRows = []
            conflictedTicketIds = []
            return
        }

        var allTickets = workspace.tickets
        if let selectedSprint {
            allTickets = allTickets.filter { $0.sprint?.id == selectedSprint.id }
        }

        scheduledTickets = allTickets
            .filter { $0.startDate != nil && $0.endDate != nil }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        unscheduledTickets = allTickets
            .filter { $0.startDate == nil || $0.endDate == nil }
            .sorted { $0.title < $1.title }

        timelineRows = makeTimelineRows(from: scheduledTickets, workspace: workspace)
        evaluateConflicts()
    }

    private func makeTimelineRows(from tickets: [Ticket], workspace: Workspace) -> [GanttTimelineRow] {
        let membersWithTickets = workspace.members
            .compactMap { member -> GanttTimelineRow? in
                let memberTickets = tickets
                    .filter { $0.assignee?.id == member.id }
                    .sorted(by: timelineSort)
                guard !memberTickets.isEmpty else { return nil }
                return GanttTimelineRow(
                    id: member.id.uuidString,
                    member: member,
                    title: member.displayName,
                    subtitle: "@\(member.username)",
                    initials: initials(for: member.displayName),
                    tickets: memberTickets
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let unassignedTickets = tickets
            .filter { $0.assignee == nil }
            .sorted(by: timelineSort)

        guard !unassignedTickets.isEmpty else {
            return membersWithTickets
        }

        return membersWithTickets + [
            GanttTimelineRow(
                id: "unassigned",
                member: nil,
                title: "Unassigned",
                subtitle: "No developer",
                initials: "?",
                tickets: unassignedTickets
            )
        ]
    }

    private func timelineSort(_ lhs: Ticket, _ rhs: Ticket) -> Bool {
        let lhsStart = lhs.startDate ?? .distantFuture
        let rhsStart = rhs.startDate ?? .distantFuture
        if lhsStart == rhsStart {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhsStart < rhsStart
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        if letters.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return String(letters).uppercased()
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
        return CGFloat(days) * pointsPerDay
    }

    /// Converts an x-position to a date on the chart.
    func date(forXPosition x: CGFloat) -> Date {
        let days = Int(x / pointsPerDay)
        return Calendar.current.date(byAdding: .day, value: days, to: chartStartDate) ?? chartStartDate
    }

    /// Returns the width in points for a ticket bar.
    func barWidth(for ticket: Ticket) -> CGFloat {
        guard let start = ticket.startDate, let end = ticket.endDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
        return CGFloat(max(days, 1)) * pointsPerDay
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

    /// Returns the top y-position for a developer row.
    func rowYPosition(forRow rowIndex: Int) -> CGFloat {
        headerHeight + timelineRows.prefix(rowIndex).reduce(CGFloat(0)) { total, row in
            total + rowHeight(for: row)
        }
    }

    /// Returns the height for a developer row based on ticket lanes.
    func rowHeight(for row: GanttTimelineRow) -> CGFloat {
        let laneCount = max(row.tickets.count, 1)
        let laneHeight = CGFloat(laneCount) * (rowHeight + rowSpacing) + rowSpacing
        return max(88, laneHeight)
    }

    /// Returns the y-position for a ticket inside a developer row.
    func barYPosition(for ticket: Ticket, in row: GanttTimelineRow, rowIndex: Int) -> CGFloat {
        let laneIndex = row.tickets.firstIndex { $0.id == ticket.id } ?? 0
        return rowYPosition(forRow: rowIndex) + rowSpacing + CGFloat(laneIndex) * (rowHeight + rowSpacing)
    }

    /// Returns the duration in days for a ticket.
    func ticketDuration(for ticket: Ticket) -> Int {
        guard let start = ticket.startDate, let end = ticket.endDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    // MARK: - Zoom

    /// Zooms in one level.
    func zoomIn() {
        pointsPerDay = min(maximumPointsPerDay, pointsPerDay * 1.25)
    }

    /// Zooms out one level.
    func zoomOut() {
        pointsPerDay = max(minimumPointsPerDay, pointsPerDay / 1.25)
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
        pan(by: translation, viewportSize: CGSize(width: 800, height: 400))
    }

    /// Updates scroll offset using the actual visible chart size.
    func pan(by translation: CGSize, viewportSize: CGSize) {
        scrollOffset.x += translation.width
        scrollOffset.y += translation.height

        let maxScrollX: CGFloat = 0
        let visibleTimelineWidth = max(0, viewportSize.width - labelWidth)
        let minScrollX = -max(0, totalContentWidth - visibleTimelineWidth)
        scrollOffset.x = min(maxScrollX, max(minScrollX, scrollOffset.x))

        let maxScrollY: CGFloat = 0
        let visibleTimelineHeight = max(0, viewportSize.height - headerHeight)
        let minScrollY = -max(0, scheduledSectionHeight - visibleTimelineHeight)
        scrollOffset.y = min(maxScrollY, max(minScrollY, scrollOffset.y))
    }

    /// Converts AppKit scroll-wheel deltas into the chart's pan coordinate space.
    func panTranslationForScrollWheel(
        scrollingDeltaX: CGFloat,
        scrollingDeltaY: CGFloat,
        isShiftPressed: Bool
    ) -> CGSize {
        let horizontalDelta = scrollingDeltaX != 0 || isShiftPressed
            ? (scrollingDeltaX != 0 ? scrollingDeltaX : scrollingDeltaY)
            : 0
        let verticalDelta = isShiftPressed ? 0 : scrollingDeltaY

        return CGSize(width: -horizontalDelta, height: -verticalDelta)
    }

    /// Returns the rendered ticket under a chart point, accounting for current scroll offset.
    func ticket(at location: CGPoint) -> Ticket? {
        let offsetX = scrollOffset.x + labelWidth
        let offsetY = scrollOffset.y

        guard location.x >= labelWidth, location.y >= headerHeight else {
            return nil
        }

        for (rowIndex, row) in timelineRows.enumerated() {
            for ticket in row.tickets {
                let barRect = CGRect(
                    x: barXPosition(for: ticket) + offsetX,
                    y: barYPosition(for: ticket, in: row, rowIndex: rowIndex) + offsetY,
                    width: max(barWidth(for: ticket), 12),
                    height: rowHeight
                )
                if barRect.contains(location) {
                    return ticket
                }
            }
        }

        return nil
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
        let dayShift = Int(round(dragOffset / pointsPerDay))

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

    /// Returns the local dependency neighborhood for hover/selection emphasis.
    func focusedDependencyIds(for ticket: Ticket?) -> Set<UUID> {
        guard let ticket else { return [] }
        var ids: Set<UUID> = [ticket.id]
        for blocker in ticket.blockedBy {
            ids.insert(blocker.id)
        }
        for blocked in ticket.blocks {
            ids.insert(blocked.id)
        }
        return ids
    }

    // MARK: - Timeline Bar Color

    /// Returns a calm semantic fill color for a ticket timeline bar.
    func barColor(for ticket: Ticket) -> Color {
        if hasConflict(ticket) {
            return DesignSystem.Colors.timelineConflict
        }

        guard ticket.assignee != nil else {
            return DesignSystem.Colors.timelineUnassigned
        }

        switch ticket.status {
        case .backlog:
            return DesignSystem.Colors.timelineBacklog
        case .todo:
            return DesignSystem.Colors.timelineTodo
        case .inProgress:
            return DesignSystem.Colors.timelineInProgress
        case .inReview:
            return DesignSystem.Colors.timelineInReview
        case .done:
            return DesignSystem.Colors.timelineDone
        }
    }

    /// Returns the border color for a ticket bar.
    func barBorderColor(for ticket: Ticket) -> Color {
        if hasConflict(ticket) {
            return DesignSystem.Colors.timelineConflictBorder
        }

        guard ticket.assignee != nil else {
            return DesignSystem.Colors.timelineUnassignedBorder
        }

        switch ticket.status {
        case .backlog:
            return DesignSystem.Colors.timelineBacklogBorder
        case .todo:
            return DesignSystem.Colors.timelineTodoBorder
        case .inProgress:
            return DesignSystem.Colors.timelineInProgressBorder
        case .inReview:
            return DesignSystem.Colors.timelineInReviewBorder
        case .done:
            return DesignSystem.Colors.timelineDoneBorder
        }
    }

    // MARK: - Timeline Header Labels

    /// Returns date labels for the timeline header based on the current zoom level.
    func timelineLabels() -> [(date: Date, label: String)] {
        var labels: [(Date, String)] = []
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if pointsPerDay >= 45 {
            formatter.dateFormat = "MMM d"
            var current = chartStartDate
            while current <= chartEndDate {
                labels.append((current, formatter.string(from: current)))
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
        } else if pointsPerDay >= 10 {
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
        } else if pointsPerDay >= 3 {
            formatter.dateFormat = "MMM yyyy"
            var components = calendar.dateComponents([.year, .month], from: chartStartDate)
            components.day = 1
            var current = calendar.date(from: components) ?? chartStartDate
            while current <= chartEndDate {
                labels.append((current, formatter.string(from: current)))
                current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            }
        } else {
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
