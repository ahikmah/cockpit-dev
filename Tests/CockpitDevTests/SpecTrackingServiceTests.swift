import XCTest
import SwiftData
@testable import CockpitDev

/// Unit tests for the SpecTrackingService covering:
/// - Push hook detection for spec file changes
/// - Phase detection from directory structure
/// - Branch deletion handling (marking specs unavailable)
/// - Content hash computation
/// - Spec file change detection
@MainActor
final class SpecTrackingServiceTests: CockpitDevTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var specTrackingService: SpecTrackingService!
    private var mockAPIClient: GitLabAPIClient!
    private var mockServer: MockHTTPServer?

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

        specTrackingService = SpecTrackingService(apiClient: mockAPIClient, modelContext: modelContext)
    }

    override func tearDown() async throws {
        try await mockServer?.stop()
        mockServer = nil
        specTrackingService = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Push Hook Detection Tests

    func testPushContainsSpecChanges_withSpecFileAdded_returnsTrue() {
        // Given: A push payload with a file added in the spec directory
        let payload = makePushPayload(
            branchName: "feature/auth",
            commits: [
                makeCommit(added: [".kiro/specs/auth-feature/requirements.md"])
            ]
        )

        // When
        let result = specTrackingService.pushContainsSpecChanges(
            payload: payload,
            specPath: ".kiro/specs"
        )

        // Then
        XCTAssertTrue(result)
    }

    func testPushContainsSpecChanges_withSpecFileModified_returnsTrue() {
        // Given: A push payload with a file modified in the spec directory
        let payload = makePushPayload(
            branchName: "feature/auth",
            commits: [
                makeCommit(modified: [".kiro/specs/auth-feature/design.md"])
            ]
        )

        // When
        let result = specTrackingService.pushContainsSpecChanges(
            payload: payload,
            specPath: ".kiro/specs"
        )

        // Then
        XCTAssertTrue(result)
    }

    func testPushContainsSpecChanges_withSpecFileRemoved_returnsTrue() {
        // Given: A push payload with a file removed from the spec directory
        let payload = makePushPayload(
            branchName: "feature/auth",
            commits: [
                makeCommit(removed: [".kiro/specs/old-feature/tasks.md"])
            ]
        )

        // When
        let result = specTrackingService.pushContainsSpecChanges(
            payload: payload,
            specPath: ".kiro/specs"
        )

        // Then
        XCTAssertTrue(result)
    }

    func testPushContainsSpecChanges_withNoSpecFiles_returnsFalse() {
        // Given: A push payload with files outside the spec directory
        let payload = makePushPayload(
            branchName: "feature/auth",
            commits: [
                makeCommit(
                    added: ["src/main.swift"],
                    modified: ["README.md"]
                )
            ]
        )

        // When
        let result = specTrackingService.pushContainsSpecChanges(
            payload: payload,
            specPath: ".kiro/specs"
        )

        // Then
        XCTAssertFalse(result)
    }

    func testPushContainsSpecChanges_withNoCommits_returnsFalse() {
        // Given: A push payload with no commits
        let payload = makePushPayload(branchName: "main", commits: nil)

        // When
        let result = specTrackingService.pushContainsSpecChanges(
            payload: payload,
            specPath: ".kiro/specs"
        )

        // Then
        XCTAssertFalse(result)
    }

    func testPushContainsSpecChanges_withTrailingSlashInSpecPath_returnsTrue() {
        // Given: Spec path with trailing slash
        let payload = makePushPayload(
            branchName: "feature/auth",
            commits: [
                makeCommit(added: [".kiro/specs/auth/requirements.md"])
            ]
        )

        // When
        let result = specTrackingService.pushContainsSpecChanges(
            payload: payload,
            specPath: ".kiro/specs/"
        )

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - Branch Deletion Handling Tests

    func testMarkBranchSpecsUnavailable_marksAllSpecsOnBranch() {
        // Given: A workspace with specs on multiple branches
        let workspace = Workspace(name: "Test Workspace", specDirectoryPath: ".kiro/specs")
        modelContext.insert(workspace)

        let spec1 = OpenSpecEntry(specName: "feature-a", branchName: "feature/a", phase: .design, isAvailable: true)
        spec1.workspace = workspace
        modelContext.insert(spec1)

        let spec2 = OpenSpecEntry(specName: "feature-b", branchName: "feature/a", phase: .tasks, isAvailable: true)
        spec2.workspace = workspace
        modelContext.insert(spec2)

        let spec3 = OpenSpecEntry(specName: "feature-c", branchName: "feature/c", phase: .proposal, isAvailable: true)
        spec3.workspace = workspace
        modelContext.insert(spec3)

        workspace.specs = [spec1, spec2, spec3]
        try? modelContext.save()

        // When: Branch "feature/a" is deleted
        specTrackingService.markBranchSpecsUnavailable(branchName: "feature/a", workspace: workspace)

        // Then: Only specs on "feature/a" are marked unavailable
        XCTAssertFalse(spec1.isAvailable)
        XCTAssertFalse(spec2.isAvailable)
        XCTAssertTrue(spec3.isAvailable) // Different branch, unaffected
    }

    func testMarkBranchSpecsUnavailable_noSpecsOnBranch_noChanges() {
        // Given: A workspace with no specs on the deleted branch
        let workspace = Workspace(name: "Test Workspace", specDirectoryPath: ".kiro/specs")
        modelContext.insert(workspace)

        let spec1 = OpenSpecEntry(specName: "feature-x", branchName: "main", phase: .tasks, isAvailable: true)
        spec1.workspace = workspace
        modelContext.insert(spec1)

        workspace.specs = [spec1]
        try? modelContext.save()

        // When: A different branch is deleted
        specTrackingService.markBranchSpecsUnavailable(branchName: "feature/deleted", workspace: workspace)

        // Then: Existing specs remain available
        XCTAssertTrue(spec1.isAvailable)
    }

    // MARK: - Content Hash Computation Tests

    func testComputeContentHash_sameContent_sameHash() {
        // Given: Same content string
        let content = "# Requirements\n\nThis is a test spec."

        // When
        let hash1 = specTrackingService.computeContentHash(content)
        let hash2 = specTrackingService.computeContentHash(content)

        // Then
        XCTAssertEqual(hash1, hash2)
    }

    func testComputeContentHash_differentContent_differentHash() {
        // Given: Different content strings
        let content1 = "# Requirements\n\nVersion 1"
        let content2 = "# Requirements\n\nVersion 2"

        // When
        let hash1 = specTrackingService.computeContentHash(content1)
        let hash2 = specTrackingService.computeContentHash(content2)

        // Then
        XCTAssertNotEqual(hash1, hash2)
    }

    func testComputeContentHash_producesValidSHA256() {
        // Given
        let content = "Hello, World!"

        // When
        let hash = specTrackingService.computeContentHash(content)

        // Then: SHA-256 produces a 64-character hex string
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Primary File Name Tests

    func testPrimaryFileName_proposal_returnsProposalMd() {
        XCTAssertEqual(specTrackingService.primaryFileName(for: .proposal), "proposal.md")
    }

    func testPrimaryFileName_design_returnsDesignMd() {
        XCTAssertEqual(specTrackingService.primaryFileName(for: .design), "design.md")
    }

    func testPrimaryFileName_tasks_returnsTasksMd() {
        XCTAssertEqual(specTrackingService.primaryFileName(for: .tasks), "tasks.md")
    }

    // MARK: - Push Event with Branch Deletion Tests

    func testHandlePushEvent_branchDeletion_marksSpecsUnavailable() async throws {
        // Given: A workspace with specs on a branch
        let workspace = Workspace(name: "Test Workspace", specDirectoryPath: ".kiro/specs")
        let repository = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/test/repo",
            defaultBranch: "main"
        )
        repository.workspace = workspace
        workspace.repositories = [repository]
        modelContext.insert(workspace)
        modelContext.insert(repository)

        let spec = OpenSpecEntry(specName: "auth-feature", branchName: "feature/auth", phase: .design, isAvailable: true)
        spec.workspace = workspace
        workspace.specs = [spec]
        modelContext.insert(spec)
        try modelContext.save()

        // When: A branch deletion push event is received
        let payload = makePushPayload(
            branchName: "feature/auth",
            isBranchDeletion: true
        )

        try await specTrackingService.handlePushEvent(payload, workspace: workspace)

        // Then: The spec is marked unavailable
        XCTAssertFalse(spec.isAvailable)
    }

    func testHandlePushEvent_emptySpecPath_throwsError() async {
        // Given: A workspace with empty spec directory path
        let workspace = Workspace(name: "Test Workspace", specDirectoryPath: "")
        modelContext.insert(workspace)
        try? modelContext.save()

        let payload = makePushPayload(branchName: "feature/test")

        // When/Then: Should throw specDirectoryNotConfigured error
        do {
            try await specTrackingService.handlePushEvent(payload, workspace: workspace)
            XCTFail("Expected error to be thrown")
        } catch let error as SpecTrackingError {
            if case .specDirectoryNotConfigured = error {
                // Expected
            } else {
                XCTFail("Expected specDirectoryNotConfigured error, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDiscoverSpecsOnBranch_readsOpenSpecDocumentFolder() async throws {
        let server = MockHTTPServer()
        mockServer = server
        let port = try await server.start()
        let client = GitLabAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "mock-token" }
        )
        specTrackingService = SpecTrackingService(apiClient: client, modelContext: modelContext)

        let rootPath = "openspec/changes"
        let changePath = "\(rootPath)/cyint84-010-news-detail-dedicated-page"
        server.handler = { head, _ in
            let components = URLComponents(string: "http://localhost\(head.uri)")!
            let path = components.queryItems?.first(where: { $0.name == "path" })?.value

            if head.uri.contains("/repository/tree") {
                let response: String
                switch path {
                case rootPath:
                    response = """
                    [{"id":"1","name":"cyint84-010-news-detail-dedicated-page","type":"tree","path":"\(changePath)","mode":"040000"}]
                    """
                case changePath:
                    response = """
                    [
                      {"id":"2","name":"proposal.md","type":"blob","path":"\(changePath)/proposal.md","mode":"100644"},
                      {"id":"3","name":"design.md","type":"blob","path":"\(changePath)/design.md","mode":"100644"},
                      {"id":"4","name":"tasks.md","type":"blob","path":"\(changePath)/tasks.md","mode":"100644"},
                      {"id":"5","name":"specs","type":"tree","path":"\(changePath)/specs","mode":"040000"}
                    ]
                    """
                case "\(changePath)/specs":
                    response = """
                    [{"id":"6","name":"adjacent-articles-api","type":"tree","path":"\(changePath)/specs/adjacent-articles-api","mode":"040000"}]
                    """
                case "\(changePath)/specs/adjacent-articles-api":
                    response = """
                    [{"id":"7","name":"spec.md","type":"blob","path":"\(changePath)/specs/adjacent-articles-api/spec.md","mode":"100644"}]
                    """
                default:
                    response = "[]"
                }
                return (200, [], Data(response.utf8))
            }

            if head.uri.contains("/repository/files/") {
                let content: String
                if head.uri.contains("proposal.md") {
                    content = "# Proposal"
                } else if head.uri.contains("design.md") {
                    content = "# Design"
                } else if head.uri.contains("tasks.md") {
                    content = "- [ ] Implement"
                } else {
                    content = "# Adjacent Articles API"
                }
                let base64 = Data(content.utf8).base64EncodedString()
                return (200, [], Data("{\"content\":\"\(base64)\",\"encoding\":\"base64\"}".utf8))
            }

            if head.uri.contains("/repository/commits") {
                return (200, [], Data("[]".utf8))
            }

            return (404, [], Data("{}".utf8))
        }

        let workspace = Workspace(name: "Test", specDirectoryPath: rootPath)
        let repository = Repository(gitlabProjectId: 42, name: "cyint", url: "https://gitlab.example.com/cyint")
        repository.workspace = workspace
        workspace.repositories = [repository]
        modelContext.insert(workspace)
        modelContext.insert(repository)

        try await specTrackingService.discoverSpecsOnBranch(branchName: "orbit-dev-84", workspace: workspace)

        let entry = try XCTUnwrap(workspace.specs.first)
        XCTAssertEqual(entry.phase, .tasks)
        let version = try XCTUnwrap(entry.versions.first)
        let snapshot = OpenSpecDocumentSnapshot.decode(version.content, legacyPhase: entry.phase)
        XCTAssertEqual(snapshot.proposal, "# Proposal")
        XCTAssertEqual(snapshot.design, "# Design")
        XCTAssertEqual(snapshot.tasks, "- [ ] Implement")
        XCTAssertEqual(snapshot.specs, [
            .init(path: "specs/adjacent-articles-api/spec.md", content: "# Adjacent Articles API")
        ])
    }

    // MARK: - Helpers

    private func makePushPayload(
        branchName: String,
        isBranchDeletion: Bool = false,
        commits: [WebhookCommit]? = nil
    ) -> PushWebhookPayload {
        let before = isBranchDeletion ? "abc123" : "0000000000000000000000000000000000000000"
        let after = isBranchDeletion ? "0000000000000000000000000000000000000000" : "def456"

        return PushWebhookPayload(
            objectKind: "push",
            eventName: "push",
            ref: "refs/heads/\(branchName)",
            before: before,
            after: after,
            projectId: 123,
            project: WebhookProject(
                id: 123,
                name: "test-project",
                webUrl: "https://gitlab.com/test/project",
                pathWithNamespace: "test/project"
            ),
            commits: commits,
            totalCommitsCount: commits?.count ?? 0
        )
    }

    private func makeCommit(
        added: [String]? = nil,
        modified: [String]? = nil,
        removed: [String]? = nil
    ) -> WebhookCommit {
        WebhookCommit(
            id: UUID().uuidString,
            message: "Test commit",
            timestamp: "2024-01-01T12:00:00Z",
            url: "https://gitlab.com/test/project/-/commit/abc123",
            author: WebhookCommitAuthor(name: "Test User", email: "test@example.com"),
            added: added,
            modified: modified,
            removed: removed
        )
    }
}
