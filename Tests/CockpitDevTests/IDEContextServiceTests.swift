import XCTest
@testable import CockpitDev

/// Unit tests for IDEContextService.
///
/// Tests cover:
/// - Workspace file generation (.code-workspace JSON format)
/// - Zero-repos guard behavior
/// - Local availability checking (available, not cloned, stale path)
/// - Stale path detection
/// - Batch clone with partial failure handling
/// - Missing repo detection
@MainActor
final class IDEContextServiceTests: CockpitDevTestCase {

    private var service: IDEContextService!
    private var gitOpsService: GitOperationsService!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        gitOpsService = GitOperationsService()
        service = IDEContextService(
            gitOperationsService: gitOpsService,
            fileManager: .default
        )
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IDEContextTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        service = nil
        gitOpsService = nil
        try await super.tearDown()
    }

    // MARK: - generateWorkspaceFile Tests

    func testGenerateWorkspaceFileSuccess() throws {
        // Create a workspace with repos that have valid local paths
        let repoDir1 = tempDir.appendingPathComponent("repo1")
        let repoDir2 = tempDir.appendingPathComponent("repo2")
        try FileManager.default.createDirectory(at: repoDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoDir2, withIntermediateDirectories: true)

        let workspace = Workspace(name: "Test Workspace")
        let repo1 = Repository(gitlabProjectId: 1, name: "repo1", url: "https://gitlab.com/test/repo1.git", localPath: repoDir1.path)
        let repo2 = Repository(gitlabProjectId: 2, name: "repo2", url: "https://gitlab.com/test/repo2.git", localPath: repoDir2.path)
        workspace.repositories = [repo1, repo2]

        let fileURL = try service.generateWorkspaceFile(workspace: workspace)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Verify file content is valid JSON with correct structure
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["folders"])
        XCTAssertNotNil(json["settings"])

        let folders = json["folders"] as! [[String: String]]
        XCTAssertEqual(folders.count, 2)

        let paths = folders.map { $0["path"]! }
        XCTAssertTrue(paths.contains(repoDir1.path))
        XCTAssertTrue(paths.contains(repoDir2.path))

        // Verify file extension
        XCTAssertEqual(fileURL.pathExtension, "code-workspace")
    }

    func testGenerateWorkspaceFileZeroReposThrows() {
        let workspace = Workspace(name: "Empty Workspace")
        workspace.repositories = []

        XCTAssertThrowsError(try service.generateWorkspaceFile(workspace: workspace)) { error in
            guard let ideError = error as? IDEContextError else {
                XCTFail("Expected IDEContextError, got \(error)")
                return
            }
            if case .noRepositories = ideError {
                // Expected
            } else {
                XCTFail("Expected .noRepositories, got \(ideError)")
            }
        }
    }

    func testGenerateWorkspaceFileNoLocalPathsThrows() {
        let workspace = Workspace(name: "No Local Paths")
        let repo = Repository(gitlabProjectId: 1, name: "repo1", url: "https://gitlab.com/test/repo1.git", localPath: nil)
        workspace.repositories = [repo]

        XCTAssertThrowsError(try service.generateWorkspaceFile(workspace: workspace)) { error in
            guard let ideError = error as? IDEContextError else {
                XCTFail("Expected IDEContextError, got \(error)")
                return
            }
            if case .noRepositories = ideError {
                // Expected - no repos with valid local paths
            } else {
                XCTFail("Expected .noRepositories, got \(ideError)")
            }
        }
    }

    func testGenerateWorkspaceFileSkipsReposWithNonExistentPaths() throws {
        // One repo with valid path, one with non-existent path
        let validDir = tempDir.appendingPathComponent("valid-repo")
        try FileManager.default.createDirectory(at: validDir, withIntermediateDirectories: true)

        let workspace = Workspace(name: "Mixed Workspace")
        let repo1 = Repository(gitlabProjectId: 1, name: "valid", url: "https://gitlab.com/test/valid.git", localPath: validDir.path)
        let repo2 = Repository(gitlabProjectId: 2, name: "missing", url: "https://gitlab.com/test/missing.git", localPath: "/nonexistent/path/repo")
        workspace.repositories = [repo1, repo2]

        let fileURL = try service.generateWorkspaceFile(workspace: workspace)
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let folders = json["folders"] as! [[String: String]]

        // Only the valid repo should be included
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0]["path"], validDir.path)
    }

    func testGenerateWorkspaceFileNameSanitization() throws {
        let repoDir = tempDir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)

        let workspace = Workspace(name: "My Project / v2")
        let repo = Repository(gitlabProjectId: 1, name: "repo", url: "https://gitlab.com/test/repo.git", localPath: repoDir.path)
        workspace.repositories = [repo]

        let fileURL = try service.generateWorkspaceFile(workspace: workspace)

        // Verify filename is sanitized (no slashes)
        XCTAssertEqual(fileURL.lastPathComponent, "My-Project---v2.code-workspace")
    }

    // MARK: - checkLocalAvailability Tests

    func testCheckLocalAvailabilityAllAvailable() throws {
        let repoDir = tempDir.appendingPathComponent("available-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)

        let workspace = Workspace(name: "Test")
        let repo = Repository(gitlabProjectId: 1, name: "repo", url: "https://gitlab.com/test/repo.git", localPath: repoDir.path)
        workspace.repositories = [repo]

        let results = service.checkLocalAvailability(workspace: workspace)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].1, .available)
    }

    func testCheckLocalAvailabilityNotCloned() {
        let workspace = Workspace(name: "Test")
        let repo = Repository(gitlabProjectId: 1, name: "repo", url: "https://gitlab.com/test/repo.git", localPath: nil)
        workspace.repositories = [repo]

        let results = service.checkLocalAvailability(workspace: workspace)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].1, .notCloned)
    }

    func testCheckLocalAvailabilityStalePath() {
        let workspace = Workspace(name: "Test")
        let stalePath = "/nonexistent/path/that/does/not/exist"
        let repo = Repository(gitlabProjectId: 1, name: "repo", url: "https://gitlab.com/test/repo.git", localPath: stalePath)
        workspace.repositories = [repo]

        let results = service.checkLocalAvailability(workspace: workspace)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].1, .stalePath(stalePath))
    }

    func testCheckLocalAvailabilityMixed() throws {
        let availableDir = tempDir.appendingPathComponent("available")
        try FileManager.default.createDirectory(at: availableDir, withIntermediateDirectories: true)

        let workspace = Workspace(name: "Test")
        let repo1 = Repository(gitlabProjectId: 1, name: "available", url: "https://gitlab.com/test/available.git", localPath: availableDir.path)
        let repo2 = Repository(gitlabProjectId: 2, name: "not-cloned", url: "https://gitlab.com/test/not-cloned.git", localPath: nil)
        let repo3 = Repository(gitlabProjectId: 3, name: "stale", url: "https://gitlab.com/test/stale.git", localPath: "/gone/path")
        workspace.repositories = [repo1, repo2, repo3]

        let results = service.checkLocalAvailability(workspace: workspace)

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].1, .available)
        XCTAssertEqual(results[1].1, .notCloned)
        XCTAssertEqual(results[2].1, .stalePath("/gone/path"))
    }

    // MARK: - getMissingRepositories Tests

    func testGetMissingRepositoriesReturnsOnlyMissing() throws {
        let availableDir = tempDir.appendingPathComponent("available")
        try FileManager.default.createDirectory(at: availableDir, withIntermediateDirectories: true)

        let workspace = Workspace(name: "Test")
        let repo1 = Repository(gitlabProjectId: 1, name: "available", url: "https://gitlab.com/test/available.git", localPath: availableDir.path)
        let repo2 = Repository(gitlabProjectId: 2, name: "missing", url: "https://gitlab.com/test/missing.git", localPath: nil)
        workspace.repositories = [repo1, repo2]

        let missing = service.getMissingRepositories(workspace: workspace)

        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing[0].0.name, "missing")
        XCTAssertEqual(missing[0].1, .notCloned)
    }

    // MARK: - getStaleRepositories Tests

    func testGetStaleRepositoriesReturnsOnlyStale() throws {
        let availableDir = tempDir.appendingPathComponent("available")
        try FileManager.default.createDirectory(at: availableDir, withIntermediateDirectories: true)

        let workspace = Workspace(name: "Test")
        let repo1 = Repository(gitlabProjectId: 1, name: "available", url: "https://gitlab.com/test/available.git", localPath: availableDir.path)
        let repo2 = Repository(gitlabProjectId: 2, name: "stale", url: "https://gitlab.com/test/stale.git", localPath: "/old/path/repo")
        let repo3 = Repository(gitlabProjectId: 3, name: "not-cloned", url: "https://gitlab.com/test/not-cloned.git", localPath: nil)
        workspace.repositories = [repo1, repo2, repo3]

        let stale = service.getStaleRepositories(workspace: workspace)

        XCTAssertEqual(stale.count, 1)
        XCTAssertEqual(stale[0].0.name, "stale")
        XCTAssertEqual(stale[0].1, "/old/path/repo")
    }

    // MARK: - cloneMissingRepos Tests

    func testCloneMissingReposWithInvalidURL() async {
        let workspace = Workspace(name: "Test")
        let repo = Repository(gitlabProjectId: 1, name: "bad-url", url: "", localPath: nil)
        workspace.repositories = [repo]

        let baseDir = tempDir.appendingPathComponent("clones")
        let results = await service.cloneMissingRepos(
            repos: [repo],
            baseDirectory: baseDir,
            credentials: GitCredentials(oauthToken: "test-token"),
            progressHandler: nil
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].isSuccess)
        XCTAssertNotNil(results[0].error)
    }

    func testCloneMissingReposPartialFailure() async throws {
        // Create a bare repo for one to succeed
        let bareRepoURL = tempDir.appendingPathComponent("bare-repo.git")
        try await createBareRepo(at: bareRepoURL)

        let workspace = Workspace(name: "Test")
        let goodRepo = Repository(gitlabProjectId: 1, name: "good-repo", url: bareRepoURL.absoluteString, localPath: nil)
        let badRepo = Repository(gitlabProjectId: 2, name: "bad-repo", url: "https://nonexistent.invalid/repo.git", localPath: nil)
        workspace.repositories = [goodRepo, badRepo]

        let baseDir = tempDir.appendingPathComponent("clones")
        let results = await service.cloneMissingRepos(
            repos: [goodRepo, badRepo],
            baseDirectory: baseDir,
            credentials: GitCredentials(oauthToken: "unused-for-local"),
            progressHandler: nil
        )

        XCTAssertEqual(results.count, 2)

        // Good repo should succeed
        let goodResult = results.first { $0.repositoryName == "good-repo" }
        XCTAssertNotNil(goodResult)
        XCTAssertTrue(goodResult!.isSuccess)
        XCTAssertEqual(goodRepo.localPath, baseDir.appendingPathComponent("good-repo").path)

        // Bad repo should fail
        let badResult = results.first { $0.repositoryName == "bad-repo" }
        XCTAssertNotNil(badResult)
        XCTAssertFalse(badResult!.isSuccess)
        XCTAssertNil(badRepo.localPath) // Should not be updated on failure
    }

    func testCloneMissingReposUpdatesLocalPath() async throws {
        let bareRepoURL = tempDir.appendingPathComponent("bare-repo.git")
        try await createBareRepo(at: bareRepoURL)

        let repo = Repository(gitlabProjectId: 1, name: "my-repo", url: bareRepoURL.absoluteString, localPath: nil)

        let baseDir = tempDir.appendingPathComponent("clones")
        let results = await service.cloneMissingRepos(
            repos: [repo],
            baseDirectory: baseDir,
            credentials: GitCredentials(oauthToken: "unused-for-local"),
            progressHandler: nil
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isSuccess)

        // Verify localPath was updated
        let expectedPath = baseDir.appendingPathComponent("my-repo").path
        XCTAssertEqual(repo.localPath, expectedPath)

        // Verify the directory actually exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath))
    }

    func testCloneMissingReposProgressReporting() async throws {
        let bareRepoURL = tempDir.appendingPathComponent("bare-repo.git")
        try await createBareRepo(at: bareRepoURL)

        let repo = Repository(gitlabProjectId: 1, name: "progress-repo", url: bareRepoURL.absoluteString, localPath: nil)

        let baseDir = tempDir.appendingPathComponent("clones")
        let progressUpdates = LockedRecorder<(String, CloneProgress)>()

        let results = await service.cloneMissingRepos(
            repos: [repo],
            baseDirectory: baseDir,
            credentials: GitCredentials(oauthToken: "unused-for-local"),
            progressHandler: { repo, progress in
                progressUpdates.append((repo.name, progress))
            }
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isSuccess)
        XCTAssertFalse(progressUpdates.isEmpty, "Progress should have been reported")
    }

    func testCloneMissingReposEmptyList() async {
        let baseDir = tempDir.appendingPathComponent("clones")
        let results = await service.cloneMissingRepos(
            repos: [],
            baseDirectory: baseDir,
            credentials: GitCredentials(oauthToken: "test"),
            progressHandler: nil
        )

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - openInIDE Tests

    func testOpenInIDEZeroReposThrows() async {
        let workspace = Workspace(name: "Empty")
        workspace.repositories = []

        do {
            try await service.openInIDE(workspace: workspace)
            XCTFail("Should throw noRepositories error")
        } catch let error as IDEContextError {
            if case .noRepositories = error {
                // Expected
            } else {
                XCTFail("Expected .noRepositories, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testOpenInIDENoAvailableReposThrows() async {
        let workspace = Workspace(name: "No Available")
        let repo = Repository(gitlabProjectId: 1, name: "repo", url: "https://gitlab.com/test/repo.git", localPath: nil)
        workspace.repositories = [repo]

        do {
            try await service.openInIDE(workspace: workspace)
            XCTFail("Should throw noRepositories error")
        } catch let error as IDEContextError {
            if case .noRepositories = error {
                // Expected - no repos with valid local paths
            } else {
                XCTFail("Expected .noRepositories, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testOpenInIDE_launchesWorkspaceRootInZed() async throws {
        let rootDirectory = tempDir.appendingPathComponent("workspace-root")
        let repoDirectory = rootDirectory.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repoDirectory, withIntermediateDirectories: true)

        let workspace = Workspace(name: "Test", localRootPath: rootDirectory.path)
        let repo = Repository(
            gitlabProjectId: 1,
            name: "repo",
            url: "https://gitlab.com/test/repo.git",
            localPath: repoDirectory.path
        )
        workspace.repositories = [repo]

        var launchedDirectory: URL?
        let launchService = IDEContextService(
            gitOperationsService: gitOpsService,
            fileManager: .default,
            zedLauncher: { directory in
                launchedDirectory = directory
                return true
            }
        )

        try await launchService.openInIDE(workspace: workspace)

        XCTAssertEqual(launchedDirectory?.standardizedFileURL.path, rootDirectory.standardizedFileURL.path)
    }

    // MARK: - RepositoryAvailability Tests

    func testRepositoryAvailabilityEquatable() {
        XCTAssertEqual(RepositoryAvailability.available, RepositoryAvailability.available)
        XCTAssertEqual(RepositoryAvailability.notCloned, RepositoryAvailability.notCloned)
        XCTAssertEqual(RepositoryAvailability.stalePath("/path"), RepositoryAvailability.stalePath("/path"))
        XCTAssertNotEqual(RepositoryAvailability.available, RepositoryAvailability.notCloned)
        XCTAssertNotEqual(RepositoryAvailability.stalePath("/a"), RepositoryAvailability.stalePath("/b"))
    }

    func testRepositoryAvailabilityIsAvailable() {
        XCTAssertTrue(RepositoryAvailability.available.isAvailable)
        XCTAssertFalse(RepositoryAvailability.notCloned.isAvailable)
        XCTAssertFalse(RepositoryAvailability.stalePath("/path").isAvailable)
    }

    // MARK: - CloneOperationResult Tests

    func testCloneOperationResultSuccess() {
        let url = URL(fileURLWithPath: "/path/to/repo")
        let result = CloneOperationResult(
            repositoryId: UUID(),
            repositoryName: "test-repo",
            result: .success(url)
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.clonedURL, url)
        XCTAssertNil(result.error)
    }

    func testCloneOperationResultFailure() {
        let error = IDEContextError.workspaceFileGenerationFailed("test error")
        let result = CloneOperationResult(
            repositoryId: UUID(),
            repositoryName: "test-repo",
            result: .failure(error)
        )

        XCTAssertFalse(result.isSuccess)
        XCTAssertNil(result.clonedURL)
        XCTAssertNotNil(result.error)
    }

    // MARK: - Helper Methods

    private func createBareRepo(at url: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "--bare", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "TestSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bare repo"])
        }
    }
}
