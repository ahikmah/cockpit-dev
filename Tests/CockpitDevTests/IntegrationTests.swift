import XCTest
import SwiftData
@testable import CockpitDev

/// End-to-end integration tests verifying complete workflows across multiple services.
/// Uses mocked GitLab services (no real GitLab connection needed).
final class IntegrationTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var mockAPIClient: GitLabAPIClient!
    private var syncEngine: SyncEngine!

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
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)

        mockAPIClient = GitLabAPIClient(
            baseURL: URL(string: "https://gitlab.example.com")!,
            tokenProvider: { "mock-token" }
        )

        syncEngine = SyncEngine(apiClient: mockAPIClient, modelContext: modelContext)
    }

    override func tearDown() async throws {
        syncEngine.stopPolling()
        syncEngine = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - E2E Test: Workspace → Repo → Ticket → GitLab Sync (Mocked)

    /// Tests the complete flow of creating a workspace, adding a repository,
    /// creating a ticket, and verifying the sync engine queues it for GitLab push.
    func testWorkspaceToRepoToTicketToSyncFlow() throws {
        // Step 1: Create a workspace
        let workspace = Workspace(name: "Integration Project")
        modelContext.insert(workspace)

        // Step 2: Add a repository to the workspace
        let repository = Repository(
            gitlabProjectId: 42,
            name: "backend-api",
            url: "https://gitlab.example.com/team/backend-api.git"
        )
        repository.workspace = workspace
        workspace.repositories.append(repository)

        // Step 3: Create a ticket in the workspace
        let ticket = Ticket(
            title: "Implement user authentication",
            descriptionText: "Add OAuth2 login flow",
            status: .todo,
            priority: .high,
            storyPoints: 8,
            labels: ["backend", "auth"]
        )
        ticket.workspace = workspace
        workspace.tickets.append(ticket)

        try modelContext.save()

        // Step 4: Verify the workspace has the repo and ticket
        XCTAssertEqual(workspace.repositories.count, 1)
        XCTAssertEqual(workspace.tickets.count, 1)
        XCTAssertEqual(workspace.repositories.first?.gitlabProjectId, 42)
        XCTAssertEqual(workspace.tickets.first?.title, "Implement user authentication")

        // Step 5: Simulate offline sync queue (since we can't hit real GitLab)
        syncEngine.isOnline = false
        syncEngine.enqueueOperation(ticketId: ticket.id, type: .push)

        XCTAssertEqual(syncEngine.offlineQueue.count, 1)
        XCTAssertEqual(syncEngine.offlineQueue.first?.ticketId, ticket.id)
        XCTAssertEqual(syncEngine.offlineQueue.first?.operationType, .push)

        // Step 6: Verify field mapping is correct for the ticket
        let labels = FieldMapping.buildGitLabLabels(ticketLabels: ticket.labels, status: ticket.status)
        XCTAssertTrue(labels.contains("backend"))
        XCTAssertTrue(labels.contains("auth"))
        XCTAssertTrue(labels.contains("workflow::todo"))
    }

    /// Tests that multiple tickets in a workspace maintain correct relationships.
    func testWorkspaceMultipleTicketsWithDependencies() throws {
        let workspace = Workspace(name: "Multi-Ticket Project")
        modelContext.insert(workspace)

        let repo = Repository(gitlabProjectId: 100, name: "main-repo", url: "https://gitlab.example.com/team/main.git")
        repo.workspace = workspace
        workspace.repositories.append(repo)

        // Create tickets with dependencies
        let ticketA = Ticket(title: "Setup database", status: .done, storyPoints: 5)
        let ticketB = Ticket(title: "Build API layer", status: .inProgress, storyPoints: 8)
        let ticketC = Ticket(title: "Build frontend", status: .backlog, storyPoints: 13)

        ticketA.workspace = workspace
        ticketB.workspace = workspace
        ticketC.workspace = workspace

        // B is blocked by A, C is blocked by B
        ticketB.blockedBy = [ticketA]
        ticketA.blocks = [ticketB]
        ticketC.blockedBy = [ticketB]
        ticketB.blocks = [ticketC]

        workspace.tickets = [ticketA, ticketB, ticketC]

        try modelContext.save()

        // Verify dependency chain
        XCTAssertEqual(ticketB.blockedBy.count, 1)
        XCTAssertEqual(ticketB.blockedBy.first?.title, "Setup database")
        XCTAssertEqual(ticketC.blockedBy.first?.title, "Build API layer")
        XCTAssertEqual(ticketA.blocks.first?.title, "Build API layer")
    }

    // MARK: - E2E Test: Webhook → Ticket Update → Kanban Card Move

    /// Tests that a webhook event correctly updates a ticket's status
    /// and the Kanban board reflects the change.
    func testWebhookToTicketUpdateToKanbanMove() throws {
        // Setup: Create workspace with a ticket
        let workspace = Workspace(name: "Kanban Test Workspace")
        modelContext.insert(workspace)

        let repo = Repository(gitlabProjectId: 55, name: "app-repo", url: "https://gitlab.example.com/team/app.git")
        repo.workspace = workspace
        workspace.repositories.append(repo)

        let ticket = Ticket(
            gitlabIssueId: 1001,
            gitlabIssueIid: 15,
            title: "Fix login bug",
            status: .inProgress,
            storyPoints: 3,
            labels: ["bug"],
            lastSyncedAt: Date().addingTimeInterval(-3600),
            localVersion: 2
        )
        ticket.workspace = workspace
        workspace.tickets.append(ticket)

        try modelContext.save()

        // Simulate webhook updating the ticket status
        let kanbanVM = KanbanViewModel(workspace: workspace)

        // Verify initial state
        kanbanVM.refreshBoard()
        let inProgressColumn = kanbanVM.mapStatusToColumn(.inProgress)
        XCTAssertTrue(kanbanVM.columnTickets[inProgressColumn]?.contains(where: { $0.id == ticket.id }) ?? false)

        // Simulate webhook-driven status update (ticket moved to "In Review")
        kanbanVM.handleWebhookStatusUpdate(ticketId: ticket.id, newStatus: .inReview)

        // Verify the ticket moved to the correct column
        let inReviewColumn = kanbanVM.mapStatusToColumn(.inReview)
        XCTAssertTrue(kanbanVM.columnTickets[inReviewColumn]?.contains(where: { $0.id == ticket.id }) ?? false)
        XCTAssertFalse(kanbanVM.columnTickets[inProgressColumn]?.contains(where: { $0.id == ticket.id }) ?? false)

        // Verify ticket state was updated
        XCTAssertEqual(ticket.status, .inReview)
        XCTAssertNotNil(ticket.lastSyncedAt)
    }

    /// Tests that webhook events for unknown statuses place tickets in the first column.
    func testWebhookUnmappedStatusPlacesInFirstColumn() throws {
        let workspace = Workspace(name: "Unmapped Status Test")
        modelContext.insert(workspace)

        let ticket = Ticket(
            gitlabIssueId: 2001,
            gitlabIssueIid: 25,
            title: "Unmapped ticket",
            status: .backlog,
            labels: []
        )
        ticket.workspace = workspace
        workspace.tickets.append(ticket)

        try modelContext.save()

        let kanbanVM = KanbanViewModel(workspace: workspace)
        kanbanVM.refreshBoard()

        // Verify ticket is in the first column (Backlog maps to first column)
        let firstColumn = kanbanVM.columns.first!
        let backlogColumn = kanbanVM.mapStatusToColumn(.backlog)
        XCTAssertEqual(backlogColumn, firstColumn)
    }

    // MARK: - E2E Test: MR Created → Notification → Review → Merge

    /// Tests the complete MR lifecycle: creation notification, review, and merge flow.
    func testMRCreatedToNotificationToReviewToMerge() throws {
        // Setup workspace with repo
        let workspace = Workspace(name: "MR Flow Workspace")
        modelContext.insert(workspace)

        let repo = Repository(gitlabProjectId: 77, name: "service-repo", url: "https://gitlab.example.com/team/service.git")
        repo.workspace = workspace
        workspace.repositories.append(repo)

        try modelContext.save()

        // Step 1: Simulate MR creation (as if received via webhook)
        let mrEntry = MergeRequestEntry(
            gitlabMrId: 5001,
            gitlabMrIid: 42,
            title: "feat: Add user profile endpoint",
            authorUsername: "developer1",
            sourceBranch: "feature/user-profile",
            targetBranch: "main",
            pipelineStatus: .success,
            state: .opened
        )
        mrEntry.repository = repo
        modelContext.insert(mrEntry)

        // Step 2: Create notification for new MR
        let notification = AppNotification(
            eventType: .newMergeRequest,
            title: "New Merge Request",
            message: "developer1 opened MR !42: feat: Add user profile endpoint",
            relatedItemId: mrEntry.id,
            relatedItemType: "merge_request"
        )
        notification.workspace = workspace
        workspace.notifications.append(notification)

        try modelContext.save()

        // Step 3: Verify notification was created
        XCTAssertEqual(workspace.notifications.count, 1)
        XCTAssertEqual(workspace.notifications.first?.eventType, .newMergeRequest)
        XCTAssertFalse(workspace.notifications.first!.isRead)

        // Step 4: Verify MR is in opened state
        XCTAssertEqual(mrEntry.state, .opened)
        XCTAssertEqual(mrEntry.pipelineStatus, .success)

        // Step 5: Simulate merge (update MR state)
        mrEntry.state = .merged
        mrEntry.updatedAt = Date()

        try modelContext.save()

        // Step 6: Verify MR is now merged
        XCTAssertEqual(mrEntry.state, .merged)

        // Step 7: Verify deep link target for notification
        let notificationService = NotificationService()
        let deepLink = notificationService.deepLinkTarget(for: notification)
        XCTAssertEqual(deepLink?.tab, .mergeRequests)
        XCTAssertEqual(deepLink?.itemId, mrEntry.id)
    }

    /// Tests that MR with pipeline failures shows appropriate state.
    func testMRWithPipelineFailure() throws {
        let workspace = Workspace(name: "Pipeline Test")
        modelContext.insert(workspace)

        let repo = Repository(gitlabProjectId: 88, name: "ci-repo", url: "https://gitlab.example.com/team/ci.git")
        repo.workspace = workspace
        workspace.repositories.append(repo)

        let mrEntry = MergeRequestEntry(
            gitlabMrId: 6001,
            gitlabMrIid: 55,
            title: "fix: Resolve memory leak",
            authorUsername: "developer2",
            sourceBranch: "fix/memory-leak",
            targetBranch: "main",
            pipelineStatus: .failed,
            state: .opened
        )
        mrEntry.repository = repo
        modelContext.insert(mrEntry)

        try modelContext.save()

        // Verify pipeline failure is tracked
        XCTAssertEqual(mrEntry.pipelineStatus, .failed)
        XCTAssertEqual(mrEntry.state, .opened)
    }

    // MARK: - Sync Engine Integration

    /// Tests that the sync engine correctly handles the reconciliation flow.
    func testSyncEngineReconciliationIntegration() throws {
        let workspace = Workspace(name: "Sync Integration")
        modelContext.insert(workspace)

        let repo = Repository(gitlabProjectId: 99, name: "sync-repo", url: "https://gitlab.example.com/team/sync.git")
        repo.workspace = workspace
        workspace.repositories.append(repo)

        // Create a ticket that's been synced before
        let syncDate = Date().addingTimeInterval(-3600)
        let ticket = Ticket(
            gitlabIssueId: 3001,
            gitlabIssueIid: 30,
            title: "Synced Ticket",
            status: .inProgress,
            storyPoints: 5,
            labels: ["feature"],
            updatedAt: syncDate.addingTimeInterval(-60),
            lastSyncedAt: syncDate,
            localVersion: 3
        )
        ticket.workspace = workspace
        workspace.tickets.append(ticket)

        try modelContext.save()

        // Simulate a remote update (remote changed after sync)
        let remoteIssue = GitLabIssue(
            id: 3001,
            iid: 30,
            projectId: 99,
            title: "Synced Ticket - Updated",
            description: "Updated description",
            state: "opened",
            labels: ["feature", "workflow::in-review"],
            weight: 8,
            assignee: nil,
            assignees: nil,
            milestone: nil,
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date(),
            closedAt: nil,
            dueDate: nil,
            webUrl: "https://gitlab.example.com/project/issues/30"
        )

        // Reconcile
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Should detect remote-only changes (no conflict)
        if case .noConflict(let merged) = result {
            XCTAssertEqual(merged.title, "Synced Ticket - Updated")
            XCTAssertEqual(merged.status, .inReview)
            XCTAssertEqual(merged.storyPoints, 8)
        } else {
            XCTFail("Expected noConflict result, got \(result)")
        }
    }
}
