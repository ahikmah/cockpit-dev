import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class SprintViewModelTests: CockpitDevTestCase {

    private var viewModel: SprintViewModel!
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

        viewModel = SprintViewModel(workspace: workspace, gitLabClient: nil, modelContext: modelContext)
    }

    override func tearDown() async throws {
        viewModel = nil
        modelContext = nil
        container = nil
        workspace = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func createSprint(
        name: String,
        startDate: Date = Date(),
        endDate: Date? = nil
    ) -> Sprint {
        let end = endDate ?? Calendar.current.date(byAdding: .day, value: 14, to: startDate)!
        let sprint = Sprint(name: name, startDate: startDate, endDate: end)
        sprint.workspace = workspace
        workspace.sprints.append(sprint)
        modelContext.insert(sprint)
        try? modelContext.save()
        return sprint
    }

    private func createTicket(
        title: String,
        status: TicketStatus = .backlog,
        storyPoints: Int? = nil,
        sprint: Sprint? = nil
    ) -> Ticket {
        let ticket = Ticket(title: title, status: status, storyPoints: storyPoints)
        ticket.workspace = workspace
        ticket.sprint = sprint
        if let sprint = sprint {
            sprint.tickets.append(ticket)
        }
        workspace.tickets.append(ticket)
        modelContext.insert(ticket)
        try? modelContext.save()
        return ticket
    }

    // MARK: - Sprint Form Validation Tests

    func testOrderedTicketsUsesPlanningDateThenIssueIid() {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        let sprint = createSprint(name: "Planning Sprint", startDate: base)

        let later = createTicket(title: "Later", storyPoints: 13, sprint: sprint)
        later.startDate = calendar.date(byAdding: .day, value: 3, to: base)
        later.endDate = calendar.date(byAdding: .day, value: 5, to: base)
        later.gitlabIssueIid = 9

        let earlierHighSp = createTicket(title: "Earlier High SP", storyPoints: 21, sprint: sprint)
        earlierHighSp.startDate = calendar.date(byAdding: .day, value: 1, to: base)
        earlierHighSp.endDate = calendar.date(byAdding: .day, value: 2, to: base)
        earlierHighSp.gitlabIssueIid = 7

        let sameDateLowerIid = createTicket(title: "Same Date Lower IID", storyPoints: 1, sprint: sprint)
        sameDateLowerIid.startDate = earlierHighSp.startDate
        sameDateLowerIid.endDate = earlierHighSp.endDate
        sameDateLowerIid.gitlabIssueIid = 4

        let unscheduled = createTicket(title: "Unscheduled", storyPoints: 34, sprint: sprint)
        unscheduled.gitlabIssueIid = 1
        try? modelContext.save()

        XCTAssertEqual(
            viewModel.orderedTickets(for: sprint).map(\.title),
            ["Same Date Lower IID", "Earlier High SP", "Later", "Unscheduled"]
        )
    }

    func testValidateSprintForm_validInput() {
        viewModel.newSprintName = "Sprint 1"
        viewModel.newSprintStartDate = Date()
        viewModel.newSprintEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        XCTAssertTrue(viewModel.validateSprintForm())
        XCTAssertNil(viewModel.formValidationError)
    }

    func testValidateSprintForm_emptyName() {
        viewModel.newSprintName = ""
        viewModel.newSprintStartDate = Date()
        viewModel.newSprintEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        XCTAssertFalse(viewModel.validateSprintForm())
        XCTAssertEqual(viewModel.formValidationError, "Sprint name is required.")
    }

    func testValidateSprintForm_whitespaceName() {
        viewModel.newSprintName = "   "
        viewModel.newSprintStartDate = Date()
        viewModel.newSprintEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        XCTAssertFalse(viewModel.validateSprintForm())
        XCTAssertEqual(viewModel.formValidationError, "Sprint name is required.")
    }

    func testValidateSprintForm_nameTooLong() {
        viewModel.newSprintName = String(repeating: "a", count: 101)
        viewModel.newSprintStartDate = Date()
        viewModel.newSprintEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        XCTAssertFalse(viewModel.validateSprintForm())
        XCTAssertEqual(viewModel.formValidationError, "Sprint name must be 100 characters or fewer.")
    }

    func testValidateSprintForm_nameExactly100Chars() {
        viewModel.newSprintName = String(repeating: "a", count: 100)
        viewModel.newSprintStartDate = Date()
        viewModel.newSprintEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        XCTAssertTrue(viewModel.validateSprintForm())
        XCTAssertNil(viewModel.formValidationError)
    }

    func testValidateSprintForm_startDateAfterEndDate() {
        viewModel.newSprintName = "Sprint 1"
        viewModel.newSprintStartDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        viewModel.newSprintEndDate = Date()

        XCTAssertFalse(viewModel.validateSprintForm())
        XCTAssertEqual(viewModel.formValidationError, "Start date must be before end date.")
    }

    func testValidateSprintForm_startDateEqualsEndDate() {
        viewModel.newSprintName = "Sprint 1"
        let now = Date()
        viewModel.newSprintStartDate = now
        viewModel.newSprintEndDate = now

        XCTAssertFalse(viewModel.validateSprintForm())
        XCTAssertEqual(viewModel.formValidationError, "Start date must be before end date.")
    }

    // MARK: - Sprint Creation Tests

    func testCreateSprint_success() async {
        viewModel.newSprintName = "Sprint 1"
        viewModel.newSprintStartDate = Date()
        viewModel.newSprintEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        await viewModel.createSprint()

        XCTAssertEqual(viewModel.sprints.count, 1)
        XCTAssertEqual(viewModel.sprints.first?.name, "Sprint 1")
        XCTAssertFalse(viewModel.showCreateSprint)
        XCTAssertEqual(viewModel.newSprintName, "")
    }

    func testCreateSprint_invalidForm_doesNotCreate() async {
        viewModel.newSprintName = ""

        await viewModel.createSprint()

        XCTAssertEqual(viewModel.sprints.count, 0)
    }

    // MARK: - Progress Calculation Tests

    func testProgressPercentage_noTickets() {
        let sprint = createSprint(name: "Empty Sprint")
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.progressPercentage(for: sprint), 0)
    }

    func testProgressPercentage_noStoryPoints() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "No SP", status: .done, storyPoints: nil, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.progressPercentage(for: sprint), 0)
    }

    func testProgressPercentage_allDone() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Done 1", status: .done, storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "Done 2", status: .done, storyPoints: 8, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.progressPercentage(for: sprint), 100.0)
    }

    func testProgressPercentage_partial() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Done", status: .done, storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "In Progress", status: .inProgress, storyPoints: 5, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.progressPercentage(for: sprint), 50.0)
    }

    func testProgressPercentage_noneDone() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Backlog", status: .backlog, storyPoints: 8, sprint: sprint)
        _ = createTicket(title: "Todo", status: .todo, storyPoints: 5, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.progressPercentage(for: sprint), 0)
    }

    func testTotalStoryPoints() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "T1", status: .backlog, storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "T2", status: .inProgress, storyPoints: 8, sprint: sprint)
        _ = createTicket(title: "T3", status: .done, storyPoints: 3, sprint: sprint)
        _ = createTicket(title: "T4 No SP", status: .backlog, storyPoints: nil, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.totalStoryPoints(for: sprint), 16)
    }

    func testDoneStoryPoints() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Done 1", status: .done, storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "Done 2", status: .done, storyPoints: 3, sprint: sprint)
        _ = createTicket(title: "Not Done", status: .inProgress, storyPoints: 8, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.doneStoryPoints(for: sprint), 8)
    }

    // MARK: - Ticket Assignment Tests

    func testAssignTicket() {
        let sprint = createSprint(name: "Sprint 1")
        let ticket = createTicket(title: "Unassigned Ticket", storyPoints: 5)
        viewModel.refreshSprints()

        viewModel.assignTicket(ticket, to: sprint)

        XCTAssertEqual(ticket.sprint?.id, sprint.id)
        XCTAssertTrue(sprint.tickets.contains(where: { $0.id == ticket.id }))
    }

    func testUnassignTicket() {
        let sprint = createSprint(name: "Sprint 1")
        let ticket = createTicket(title: "Assigned Ticket", storyPoints: 5, sprint: sprint)
        viewModel.refreshSprints()

        viewModel.unassignTicket(ticket)

        XCTAssertNil(ticket.sprint)
        XCTAssertFalse(sprint.tickets.contains(where: { $0.id == ticket.id }))
    }

    func testDeleteSprintRemovesSprintAndNullifiesTickets() async {
        let sprint = createSprint(name: "Sprint 1")
        let ticket = createTicket(title: "Assigned Ticket", storyPoints: 5, sprint: sprint)
        viewModel.refreshSprints()

        await viewModel.deleteSprint(sprint)

        XCTAssertTrue(viewModel.sprints.isEmpty)
        XCTAssertNil(ticket.sprint)
        XCTAssertTrue(workspace.tickets.contains(where: { $0.id == ticket.id }))
        XCTAssertFalse(workspace.sprints.contains(where: { $0.id == sprint.id }))
    }

    func testAssignTicket_alreadyAssigned_noDuplicate() {
        let sprint = createSprint(name: "Sprint 1")
        let ticket = createTicket(title: "Ticket", storyPoints: 5, sprint: sprint)
        viewModel.refreshSprints()

        // Assign again
        viewModel.assignTicket(ticket, to: sprint)

        // Should not duplicate
        let count = sprint.tickets.filter { $0.id == ticket.id }.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - Sprint Status Tests

    func testIsSprintActive_currentSprint() {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let sprint = createSprint(name: "Active Sprint", startDate: start, endDate: end)
        viewModel.refreshSprints()

        XCTAssertTrue(viewModel.isSprintActive(sprint))
        XCTAssertFalse(viewModel.isSprintCompleted(sprint))
    }

    func testIsSprintCompleted_pastSprint() {
        let start = Calendar.current.date(byAdding: .day, value: -21, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let sprint = createSprint(name: "Past Sprint", startDate: start, endDate: end)
        viewModel.refreshSprints()

        XCTAssertTrue(viewModel.isSprintCompleted(sprint))
        XCTAssertFalse(viewModel.isSprintActive(sprint))
    }

    func testIsSprintUpcoming_futureSprint() {
        let start = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 21, to: Date())!
        let sprint = createSprint(name: "Future Sprint", startDate: start, endDate: end)
        viewModel.refreshSprints()

        XCTAssertFalse(viewModel.isSprintActive(sprint))
        XCTAssertFalse(viewModel.isSprintCompleted(sprint))
        XCTAssertEqual(viewModel.statusLabel(for: sprint), "Upcoming")
    }

    // MARK: - Next Sprint Tests

    func testNextSprint_exists() {
        let sprint1 = createSprint(name: "Sprint 1", startDate: Date())
        let sprint2Start = Calendar.current.date(byAdding: .day, value: 15, to: Date())!
        let sprint2 = createSprint(name: "Sprint 2", startDate: sprint2Start)
        viewModel.refreshSprints()

        let next = viewModel.nextSprint(after: sprint1)
        XCTAssertEqual(next?.id, sprint2.id)
    }

    func testNextSprint_doesNotExist() {
        let sprint1 = createSprint(name: "Sprint 1", startDate: Date())
        viewModel.refreshSprints()

        let next = viewModel.nextSprint(after: sprint1)
        XCTAssertNil(next)
    }

    // MARK: - Move Incomplete Tickets Tests

    func testMoveIncompleteToNextSprint() {
        let sprint1Start = Calendar.current.date(byAdding: .day, value: -21, to: Date())!
        let sprint1End = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let sprint1 = createSprint(name: "Sprint 1", startDate: sprint1Start, endDate: sprint1End)

        let sprint2Start = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        let sprint2 = createSprint(name: "Sprint 2", startDate: sprint2Start)

        let doneTicket = createTicket(title: "Done", status: .done, storyPoints: 5, sprint: sprint1)
        let incompleteTicket = createTicket(title: "Incomplete", status: .inProgress, storyPoints: 8, sprint: sprint1)
        viewModel.refreshSprints()

        viewModel.moveIncompleteToNextSprint(from: sprint1)

        // Done ticket stays in sprint 1
        XCTAssertEqual(doneTicket.sprint?.id, sprint1.id)
        // Incomplete ticket moved to sprint 2
        XCTAssertEqual(incompleteTicket.sprint?.id, sprint2.id)
        XCTAssertTrue(sprint2.tickets.contains(where: { $0.id == incompleteTicket.id }))
    }

    func testMoveIncompleteToNextSprint_noNextSprint_showsCreateOption() {
        let sprint1Start = Calendar.current.date(byAdding: .day, value: -21, to: Date())!
        let sprint1End = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let sprint1 = createSprint(name: "Sprint 1", startDate: sprint1Start, endDate: sprint1End)
        _ = createTicket(title: "Incomplete", status: .inProgress, storyPoints: 8, sprint: sprint1)
        viewModel.refreshSprints()

        viewModel.moveIncompleteToNextSprint(from: sprint1)

        XCTAssertTrue(viewModel.showCreateNewSprintForIncomplete)
    }

    // MARK: - Burndown Chart Data Tests

    func testBurndownData_generatesDataPoints() {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let sprint = createSprint(name: "Active Sprint", startDate: start, endDate: end)
        _ = createTicket(title: "T1", status: .done, storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "T2", status: .inProgress, storyPoints: 8, sprint: sprint)
        viewModel.refreshSprints()

        let data = viewModel.burndownData(for: sprint)

        // Should have data points from start to today (8 days)
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertLessThanOrEqual(data.count, 15) // max 14 days + 1
    }

    func testBurndownData_emptySprintNoTickets() {
        let start = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 11, to: Date())!
        let sprint = createSprint(name: "Empty Sprint", startDate: start, endDate: end)
        viewModel.refreshSprints()

        let data = viewModel.burndownData(for: sprint)

        // Should still generate data points (all zeros)
        XCTAssertGreaterThan(data.count, 0)
        for point in data {
            XCTAssertEqual(point.remainingStoryPoints, 0)
        }
    }

    func testBurndownData_futureSprint_noDataPoints() {
        let start = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 21, to: Date())!
        let sprint = createSprint(name: "Future Sprint", startDate: start, endDate: end)
        _ = createTicket(title: "T1", status: .backlog, storyPoints: 5, sprint: sprint)
        viewModel.refreshSprints()

        let data = viewModel.burndownData(for: sprint)

        // Future sprint hasn't started, no data points
        XCTAssertEqual(data.count, 0)
    }

    func testBurndownData_idealLineDecreasesLinearly() {
        let start = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 4, to: Date())!
        let sprint = createSprint(name: "Sprint", startDate: start, endDate: end)
        _ = createTicket(title: "T1", status: .inProgress, storyPoints: 14, sprint: sprint)
        viewModel.refreshSprints()

        let data = viewModel.burndownData(for: sprint)

        // First point ideal should be total SP
        if let first = data.first {
            XCTAssertEqual(first.idealRemaining, 14.0, accuracy: 0.01)
        }

        // Ideal line should decrease
        if data.count >= 2 {
            XCTAssertGreaterThan(data[0].idealRemaining, data[1].idealRemaining)
        }
    }

    // MARK: - Incomplete Ticket Count Tests

    func testIncompleteTicketCount() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Done", status: .done, storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "In Progress", status: .inProgress, storyPoints: 8, sprint: sprint)
        _ = createTicket(title: "Backlog", status: .backlog, storyPoints: 3, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.incompleteTicketCount(for: sprint), 2)
    }

    func testIncompleteTickets() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Done", status: .done, storyPoints: 5, sprint: sprint)
        let inProgress = createTicket(title: "In Progress", status: .inProgress, storyPoints: 8, sprint: sprint)
        let backlog = createTicket(title: "Backlog", status: .backlog, storyPoints: 3, sprint: sprint)
        viewModel.refreshSprints()

        let incomplete = viewModel.incompleteTickets(for: sprint)
        XCTAssertEqual(incomplete.count, 2)
        XCTAssertTrue(incomplete.contains(where: { $0.id == inProgress.id }))
        XCTAssertTrue(incomplete.contains(where: { $0.id == backlog.id }))
    }

    // MARK: - Refresh Tests

    func testRefreshSprints_sortsByStartDate() {
        let date1 = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let date2 = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let date3 = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        _ = createSprint(name: "Sprint C", startDate: date1)
        _ = createSprint(name: "Sprint A", startDate: date2)
        _ = createSprint(name: "Sprint B", startDate: date3)

        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.sprints[0].name, "Sprint A")
        XCTAssertEqual(viewModel.sprints[1].name, "Sprint B")
        XCTAssertEqual(viewModel.sprints[2].name, "Sprint C")
    }

    func testRefreshUnassignedTickets() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Assigned", storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "Unassigned 1", storyPoints: 3)
        _ = createTicket(title: "Unassigned 2", storyPoints: 8)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.unassignedTickets.count, 2)
    }

    // MARK: - Formatted Output Tests

    func testFormattedProgress() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Done", status: .done, storyPoints: 3, sprint: sprint)
        _ = createTicket(title: "Todo", status: .todo, storyPoints: 7, sprint: sprint)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.formattedProgress(for: sprint), "30%")
    }

    func testStatusLabel_active() {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let sprint = createSprint(name: "Active", startDate: start, endDate: end)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.statusLabel(for: sprint), "Active")
    }

    func testStatusLabel_completed() {
        let start = Calendar.current.date(byAdding: .day, value: -21, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let sprint = createSprint(name: "Completed", startDate: start, endDate: end)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.statusLabel(for: sprint), "Completed")
    }

    func testStatusLabel_upcoming() {
        let start = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let end = Calendar.current.date(byAdding: .day, value: 21, to: Date())!
        let sprint = createSprint(name: "Upcoming", startDate: start, endDate: end)
        viewModel.refreshSprints()

        XCTAssertEqual(viewModel.statusLabel(for: sprint), "Upcoming")
    }
}
