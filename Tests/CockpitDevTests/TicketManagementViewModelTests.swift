import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class TicketManagementViewModelTests: CockpitDevTestCase {

    private var viewModel: TicketManagementViewModel!
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

        viewModel = TicketManagementViewModel()
        viewModel.configure(modelContext: modelContext, syncEngine: nil, workspace: workspace)
    }

    override func tearDown() async throws {
        viewModel = nil
        modelContext = nil
        container = nil
        workspace = nil
        try await super.tearDown()
    }

    // MARK: - Story Points Validation Tests

    func testValidateStoryPoints_validFibonacciValues() {
        for value in AppConstants.fibonacciSequence {
            XCTAssertNil(viewModel.validateStoryPoints(value), "Value \(value) should be valid")
        }
    }

    func testValidateStoryPoints_allowsPositiveExternalWeights() {
        let externalWeights = [4, 6, 7, 9, 10, 11, 14, 15, 20, 22, 25, 100]
        for value in externalWeights {
            XCTAssertNil(viewModel.validateStoryPoints(value), "External GitLab weight \(value) should be valid")
        }
    }

    func testValidateStoryPoints_rejectsNonPositiveValues() {
        let invalidValues = [-3, -1, 0]
        for value in invalidValues {
            XCTAssertNotNil(viewModel.validateStoryPoints(value), "Value \(value) should be invalid")
        }
    }

    func testValidateStoryPoints_errorMessageExplainsPositiveValues() {
        let error = viewModel.validateStoryPoints(0)
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("positive"))
    }

    // MARK: - Non-Standard SP Indicator Tests

    func testIsNonStandardStoryPoints_standardValues() {
        for value in AppConstants.fibonacciSequence {
            XCTAssertFalse(viewModel.isNonStandardStoryPoints(value), "Value \(value) should be standard")
        }
    }

    func testIsNonStandardStoryPoints_nonStandardValues() {
        let nonStandard = [4, 6, 7, 9, 10, 15, 22, 50]
        for value in nonStandard {
            XCTAssertTrue(viewModel.isNonStandardStoryPoints(value), "Value \(value) should be non-standard")
        }
    }

    // MARK: - Ticket Creation Tests

    func testCreateTicket_success() {
        let result = viewModel.createTicket(
            title: "Test Ticket",
            description: "A test description",
            priority: .medium,
            storyPoints: 5,
            labels: ["bug", "frontend"],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.tickets.count, 1)
        XCTAssertEqual(viewModel.tickets.first?.title, "Test Ticket")
        XCTAssertEqual(viewModel.tickets.first?.descriptionText, "A test description")
        XCTAssertEqual(viewModel.tickets.first?.priority, .medium)
        XCTAssertEqual(viewModel.tickets.first?.storyPoints, 5)
        XCTAssertEqual(viewModel.tickets.first?.labels, ["bug", "frontend"])
        XCTAssertEqual(viewModel.tickets.first?.status, .backlog)
        XCTAssertEqual(viewModel.tickets.first?.localVersion, 1)
    }

    func testCreateTicketAssignsDefaultSprint() {
        let sprint = Sprint(name: "Sprint 1", startDate: Date(), endDate: Date().addingTimeInterval(86_400))
        sprint.workspace = workspace
        workspace.sprints.append(sprint)
        modelContext.insert(sprint)

        let result = viewModel.createTicket(
            title: "Sprint ticket",
            description: nil,
            priority: nil,
            storyPoints: 3,
            labels: [],
            assignee: nil,
            sprint: sprint,
            startDate: nil,
            endDate: nil
        )

        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.tickets.first?.sprint?.id, sprint.id)
        XCTAssertTrue(sprint.tickets.contains { $0.title == "Sprint ticket" })
    }

    func testCreateTicket_emptyTitle_fails() {
        let result = viewModel.createTicket(
            title: "",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.tickets.count, 0)
        XCTAssertTrue(viewModel.showError)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testCreateTicket_whitespaceOnlyTitle_fails() {
        let result = viewModel.createTicket(
            title: "   ",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.tickets.count, 0)
    }

    func testCreateTicket_nonPositiveStoryPoints_fails() {
        let result = viewModel.createTicket(
            title: "Test Ticket",
            description: nil,
            priority: nil,
            storyPoints: 0,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.tickets.count, 0)
        XCTAssertTrue(viewModel.showError)
    }

    func testCreateTicket_nilStoryPoints_succeeds() {
        let result = viewModel.createTicket(
            title: "No SP Ticket",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.tickets.count, 1)
        XCTAssertNil(viewModel.tickets.first?.storyPoints)
    }

    func testCreateTicket_trimsTitleWhitespace() {
        let result = viewModel.createTicket(
            title: "  Trimmed Title  ",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.tickets.first?.title, "Trimmed Title")
    }

    func testCreateTicket_withAssignee() {
        let member = Member(gitlabUserId: 1, username: "dev1", displayName: "Developer One")
        member.workspace = workspace
        modelContext.insert(member)
        try? modelContext.save()

        let result = viewModel.createTicket(
            title: "Assigned Ticket",
            description: nil,
            priority: .high,
            storyPoints: 8,
            labels: [],
            assignee: member,
            startDate: nil,
            endDate: nil
        )

        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.tickets.first?.assignee?.username, "dev1")
    }

    func testCreateTicket_withDates() {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!

        let result = viewModel.createTicket(
            title: "Dated Ticket",
            description: nil,
            priority: nil,
            storyPoints: 3,
            labels: [],
            assignee: nil,
            startDate: start,
            endDate: end
        )

        XCTAssertTrue(result)
        XCTAssertNotNil(viewModel.tickets.first?.startDate)
        XCTAssertNotNil(viewModel.tickets.first?.endDate)
    }

    // MARK: - Ticket Update Tests

    func testUpdateTicket_title() {
        _ = viewModel.createTicket(
            title: "Original",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        guard let ticket = viewModel.tickets.first else {
            XCTFail("Ticket should exist")
            return
        }

        viewModel.updateTicket(ticket, title: "Updated Title")

        XCTAssertEqual(ticket.title, "Updated Title")
        XCTAssertEqual(ticket.localVersion, 2)
    }

    func testUpdateTicket_invalidStoryPoints_showsError() {
        _ = viewModel.createTicket(
            title: "Test",
            description: nil,
            priority: nil,
            storyPoints: 5,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        guard let ticket = viewModel.tickets.first else {
            XCTFail("Ticket should exist")
            return
        }

        viewModel.updateTicket(ticket, storyPoints: 25)

        XCTAssertEqual(ticket.storyPoints, 25)
        XCTAssertFalse(viewModel.showError)
    }

    func testUpdateTicket_emptyTitle_showsError() {
        _ = viewModel.createTicket(
            title: "Test",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        guard let ticket = viewModel.tickets.first else {
            XCTFail("Ticket should exist")
            return
        }

        viewModel.updateTicket(ticket, title: "   ")

        XCTAssertEqual(ticket.title, "Test") // Unchanged
        XCTAssertTrue(viewModel.showError)
    }

    func testUpdateTicket_clearStoryPoints() {
        _ = viewModel.createTicket(
            title: "Test",
            description: nil,
            priority: nil,
            storyPoints: 8,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        guard let ticket = viewModel.tickets.first else {
            XCTFail("Ticket should exist")
            return
        }

        viewModel.updateTicket(ticket, clearStoryPoints: true)

        XCTAssertNil(ticket.storyPoints)
    }

    func testUpdateTicket_statusChange() {
        _ = viewModel.createTicket(
            title: "Test",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        guard let ticket = viewModel.tickets.first else {
            XCTFail("Ticket should exist")
            return
        }

        viewModel.updateTicket(ticket, status: .inProgress)

        XCTAssertEqual(ticket.status, .inProgress)
    }

    // MARK: - Deletion Tests

    func testConfirmDeletion_localOnlyTicket_showsDeleteConfirmation() {
        _ = viewModel.createTicket(
            title: "Local Only",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        guard let ticket = viewModel.tickets.first else {
            XCTFail("Ticket should exist")
            return
        }

        viewModel.confirmDeletion(of: ticket)

        XCTAssertTrue(viewModel.showDeleteConfirmation)
        XCTAssertFalse(viewModel.showCloseGitLabPrompt)
    }

    func testConfirmDeletion_gitlabTicket_showsClosePrompt() {
        let ticket = Ticket(
            gitlabIssueId: 123,
            gitlabIssueIid: 45,
            title: "GitLab Ticket"
        )
        ticket.workspace = workspace
        modelContext.insert(ticket)
        try? modelContext.save()
        viewModel.fetchTickets()

        viewModel.confirmDeletion(of: ticket)

        XCTAssertTrue(viewModel.showCloseGitLabPrompt)
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    func testExecuteDeletion_removesTicket() {
        _ = viewModel.createTicket(
            title: "To Delete",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        guard let ticket = viewModel.tickets.first else {
            XCTFail("Ticket should exist")
            return
        }

        viewModel.ticketPendingDeletion = ticket
        viewModel.executeDeletion(closeOnGitLab: false)

        XCTAssertEqual(viewModel.tickets.count, 0)
    }

    // MARK: - Conflict Resolution Tests

    func testResolveConflict_keepLocal() {
        let ticket = Ticket(title: "Local Version", status: .inProgress)
        ticket.workspace = workspace
        modelContext.insert(ticket)
        try? modelContext.save()

        let remoteSnapshot = TicketSnapshot(
            title: "Remote Version",
            status: .done,
            storyPoints: 5,
            updatedAt: Date()
        )

        viewModel.conflictTicket = ticket
        viewModel.conflictLocal = TicketSnapshot(from: ticket)
        viewModel.conflictRemote = remoteSnapshot

        viewModel.resolveConflict(keepLocal: true)

        // Local version should be preserved
        XCTAssertEqual(ticket.title, "Local Version")
        XCTAssertEqual(ticket.status, .inProgress)
        XCTAssertNil(viewModel.conflictTicket)
    }

    func testResolveConflict_keepRemote() {
        let ticket = Ticket(title: "Local Version", status: .inProgress)
        ticket.workspace = workspace
        modelContext.insert(ticket)
        try? modelContext.save()

        let remoteSnapshot = TicketSnapshot(
            title: "Remote Version",
            status: .done,
            storyPoints: 5,
            labels: ["updated"],
            updatedAt: Date()
        )

        viewModel.conflictTicket = ticket
        viewModel.conflictLocal = TicketSnapshot(from: ticket)
        viewModel.conflictRemote = remoteSnapshot

        viewModel.resolveConflict(keepLocal: false)

        // Remote version should be applied
        XCTAssertEqual(ticket.title, "Remote Version")
        XCTAssertEqual(ticket.status, .done)
        XCTAssertEqual(ticket.storyPoints, 5)
        XCTAssertEqual(ticket.labels, ["updated"])
        XCTAssertNil(viewModel.conflictTicket)
    }

    // MARK: - All Fibonacci Values Tests

    func testCreateTicket_allFibonacciValues_succeed() {
        for (index, sp) in AppConstants.fibonacciSequence.enumerated() {
            let result = viewModel.createTicket(
                title: "Ticket \(index)",
                description: nil,
                priority: nil,
                storyPoints: sp,
                labels: [],
                assignee: nil,
                startDate: nil,
                endDate: nil
            )
            XCTAssertTrue(result, "Creating ticket with SP=\(sp) should succeed")
        }

        XCTAssertEqual(viewModel.tickets.count, AppConstants.fibonacciSequence.count)
    }

    // MARK: - Workspace Association Tests

    func testCreateTicket_associatesWithWorkspace() {
        _ = viewModel.createTicket(
            title: "Workspace Ticket",
            description: nil,
            priority: nil,
            storyPoints: nil,
            labels: [],
            assignee: nil,
            startDate: nil,
            endDate: nil
        )

        XCTAssertEqual(viewModel.tickets.first?.workspace?.id, workspace.id)
    }
}
