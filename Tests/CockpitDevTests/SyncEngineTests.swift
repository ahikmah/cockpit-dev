import XCTest
import SwiftData
@testable import CockpitDev

/// Unit tests for the SyncEngine's reconciliation and conflict detection logic.
final class SyncEngineTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var syncEngine: SyncEngine!
    private var mockAPIClient: GitLabAPIClient!

    override func setUp() async throws {
        try await super.setUp()

        // Create an in-memory model container for testing
        let schema = Schema([
            Workspace.self,
            Repository.self,
            Member.self,
            Ticket.self,
            Sprint.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)

        // Create a mock API client (won't be used for reconcile tests)
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

    // MARK: - Reconciliation Tests

    func testReconcile_noChanges_returnsNoConflict() throws {
        // Given: A ticket synced 1 hour ago with no local or remote changes
        let syncDate = Date().addingTimeInterval(-3600)
        let ticket = Ticket(
            title: "Test Ticket",
            status: .inProgress,
            storyPoints: 5,
            labels: ["bug"],
            updatedAt: syncDate.addingTimeInterval(-60), // Updated before sync
            lastSyncedAt: syncDate,
            localVersion: 2
        )
        ticket.gitlabIssueId = 100
        ticket.gitlabIssueIid = 10

        let remoteIssue = makeGitLabIssue(
            id: 100,
            iid: 10,
            title: "Test Ticket",
            description: nil,
            state: "opened",
            labels: ["bug", "workflow::in-progress"],
            weight: 5,
            updatedAt: syncDate.addingTimeInterval(-60) // Updated before sync
        )

        // When
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Then: No conflict, local snapshot returned
        if case .noConflict(let merged) = result {
            XCTAssertEqual(merged.title, "Test Ticket")
            XCTAssertEqual(merged.status, .inProgress)
            XCTAssertEqual(merged.storyPoints, 5)
        } else {
            XCTFail("Expected noConflict result, got \(result)")
        }
    }

    func testReconcile_remoteOnlyChanges_returnsNoConflictWithRemoteData() throws {
        // Given: A ticket synced 1 hour ago, remote updated after sync, local not updated
        let syncDate = Date().addingTimeInterval(-3600)
        let ticket = Ticket(
            title: "Original Title",
            status: .todo,
            storyPoints: 3,
            labels: ["feature"],
            updatedAt: syncDate.addingTimeInterval(-120), // Updated before sync
            lastSyncedAt: syncDate,
            localVersion: 1
        )
        ticket.gitlabIssueId = 200
        ticket.gitlabIssueIid = 20

        let remoteIssue = makeGitLabIssue(
            id: 200,
            iid: 20,
            title: "Updated Title",
            description: "New description",
            state: "opened",
            labels: ["feature", "workflow::in-progress"],
            weight: 8,
            updatedAt: Date() // Updated after sync
        )

        // When
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Then: No conflict, remote data merged
        if case .noConflict(let merged) = result {
            XCTAssertEqual(merged.title, "Updated Title")
            XCTAssertEqual(merged.descriptionText, "New description")
            XCTAssertEqual(merged.status, .inProgress)
            XCTAssertEqual(merged.storyPoints, 8)
            XCTAssertEqual(merged.labels, ["feature"])
        } else {
            XCTFail("Expected noConflict result, got \(result)")
        }
    }

    func testReconcile_localOnlyChanges_returnsNoConflictWithLocalData() throws {
        // Given: A ticket synced 1 hour ago, local updated after sync, remote not updated
        let syncDate = Date().addingTimeInterval(-3600)
        let ticket = Ticket(
            title: "Locally Updated Title",
            status: .inReview,
            storyPoints: 13,
            labels: ["enhancement"],
            updatedAt: Date(), // Updated after sync
            lastSyncedAt: syncDate,
            localVersion: 3
        )
        ticket.gitlabIssueId = 300
        ticket.gitlabIssueIid = 30

        let remoteIssue = makeGitLabIssue(
            id: 300,
            iid: 30,
            title: "Original Title",
            description: nil,
            state: "opened",
            labels: ["enhancement", "workflow::todo"],
            weight: 5,
            updatedAt: syncDate.addingTimeInterval(-60) // Updated before sync
        )

        // When
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Then: No conflict, local data preserved
        if case .noConflict(let merged) = result {
            XCTAssertEqual(merged.title, "Locally Updated Title")
            XCTAssertEqual(merged.status, .inReview)
            XCTAssertEqual(merged.storyPoints, 13)
        } else {
            XCTFail("Expected noConflict result, got \(result)")
        }
    }

    func testReconcile_bothSidesModified_returnsConflict() throws {
        // Given: A ticket synced 1 hour ago, both local and remote updated after sync
        let syncDate = Date().addingTimeInterval(-3600)
        let ticket = Ticket(
            title: "Local Title",
            status: .inProgress,
            storyPoints: 8,
            labels: ["bug"],
            updatedAt: Date().addingTimeInterval(-300), // Updated after sync
            lastSyncedAt: syncDate,
            localVersion: 4
        )
        ticket.gitlabIssueId = 400
        ticket.gitlabIssueIid = 40

        let remoteIssue = makeGitLabIssue(
            id: 400,
            iid: 40,
            title: "Remote Title",
            description: "Remote description",
            state: "opened",
            labels: ["bug", "workflow::in-review"],
            weight: 13,
            updatedAt: Date().addingTimeInterval(-600) // Also updated after sync
        )

        // When
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Then: Conflict detected
        if case .conflict(let local, let remote) = result {
            XCTAssertEqual(local.title, "Local Title")
            XCTAssertEqual(local.status, .inProgress)
            XCTAssertEqual(local.storyPoints, 8)
            XCTAssertEqual(remote.title, "Remote Title")
            XCTAssertEqual(remote.status, .inReview)
            XCTAssertEqual(remote.storyPoints, 13)
        } else {
            XCTFail("Expected conflict result, got \(result)")
        }
    }

    func testReconcile_neverSynced_withRemoteChanges_returnsConflict() throws {
        // Given: A ticket that has never been synced but has a GitLab ID (created locally, pushed once)
        let ticket = Ticket(
            title: "New Ticket",
            status: .backlog,
            storyPoints: 3,
            labels: [],
            updatedAt: Date(),
            lastSyncedAt: nil, // Never synced
            localVersion: 1
        )
        ticket.gitlabIssueId = 500
        ticket.gitlabIssueIid = 50

        let remoteIssue = makeGitLabIssue(
            id: 500,
            iid: 50,
            title: "Remote Version",
            description: nil,
            state: "opened",
            labels: ["workflow::todo"],
            weight: nil,
            updatedAt: Date()
        )

        // When
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Then: Conflict because both sides appear modified (never synced + remote exists)
        if case .conflict(let local, let remote) = result {
            XCTAssertEqual(local.title, "New Ticket")
            XCTAssertEqual(remote.title, "Remote Version")
        } else {
            XCTFail("Expected conflict result, got \(result)")
        }
    }

    // MARK: - Conflict Detection Tests

    func testConflictDetection_localVersionIncrement() throws {
        // Given: A ticket with localVersion tracking
        let syncDate = Date().addingTimeInterval(-3600)
        let ticket = Ticket(
            title: "Versioned Ticket",
            status: .todo,
            updatedAt: Date(), // Modified after sync
            lastSyncedAt: syncDate,
            localVersion: 5
        )
        ticket.gitlabIssueId = 600
        ticket.gitlabIssueIid = 60

        let remoteIssue = makeGitLabIssue(
            id: 600,
            iid: 60,
            title: "Versioned Ticket",
            description: nil,
            state: "opened",
            labels: ["workflow::todo"],
            weight: nil,
            updatedAt: Date() // Also modified after sync
        )

        // When
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Then: Conflict detected due to both sides being modified
        if case .conflict(let local, _) = result {
            XCTAssertEqual(local.localVersion, 5)
        } else {
            XCTFail("Expected conflict result")
        }
    }

    func testConflictDetection_lastSyncedAtUsedForComparison() throws {
        // Given: A ticket synced very recently, with remote update before sync
        let syncDate = Date()
        let ticket = Ticket(
            title: "Recent Sync",
            status: .inProgress,
            updatedAt: syncDate.addingTimeInterval(-10), // Updated before sync
            lastSyncedAt: syncDate,
            localVersion: 2
        )
        ticket.gitlabIssueId = 700
        ticket.gitlabIssueIid = 70

        let remoteIssue = makeGitLabIssue(
            id: 700,
            iid: 70,
            title: "Recent Sync",
            description: nil,
            state: "opened",
            labels: ["workflow::in-progress"],
            weight: nil,
            updatedAt: syncDate.addingTimeInterval(-5) // Updated before sync
        )

        // When
        let result = syncEngine.reconcile(local: ticket, remote: remoteIssue)

        // Then: No conflict because neither side was modified after sync
        if case .noConflict = result {
            // Expected
        } else {
            XCTFail("Expected noConflict result, got \(result)")
        }
    }

    // MARK: - Field Mapping Tests

    func testFieldMapping_statusToGitLab_backlog() {
        let (state, label) = FieldMapping.statusToGitLab(.backlog)
        XCTAssertEqual(state, "opened")
        XCTAssertEqual(label, "workflow::backlog")
    }

    func testFieldMapping_statusToGitLab_todo() {
        let (state, label) = FieldMapping.statusToGitLab(.todo)
        XCTAssertEqual(state, "opened")
        XCTAssertEqual(label, "workflow::todo")
    }

    func testFieldMapping_statusToGitLab_inProgress() {
        let (state, label) = FieldMapping.statusToGitLab(.inProgress)
        XCTAssertEqual(state, "opened")
        XCTAssertEqual(label, "workflow::in-progress")
    }

    func testFieldMapping_statusToGitLab_inReview() {
        let (state, label) = FieldMapping.statusToGitLab(.inReview)
        XCTAssertEqual(state, "opened")
        XCTAssertEqual(label, "workflow::in-review")
    }

    func testFieldMapping_statusToGitLab_done() {
        let (state, label) = FieldMapping.statusToGitLab(.done)
        XCTAssertEqual(state, "closed")
        XCTAssertEqual(label, "workflow::done")
    }

    func testFieldMapping_gitLabToStatus_closedState() {
        let status = FieldMapping.gitLabToStatus(state: "closed", labels: [])
        XCTAssertEqual(status, .done)
    }

    func testFieldMapping_gitLabToStatus_openedWithWorkflowLabel() {
        let status = FieldMapping.gitLabToStatus(state: "opened", labels: ["bug", "workflow::in-progress"])
        XCTAssertEqual(status, .inProgress)
    }

    func testFieldMapping_gitLabToStatus_openedWithNoWorkflowLabel() {
        let status = FieldMapping.gitLabToStatus(state: "opened", labels: ["bug", "feature"])
        XCTAssertEqual(status, .backlog)
    }

    func testFieldMapping_gitLabToStatus_closedOverridesWorkflowLabel() {
        // Closed state takes precedence over workflow labels
        let status = FieldMapping.gitLabToStatus(state: "closed", labels: ["workflow::in-progress"])
        XCTAssertEqual(status, .done)
    }

    func testFieldMapping_nonWorkflowLabels_filtersCorrectly() {
        let labels = ["bug", "workflow::in-progress", "feature", "workflow::todo", "priority::high"]
        let filtered = FieldMapping.nonWorkflowLabels(labels)
        XCTAssertEqual(filtered, ["bug", "feature", "priority::high"])
    }

    func testFieldMapping_buildGitLabLabels_includesWorkflowLabel() {
        let labels = FieldMapping.buildGitLabLabels(ticketLabels: ["bug", "feature"], status: .inProgress)
        XCTAssertTrue(labels.contains("bug"))
        XCTAssertTrue(labels.contains("feature"))
        XCTAssertTrue(labels.contains("workflow::in-progress"))
        XCTAssertEqual(labels.count, 3)
    }

    func testFieldMapping_buildGitLabLabels_stripsExistingWorkflowLabels() {
        // If ticket labels already contain workflow labels, they should be stripped
        let labels = FieldMapping.buildGitLabLabels(
            ticketLabels: ["bug", "workflow::old-label", "feature"],
            status: .todo
        )
        XCTAssertTrue(labels.contains("bug"))
        XCTAssertTrue(labels.contains("feature"))
        XCTAssertTrue(labels.contains("workflow::todo"))
        XCTAssertFalse(labels.contains("workflow::old-label"))
        XCTAssertEqual(labels.count, 3)
    }

    func testFieldMapping_storyPointsToWeight() {
        XCTAssertEqual(FieldMapping.storyPointsToWeight(5), 5)
        XCTAssertEqual(FieldMapping.storyPointsToWeight(13), 13)
        XCTAssertNil(FieldMapping.storyPointsToWeight(nil))
    }

    func testFieldMapping_weightToStoryPoints() {
        XCTAssertEqual(FieldMapping.weightToStoryPoints(8), 8)
        XCTAssertEqual(FieldMapping.weightToStoryPoints(21), 21)
        XCTAssertNil(FieldMapping.weightToStoryPoints(nil))
    }

    // MARK: - Offline Queue Tests

    func testOfflineQueue_enqueuesOperation() {
        let ticketId = UUID()
        syncEngine.isOnline = false

        syncEngine.enqueueOperation(ticketId: ticketId, type: .push)

        XCTAssertEqual(syncEngine.offlineQueue.count, 1)
        XCTAssertEqual(syncEngine.offlineQueue.first?.ticketId, ticketId)
        XCTAssertEqual(syncEngine.offlineQueue.first?.operationType, .push)
    }

    func testOfflineQueue_preventsDuplicates() {
        let ticketId = UUID()
        syncEngine.isOnline = false

        syncEngine.enqueueOperation(ticketId: ticketId, type: .push)
        syncEngine.enqueueOperation(ticketId: ticketId, type: .push)

        XCTAssertEqual(syncEngine.offlineQueue.count, 1)
    }

    func testOfflineQueue_allowsDifferentOperationTypes() {
        let ticketId = UUID()
        syncEngine.isOnline = false

        syncEngine.enqueueOperation(ticketId: ticketId, type: .push)
        syncEngine.enqueueOperation(ticketId: ticketId, type: .pull)

        XCTAssertEqual(syncEngine.offlineQueue.count, 2)
    }

    func testOfflineQueue_allowsDifferentTickets() {
        let ticketId1 = UUID()
        let ticketId2 = UUID()
        syncEngine.isOnline = false

        syncEngine.enqueueOperation(ticketId: ticketId1, type: .push)
        syncEngine.enqueueOperation(ticketId: ticketId2, type: .push)

        XCTAssertEqual(syncEngine.offlineQueue.count, 2)
    }

    // MARK: - Polling Tests

    func testPolling_startsAndStops() {
        XCTAssertFalse(syncEngine.isPolling)

        syncEngine.startPolling(interval: 60)
        XCTAssertTrue(syncEngine.isPolling)
        XCTAssertEqual(syncEngine.pollingInterval, 60)

        syncEngine.stopPolling()
        XCTAssertFalse(syncEngine.isPolling)
    }

    func testPolling_defaultInterval() {
        XCTAssertEqual(syncEngine.pollingInterval, AppConstants.defaultPollInterval)
    }

    func testPolling_customInterval() {
        let customEngine = SyncEngine(
            apiClient: mockAPIClient,
            modelContext: modelContext,
            pollingInterval: 120
        )
        XCTAssertEqual(customEngine.pollingInterval, 120)
    }

    // MARK: - Online Status Tests

    func testSetOnlineStatus_updatesFlag() {
        syncEngine.isOnline = true
        syncEngine.setOnlineStatus(false)
        XCTAssertFalse(syncEngine.isOnline)

        syncEngine.setOnlineStatus(true)
        XCTAssertTrue(syncEngine.isOnline)
    }

    // MARK: - TicketSnapshot Tests

    func testTicketSnapshot_fromTicket() {
        let ticket = Ticket(
            title: "Snapshot Test",
            descriptionText: "Description",
            status: .inReview,
            storyPoints: 8,
            labels: ["test", "snapshot"],
            localVersion: 3
        )
        ticket.gitlabIssueId = 999
        ticket.gitlabIssueIid = 99

        let snapshot = TicketSnapshot(from: ticket)

        XCTAssertEqual(snapshot.title, "Snapshot Test")
        XCTAssertEqual(snapshot.descriptionText, "Description")
        XCTAssertEqual(snapshot.status, .inReview)
        XCTAssertEqual(snapshot.storyPoints, 8)
        XCTAssertEqual(snapshot.labels, ["test", "snapshot"])
        XCTAssertEqual(snapshot.localVersion, 3)
        XCTAssertEqual(snapshot.gitlabIssueId, 999)
        XCTAssertEqual(snapshot.gitlabIssueIid, 99)
    }

    // MARK: - Helpers

    /// Creates a GitLabIssue for testing purposes.
    private func makeGitLabIssue(
        id: Int,
        iid: Int,
        title: String,
        description: String?,
        state: String,
        labels: [String],
        weight: Int?,
        updatedAt: Date
    ) -> GitLabIssue {
        return GitLabIssue(
            id: id,
            iid: iid,
            projectId: 1,
            title: title,
            description: description,
            state: state,
            labels: labels,
            weight: weight,
            assignee: nil,
            assignees: nil,
            milestone: nil,
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: updatedAt,
            closedAt: nil,
            dueDate: nil,
            webUrl: "https://gitlab.example.com/project/issues/\(iid)"
        )
    }
}
