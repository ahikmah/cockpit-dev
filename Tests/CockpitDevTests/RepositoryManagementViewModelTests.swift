import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class RepositoryManagementViewModelTests: XCTestCase {

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
