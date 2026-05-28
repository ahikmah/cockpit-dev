import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class GanttViewModelTests: CockpitDevTestCase {

    private var viewModel: GanttViewModel!
    private var modelContext: ModelContext!
    private var container: ModelContainer!
    private var workspace: Workspace!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            Workspace.self,
            Repository.self,
            Member.self,
            Ticket.self,
            Sprint.self,
            MergeRequestEntry.self,
            Document.self,
            OpenSpecEntry.self,
            DocSpecVersion.self,
            AppNotification.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        modelContext = container.mainContext

        workspace = Workspace(name: "Test Workspace")
        modelContext.insert(workspace)
        try modelContext.save()

        viewModel = GanttViewModel(workspace: workspace, syncEngine: nil, modelContext: modelContext)
    }

    override func tearDown() async throws {
        viewModel = nil
        modelContext = nil
        container = nil
        workspace = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createTicket(
        title: String,
        status: TicketStatus = .backlog,
        storyPoints: Int? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        assignee: Member? = nil,
        sprint: Sprint? = nil
    ) -> Ticket {
        let ticket = Ticket(
            title: title,
            status: status,
            storyPoints: storyPoints,
            startDate: startDate,
            endDate: endDate
        )
        ticket.workspace = workspace
        ticket.assignee = assignee
        ticket.sprint = sprint
        if let sprint {
            sprint.tickets.append(ticket)
        }
        modelContext.insert(ticket)
        try? modelContext.save()
        return ticket
    }

    private func createMember(username: String, displayName: String) -> Member {
        let member = Member(gitlabUserId: Int.random(in: 1...9999), username: username, displayName: displayName)
        member.workspace = workspace
        modelContext.insert(member)
        try? modelContext.save()
        return member
    }

    private func createSprint(name: String, startDate: Date, endDate: Date) -> Sprint {
        let sprint = Sprint(name: name, startDate: startDate, endDate: endDate)
        sprint.workspace = workspace
        workspace.sprints.append(sprint)
        modelContext.insert(sprint)
        try? modelContext.save()
        return sprint
    }

    // MARK: - Data Refresh Tests

    func testRefreshDataSeparatesScheduledAndUnscheduled() {
        let calendar = Calendar.current
        let today = Date()
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!

        // Scheduled ticket (has both dates)
        _ = createTicket(title: "Scheduled", startDate: today, endDate: nextWeek)

        // Unscheduled ticket (no dates)
        _ = createTicket(title: "Unscheduled")

        // Partially scheduled (only start date)
        _ = createTicket(title: "Partial", startDate: today)

        viewModel.refreshData()

        XCTAssertEqual(viewModel.scheduledTickets.count, 1)
        XCTAssertEqual(viewModel.unscheduledTickets.count, 2)
        XCTAssertEqual(viewModel.scheduledTickets.first?.title, "Scheduled")
    }

    func testRefreshDataSortsScheduledByStartDate() {
        let calendar = Calendar.current
        let today = Date()

        let laterStart = calendar.date(byAdding: .day, value: 5, to: today)!
        let earlierStart = calendar.date(byAdding: .day, value: 1, to: today)!
        let endDate = calendar.date(byAdding: .day, value: 10, to: today)!

        _ = createTicket(title: "Later", startDate: laterStart, endDate: endDate)
        _ = createTicket(title: "Earlier", startDate: earlierStart, endDate: endDate)

        viewModel.refreshData()

        XCTAssertEqual(viewModel.scheduledTickets.count, 2)
        XCTAssertEqual(viewModel.scheduledTickets[0].title, "Earlier")
        XCTAssertEqual(viewModel.scheduledTickets[1].title, "Later")
    }

    func testRefreshDataSortsUnscheduledByTitle() {
        _ = createTicket(title: "Zebra")
        _ = createTicket(title: "Alpha")
        _ = createTicket(title: "Middle")

        viewModel.refreshData()

        XCTAssertEqual(viewModel.unscheduledTickets.count, 3)
        XCTAssertEqual(viewModel.unscheduledTickets[0].title, "Alpha")
        XCTAssertEqual(viewModel.unscheduledTickets[1].title, "Middle")
        XCTAssertEqual(viewModel.unscheduledTickets[2].title, "Zebra")
    }

    func testRefreshDataFiltersScheduledTicketsBySelectedMilestone() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sprint1 = createSprint(
            name: "Milestone 1",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 7, to: today)!
        )
        let sprint2 = createSprint(
            name: "Milestone 2",
            startDate: calendar.date(byAdding: .day, value: 8, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 14, to: today)!
        )

        _ = createTicket(
            title: "Visible",
            startDate: sprint1.startDate,
            endDate: sprint1.endDate,
            sprint: sprint1
        )
        _ = createTicket(
            title: "Hidden",
            startDate: sprint2.startDate,
            endDate: sprint2.endDate,
            sprint: sprint2
        )

        viewModel.selectedSprint = sprint1
        viewModel.refreshData()

        XCTAssertEqual(viewModel.scheduledTickets.map(\.title), ["Visible"])
        XCTAssertEqual(viewModel.timelineRows.count, 1)
        XCTAssertEqual(viewModel.timelineRows[0].tickets.map(\.title), ["Visible"])
    }

    func testRefreshDataGroupsScheduledTicketsByDeveloper() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let rico = createMember(username: "rico", displayName: "Rico")
        let ahikmah = createMember(username: "ahikmah", displayName: "Ahikmah")

        _ = createTicket(
            title: "Rico Task",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 3, to: today)!,
            assignee: rico
        )
        _ = createTicket(
            title: "Ahikmah Task",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 2, to: today)!,
            assignee: ahikmah
        )
        _ = createTicket(
            title: "Unassigned Task",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 1, to: today)!
        )

        viewModel.refreshData()

        XCTAssertEqual(viewModel.timelineRows.map(\.title), ["Ahikmah", "Rico", "Unassigned"])
        XCTAssertEqual(viewModel.timelineRows.map { $0.tickets.count }, [1, 1, 1])
    }

    // MARK: - Zoom Tests

    func testZoomInDecreasesLevel() {
        viewModel.pointsPerDay = 20
        viewModel.zoomIn()
        XCTAssertGreaterThan(viewModel.pointsPerDay, 20)
        XCTAssertNotEqual(viewModel.pointsPerDay, 60)
    }

    func testZoomOutIncreasesLevel() {
        viewModel.pointsPerDay = 20
        viewModel.zoomOut()
        XCTAssertLessThan(viewModel.pointsPerDay, 20)
        XCTAssertNotEqual(viewModel.pointsPerDay, 6)
    }

    func testZoomInClampsAtMaximumContinuousZoom() {
        viewModel.pointsPerDay = viewModel.maximumPointsPerDay
        viewModel.zoomIn()
        XCTAssertEqual(viewModel.pointsPerDay, viewModel.maximumPointsPerDay)
    }

    func testZoomOutClampsAtMinimumContinuousZoom() {
        viewModel.pointsPerDay = viewModel.minimumPointsPerDay
        viewModel.zoomOut()
        XCTAssertEqual(viewModel.pointsPerDay, viewModel.minimumPointsPerDay)
    }

    func testHandleZoomGesturePositiveDeltaZoomsIn() {
        viewModel.pointsPerDay = 20
        viewModel.handleZoomGesture(delta: 1.0)
        XCTAssertGreaterThan(viewModel.pointsPerDay, 20)
    }

    func testHandleZoomGestureNegativeDeltaZoomsOut() {
        viewModel.pointsPerDay = 20
        viewModel.handleZoomGesture(delta: -1.0)
        XCTAssertLessThan(viewModel.pointsPerDay, 20)
    }

    // MARK: - Coordinate Calculation Tests

    func testXPositionForDate() {
        let calendar = Calendar.current
        let today = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today)!
        _ = createTicket(title: "Anchor", startDate: today, endDate: nextMonth)
        viewModel.refreshData()

        viewModel.pointsPerDay = 20
        // chartStartDate is 7 days before the earliest ticket start
        let chartStart = viewModel.chartStartDate
        let tenDaysLater = calendar.date(byAdding: .day, value: 10, to: chartStart)!
        let x = viewModel.xPosition(for: tenDaysLater)
        XCTAssertEqual(x, 10 * 20, accuracy: 1)
    }

    func testDateForXPosition() {
        viewModel.pointsPerDay = 20
        let x: CGFloat = 5 * 20
        let date = viewModel.date(forXPosition: x)

        let calendar = Calendar.current
        let expectedDate = calendar.date(byAdding: .day, value: 5, to: viewModel.chartStartDate)!
        let daysDiff = calendar.dateComponents([.day], from: expectedDate, to: date).day ?? 99
        XCTAssertEqual(daysDiff, 0)
    }

    func testBarWidthCalculation() {
        let calendar = Calendar.current
        let today = Date()
        let fiveDaysLater = calendar.date(byAdding: .day, value: 5, to: today)!

        let ticket = createTicket(title: "Test", startDate: today, endDate: fiveDaysLater)
        viewModel.refreshData()

        viewModel.pointsPerDay = 20
        let width = viewModel.barWidth(for: ticket)
        XCTAssertEqual(width, 5 * 20, accuracy: 1)
    }

    func testBarWidthMinimumOneDay() {
        let today = Date()
        // Same start and end date
        let ticket = createTicket(title: "Test", startDate: today, endDate: today)
        viewModel.refreshData()

        viewModel.pointsPerDay = 20
        let width = viewModel.barWidth(for: ticket)
        XCTAssertEqual(width, 20, accuracy: 1)
    }

    // MARK: - Drag-to-Reschedule Tests

    func testBeginDragSetsState() {
        let today = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        let ticket = createTicket(title: "Drag Me", startDate: today, endDate: nextWeek)
        viewModel.refreshData()

        viewModel.beginDrag(ticket: ticket)

        XCTAssertEqual(viewModel.draggingTicket?.id, ticket.id)
        XCTAssertEqual(viewModel.dragOffset, 0)
    }

    func testUpdateDragSetsOffset() {
        let today = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        let ticket = createTicket(title: "Drag Me", startDate: today, endDate: nextWeek)
        viewModel.refreshData()

        viewModel.beginDrag(ticket: ticket)
        viewModel.updateDrag(offset: 50)

        XCTAssertEqual(viewModel.dragOffset, 50)
    }

    func testEndDragPreservesDuration() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let fiveDaysLater = calendar.date(byAdding: .day, value: 5, to: today)!

        let ticket = createTicket(title: "Drag Me", startDate: today, endDate: fiveDaysLater)
        viewModel.refreshData()

        viewModel.pointsPerDay = 20
        viewModel.beginDrag(ticket: ticket)
        // Drag 3 days worth (60 points at week zoom)
        viewModel.updateDrag(offset: 60)

        await viewModel.endDrag()

        // Duration should still be 5 days
        let newDuration = calendar.dateComponents([.day], from: ticket.startDate!, to: ticket.endDate!).day!
        XCTAssertEqual(newDuration, 5)

        // Start should have shifted by 3 days
        let dayShift = calendar.dateComponents([.day], from: today, to: ticket.startDate!).day!
        XCTAssertEqual(dayShift, 3)
    }

    func testEndDragWithZeroOffsetDoesNothing() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let fiveDaysLater = calendar.date(byAdding: .day, value: 5, to: today)!

        let ticket = createTicket(title: "No Move", startDate: today, endDate: fiveDaysLater)
        viewModel.refreshData()

        viewModel.beginDrag(ticket: ticket)
        viewModel.updateDrag(offset: 0)

        await viewModel.endDrag()

        // Dates should be unchanged
        let daysDiff = calendar.dateComponents([.day], from: today, to: ticket.startDate!).day!
        XCTAssertEqual(daysDiff, 0)
    }

    // MARK: - Conflict Detection Tests

    func testConflictDetectionIdentifiesScheduleConflicts() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Blocker: starts today, ends in 5 days
        let blocker = createTicket(
            title: "Blocker",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 5, to: today)!
        )

        // Dependent: starts in 3 days (before blocker ends) - conflict!
        let dependent = createTicket(
            title: "Dependent",
            startDate: calendar.date(byAdding: .day, value: 3, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 8, to: today)!
        )

        dependent.blockedBy = [blocker]
        blocker.blocks = [dependent]
        try? modelContext.save()

        viewModel.refreshData()

        XCTAssertTrue(viewModel.hasConflict(dependent))
        XCTAssertTrue(viewModel.hasConflict(blocker))
    }

    func testNoConflictWhenDependentStartsAfterBlockerEnds() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Blocker: starts today, ends in 5 days
        let blocker = createTicket(
            title: "Blocker",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 5, to: today)!
        )

        // Dependent: starts in 6 days (after blocker ends) - no conflict
        let dependent = createTicket(
            title: "Dependent",
            startDate: calendar.date(byAdding: .day, value: 6, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 10, to: today)!
        )

        dependent.blockedBy = [blocker]
        blocker.blocks = [dependent]
        try? modelContext.save()

        viewModel.refreshData()

        XCTAssertFalse(viewModel.hasConflict(dependent))
        XCTAssertFalse(viewModel.hasConflict(blocker))
    }

    func testFocusedDependencyIdsIncludesHoveredTicketBlockersAndBlockedTickets() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let blocker = createTicket(
            title: "Blocker",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 1, to: today)!
        )
        let focused = createTicket(
            title: "Focused",
            startDate: calendar.date(byAdding: .day, value: 1, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 5, to: today)!
        )
        let dependent = createTicket(
            title: "Dependent",
            startDate: calendar.date(byAdding: .day, value: 5, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 6, to: today)!
        )
        let unrelated = createTicket(
            title: "Unrelated",
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 6, to: today)!
        )

        focused.blockedBy = [blocker]
        blocker.blocks = [focused]
        focused.blocks = [dependent]
        dependent.blockedBy = [focused]
        try? modelContext.save()

        let ids = viewModel.focusedDependencyIds(for: focused)

        XCTAssertEqual(ids, Set([blocker.id, focused.id, dependent.id]))
        XCTAssertFalse(ids.contains(unrelated.id))
    }

    // MARK: - Assignee Color Tests

    func testBarColorForConflictedTicket() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let blocker = createTicket(
            title: "Blocker",
            status: .inProgress,
            startDate: today,
            endDate: calendar.date(byAdding: .day, value: 5, to: today)!
        )

        let dependent = createTicket(
            title: "Dependent",
            status: .inProgress,
            startDate: calendar.date(byAdding: .day, value: 2, to: today)!,
            endDate: calendar.date(byAdding: .day, value: 7, to: today)!
        )

        dependent.blockedBy = [blocker]
        blocker.blocks = [dependent]
        try? modelContext.save()

        viewModel.refreshData()

        let color = viewModel.barColor(for: dependent)
        XCTAssertEqual(color, DesignSystem.Colors.timelineConflict)
        XCTAssertEqual(viewModel.barBorderColor(for: dependent), DesignSystem.Colors.timelineConflictBorder)
    }

    func testBarColorForUnassignedTicket() {
        let today = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        let ticket = createTicket(title: "No Assignee", startDate: today, endDate: nextWeek)
        viewModel.refreshData()

        let color = viewModel.barColor(for: ticket)
        XCTAssertEqual(color, DesignSystem.Colors.timelineUnassigned)
        XCTAssertEqual(viewModel.barBorderColor(for: ticket), DesignSystem.Colors.timelineUnassignedBorder)
    }

    func testBarColorUsesSemanticTicketStatusPalette() {
        let member = createMember(username: "dev1", displayName: "Developer 1")
        let today = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!

        let backlog = createTicket(title: "Backlog", status: .backlog, startDate: today, endDate: nextWeek, assignee: member)
        let todo = createTicket(title: "Todo", status: .todo, startDate: today, endDate: nextWeek, assignee: member)
        let inProgress = createTicket(title: "Doing", status: .inProgress, startDate: today, endDate: nextWeek, assignee: member)
        let inReview = createTicket(title: "Review", status: .inReview, startDate: today, endDate: nextWeek, assignee: member)
        let done = createTicket(title: "Done", status: .done, startDate: today, endDate: nextWeek, assignee: member)
        viewModel.refreshData()

        XCTAssertEqual(viewModel.barColor(for: backlog), DesignSystem.Colors.timelineBacklog)
        XCTAssertEqual(viewModel.barColor(for: todo), DesignSystem.Colors.timelineTodo)
        XCTAssertEqual(viewModel.barColor(for: inProgress), DesignSystem.Colors.timelineInProgress)
        XCTAssertEqual(viewModel.barColor(for: inReview), DesignSystem.Colors.timelineInReview)
        XCTAssertEqual(viewModel.barColor(for: done), DesignSystem.Colors.timelineDone)
        XCTAssertEqual(viewModel.barBorderColor(for: done), DesignSystem.Colors.timelineDoneBorder)
    }

    // MARK: - Auto-Scroll Tests

    func testScrollToTodaySetsOffset() {
        let today = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        _ = createTicket(title: "Test", startDate: today, endDate: nextWeek)
        viewModel.refreshData()

        viewModel.scrollToToday(viewWidth: 800)

        XCTAssertTrue(viewModel.hasAutoScrolledToToday)
        XCTAssertNotEqual(viewModel.scrollOffset.x, 0)
    }

    // MARK: - Timeline Labels Tests

    func testTimelineLabelsAtDayZoom() {
        let today = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        _ = createTicket(title: "Test", startDate: today, endDate: nextWeek)
        viewModel.refreshData()

        viewModel.pointsPerDay = 60
        let labels = viewModel.timelineLabels()

        // Should have one label per day
        XCTAssertGreaterThan(labels.count, 7)
    }

    func testTimelineLabelsAtWeekZoom() {
        let today = Date()
        let twoMonthsLater = Calendar.current.date(byAdding: .month, value: 2, to: today)!
        _ = createTicket(title: "Test", startDate: today, endDate: twoMonthsLater)
        viewModel.refreshData()

        viewModel.pointsPerDay = 20
        let labels = viewModel.timelineLabels()

        // Should have roughly 8-10 labels for 2 months at week zoom
        XCTAssertGreaterThan(labels.count, 5)
        XCTAssertLessThan(labels.count, 15)
    }

    // MARK: - Continuous Zoom Properties Tests

    func testContinuousZoomBounds() {
        XCTAssertEqual(viewModel.minimumPointsPerDay, 1.5)
        XCTAssertEqual(viewModel.maximumPointsPerDay, 120)
    }

    func testZoomLabelAdaptsToScale() {
        viewModel.pointsPerDay = 100
        XCTAssertEqual(viewModel.zoomLabel, "Fine")

        viewModel.pointsPerDay = 20
        XCTAssertEqual(viewModel.zoomLabel, "Weekly")

        viewModel.pointsPerDay = 2
        XCTAssertEqual(viewModel.zoomLabel, "Overview")
    }

    // MARK: - Ticket Duration Tests

    func testTicketDurationCalculation() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tenDaysLater = calendar.date(byAdding: .day, value: 10, to: today)!

        let ticket = createTicket(title: "Duration Test", startDate: today, endDate: tenDaysLater)
        viewModel.refreshData()

        let duration = viewModel.ticketDuration(for: ticket)
        XCTAssertEqual(duration, 10)
    }

    func testTicketDurationWithNoDates() {
        let ticket = createTicket(title: "No Dates")
        viewModel.refreshData()

        let duration = viewModel.ticketDuration(for: ticket)
        XCTAssertEqual(duration, 0)
    }

    // MARK: - Pan Tests

    func testPanUpdatesScrollOffset() {
        let calendar = Calendar.current
        let today = Date()
        // Create many tickets spanning a long time to ensure content is large enough for scrolling
        for i in 0..<20 {
            let start = calendar.date(byAdding: .day, value: i * 7, to: today)!
            let end = calendar.date(byAdding: .day, value: i * 7 + 5, to: today)!
            _ = createTicket(title: "Task \(i)", startDate: start, endDate: end)
        }
        viewModel.refreshData()

        // Set initial offset to something non-zero so we can pan in both directions
        viewModel.scrollOffset = CGPoint(x: -100, y: -100)

        let initialX = viewModel.scrollOffset.x
        viewModel.pan(by: CGSize(width: 20, height: 0))

        XCTAssertNotEqual(viewModel.scrollOffset.x, initialX)
    }

    func testPanUsesActualViewportBoundsForHorizontalAndVerticalScroll() {
        let calendar = Calendar.current
        let today = Date()
        let member = createMember(username: "dev", displayName: "Developer")
        for i in 0..<18 {
            let start = calendar.date(byAdding: .day, value: i * 7, to: today)!
            let end = calendar.date(byAdding: .day, value: i * 7 + 5, to: today)!
            _ = createTicket(title: "Task \(i)", startDate: start, endDate: end, assignee: member)
        }
        viewModel.refreshData()
        viewModel.pointsPerDay = 20

        viewModel.pan(by: CGSize(width: -300, height: -300), viewportSize: CGSize(width: 500, height: 140))

        XCTAssertLessThan(viewModel.scrollOffset.x, 0)
        XCTAssertLessThan(viewModel.scrollOffset.y, 0)
    }

    func testPanLeavesBottomPaddingForLastVisibleRow() {
        let calendar = Calendar.current
        let today = Date()
        let member = createMember(username: "dev", displayName: "Developer")
        for i in 0..<18 {
            let start = calendar.date(byAdding: .day, value: i, to: today)!
            let end = calendar.date(byAdding: .day, value: i + 1, to: today)!
            _ = createTicket(title: "Task \(i)", startDate: start, endDate: end, assignee: member)
        }
        viewModel.refreshData()

        let viewport = CGSize(width: 500, height: 220)
        viewModel.pan(by: CGSize(width: 0, height: -10_000), viewportSize: viewport)

        let row = viewModel.timelineRows[0]
        let lastRowBottom = viewModel.rowYPosition(forRow: 0)
            + viewModel.rowHeight(for: row)
            + viewModel.scrollOffset.y

        XCTAssertLessThanOrEqual(lastRowBottom, viewport.height - viewModel.bottomContentPadding + 0.5)
    }

    func testScrollWheelDownMapsToNegativeVerticalPan() {
        let translation = viewModel.panTranslationForScrollWheel(
            scrollingDeltaX: 0,
            scrollingDeltaY: 24,
            isShiftPressed: false
        )

        XCTAssertEqual(translation.width, 0)
        XCTAssertEqual(translation.height, -24)
    }

    func testShiftScrollWheelMapsVerticalWheelToHorizontalPan() {
        let translation = viewModel.panTranslationForScrollWheel(
            scrollingDeltaX: 0,
            scrollingDeltaY: 18,
            isShiftPressed: true
        )

        XCTAssertEqual(translation.width, -18)
        XCTAssertEqual(translation.height, 0)
    }

    func testTicketAtLocationFindsRenderedTicket() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 5, to: today)!
        let ticket = createTicket(title: "Hover target", startDate: today, endDate: end)
        viewModel.refreshData()
        viewModel.pointsPerDay = 20

        let location = CGPoint(
            x: viewModel.labelWidth + viewModel.barXPosition(for: ticket) + 8,
            y: viewModel.barYPosition(for: ticket, in: viewModel.timelineRows[0], rowIndex: 0) + 8
        )

        XCTAssertEqual(viewModel.ticket(at: location)?.id, ticket.id)
    }
}
