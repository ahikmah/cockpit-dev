import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class RepositoryManagementViewModelTests: CockpitDevTestCase {

    private var viewModel: RepositoryManagementViewModel!
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var workspace: Workspace!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            Workspace.self, Repository.self, Member.self, Ticket.self,
            Sprint.self, Document.self, OpenSpecEntry.self,
            DocSpecVersion.self, AppNotification.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext

        workspace = Workspace(name: "Test Workspace")
        modelContext.insert(workspace)
        try modelContext.save()

        viewModel = RepositoryManagementViewModel()
        viewModel.configure(workspace: workspace, modelContext: modelContext)
    }

    override func tearDown() async throws {
        viewModel = nil
        workspace = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_repositoriesEmpty() {
        XCTAssertTrue(viewModel.repositories.isEmpty)
    }

    func testInitialState_noErrors() {
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
        XCTAssertFalse(viewModel.isValidating)
    }

    func testWorkspaceLocalRootPath_isPersistedForRepositoryPlacement() throws {
        workspace.localRootPath = "/tmp/Test-Workspace"
        try modelContext.save()

        XCTAssertEqual(workspace.localRootPath, "/tmp/Test-Workspace")
    }

    // MARK: - URL Validation Tests

    func testAddRepository_emptyURL_showsError() async {
        viewModel.newRepositoryURL = ""
        let success = await viewModel.addRepository()

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage?.contains("empty") ?? false)
    }

    func testAddRepository_invalidURLFormat_showsError() async {
        viewModel.newRepositoryURL = "not-a-valid-url"
        let success = await viewModel.addRepository()

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage?.contains("invalid") ?? false)
    }

    func testAddRepository_whitespaceOnlyURL_showsError() async {
        viewModel.newRepositoryURL = "   "
        let success = await viewModel.addRepository()

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
    }

    func testAddRepository_httpsURL_passesFormatValidation() async {
        // This will fail at the API validation step (no client configured),
        // but should pass the format check
        viewModel.newRepositoryURL = "https://gitlab.com/namespace/project.git"
        let success = await viewModel.addRepository()

        // Should fail because no GitLab API client is configured
        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage?.contains("GitLab API client") ?? false)
    }

    func testAddRepository_sshURL_passesFormatValidation() async {
        viewModel.newRepositoryURL = "git@gitlab.com:namespace/project.git"
        let success = await viewModel.addRepository()

        // Should fail because no GitLab API client is configured
        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage?.contains("GitLab API client") ?? false)
    }

    func testAddRepository_clonesIntoWorkspaceRootBeforeSaving() async throws {
        let server = MockHTTPServer()
        let port = try await server.start()
        defer {
            Task { try? await server.stop() }
        }

        server.handler = { _, _ in
            let project = """
            {
              "id": 42,
              "name": "cyint",
              "name_with_namespace": "devbuddy / cyint",
              "path": "cyint",
              "path_with_namespace": "devbuddy/cyint",
              "default_branch": "main",
              "http_url_to_repo": "https://gitlab.example/devbuddy/cyint.git",
              "ssh_url_to_repo": "git@gitlab.example:devbuddy/cyint.git",
              "web_url": "https://gitlab.example/devbuddy/cyint",
              "visibility": "private"
            }
            """
            return (200, [], Data(project.utf8))
        }

        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CockpitDev-WorkspaceRoot-\(UUID().uuidString)", isDirectory: true)
        workspace.localRootPath = rootDirectory.path

        var clonedBaseDirectory: URL?
        let autoCloneViewModel = RepositoryManagementViewModel(
            repositoryCloneHandler: { repository, baseDirectory, _ in
                clonedBaseDirectory = baseDirectory
                let checkout = baseDirectory.appendingPathComponent(repository.name, isDirectory: true)
                repository.localPath = checkout.path
                return .success(checkout)
            }
        )
        autoCloneViewModel.configure(
            workspace: workspace,
            modelContext: modelContext,
            gitLabAPIClient: GitLabAPIClient(
                baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                tokenProvider: { "api-token" }
            ),
            cloneTokenProvider: { "clone-token" }
        )
        autoCloneViewModel.newRepositoryURL = "https://gitlab.example/devbuddy/cyint"

        let success = await autoCloneViewModel.addRepository()

        XCTAssertTrue(success)
        XCTAssertEqual(clonedBaseDirectory?.standardizedFileURL.path, rootDirectory.standardizedFileURL.path)
        XCTAssertEqual(workspace.repositories.first?.localPath, rootDirectory.appendingPathComponent("cyint").path)
        XCTAssertEqual(workspace.repositories.first?.url, "https://gitlab.example/devbuddy/cyint.git")
    }

    // MARK: - Duplicate Detection Tests

    func testAddRepository_duplicateURL_showsError() async {
        // Manually add a repository to the workspace
        let repo = Repository(
            gitlabProjectId: 123,
            name: "existing-repo",
            url: "https://gitlab.com/namespace/existing.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        // Try to add the same URL
        viewModel.newRepositoryURL = "https://gitlab.com/namespace/existing.git"
        let success = await viewModel.addRepository()

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage?.contains("already associated") ?? false)
    }

    func testAddRepository_duplicateURLCaseInsensitive_showsError() async {
        let repo = Repository(
            gitlabProjectId: 123,
            name: "existing-repo",
            url: "https://gitlab.com/Namespace/Project.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        viewModel.newRepositoryURL = "https://gitlab.com/namespace/project.git"
        let success = await viewModel.addRepository()

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
    }

    // MARK: - Remove Repository Tests

    func testConfirmRemoval_setsRepositoryPendingRemoval() {
        let repo = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/ns/test.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        viewModel.confirmRemoval(of: repo)

        XCTAssertEqual(viewModel.repositoryPendingRemoval?.id, repo.id)
        XCTAssertTrue(viewModel.showRemoveConfirmation)
    }

    func testExecuteRemoval_removesRepositoryFromWorkspace() {
        let repo = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/ns/test.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        viewModel.confirmRemoval(of: repo)
        viewModel.executeRemoval()

        XCTAssertTrue(workspace.repositories.isEmpty)
        XCTAssertNil(viewModel.repositoryPendingRemoval)
    }

    func testExecuteRemoval_doesNotDeleteRemoteRepository() {
        // This test verifies the behavior is disassociation only.
        // The remote GitLab repository should remain untouched.
        let repo = Repository(
            gitlabProjectId: 456,
            name: "remote-repo",
            url: "https://gitlab.com/ns/remote.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        viewModel.confirmRemoval(of: repo)
        viewModel.executeRemoval()

        // Verify workspace no longer has the repo
        XCTAssertFalse(workspace.repositories.contains { $0.id == repo.id })
    }

    // MARK: - Local Path Management Tests

    func testUpdateLocalPath_setsPath() {
        let repo = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/ns/test.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        viewModel.updateLocalPath(for: repo, path: "/Users/test/projects/test-repo")

        XCTAssertEqual(repo.localPath, "/Users/test/projects/test-repo")
    }

    func testClearLocalPath_removesPath() {
        let repo = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/ns/test.git",
            localPath: "/Users/test/projects/test-repo"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        viewModel.clearLocalPath(for: repo)

        XCTAssertNil(repo.localPath)
    }

    // MARK: - IDE Context Tests

    func testCheckLocalAvailability_noRepos_returnsEmpty() {
        let availability = viewModel.checkLocalAvailability()
        XCTAssertTrue(availability.isEmpty)
    }

    func testCheckLocalAvailability_repoWithoutLocalPath_returnsFalse() {
        let repo = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/ns/test.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        let availability = viewModel.checkLocalAvailability()

        XCTAssertEqual(availability.count, 1)
        XCTAssertFalse(availability[0].1)
    }

    func testCheckLocalAvailability_repoWithInvalidPath_returnsFalse() {
        let repo = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/ns/test.git",
            localPath: "/nonexistent/path/that/does/not/exist"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        let availability = viewModel.checkLocalAvailability()

        XCTAssertEqual(availability.count, 1)
        XCTAssertFalse(availability[0].1)
    }

    func testCheckLocalAvailability_repoWithValidPath_returnsTrue() {
        // Use a path that exists on macOS
        let repo = Repository(
            gitlabProjectId: 123,
            name: "test-repo",
            url: "https://gitlab.com/ns/test.git",
            localPath: "/tmp"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)
        try? modelContext.save()

        let availability = viewModel.checkLocalAvailability()

        XCTAssertEqual(availability.count, 1)
        XCTAssertTrue(availability[0].1)
    }

    func testOpenInIDE_clonesRemoteOnlyReposIntoWorkspaceRootAndLaunchesZed() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CockpitDev-OpenRoot-\(UUID().uuidString)", isDirectory: true)
        workspace.localRootPath = rootDirectory.path

        let repo = Repository(
            gitlabProjectId: 123,
            name: "cyint",
            url: "https://gitlab.example/devbuddy/cyint.git"
        )
        repo.workspace = workspace
        workspace.repositories.append(repo)
        modelContext.insert(repo)

        var launchedDirectory: URL?
        let service = IDEContextService(
            zedLauncher: { directory in
                launchedDirectory = directory
                return true
            }
        )
        let openingViewModel = RepositoryManagementViewModel(
            ideContextService: service,
            repositoryCloneHandler: { repository, baseDirectory, _ in
                let checkout = baseDirectory.appendingPathComponent(repository.name, isDirectory: true)
                try? FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
                repository.localPath = checkout.path
                return .success(checkout)
            }
        )
        openingViewModel.configure(
            workspace: workspace,
            modelContext: modelContext,
            cloneTokenProvider: { "clone-token" }
        )

        await openingViewModel.openInIDE()

        XCTAssertEqual(repo.localPath, rootDirectory.appendingPathComponent("cyint").path)
        XCTAssertEqual(launchedDirectory?.standardizedFileURL.path, rootDirectory.standardizedFileURL.path)
    }

    // MARK: - Reset Form Tests

    func testResetAddForm_clearsState() {
        viewModel.newRepositoryURL = "https://gitlab.com/test"
        viewModel.errorMessage = "Some error"
        viewModel.showError = true

        viewModel.resetAddForm()

        XCTAssertEqual(viewModel.newRepositoryURL, "")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
    }
}
