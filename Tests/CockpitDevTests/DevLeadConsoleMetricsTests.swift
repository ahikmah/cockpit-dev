import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class DevLeadConsoleMetricsTests: CockpitDevTestCase {

    private var container: ModelContainer!
    private var modelContext: ModelContext!
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

        workspace = Workspace(name: "Dev Lead Workspace", maxStoryPointsThreshold: 13)
        modelContext.insert(workspace)
    }

    override func tearDown() async throws {
        workspace = nil
        modelContext = nil
        container = nil
        try await super.tearDown()
    }

    func testMetricsSummarizeDevLeadRiskSignals() {
        let now = Date()
        let sprint = Sprint(
            name: "Current Sprint",
            startDate: now.addingTimeInterval(-86_400),
            endDate: now.addingTimeInterval(86_400 * 6)
        )
        sprint.workspace = workspace
        workspace.sprints.append(sprint)
        modelContext.insert(sprint)

        let overloadedMember = Member(gitlabUserId: 1, username: "maya", displayName: "Maya")
        overloadedMember.workspace = workspace
        workspace.members.append(overloadedMember)
        modelContext.insert(overloadedMember)

        let doneBlocker = Ticket(title: "Completed blocker", status: .done, storyPoints: 3)
        let activeBlocker = Ticket(title: "Active blocker", status: .inProgress, storyPoints: 5)
        let blockedTicket = Ticket(title: "Blocked checkout", status: .inProgress, storyPoints: 8)
        blockedTicket.blockedBy = [activeBlocker, doneBlocker]
        let completedTicket = Ticket(title: "Done task", status: .done, storyPoints: 5)
        let overloadedTicket = Ticket(title: "Large implementation", status: .todo, storyPoints: 14)
        overloadedTicket.assignee = overloadedMember
        overloadedTicket.sprint = sprint

        for ticket in [doneBlocker, activeBlocker, blockedTicket, completedTicket, overloadedTicket] {
            ticket.workspace = workspace
            ticket.sprint = sprint
            sprint.tickets.append(ticket)
            workspace.tickets.append(ticket)
            modelContext.insert(ticket)
        }

        let freshMR = MergeRequestEntry(
            gitlabMrId: 1,
            gitlabMrIid: 1,
            title: "Fresh MR",
            authorUsername: "alice",
            sourceBranch: "feature/a",
            targetBranch: "main",
            state: .opened,
            updatedAt: now
        )
        let staleMR = MergeRequestEntry(
            gitlabMrId: 2,
            gitlabMrIid: 2,
            title: "Stale MR",
            authorUsername: "raka",
            sourceBranch: "feature/b",
            targetBranch: "main",
            state: .opened,
            updatedAt: now.addingTimeInterval(-86_400 * 3)
        )
        let repo = Repository(gitlabProjectId: 1, name: "ios-app", url: "https://gitlab.com/example/ios-app")
        repo.workspace = workspace
        workspace.repositories.append(repo)
        freshMR.repository = repo
        staleMR.repository = repo
        modelContext.insert(repo)
        modelContext.insert(freshMR)
        modelContext.insert(staleMR)

        let metrics = DevLeadConsoleMetrics(workspace: workspace, mergeRequests: [freshMR, staleMR], now: now)

        XCTAssertEqual(metrics.openTicketCount, 3)
        XCTAssertEqual(metrics.blockedTicketCount, 1)
        XCTAssertEqual(metrics.staleMergeRequestCount, 1)
        XCTAssertEqual(metrics.overloadedMemberCount, 1)
        XCTAssertEqual(metrics.sprintProgressPercent, 23)
        XCTAssertEqual(metrics.attentionItems.count, 2)
        XCTAssertEqual(metrics.attentionItems.first?.title, "Blocked checkout")
    }

    func testMetricsUseLatestSprintWithTicketsWhenNoSprintIsDateActive() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let olderSprint = Sprint(
            name: "Older Sprint",
            startDate: now.addingTimeInterval(-86_400 * 30),
            endDate: now.addingTimeInterval(-86_400 * 20)
        )
        let latestSprint = Sprint(
            name: "Latest Synced Sprint",
            startDate: now.addingTimeInterval(-86_400 * 12),
            endDate: now.addingTimeInterval(-86_400 * 6)
        )

        for sprint in [olderSprint, latestSprint] {
            sprint.workspace = workspace
            workspace.sprints.append(sprint)
            modelContext.insert(sprint)
        }

        let member = Member(gitlabUserId: 1, username: "rico", displayName: "Rico")
        member.workspace = workspace
        workspace.members.append(member)
        modelContext.insert(member)

        let oldTicket = Ticket(title: "Old completed task", status: .done, storyPoints: 3)
        oldTicket.workspace = workspace
        oldTicket.sprint = olderSprint
        olderSprint.tickets.append(oldTicket)
        workspace.tickets.append(oldTicket)
        modelContext.insert(oldTicket)

        let openTicket = Ticket(title: "Synced planning task", status: .inProgress, storyPoints: 8)
        let doneTicket = Ticket(title: "Synced completed task", status: .done, storyPoints: 4)
        for ticket in [openTicket, doneTicket] {
            ticket.workspace = workspace
            ticket.sprint = latestSprint
            ticket.assignee = member
            latestSprint.tickets.append(ticket)
            workspace.tickets.append(ticket)
            modelContext.insert(ticket)
        }

        let metrics = DevLeadConsoleMetrics(workspace: workspace, now: now)

        XCTAssertEqual(metrics.focusSprintName, "Latest Synced Sprint")
        XCTAssertEqual(metrics.sprintProgressPercent, 33)
        XCTAssertEqual(metrics.ownerLoadRows, [
            .init(
                id: member.id,
                memberName: "Rico",
                storyPoints: 12,
                ratio: 12.0 / 13.0,
                isOverloaded: false
            )
        ])
    }
}
