import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class KanbanViewModelTests: CockpitDevTestCase {

    private var viewModel: KanbanViewModel!
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

        viewModel = KanbanViewModel(workspace: workspace, syncEngine: nil, modelContext: modelContext)
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
        labels: [String] = [],
        assignee: Member? = nil,
        sprint: Sprint? = nil
    ) -> Ticket {
        let ticket = Ticket(title: title, status: status, storyPoints: storyPoints, labels: labels)
        ticket.workspace = workspace
        ticket.assignee = assignee
        ticket.sprint = sprint
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

    private func createSprint(name: String) -> Sprint {
        let sprint = Sprint(
            name: name,
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        )
        sprint.workspace = workspace
        modelContext.insert(sprint)
        try? modelContext.save()
        return sprint
    }

    // MARK: - Column Configuration Tests

    func testDefaultColumns() {
        XCTAssertEqual(viewModel.columns, AppConstants.defaultKanbanColumns)
        XCTAssertEqual(viewModel.columns.count, 5)
    }

    func testAddColumn_success() {
        let result = viewModel.addColumn(name: "Testing", currentUserRole: .owner)
        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.columns.count, 6)
        XCTAssertTrue(viewModel.columns.contains("Testing"))
    }

    func testAddColumn_maxLimit() {
        // Add columns up to the max
        for i in 0..<5 {
            _ = viewModel.addColumn(name: "Extra \(i)", currentUserRole: .owner)
        }
        XCTAssertEqual(viewModel.columns.count, 10)

        // Try to add one more
        let result = viewModel.addColumn(name: "Over Limit", currentUserRole: .owner)
        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.columns.count, 10)
        XCTAssertTrue(viewModel.showError)
    }

    func testAddColumn_duplicateName() {
        let result = viewModel.addColumn(name: "Backlog", currentUserRole: .owner)
        XCTAssertFalse(result)
        XCTAssertTrue(viewModel.showError)
    }

    func testAddColumn_emptyName() {
        let result = viewModel.addColumn(name: "   ", currentUserRole: .owner)
        XCTAssertFalse(result)
        XCTAssertTrue(viewModel.showError)
    }

    func testAddColumn_memberRole_denied() {
        let result = viewModel.addColumn(name: "New Column", currentUserRole: .member)
        XCTAssertFalse(result)
        XCTAssertTrue(viewModel.showError)
    }

    func testAddColumn_viewerRole_denied() {
        let result = viewModel.addColumn(name: "New Column", currentUserRole: .viewer)
        XCTAssertFalse(result)
        XCTAssertTrue(viewModel.showError)
    }

    func testAddColumn_adminRole_allowed() {
        let result = viewModel.addColumn(name: "New Column", currentUserRole: .admin)
        XCTAssertTrue(result)
        XCTAssertTrue(viewModel.columns.contains("New Column"))
    }

    func testRemoveColumn_success() {
        let result = viewModel.removeColumn(name: "In Review", currentUserRole: .owner)
        XCTAssertTrue(result)
        XCTAssertFalse(viewModel.columns.contains("In Review"))
        XCTAssertEqual(viewModel.columns.count, 4)
    }

    func testRemoveColumn_lastColumn_denied() {
        // Remove all but one
        _ = viewModel.removeColumn(name: "Backlog", currentUserRole: .owner)
        _ = viewModel.removeColumn(name: "To Do", currentUserRole: .owner)
        _ = viewModel.removeColumn(name: "In Progress", currentUserRole: .owner)
        _ = viewModel.removeColumn(name: "In Review", currentUserRole: .owner)
        XCTAssertEqual(viewModel.columns.count, 1)

        // Try to remove the last one
        let result = viewModel.removeColumn(name: "Done", currentUserRole: .owner)
        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.columns.count, 1)
        XCTAssertTrue(viewModel.showError)
    }

    func testRenameColumn_success() {
        let result = viewModel.renameColumn(oldName: "Backlog", newName: "Icebox", currentUserRole: .owner)
        XCTAssertTrue(result)
        XCTAssertTrue(viewModel.columns.contains("Icebox"))
        XCTAssertFalse(viewModel.columns.contains("Backlog"))
    }

    func testRenameColumn_duplicateName() {
        let result = viewModel.renameColumn(oldName: "Backlog", newName: "Done", currentUserRole: .owner)
        XCTAssertFalse(result)
        XCTAssertTrue(viewModel.showError)
    }

    func testRenameColumn_emptyName() {
        let result = viewModel.renameColumn(oldName: "Backlog", newName: "  ", currentUserRole: .owner)
        XCTAssertFalse(result)
        XCTAssertTrue(viewModel.showError)
    }

    func testReorderColumn() {
        let result = viewModel.reorderColumn(from: IndexSet(integer: 0), to: 3, currentUserRole: .owner)
        XCTAssertTrue(result)
        // "Backlog" should have moved
        XCTAssertNotEqual(viewModel.columns.first, "Backlog")
    }

    // MARK: - Status ↔ Column Mapping Tests

    func testMapStatusToColumn_defaultColumns() {
        XCTAssertEqual(viewModel.mapStatusToColumn(.backlog), "Backlog")
        XCTAssertEqual(viewModel.mapStatusToColumn(.todo), "To Do")
        XCTAssertEqual(viewModel.mapStatusToColumn(.inProgress), "In Progress")
        XCTAssertEqual(viewModel.mapStatusToColumn(.inReview), "In Review")
        XCTAssertEqual(viewModel.mapStatusToColumn(.done), "Done")
    }

    func testMapColumnToStatus() {
        XCTAssertEqual(viewModel.mapColumnToStatus("Backlog"), .backlog)
        XCTAssertEqual(viewModel.mapColumnToStatus("To Do"), .todo)
        XCTAssertEqual(viewModel.mapColumnToStatus("In Progress"), .inProgress)
        XCTAssertEqual(viewModel.mapColumnToStatus("In Review"), .inReview)
        XCTAssertEqual(viewModel.mapColumnToStatus("Done"), .done)
    }

    func testMapColumnToStatus_caseInsensitive() {
        XCTAssertEqual(viewModel.mapColumnToStatus("in progress"), .inProgress)
        XCTAssertEqual(viewModel.mapColumnToStatus("IN REVIEW"), .inReview)
        XCTAssertEqual(viewModel.mapColumnToStatus("DONE"), .done)
    }

    func testMapColumnToStatus_unknownColumn_defaultsToBacklog() {
        XCTAssertEqual(viewModel.mapColumnToStatus("Unknown Column"), .backlog)
        XCTAssertEqual(viewModel.mapColumnToStatus("Custom"), .backlog)
    }

    // MARK: - Card Ordering Tests

    func testCardOrdering_spDescending() {
        _ = createTicket(title: "Low SP", status: .backlog, storyPoints: 2)
        _ = createTicket(title: "High SP", status: .backlog, storyPoints: 13)
        _ = createTicket(title: "Mid SP", status: .backlog, storyPoints: 5)

        viewModel.refreshBoard()

        let backlogTickets = viewModel.columnTickets["Backlog"] ?? []
        XCTAssertEqual(backlogTickets.count, 3)
        XCTAssertEqual(backlogTickets[0].storyPoints, 13)
        XCTAssertEqual(backlogTickets[1].storyPoints, 5)
        XCTAssertEqual(backlogTickets[2].storyPoints, 2)
    }

    func testCardOrdering_noSpAtBottom() {
        _ = createTicket(title: "With SP", status: .backlog, storyPoints: 5)
        _ = createTicket(title: "No SP", status: .backlog, storyPoints: nil)
        _ = createTicket(title: "Another SP", status: .backlog, storyPoints: 8)

        viewModel.refreshBoard()

        let backlogTickets = viewModel.columnTickets["Backlog"] ?? []
        XCTAssertEqual(backlogTickets.count, 3)
        // SP tickets first (descending), then no-SP
        XCTAssertEqual(backlogTickets[0].storyPoints, 8)
        XCTAssertEqual(backlogTickets[1].storyPoints, 5)
        XCTAssertNil(backlogTickets[2].storyPoints)
    }

    func testCardOrdering_sameSp_alphabetical() {
        _ = createTicket(title: "Zebra", status: .backlog, storyPoints: 5)
        _ = createTicket(title: "Alpha", status: .backlog, storyPoints: 5)

        viewModel.refreshBoard()

        let backlogTickets = viewModel.columnTickets["Backlog"] ?? []
        XCTAssertEqual(backlogTickets[0].title, "Alpha")
        XCTAssertEqual(backlogTickets[1].title, "Zebra")
    }

    // MARK: - Filtering Tests

    func testFilterByAssignee() {
        let member = createMember(username: "dev1", displayName: "Developer One")
        _ = createTicket(title: "Assigned", status: .backlog, assignee: member)
        _ = createTicket(title: "Unassigned", status: .backlog)

        viewModel.filterAssignee = member
        viewModel.refreshBoard()

        let allTickets = viewModel.columnTickets.values.flatMap { $0 }
        XCTAssertEqual(allTickets.count, 1)
        XCTAssertEqual(allTickets.first?.title, "Assigned")
    }

    func testFilterByLabel() {
        _ = createTicket(title: "Bug", status: .backlog, labels: ["bug", "frontend"])
        _ = createTicket(title: "Feature", status: .backlog, labels: ["feature"])

        viewModel.filterLabel = "bug"
        viewModel.refreshBoard()

        let allTickets = viewModel.columnTickets.values.flatMap { $0 }
        XCTAssertEqual(allTickets.count, 1)
        XCTAssertEqual(allTickets.first?.title, "Bug")
    }

    func testFilterBySprint() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "In Sprint", status: .backlog, sprint: sprint)
        _ = createTicket(title: "No Sprint", status: .backlog)

        viewModel.filterSprint = sprint
        viewModel.refreshBoard()

        let allTickets = viewModel.columnTickets.values.flatMap { $0 }
        XCTAssertEqual(allTickets.count, 1)
        XCTAssertEqual(allTickets.first?.title, "In Sprint")
    }

    func testClearFilters() {
        let member = createMember(username: "dev1", displayName: "Developer One")
        _ = createTicket(title: "Ticket 1", status: .backlog, assignee: member)
        _ = createTicket(title: "Ticket 2", status: .backlog)

        viewModel.filterAssignee = member
        viewModel.refreshBoard()
        XCTAssertEqual(viewModel.columnTickets.values.flatMap { $0 }.count, 1)

        viewModel.clearFilters()
        XCTAssertNil(viewModel.filterAssignee)
        XCTAssertNil(viewModel.filterLabel)
        XCTAssertNil(viewModel.filterSprint)
        XCTAssertEqual(viewModel.columnTickets.values.flatMap { $0 }.count, 2)
    }

    // MARK: - Board Refresh Tests

    func testRefreshBoard_ticketsInCorrectColumns() {
        _ = createTicket(title: "Backlog Ticket", status: .backlog)
        _ = createTicket(title: "Todo Ticket", status: .todo)
        _ = createTicket(title: "In Progress Ticket", status: .inProgress)
        _ = createTicket(title: "In Review Ticket", status: .inReview)
        _ = createTicket(title: "Done Ticket", status: .done)

        viewModel.refreshBoard()

        XCTAssertEqual(viewModel.columnTickets["Backlog"]?.count, 1)
        XCTAssertEqual(viewModel.columnTickets["To Do"]?.count, 1)
        XCTAssertEqual(viewModel.columnTickets["In Progress"]?.count, 1)
        XCTAssertEqual(viewModel.columnTickets["In Review"]?.count, 1)
        XCTAssertEqual(viewModel.columnTickets["Done"]?.count, 1)
    }

    func testRefreshBoard_emptyWorkspace() {
        viewModel.refreshBoard()

        for column in viewModel.columns {
            XCTAssertEqual(viewModel.columnTickets[column]?.count ?? 0, 0)
        }
    }

    // MARK: - Drag and Drop Tests

    func testBeginDrag_setsState() {
        let ticket = createTicket(title: "Drag Me", status: .backlog)

        viewModel.beginDrag(ticket: ticket, fromColumn: "Backlog")

        XCTAssertEqual(viewModel.draggingTicket?.id, ticket.id)
        XCTAssertEqual(viewModel.dragSourceColumn, "Backlog")
    }

    func testUpdateDropTarget() {
        viewModel.updateDropTarget("In Progress")
        XCTAssertEqual(viewModel.dropTargetColumn, "In Progress")

        viewModel.updateDropTarget(nil)
        XCTAssertNil(viewModel.dropTargetColumn)
    }

    func testDropTicket_updatesStatus() async {
        let ticket = createTicket(title: "Move Me", status: .backlog)
        viewModel.refreshBoard()

        viewModel.beginDrag(ticket: ticket, fromColumn: "Backlog")
        await viewModel.dropTicket(on: "In Progress")

        XCTAssertEqual(ticket.status, .inProgress)
    }

    func testDropTicket_sameColumn_noChange() async {
        let ticket = createTicket(title: "Stay Here", status: .backlog)
        viewModel.refreshBoard()

        viewModel.beginDrag(ticket: ticket, fromColumn: "Backlog")
        await viewModel.dropTicket(on: "Backlog")

        XCTAssertEqual(ticket.status, .backlog)
    }

    func testDropTicket_resetsDragState() async {
        let ticket = createTicket(title: "Drag Ticket", status: .backlog)
        viewModel.refreshBoard()

        viewModel.beginDrag(ticket: ticket, fromColumn: "Backlog")
        await viewModel.dropTicket(on: "Done")

        XCTAssertNil(viewModel.draggingTicket)
        XCTAssertNil(viewModel.dragSourceColumn)
        XCTAssertNil(viewModel.dropTargetColumn)
    }

    // MARK: - Webhook Status Update Tests

    func testHandleWebhookStatusUpdate() {
        let ticket = createTicket(title: "Webhook Ticket", status: .backlog)
        viewModel.refreshBoard()

        viewModel.handleWebhookStatusUpdate(ticketId: ticket.id, newStatus: .inProgress)

        XCTAssertEqual(ticket.status, .inProgress)
        // Ticket should now be in "In Progress" column
        let inProgressTickets = viewModel.columnTickets["In Progress"] ?? []
        XCTAssertTrue(inProgressTickets.contains(where: { $0.id == ticket.id }))
    }

    func testHandleWebhookStatusUpdate_unknownTicket_noEffect() {
        _ = createTicket(title: "Existing", status: .backlog)
        viewModel.refreshBoard()

        let unknownId = UUID()
        viewModel.handleWebhookStatusUpdate(ticketId: unknownId, newStatus: .done)

        // No crash, no change
        let allTickets = viewModel.columnTickets.values.flatMap { $0 }
        XCTAssertEqual(allTickets.count, 1)
        XCTAssertEqual(allTickets.first?.status, .backlog)
    }

    // MARK: - Permission Tests

    func testCanConfigureColumns_ownerAllowed() {
        XCTAssertTrue(viewModel.canConfigureColumns(currentUserRole: .owner))
    }

    func testCanConfigureColumns_adminAllowed() {
        XCTAssertTrue(viewModel.canConfigureColumns(currentUserRole: .admin))
    }

    func testCanConfigureColumns_memberDenied() {
        XCTAssertFalse(viewModel.canConfigureColumns(currentUserRole: .member))
    }

    func testCanConfigureColumns_viewerDenied() {
        XCTAssertFalse(viewModel.canConfigureColumns(currentUserRole: .viewer))
    }
}
