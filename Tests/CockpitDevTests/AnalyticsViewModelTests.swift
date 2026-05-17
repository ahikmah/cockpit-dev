import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class AnalyticsViewModelTests: XCTestCase {

    private var viewModel: AnalyticsViewModel!
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

        viewModel = AnalyticsViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        modelContext = nil
        container = nil
        workspace = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

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

    private func createMember(
        displayName: String,
        username: String,
        gitlabUserId: Int = Int.random(in: 1...10000)
    ) -> Member {
        let member = Member(gitlabUserId: gitlabUserId, username: username, displayName: displayName)
        member.workspace = workspace
        workspace.members.append(member)
        modelContext.insert(member)
        try? modelContext.save()
        return member
    }

    private func createTicket(
        title: String,
        status: TicketStatus = .backlog,
        storyPoints: Int? = nil,
        assignee: Member? = nil,
        sprint: Sprint? = nil,
        startDate: Date? = nil,
        updatedAt: Date = Date(),
        labels: [String] = []
    ) -> Ticket {
        let ticket = Ticket(
            title: title,
            status: status,
            storyPoints: storyPoints,
            startDate: startDate,
            labels: labels,
            updatedAt: updatedAt
        )
        ticket.workspace = workspace
        ticket.assignee = assignee
        ticket.sprint = sprint
        if let sprint = sprint {
            sprint.tickets.append(ticket)
        }
        workspace.tickets.append(ticket)
        modelContext.insert(ticket)
        try? modelContext.save()
        return ticket
    }

    private func createMergeRequest(
        authorUsername: String,
        state: MRState = .merged,
        repository: Repository? = nil
    ) -> MergeRequestEntry {
        let mr = MergeRequestEntry(
            gitlabMrId: Int.random(in: 1...10000),
            gitlabMrIid: Int.random(in: 1...10000),
            title: "MR by \(authorUsername)",
            authorUsername: authorUsername,
            sourceBranch: "feature",
            targetBranch: "main",
            state: state
        )
        mr.repository = repository
        modelContext.insert(mr)
        try? modelContext.save()
        return mr
    }

    private func createRepository(name: String) -> Repository {
        let repo = Repository(gitlabProjectId: Int.random(in: 1...10000), name: name, url: "https://gitlab.com/test/\(name)")
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()
        return repo
    }

    // MARK: - Empty State Tests

    func testEmptyWorkspace_hasNoData() {
        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertFalse(viewModel.hasData)
        XCTAssertTrue(viewModel.velocityData.isEmpty)
        XCTAssertTrue(viewModel.workloadData.isEmpty)
        XCTAssertTrue(viewModel.throughputData.isEmpty)
        XCTAssertTrue(viewModel.cycleTimeData.isEmpty)
        XCTAssertTrue(viewModel.contributionData.isEmpty)
    }

    // MARK: - Velocity Tests

    func testVelocity_completedSPPerSprint() {
        let sprint1 = createSprint(name: "Sprint 1", startDate: Date().addingTimeInterval(-86400 * 28))
        let sprint2 = createSprint(name: "Sprint 2", startDate: Date().addingTimeInterval(-86400 * 14))

        _ = createTicket(title: "T1", status: .done, storyPoints: 5, sprint: sprint1)
        _ = createTicket(title: "T2", status: .done, storyPoints: 8, sprint: sprint1)
        _ = createTicket(title: "T3", status: .inProgress, storyPoints: 3, sprint: sprint1)
        _ = createTicket(title: "T4", status: .done, storyPoints: 13, sprint: sprint2)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.velocityData.count, 2)
        XCTAssertEqual(viewModel.velocityData[0].sprintName, "Sprint 1")
        XCTAssertEqual(viewModel.velocityData[0].completedStoryPoints, 13) // 5 + 8
        XCTAssertEqual(viewModel.velocityData[1].sprintName, "Sprint 2")
        XCTAssertEqual(viewModel.velocityData[1].completedStoryPoints, 13)
    }

    func testVelocity_limitsTo12Sprints() {
        for i in 1...15 {
            let start = Date().addingTimeInterval(-86400 * Double(15 - i) * 14)
            let sprint = createSprint(name: "Sprint \(i)", startDate: start)
            _ = createTicket(title: "T\(i)", status: .done, storyPoints: 5, sprint: sprint)
        }

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.velocityData.count, 12)
    }

    func testVelocity_excludesNonDoneTickets() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "Done", status: .done, storyPoints: 5, sprint: sprint)
        _ = createTicket(title: "InProgress", status: .inProgress, storyPoints: 8, sprint: sprint)
        _ = createTicket(title: "Backlog", status: .backlog, storyPoints: 3, sprint: sprint)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.velocityData.first?.completedStoryPoints, 5)
    }

    // MARK: - Workload Distribution Tests

    func testWorkloadDistribution_assignedSPPerMember() {
        let member1 = createMember(displayName: "Alice", username: "alice")
        let member2 = createMember(displayName: "Bob", username: "bob")

        let now = Date()
        let sprint = createSprint(
            name: "Current Sprint",
            startDate: now.addingTimeInterval(-86400 * 7),
            endDate: now.addingTimeInterval(86400 * 7)
        )

        _ = createTicket(title: "T1", status: .inProgress, storyPoints: 8, assignee: member1, sprint: sprint)
        _ = createTicket(title: "T2", status: .todo, storyPoints: 5, assignee: member1, sprint: sprint)
        _ = createTicket(title: "T3", status: .inProgress, storyPoints: 13, assignee: member2, sprint: sprint)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.workloadData.count, 2)
        // Sorted by SP descending
        XCTAssertEqual(viewModel.workloadData[0].member.username, "alice")
        XCTAssertEqual(viewModel.workloadData[0].assignedStoryPoints, 13) // 8 + 5
        XCTAssertEqual(viewModel.workloadData[1].member.username, "bob")
        XCTAssertEqual(viewModel.workloadData[1].assignedStoryPoints, 13)
    }

    func testWorkloadDistribution_overloadIndicator() {
        let member = createMember(displayName: "Alice", username: "alice")

        let now = Date()
        let sprint = createSprint(
            name: "Current Sprint",
            startDate: now.addingTimeInterval(-86400 * 7),
            endDate: now.addingTimeInterval(86400 * 7)
        )

        // Assign 22 SP (exceeds default threshold of 21)
        _ = createTicket(title: "T1", status: .inProgress, storyPoints: 13, assignee: member, sprint: sprint)
        _ = createTicket(title: "T2", status: .todo, storyPoints: 8, assignee: member, sprint: sprint)
        _ = createTicket(title: "T3", status: .backlog, storyPoints: 1, assignee: member, sprint: sprint)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.workloadData.count, 1)
        XCTAssertEqual(viewModel.workloadData[0].assignedStoryPoints, 22)
        XCTAssertTrue(viewModel.workloadData[0].isOverloaded)
    }

    func testWorkloadDistribution_notOverloaded() {
        let member = createMember(displayName: "Alice", username: "alice")

        let now = Date()
        let sprint = createSprint(
            name: "Current Sprint",
            startDate: now.addingTimeInterval(-86400 * 7),
            endDate: now.addingTimeInterval(86400 * 7)
        )

        _ = createTicket(title: "T1", status: .inProgress, storyPoints: 13, assignee: member, sprint: sprint)
        _ = createTicket(title: "T2", status: .todo, storyPoints: 5, assignee: member, sprint: sprint)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.workloadData[0].assignedStoryPoints, 18)
        XCTAssertFalse(viewModel.workloadData[0].isOverloaded)
    }

    // MARK: - Cycle Time Tests

    func testCycleTime_computesAverageDays() {
        let member = createMember(displayName: "Alice", username: "alice")

        let startDate1 = Date().addingTimeInterval(-86400 * 10) // 10 days ago
        let updatedAt1 = Date().addingTimeInterval(-86400 * 5)  // 5 days ago (5 day cycle)

        let startDate2 = Date().addingTimeInterval(-86400 * 8)  // 8 days ago
        let updatedAt2 = Date().addingTimeInterval(-86400 * 5)  // 5 days ago (3 day cycle)

        _ = createTicket(title: "T1", status: .done, storyPoints: 5, assignee: member, startDate: startDate1, updatedAt: updatedAt1)
        _ = createTicket(title: "T2", status: .done, storyPoints: 3, assignee: member, startDate: startDate2, updatedAt: updatedAt2)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.cycleTimeData.count, 1)
        XCTAssertEqual(viewModel.cycleTimeData[0].label, "Alice")
        // Average of 5 and 3 = 4 days
        XCTAssertEqual(viewModel.cycleTimeData[0].averageDays, 4.0, accuracy: 0.1)
    }

    func testCycleTime_workspaceAverage() {
        let member1 = createMember(displayName: "Alice", username: "alice")
        let member2 = createMember(displayName: "Bob", username: "bob")

        let startDate1 = Date().addingTimeInterval(-86400 * 6)
        let updatedAt1 = Date() // 6 day cycle

        let startDate2 = Date().addingTimeInterval(-86400 * 4)
        let updatedAt2 = Date() // 4 day cycle

        _ = createTicket(title: "T1", status: .done, storyPoints: 5, assignee: member1, startDate: startDate1, updatedAt: updatedAt1)
        _ = createTicket(title: "T2", status: .done, storyPoints: 3, assignee: member2, startDate: startDate2, updatedAt: updatedAt2)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        // Workspace average: (6 + 4) / 2 = 5 days
        XCTAssertEqual(viewModel.workspaceCycleTime, 5.0, accuracy: 0.1)
    }

    // MARK: - Throughput Tests

    func testThroughput_ticketsCompletedPerSprint() {
        let sprint1 = createSprint(name: "Sprint 1", startDate: Date().addingTimeInterval(-86400 * 28))
        let sprint2 = createSprint(name: "Sprint 2", startDate: Date().addingTimeInterval(-86400 * 14))

        _ = createTicket(title: "T1", status: .done, storyPoints: 5, sprint: sprint1)
        _ = createTicket(title: "T2", status: .done, storyPoints: 3, sprint: sprint1)
        _ = createTicket(title: "T3", status: .inProgress, storyPoints: 8, sprint: sprint1)
        _ = createTicket(title: "T4", status: .done, storyPoints: 13, sprint: sprint2)
        _ = createTicket(title: "T5", status: .done, storyPoints: 5, sprint: sprint2)
        _ = createTicket(title: "T6", status: .done, storyPoints: 2, sprint: sprint2)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.throughputData.count, 2)
        XCTAssertEqual(viewModel.throughputData[0].ticketsCompleted, 2) // Sprint 1: 2 done
        XCTAssertEqual(viewModel.throughputData[1].ticketsCompleted, 3) // Sprint 2: 3 done
    }

    func testThroughput_limitsTo12Sprints() {
        for i in 1...15 {
            let start = Date().addingTimeInterval(-86400 * Double(15 - i) * 14)
            let sprint = createSprint(name: "Sprint \(i)", startDate: start)
            _ = createTicket(title: "T\(i)", status: .done, storyPoints: 5, sprint: sprint)
        }

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.throughputData.count, 12)
    }

    // MARK: - Individual Contributions Tests

    func testContributions_ticketsCompleted() {
        let member1 = createMember(displayName: "Alice", username: "alice")
        let member2 = createMember(displayName: "Bob", username: "bob")

        _ = createTicket(title: "T1", status: .done, storyPoints: 5, assignee: member1)
        _ = createTicket(title: "T2", status: .done, storyPoints: 3, assignee: member1)
        _ = createTicket(title: "T3", status: .done, storyPoints: 8, assignee: member2)
        _ = createTicket(title: "T4", status: .inProgress, storyPoints: 5, assignee: member2)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        // Sorted by tickets completed descending
        XCTAssertEqual(viewModel.contributionData.count, 2)
        XCTAssertEqual(viewModel.contributionData[0].member.username, "alice")
        XCTAssertEqual(viewModel.contributionData[0].ticketsCompleted, 2)
        XCTAssertEqual(viewModel.contributionData[1].member.username, "bob")
        XCTAssertEqual(viewModel.contributionData[1].ticketsCompleted, 1)
    }

    func testContributions_mergeRequestsMerged() {
        let member = createMember(displayName: "Alice", username: "alice")
        let repo = createRepository(name: "backend")

        _ = createMergeRequest(authorUsername: "alice", state: .merged, repository: repo)
        _ = createMergeRequest(authorUsername: "alice", state: .merged, repository: repo)
        _ = createMergeRequest(authorUsername: "alice", state: .opened, repository: repo)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        let aliceData = viewModel.contributionData.first { $0.member.username == "alice" }
        XCTAssertNotNil(aliceData)
        XCTAssertEqual(aliceData?.mergeRequestsMerged, 2)
    }

    // MARK: - Filter Tests

    func testFilter_byMember() {
        let member1 = createMember(displayName: "Alice", username: "alice")
        let member2 = createMember(displayName: "Bob", username: "bob")

        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "T1", status: .done, storyPoints: 5, assignee: member1, sprint: sprint)
        _ = createTicket(title: "T2", status: .done, storyPoints: 8, assignee: member2, sprint: sprint)

        viewModel.configure(workspace: workspace, modelContext: modelContext)
        viewModel.filter.selectedMember = member1
        viewModel.applyFilters()

        // Velocity should only count member1's tickets
        XCTAssertEqual(viewModel.velocityData.first?.completedStoryPoints, 5)
    }

    func testFilter_byLabel() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "T1", status: .done, storyPoints: 5, sprint: sprint, labels: ["backend"])
        _ = createTicket(title: "T2", status: .done, storyPoints: 8, sprint: sprint, labels: ["frontend"])

        viewModel.configure(workspace: workspace, modelContext: modelContext)
        viewModel.filter.selectedLabel = "backend"
        viewModel.applyFilters()

        XCTAssertEqual(viewModel.velocityData.first?.completedStoryPoints, 5)
    }

    func testFilter_bySprintRange() {
        let sprint1 = createSprint(name: "Sprint 1", startDate: Date().addingTimeInterval(-86400 * 42))
        let sprint2 = createSprint(name: "Sprint 2", startDate: Date().addingTimeInterval(-86400 * 28))
        let sprint3 = createSprint(name: "Sprint 3", startDate: Date().addingTimeInterval(-86400 * 14))

        _ = createTicket(title: "T1", status: .done, storyPoints: 5, sprint: sprint1)
        _ = createTicket(title: "T2", status: .done, storyPoints: 8, sprint: sprint2)
        _ = createTicket(title: "T3", status: .done, storyPoints: 13, sprint: sprint3)

        viewModel.configure(workspace: workspace, modelContext: modelContext)
        viewModel.filter.startSprint = sprint2
        viewModel.filter.endSprint = sprint3
        viewModel.applyFilters()

        // Should only include Sprint 2 and Sprint 3
        XCTAssertEqual(viewModel.velocityData.count, 2)
        XCTAssertEqual(viewModel.velocityData[0].sprintName, "Sprint 2")
        XCTAssertEqual(viewModel.velocityData[1].sprintName, "Sprint 3")
    }

    // MARK: - Available Options Tests

    func testAvailableSprints_sortedByStartDate() {
        _ = createSprint(name: "Sprint C", startDate: Date().addingTimeInterval(86400 * 14))
        _ = createSprint(name: "Sprint A", startDate: Date().addingTimeInterval(-86400 * 14))
        _ = createSprint(name: "Sprint B", startDate: Date())

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.availableSprints[0].name, "Sprint A")
        XCTAssertEqual(viewModel.availableSprints[1].name, "Sprint B")
        XCTAssertEqual(viewModel.availableSprints[2].name, "Sprint C")
    }

    func testAvailableLabels_collectsUniqueLabels() {
        _ = createTicket(title: "T1", labels: ["backend", "urgent"])
        _ = createTicket(title: "T2", labels: ["frontend", "urgent"])
        _ = createTicket(title: "T3", labels: ["backend"])

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertEqual(viewModel.availableLabels.count, 3)
        XCTAssertTrue(viewModel.availableLabels.contains("backend"))
        XCTAssertTrue(viewModel.availableLabels.contains("frontend"))
        XCTAssertTrue(viewModel.availableLabels.contains("urgent"))
    }

    func testHasData_trueWhenVelocityExists() {
        let sprint = createSprint(name: "Sprint 1")
        _ = createTicket(title: "T1", status: .done, storyPoints: 5, sprint: sprint)

        viewModel.configure(workspace: workspace, modelContext: modelContext)

        XCTAssertTrue(viewModel.hasData)
    }
}
