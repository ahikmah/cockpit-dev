import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class TicketListViewModelTests: CockpitDevTestCase {
    private var container: ModelContainer!
    private var modelContext: ModelContext!
    private var workspace: Workspace!
    private var viewModel: TicketListViewModel!

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

        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        modelContext = container.mainContext
        workspace = Workspace(name: "Tickets Workspace")
        modelContext.insert(workspace)
        try modelContext.save()
        viewModel = TicketListViewModel(workspace: workspace)
    }

    override func tearDown() async throws {
        viewModel = nil
        workspace = nil
        modelContext = nil
        container = nil
        try await super.tearDown()
    }

    func testFilteredTicketsFilterBySprintStatusAndSearch() {
        let sprint = createSprint(name: "Milestone 1", dayOffset: 0)
        _ = createTicket(title: "CYINT84-001 API Parser", status: .done, sprint: sprint, labels: ["backend"])
        _ = createTicket(title: "CYINT84-002 Frontend", status: .todo, sprint: sprint, labels: ["frontend"])
        _ = createTicket(title: "CYINT84-003 Other", status: .done, sprint: nil, labels: ["backend"])

        viewModel.selectedSprint = sprint
        viewModel.selectedStatus = .done
        viewModel.searchText = "parser"

        XCTAssertEqual(viewModel.filteredTickets.map(\.title), ["CYINT84-001 API Parser"])
    }

    func testPlanningSortUsesSprintDateThenTicketDateThenIssueIid() {
        let laterSprint = createSprint(name: "Later", dayOffset: 7)
        let earlierSprint = createSprint(name: "Earlier", dayOffset: 0)
        let later = createTicket(title: "Later Sprint", sprint: laterSprint, startOffset: 1, iid: 1)
        let higherIid = createTicket(title: "Higher IID", sprint: earlierSprint, startOffset: 1, iid: 20)
        let lowerIid = createTicket(title: "Lower IID", sprint: earlierSprint, startOffset: 1, iid: 2)
        let noSprint = createTicket(title: "No Sprint", sprint: nil, startOffset: 0, iid: 0)

        viewModel.sort = .planning

        XCTAssertEqual(viewModel.filteredTickets.map(\.id), [
            lowerIid.id,
            higherIid.id,
            later.id,
            noSprint.id
        ])
    }

    private func createSprint(name: String, dayOffset: Int) -> Sprint {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
        let end = calendar.date(byAdding: .day, value: dayOffset + 5, to: start)!
        let sprint = Sprint(name: name, startDate: start, endDate: end)
        sprint.workspace = workspace
        workspace.sprints.append(sprint)
        modelContext.insert(sprint)
        try? modelContext.save()
        return sprint
    }

    private func createTicket(
        title: String,
        status: TicketStatus = .backlog,
        sprint: Sprint?,
        labels: [String] = [],
        startOffset: Int = 0,
        iid: Int? = nil
    ) -> Ticket {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: startOffset, to: calendar.startOfDay(for: Date()))
        let end = start.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        let ticket = Ticket(
            gitlabIssueIid: iid,
            title: title,
            status: status,
            startDate: start,
            endDate: end,
            labels: labels
        )
        ticket.workspace = workspace
        ticket.sprint = sprint
        sprint?.tickets.append(ticket)
        modelContext.insert(ticket)
        try? modelContext.save()
        return ticket
    }
}
