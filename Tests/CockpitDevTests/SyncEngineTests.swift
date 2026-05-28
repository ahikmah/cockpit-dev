import XCTest
import SwiftData
@testable import CockpitDev

/// Unit tests for the SyncEngine's reconciliation and conflict detection logic.
@MainActor
final class SyncEngineTests: CockpitDevTestCase {

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

    func testReconcile_remoteOnlyChanges_preservesDatabaseOwnedStoryPoints() throws {
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
            XCTAssertEqual(merged.storyPoints, 3)
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
            XCTAssertEqual(remote.storyPoints, 8)
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

    func testFullReconcileImportsIssuesAndMilestonesFromAllRepositories() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                let milestones = """
                [{"id":101,"iid":1,"project_id":1,"title":"Frontend Sprint","description":null,"state":"active","start_date":"2024-02-01","due_date":"2024-02-14","created_at":"2024-01-20T00:00:00Z","updated_at":"2024-01-20T00:00:00Z","web_url":"https://gitlab.example.com/frontend/-/milestones/1"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], milestones.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/2/milestones"):
                let milestones = """
                [{"id":202,"iid":1,"project_id":2,"title":"Backend Sprint","description":null,"state":"active","start_date":"2024-03-01","due_date":"2024-03-15","created_at":"2024-02-20T00:00:00Z","updated_at":"2024-02-20T00:00:00Z","web_url":"https://gitlab.example.com/backend/-/milestones/1"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], milestones.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1001,"iid":11,"project_id":1,"title":"Build dashboard","description":"Frontend task","state":"opened","labels":["feature","workflow::in-progress"],"weight":5,"assignee":{"id":7,"username":"maya","name":"Maya","avatar_url":null,"email":"maya@example.com","state":"active","web_url":null},"assignees":[{"id":7,"username":"maya","name":"Maya","avatar_url":null,"email":"maya@example.com","state":"active","web_url":null}],"milestone":{"id":101,"iid":1,"project_id":1,"title":"Frontend Sprint","description":null,"state":"active","start_date":"2024-02-01","due_date":"2024-02-14","created_at":"2024-01-20T00:00:00Z","updated_at":"2024-01-20T00:00:00Z","web_url":null},"created_at":"2024-01-21T00:00:00Z","updated_at":"2024-01-22T00:00:00Z","closed_at":null,"due_date":"2024-02-10","web_url":"https://gitlab.example.com/frontend/-/issues/11"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/2/issues"):
                let issues = """
                [{"id":2001,"iid":21,"project_id":2,"title":"Create API","description":"Backend task","state":"opened","labels":["backend","workflow::todo"],"weight":8,"assignee":null,"assignees":[],"milestone":{"id":202,"iid":1,"project_id":2,"title":"Backend Sprint","description":null,"state":"active","start_date":"2024-03-01","due_date":"2024-03-15","created_at":"2024-02-20T00:00:00Z","updated_at":"2024-02-20T00:00:00Z","web_url":null},"created_at":"2024-02-21T00:00:00Z","updated_at":"2024-02-22T00:00:00Z","closed_at":null,"due_date":null,"web_url":"https://gitlab.example.com/backend/-/issues/21"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)

            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let frontendRepo = Repository(gitlabProjectId: 1, name: "frontend", url: "https://gitlab.example.com/team/frontend.git")
        let backendRepo = Repository(gitlabProjectId: 2, name: "backend", url: "https://gitlab.example.com/team/backend.git")
        let member = Member(gitlabUserId: 7, username: "maya", displayName: "Maya")
        frontendRepo.workspace = workspace
        backendRepo.workspace = workspace
        member.workspace = workspace
        workspace.repositories = [frontendRepo, backendRepo]
        workspace.members = [member]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        XCTAssertEqual(workspace.sprints.count, 2)
        XCTAssertEqual(Set(workspace.sprints.map(\.gitlabMilestoneId)), [101, 202])
        XCTAssertEqual(Set(workspace.tickets.map(\.gitlabIssueId)), [1001, 2001])

        let dashboard = try XCTUnwrap(workspace.tickets.first { $0.gitlabIssueId == 1001 })
        XCTAssertEqual(dashboard.title, "Build dashboard")
        XCTAssertEqual(dashboard.status, .inProgress)
        XCTAssertNil(dashboard.storyPoints)
        XCTAssertEqual(dashboard.labels, ["feature"])
        XCTAssertEqual(dashboard.assignee?.gitlabUserId, 7)
        XCTAssertEqual(dashboard.sprint?.gitlabMilestoneId, 101)
        XCTAssertNil(dashboard.startDate)
        XCTAssertNil(dashboard.endDate)

        let api = try XCTUnwrap(workspace.tickets.first { $0.gitlabIssueId == 2001 })
        XCTAssertEqual(api.title, "Create API")
        XCTAssertEqual(api.status, .todo)
        XCTAssertNil(api.storyPoints)
        XCTAssertEqual(api.sprint?.gitlabMilestoneId, 202)
        XCTAssertNil(api.startDate)
        XCTAssertNil(api.endDate)
    }

    func testFullReconcileDoesNotCreatePlanningMetadataFromGitLabIssue() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                let milestones = """
                [{"id":101,"iid":1,"project_id":1,"title":"Sprint","description":null,"state":"active","start_date":"2024-02-01","due_date":"2024-02-14","created_at":"2024-01-20T00:00:00Z","updated_at":"2024-01-20T00:00:00Z","web_url":null}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], milestones.data(using: .utf8)!)
            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1001,"iid":11,"project_id":1,"title":"Scheduled by issue","description":null,"state":"opened","labels":[],"weight":5,"assignee":null,"assignees":[],"milestone":{"id":101,"iid":1,"project_id":1,"title":"Sprint","description":null,"state":"active","start_date":"2024-02-01","due_date":"2024-02-14","created_at":"2024-01-20T00:00:00Z","updated_at":"2024-01-20T00:00:00Z","web_url":null},"created_at":"2024-01-21T00:00:00Z","updated_at":"2024-01-22T00:00:00Z","closed_at":null,"start_date":"2024-02-05","due_date":"2024-02-10","web_url":"https://gitlab.example.com/frontend/-/issues/11"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)
            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "frontend", url: "https://gitlab.example.com/team/frontend.git")
        repository.workspace = workspace
        workspace.repositories = [repository]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        let ticket = try XCTUnwrap(workspace.tickets.first)
        XCTAssertNil(ticket.startDate)
        XCTAssertNil(ticket.endDate)
        XCTAssertNil(ticket.storyPoints)
    }

    func testFullReconcileUsesLatestCommitFromMentioningMRAsTicketRealizationDate() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1001,"iid":15,"project_id":1,"title":"CYINT84-015: UI/UX Reskin","description":null,"state":"closed","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2026-04-10T00:00:00Z","updated_at":"2026-04-20T00:00:00Z","closed_at":"2026-04-20T00:00:00Z","due_date":null,"web_url":"https://gitlab.example.com/frontend/-/issues/15"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests/7/commits"):
                let commits = """
                [{"id":"old111","short_id":"old111","title":"start","message":"start","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-12T08:00:00Z","committed_date":"2026-04-12T08:00:00Z"},{"id":"new222","short_id":"new222","title":"finish CYINT84-015","message":"finish CYINT84-015","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-15T18:00:00Z","committed_date":"2026-04-15T18:00:00Z"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], commits.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests"):
                let mrs = """
                [{"id":7001,"iid":7,"project_id":1,"title":"Resolve CYINT84-015","description":"Implements #15","state":"merged","source_branch":"feature/cyint84-015","target_branch":"main","author":{"id":1,"username":"dev","name":"Dev","avatar_url":null,"email":null,"state":"active","web_url":null},"assignee":null,"pipeline":null,"created_at":"2026-04-12T00:00:00Z","updated_at":"2026-04-16T00:00:00Z","merged_at":"2026-04-16T00:00:00Z","closed_at":null,"web_url":"https://gitlab.example.com/frontend/-/merge_requests/7"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], mrs.data(using: .utf8)!)

            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "frontend", url: "https://gitlab.example.com/team/frontend.git")
        repository.workspace = workspace
        workspace.repositories = [repository]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        let ticket = try XCTUnwrap(workspace.tickets.first)
        XCTAssertEqual(ticket.realizedAt, ISO8601DateFormatter().date(from: "2026-04-15T18:00:00Z"))
        XCTAssertEqual(ticket.realizationSource, .mrCommit)
        XCTAssertEqual(ticket.realizationReference, "!7 new222")
    }

    func testFullReconcileUsesLatestCommitThatMentionsIssueWhenMRMetadataDoesNotMentionIt() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues/68/related_merge_requests"):
                let mrs = """
                [{"id":7025,"iid":25,"project_id":1,"title":"Implementation cleanup","description":null,"state":"merged","source_branch":"feature/refactor","target_branch":"main","author":{"id":1,"username":"dev","name":"Dev","avatar_url":null,"email":null,"state":"active","web_url":null},"assignee":null,"pipeline":null,"created_at":"2026-04-12T00:00:00Z","updated_at":"2026-04-16T00:00:00Z","merged_at":"2026-04-16T00:00:00Z","closed_at":null,"web_url":"https://gitlab.example.com/cyint/-/merge_requests/25"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], mrs.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1068,"iid":68,"project_id":1,"title":"CYINT84-001: Intelligence Repository","description":null,"state":"closed","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2026-04-10T00:00:00Z","updated_at":"2026-04-19T00:00:00Z","closed_at":"2026-04-19T00:00:00Z","due_date":null,"web_url":"https://gitlab.example.com/cyint/-/issues/68"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests/25/commits"):
                let commits = """
                [{"id":"old111","short_id":"old111","title":"prep","message":"prep","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-14T08:00:00Z","committed_date":"2026-04-14T08:00:00Z"},{"id":"new168","short_id":"new168","title":"finish work","message":"finish work for #68","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-16T18:00:00Z","committed_date":"2026-04-16T18:00:00Z"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], commits.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "cyint", url: "https://gitlab.example.com/devbuddy/cyint.git")
        repository.workspace = workspace
        workspace.repositories = [repository]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        let ticket = try XCTUnwrap(workspace.tickets.first)
        XCTAssertEqual(ticket.realizedAt, ISO8601DateFormatter().date(from: "2026-04-16T18:00:00Z"))
        XCTAssertEqual(ticket.realizationSource, .mrCommit)
        XCTAssertEqual(ticket.realizationReference, "!25 new168")
    }

    func testFullReconcileUsesMRMentionSystemNoteBeforeIssueClosureFallback() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues/68/notes"):
                let notes = """
                [{"id":1601,"body":"mentioned in merge request !25","author":{"id":1,"username":"dev","name":"Dev","avatar_url":null,"email":null,"state":"active","web_url":null},"created_at":"2026-04-16T11:35:32Z","updated_at":"2026-04-16T11:35:32Z","system":true,"resolvable":false,"resolved":null,"resolved_by":null,"position":null}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], notes.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues/68/related_merge_requests"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1068,"iid":68,"project_id":1,"title":"CYINT84-001: Intelligence Repository","description":null,"state":"closed","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2026-04-10T00:00:00Z","updated_at":"2026-04-19T00:00:00Z","closed_at":"2026-04-19T00:00:00Z","due_date":null,"web_url":"https://gitlab.example.com/cyint/-/issues/68"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "cyint", url: "https://gitlab.example.com/devbuddy/cyint.git")
        repository.workspace = workspace
        workspace.repositories = [repository]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        let ticket = try XCTUnwrap(workspace.tickets.first)
        XCTAssertEqual(ticket.realizedAt, ISO8601DateFormatter().date(from: "2026-04-16T11:35:32Z"))
        XCTAssertEqual(ticket.realizationSource, .mrMention)
        XCTAssertEqual(ticket.realizationReference, "!25")
    }

    func testFullReconcileFetchesLatestCommitFromMergeRequestMentionedInSystemNote() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues/68/notes"):
                let notes = """
                [{"id":1601,"body":"mentioned in merge request !25","author":{"id":1,"username":"dev","name":"Dev","avatar_url":null,"email":null,"state":"active","web_url":null},"created_at":"2026-04-17T08:00:00Z","updated_at":"2026-04-17T08:00:00Z","system":true,"resolvable":false,"resolved":null,"resolved_by":null,"position":null}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], notes.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues/68/related_merge_requests"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1068,"iid":68,"project_id":1,"title":"CYINT84-001: Intelligence Repository","description":null,"state":"closed","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2026-04-10T00:00:00Z","updated_at":"2026-04-19T00:00:00Z","closed_at":"2026-04-18T01:49:52Z","due_date":null,"web_url":"https://gitlab.example.com/cyint/-/issues/68"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests/25/commits"):
                let commits = """
                [{"id":"older","short_id":"older1","title":"implementation","message":"implementation","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-15T02:00:00Z","committed_date":"2026-04-15T02:00:00Z"},{"id":"latest","short_id":"last16","title":"review fixes","message":"review fixes","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-16T11:00:00Z","committed_date":"2026-04-16T11:00:00Z"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], commits.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "cyint", url: "https://gitlab.example.com/devbuddy/cyint.git")
        repository.workspace = workspace
        workspace.repositories = [repository]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        let ticket = try XCTUnwrap(workspace.tickets.first)
        XCTAssertEqual(ticket.realizedAt, ISO8601DateFormatter().date(from: "2026-04-16T11:00:00Z"))
        XCTAssertEqual(ticket.realizationSource, .mrCommit)
        XCTAssertEqual(ticket.realizationReference, "!25 last16")
    }

    func testFullReconcileRefreshesRealizationForLegacyTicketWithOnlyIssueIidStoredAsId() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues/68/notes"):
                let notes = """
                [{"id":1601,"body":"mentioned in merge request !25 (merged)","author":{"id":1,"username":"dev","name":"Dev","avatar_url":null,"email":null,"state":"active","web_url":null},"created_at":"2026-04-16T11:35:32Z","updated_at":"2026-04-16T11:35:32Z","system":false,"resolvable":false,"resolved":null,"resolved_by":null,"position":null}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], notes.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues/68/related_merge_requests"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1068,"iid":68,"project_id":1,"title":"CYINT84-001: Intelligence Repository","description":null,"state":"closed","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2026-04-10T00:00:00Z","updated_at":"2026-04-19T00:00:00Z","closed_at":"2026-04-18T01:49:52Z","due_date":null,"web_url":"https://gitlab.example.com/cyint/-/issues/68"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests/25/commits"):
                let commits = """
                [{"id":"older","short_id":"older1","title":"implementation","message":"implementation","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-15T02:00:00Z","committed_date":"2026-04-15T02:00:00Z"},{"id":"latest","short_id":"last16","title":"review fixes","message":"review fixes","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-16T11:00:00Z","committed_date":"2026-04-16T11:00:00Z"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], commits.data(using: .utf8)!)

            case let uri where uri.contains("/api/v4/projects/1/merge_requests"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], "[]".data(using: .utf8)!)

            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "cyint", url: "https://gitlab.example.com/devbuddy/cyint.git")
        let legacyTicket = Ticket(
            gitlabIssueId: 68,
            gitlabIssueIid: nil,
            title: "CYINT84-001: Intelligence Repository",
            status: .done,
            storyPoints: 10,
            updatedAt: ISO8601DateFormatter().date(from: "2026-04-19T00:00:00Z")!
        )
        repository.workspace = workspace
        legacyTicket.workspace = workspace
        workspace.repositories = [repository]
        workspace.tickets = [legacyTicket]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        XCTAssertEqual(workspace.tickets.count, 1)
        XCTAssertEqual(legacyTicket.gitlabIssueId, 1068)
        XCTAssertEqual(legacyTicket.gitlabIssueIid, 68)
        XCTAssertEqual(legacyTicket.realizedAt, ISO8601DateFormatter().date(from: "2026-04-16T11:00:00Z"))
        XCTAssertEqual(legacyTicket.realizationSource, .mrCommit)
        XCTAssertEqual(legacyTicket.realizationReference, "!25 last16")
    }

    func testFullReconcilePreservesDatabasePlanningMetadataDuringContentConflict() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                let milestones = """
                [{"id":101,"iid":1,"project_id":1,"title":"Sprint","description":null,"state":"active","start_date":"2024-04-13","due_date":"2024-04-15","created_at":"2024-04-01T00:00:00Z","updated_at":"2024-04-01T00:00:00Z","web_url":null}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], milestones.data(using: .utf8)!)
            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1001,"iid":85,"project_id":1,"title":"Remote title","description":"Remote body","state":"closed","labels":["priority::critical"],"weight":25,"assignee":null,"assignees":[],"milestone":{"id":101,"iid":1,"project_id":1,"title":"Sprint","description":null,"state":"active","start_date":"2024-04-13","due_date":"2024-04-15","created_at":"2024-04-01T00:00:00Z","updated_at":"2024-04-01T00:00:00Z","web_url":null},"created_at":"2024-04-01T00:00:00Z","updated_at":"2024-04-20T00:00:00Z","closed_at":"2024-04-20T00:00:00Z","start_date":"2024-04-10","due_date":"2024-04-15","web_url":"https://gitlab.example.com/frontend/-/issues/85"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)
            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "frontend", url: "https://gitlab.example.com/team/frontend.git")
        let localTicket = Ticket(
            gitlabIssueId: 1001,
            gitlabIssueIid: 85,
            title: "Local edit",
            status: .inProgress,
            priority: .critical,
            storyPoints: 25,
            startDate: date("2024-04-10"),
            endDate: date("2024-04-15"),
            updatedAt: Date(),
            lastSyncedAt: date("2024-04-02")
        )
        repository.workspace = workspace
        localTicket.workspace = workspace
        workspace.repositories = [repository]
        workspace.tickets = [localTicket]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        XCTAssertEqual(localTicket.title, "Local edit")
        XCTAssertEqual(localTicket.startDate, date("2024-04-10"))
        XCTAssertEqual(localTicket.endDate, date("2024-04-15"))
        XCTAssertEqual(localTicket.storyPoints, 25)
        XCTAssertEqual(localTicket.priority, .critical)
    }

    func testRefreshPlanningMetadataAppliesFieldsFromOpenSpecDatabase() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], Data("[]".utf8))
            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1001,"iid":85,"project_id":1,"title":"CYINT84-015: UI/UX Reskin","description":null,"state":"closed","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2026-04-01T00:00:00Z","updated_at":"2026-04-01T00:00:00Z","closed_at":null,"due_date":null,"web_url":"https://gitlab.example.com/frontend/-/issues/85"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], Data(issues.utf8))
            default:
                return (404, [], Data(#"{"message":"not found"}"#.utf8))
            }
        }

        let workspace = Workspace(name: "DB Metadata Workspace")
        let repository = Repository(
            gitlabProjectId: 1,
            name: "cyint",
            url: "https://gitlab.orbit-poc.com/devbuddy/cyint.git"
        )
        let ticket = Ticket(
            gitlabIssueId: 1001,
            gitlabIssueIid: 85,
            title: "CYINT84-015: UI/UX Reskin",
            status: .done,
            storyPoints: nil,
            startDate: date("2026-04-13"),
            endDate: date("2026-04-15"),
            updatedAt: date("2026-04-01"),
            lastSyncedAt: date("2026-04-02")
        )
        repository.workspace = workspace
        ticket.workspace = workspace
        workspace.repositories = [repository]
        workspace.tickets = [ticket]
        modelContext.insert(workspace)
        try modelContext.save()

        let provider = StubOpenSpecPMMetadataProvider(features: [
            OpenSpecPMFeature(
                id: "feature-15",
                externalIssueId: 85,
                title: "CYINT84-015: UI/UX Reskin",
                status: .completed,
                priority: .critical,
                startDate: date("2026-04-10"),
                dueDate: date("2026-04-15"),
                storyPoints: 25,
                milestone: "CTI Intelligence Platform Development Project - Phase 1",
                branchName: nil,
                assignee: nil
            )
        ])
        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(
            apiClient: client,
            planningMetadataProvider: provider,
            modelContext: modelContext
        )

        try await engine.refreshPlanningMetadata(workspace: workspace)

        XCTAssertEqual(provider.requestedRepositories, [repository.url])
        XCTAssertEqual(ticket.startDate, date("2026-04-10"))
        XCTAssertEqual(ticket.endDate, date("2026-04-15"))
        XCTAssertEqual(ticket.storyPoints, 25)
        XCTAssertEqual(ticket.priority, .critical)
    }

    func testRefreshPlanningMetadataSyncsFeatureDependenciesFromOpenSpecDatabase() async throws {
        let workspace = Workspace(name: "Dependency Metadata Workspace")
        let repository = Repository(
            gitlabProjectId: 1,
            name: "cyint",
            url: "https://gitlab.orbit-poc.com/devbuddy/cyint.git"
        )
        let blocker = Ticket(
            gitlabIssueId: 1005,
            gitlabIssueIid: 72,
            title: "CYINT84-005: Multiple Source Links per Article",
            status: .done
        )
        let dependent = Ticket(
            gitlabIssueId: 1004,
            gitlabIssueIid: 71,
            title: "CYINT84-004: RSS Article Deduplication",
            status: .todo
        )
        repository.workspace = workspace
        blocker.workspace = workspace
        dependent.workspace = workspace
        workspace.repositories = [repository]
        workspace.tickets = [dependent, blocker]
        modelContext.insert(workspace)
        try modelContext.save()

        let provider = StubOpenSpecPMMetadataProvider(features: [
            OpenSpecPMFeature(
                id: "feature-004",
                externalIssueId: 71,
                title: "CYINT84-004: RSS Article Deduplication",
                status: .assigned,
                priority: .high,
                startDate: nil,
                dueDate: nil,
                storyPoints: 12,
                milestone: nil,
                branchName: nil,
                dependencies: ["feature-005"],
                assignee: nil
            ),
            OpenSpecPMFeature(
                id: "feature-005",
                externalIssueId: 72,
                title: "CYINT84-005: Multiple Source Links per Article",
                status: .completed,
                priority: .high,
                startDate: nil,
                dueDate: nil,
                storyPoints: 8,
                milestone: nil,
                branchName: nil,
                dependencies: [],
                assignee: nil
            )
        ])
        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:1")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(
            apiClient: client,
            planningMetadataProvider: provider,
            modelContext: modelContext
        )

        try await engine.refreshPlanningMetadata(workspace: workspace)

        XCTAssertEqual(dependent.blockedBy.map(\.id), [blocker.id])
        XCTAssertEqual(blocker.blocks.map(\.id), [dependent.id])
    }

    func testFullReconcileMigratesLegacyIssueIdStoredAsIid() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        server.handler = { head, _ in
            switch head.uri {
            case let uri where uri.contains("/api/v4/projects/1/milestones"):
                let milestones = """
                [{"id":101,"iid":1,"project_id":1,"title":"Sprint","description":null,"state":"active","start_date":"2024-04-13","due_date":"2024-04-15","created_at":"2024-04-01T00:00:00Z","updated_at":"2024-04-01T00:00:00Z","web_url":null}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], milestones.data(using: .utf8)!)
            case let uri where uri.contains("/api/v4/projects/1/issues"):
                let issues = """
                [{"id":1001,"iid":85,"project_id":1,"title":"CYINT84-015","description":"Remote body","state":"closed","labels":["priority::critical"],"weight":25,"assignee":null,"assignees":[],"milestone":{"id":101,"iid":1,"project_id":1,"title":"Sprint","description":null,"state":"active","start_date":"2024-04-13","due_date":"2024-04-15","created_at":"2024-04-01T00:00:00Z","updated_at":"2024-04-01T00:00:00Z","web_url":null},"created_at":"2024-04-01T00:00:00Z","updated_at":"2024-04-20T00:00:00Z","closed_at":"2024-04-20T00:00:00Z","start_date":"2024-04-10","due_date":"2024-04-15","web_url":"https://gitlab.example.com/frontend/-/issues/85"}]
                """
                return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)
            default:
                return (404, [], #"{"message":"not found"}"#.data(using: .utf8)!)
            }
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "frontend", url: "https://gitlab.example.com/team/frontend.git")
        let legacyTicket = Ticket(
            gitlabIssueId: 85,
            gitlabIssueIid: 85,
            title: "CYINT84-015",
            status: .done,
            priority: .critical,
            storyPoints: 25,
            startDate: date("2024-04-10"),
            endDate: date("2024-04-15"),
            updatedAt: date("2024-04-02"),
            lastSyncedAt: date("2024-04-02")
        )
        repository.workspace = workspace
        legacyTicket.workspace = workspace
        workspace.repositories = [repository]
        workspace.tickets = [legacyTicket]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        _ = try await engine.fullReconcile(workspace: workspace)

        XCTAssertEqual(workspace.tickets.count, 1)
        XCTAssertEqual(legacyTicket.gitlabIssueId, 1001)
        XCTAssertEqual(legacyTicket.gitlabIssueIid, 85)
        XCTAssertEqual(legacyTicket.startDate, date("2024-04-10"))
        XCTAssertEqual(legacyTicket.endDate, date("2024-04-15"))
        XCTAssertEqual(legacyTicket.storyPoints, 25)
        XCTAssertEqual(legacyTicket.priority, .critical)
    }

    func testPushTicketToGitLabExcludesDatabasePlanningFields() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        addTeardownBlock {
            try await server.stop()
        }

        var capturedBody: [String: Any]?
        server.handler = { head, body in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues"))
            XCTAssertEqual(head.method, .POST)
            if let body {
                capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }

            let issue = """
            {"id":1001,"iid":11,"project_id":1,"title":"Local feature","description":"Build it","state":"opened","labels":["workflow::in-progress"],"weight":8,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-02-01T00:00:00Z","updated_at":"2024-02-01T00:00:00Z","closed_at":null,"start_date":"2024-02-05","due_date":"2024-02-10","web_url":"https://gitlab.example.com/frontend/-/issues/11"}
            """
            return (201, [], issue.data(using: .utf8)!)
        }

        let workspace = Workspace(name: "GitLab Workspace")
        let repository = Repository(gitlabProjectId: 1, name: "frontend", url: "https://gitlab.example.com/team/frontend.git")
        let member = Member(gitlabUserId: 7, username: "maya", displayName: "Maya")
        let sprint = Sprint(name: "Sprint", startDate: date("2024-02-01"), endDate: date("2024-02-14"), gitlabMilestoneId: 101)
        let ticket = Ticket(
            title: "Local feature",
            descriptionText: "Build it",
            status: .inProgress,
            storyPoints: 8,
            startDate: date("2024-02-05"),
            endDate: date("2024-02-10")
        )
        repository.workspace = workspace
        member.workspace = workspace
        sprint.workspace = workspace
        ticket.workspace = workspace
        ticket.assignee = member
        ticket.sprint = sprint
        workspace.repositories = [repository]
        workspace.members = [member]
        workspace.sprints = [sprint]
        workspace.tickets = [ticket]
        sprint.tickets = [ticket]
        modelContext.insert(workspace)
        try modelContext.save()

        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "test-token" }
        )
        let engine = SyncEngine(apiClient: client, modelContext: modelContext)

        try await engine.pushTicketToGitLab(ticket)

        XCTAssertEqual(capturedBody?["assignee_ids"] as? [Int], [7])
        XCTAssertEqual(capturedBody?["milestone_id"] as? Int, 101)
        XCTAssertNil(capturedBody?["start_date"])
        XCTAssertNil(capturedBody?["due_date"])
        XCTAssertNil(capturedBody?["weight"])
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
            startDate: nil,
            dueDate: nil,
            webUrl: "https://gitlab.example.com/project/issues/\(iid)"
        )
    }

    private func date(_ string: String) -> Date {
        var components = DateComponents()
        let parts = string.split(separator: "-").compactMap { Int($0) }
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date!
    }
}

private final class StubOpenSpecPMMetadataProvider: OpenSpecPMMetadataProviding {
    let features: [OpenSpecPMFeature]
    private(set) var requestedRepositories: [String] = []

    init(features: [OpenSpecPMFeature]) {
        self.features = features
    }

    func fetchFeatures(repositoryURL: String) async throws -> [OpenSpecPMFeature] {
        requestedRepositories.append(repositoryURL)
        return features
    }
}
