import XCTest
@testable import CockpitDev

/// Integration tests for GitOperationsService using a local bare repository.
///
/// These tests create temporary Git repositories to verify clone, pull, push,
/// commit, and status operations work correctly.
final class GitOperationsServiceTests: XCTestCase {

    private var service: GitOperationsService!
    private var tempDir: URL!
    private var bareRepoURL: URL!
    private var workingRepoURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        service = GitOperationsService()

        // Create a temporary directory for test repos
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitOpsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a bare repository for testing
        bareRepoURL = tempDir.appendingPathComponent("test-bare.git")
        try await createBareRepo(at: bareRepoURL)

        // Create a working repository with initial commit
        workingRepoURL = tempDir.appendingPathComponent("test-working")
        try await createWorkingRepo(at: workingRepoURL, bareRepoURL: bareRepoURL)
    }

    override func tearDown() async throws {
        // Clean up temp directory
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        service = nil
        try await super.tearDown()
    }

    // MARK: - Clone Tests

    func testCloneSuccess() async throws {
        let cloneDestination = tempDir.appendingPathComponent("cloned-repo")
        var progressUpdates: [CloneProgress] = []

        try await service.clone(
            remoteURL: bareRepoURL,
            localPath: cloneDestination,
            credentials: GitCredentials(oauthToken: "unused-for-local"),
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )

        // Verify the clone was successful
        let gitDir = cloneDestination.appendingPathComponent(".git")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitDir.path),
                      "Cloned repository should have a .git directory")

        // Verify initial file exists
        let readmeFile = cloneDestination.appendingPathComponent("README.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: readmeFile.path),
                      "Cloned repository should contain README.md")

        // Verify progress was reported
        XCTAssertFalse(progressUpdates.isEmpty, "Progress should have been reported")
    }

    func testCloneDirectoryConflict() async throws {
        // Create a non-empty directory at the target path
        let conflictDir = tempDir.appendingPathComponent("conflict-dir")
        try FileManager.default.createDirectory(at: conflictDir, withIntermediateDirectories: true)
        let dummyFile = conflictDir.appendingPathComponent("existing-file.txt")
        try "existing content".write(to: dummyFile, atomically: true, encoding: .utf8)

        do {
            try await service.clone(
                remoteURL: bareRepoURL,
                localPath: conflictDir,
                credentials: GitCredentials(oauthToken: "unused"),
                progressHandler: { _ in }
            )
            XCTFail("Clone should have thrown directoryConflict error")
        } catch let error as GitOperationError {
            if case .directoryConflict = error {
                // Expected
            } else {
                XCTFail("Expected directoryConflict error, got: \(error)")
            }
        }
    }

    func testCloneEmptyDirectorySucceeds() async throws {
        // Create an empty directory - clone should succeed
        let emptyDir = tempDir.appendingPathComponent("empty-dir")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        try await service.clone(
            remoteURL: bareRepoURL,
            localPath: emptyDir,
            credentials: GitCredentials(oauthToken: "unused-for-local"),
            progressHandler: { _ in }
        )

        let gitDir = emptyDir.appendingPathComponent(".git")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitDir.path))
    }

    // MARK: - Commit Tests

    func testCommitSuccess() async throws {
        // Create a new file in the working repo
        let newFile = workingRepoURL.appendingPathComponent("new-file.txt")
        try "Hello, World!".write(to: newFile, atomically: true, encoding: .utf8)

        try await service.commit(
            localPath: workingRepoURL,
            files: ["new-file.txt"],
            message: "Add new file",
            author: GitAuthor(name: "Test User", email: "test@example.com")
        )

        // Verify the commit was created by checking git log
        let logResult = try await runGit(
            arguments: ["log", "--oneline", "-1"],
            at: workingRepoURL
        )
        XCTAssertTrue(logResult.contains("Add new file"),
                      "Commit message should appear in git log")
    }

    func testCommitEmptyFilesThrows() async throws {
        do {
            try await service.commit(
                localPath: workingRepoURL,
                files: [],
                message: "Empty commit",
                author: GitAuthor(name: "Test", email: "test@example.com")
            )
            XCTFail("Should throw emptyCommit error")
        } catch let error as GitOperationError {
            XCTAssertEqual(error, .emptyCommit)
        }
    }

    func testCommitEmptyMessageThrows() async throws {
        let newFile = workingRepoURL.appendingPathComponent("file.txt")
        try "content".write(to: newFile, atomically: true, encoding: .utf8)

        do {
            try await service.commit(
                localPath: workingRepoURL,
                files: ["file.txt"],
                message: "",
                author: GitAuthor(name: "Test", email: "test@example.com")
            )
            XCTFail("Should throw invalidCommitMessage error")
        } catch let error as GitOperationError {
            if case .invalidCommitMessage = error {
                // Expected
            } else {
                XCTFail("Expected invalidCommitMessage, got: \(error)")
            }
        }
    }

    func testCommitMessageTooLongThrows() async throws {
        let newFile = workingRepoURL.appendingPathComponent("file.txt")
        try "content".write(to: newFile, atomically: true, encoding: .utf8)

        let longMessage = String(repeating: "a", count: 501)

        do {
            try await service.commit(
                localPath: workingRepoURL,
                files: ["file.txt"],
                message: longMessage,
                author: GitAuthor(name: "Test", email: "test@example.com")
            )
            XCTFail("Should throw invalidCommitMessage error")
        } catch let error as GitOperationError {
            if case .invalidCommitMessage = error {
                // Expected
            } else {
                XCTFail("Expected invalidCommitMessage, got: \(error)")
            }
        }
    }

    func testCommitMessageExactly500CharsSucceeds() async throws {
        let newFile = workingRepoURL.appendingPathComponent("file500.txt")
        try "content".write(to: newFile, atomically: true, encoding: .utf8)

        let message = String(repeating: "a", count: 500)

        try await service.commit(
            localPath: workingRepoURL,
            files: ["file500.txt"],
            message: message,
            author: GitAuthor(name: "Test", email: "test@example.com")
        )

        // Verify commit was created
        let logResult = try await runGit(
            arguments: ["log", "--oneline", "-1"],
            at: workingRepoURL
        )
        XCTAssertFalse(logResult.isEmpty)
    }

    func testCommitNoChangesThrowsEmptyCommit() async throws {
        // Try to commit a file that hasn't changed (already committed)
        do {
            try await service.commit(
                localPath: workingRepoURL,
                files: ["README.md"],
                message: "No changes",
                author: GitAuthor(name: "Test", email: "test@example.com")
            )
            XCTFail("Should throw emptyCommit error")
        } catch let error as GitOperationError {
            XCTAssertEqual(error, .emptyCommit)
        }
    }

    // MARK: - Status Tests

    func testStatusCleanRepo() async throws {
        let statuses = try await service.status(localPath: workingRepoURL)
        XCTAssertTrue(statuses.isEmpty, "Clean repo should have no status entries")
    }

    func testStatusWithModifiedFile() async throws {
        // Modify an existing file
        let readmeFile = workingRepoURL.appendingPathComponent("README.md")
        try "Modified content".write(to: readmeFile, atomically: true, encoding: .utf8)

        let statuses = try await service.status(localPath: workingRepoURL)
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses.first?.path, "README.md")
        XCTAssertEqual(statuses.first?.state, .modified)
    }

    func testStatusWithUntrackedFile() async throws {
        // Create a new untracked file
        let newFile = workingRepoURL.appendingPathComponent("untracked.txt")
        try "new content".write(to: newFile, atomically: true, encoding: .utf8)

        let statuses = try await service.status(localPath: workingRepoURL)
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses.first?.path, "untracked.txt")
        XCTAssertEqual(statuses.first?.state, .untracked)
    }

    func testStatusWithDeletedFile() async throws {
        // Delete a tracked file
        let readmeFile = workingRepoURL.appendingPathComponent("README.md")
        try FileManager.default.removeItem(at: readmeFile)

        let statuses = try await service.status(localPath: workingRepoURL)
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses.first?.path, "README.md")
        XCTAssertEqual(statuses.first?.state, .deleted)
    }

    func testStatusWithMultipleChanges() async throws {
        // Modify a file
        let readmeFile = workingRepoURL.appendingPathComponent("README.md")
        try "Modified".write(to: readmeFile, atomically: true, encoding: .utf8)

        // Add a new file
        let newFile = workingRepoURL.appendingPathComponent("new.txt")
        try "new".write(to: newFile, atomically: true, encoding: .utf8)

        let statuses = try await service.status(localPath: workingRepoURL)
        XCTAssertEqual(statuses.count, 2)

        let paths = Set(statuses.map(\.path))
        XCTAssertTrue(paths.contains("README.md"))
        XCTAssertTrue(paths.contains("new.txt"))
    }

    // MARK: - Push Tests

    func testPushSuccess() async throws {
        // Create and commit a new file
        let newFile = workingRepoURL.appendingPathComponent("push-test.txt")
        try "push content".write(to: newFile, atomically: true, encoding: .utf8)

        try await service.commit(
            localPath: workingRepoURL,
            files: ["push-test.txt"],
            message: "Add push test file",
            author: GitAuthor(name: "Test", email: "test@example.com")
        )

        var progressUpdates: [TransferProgress] = []

        // Push to the bare repo (local, no auth needed)
        try await service.push(
            localPath: workingRepoURL,
            credentials: GitCredentials(oauthToken: "unused-for-local"),
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )

        // Verify the push was successful by checking the bare repo
        let logResult = try await runGit(
            arguments: ["log", "--oneline", "-1"],
            at: bareRepoURL
        )
        XCTAssertTrue(logResult.contains("Add push test file"))
    }

    // MARK: - Pull Tests

    func testPullSuccess() async throws {
        // Create a second clone to push changes from
        let secondClone = tempDir.appendingPathComponent("second-clone")
        try await runGitCommand(["clone", bareRepoURL.path, secondClone.path])

        // Make a change in the second clone and push
        let newFile = secondClone.appendingPathComponent("pulled-file.txt")
        try "pulled content".write(to: newFile, atomically: true, encoding: .utf8)
        try await runGitCommand(["add", "pulled-file.txt"], at: secondClone)
        try await runGitCommand(["commit", "-m", "Add pulled file", "--author=Other <other@test.com>"], at: secondClone)
        try await runGitCommand(["push", "origin", "main"], at: secondClone)

        var progressUpdates: [TransferProgress] = []

        // Pull in the original working repo
        try await service.pull(
            localPath: workingRepoURL,
            credentials: GitCredentials(oauthToken: "unused-for-local"),
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )

        // Verify the pulled file exists
        let pulledFile = workingRepoURL.appendingPathComponent("pulled-file.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pulledFile.path),
                      "Pulled file should exist in working repo")
    }

    // MARK: - Repository Validation Tests

    func testStatusInvalidRepositoryThrows() async throws {
        let nonRepoDir = tempDir.appendingPathComponent("not-a-repo")
        try FileManager.default.createDirectory(at: nonRepoDir, withIntermediateDirectories: true)

        do {
            _ = try await service.status(localPath: nonRepoDir)
            XCTFail("Should throw invalidRepository error")
        } catch let error as GitOperationError {
            if case .invalidRepository = error {
                // Expected
            } else {
                XCTFail("Expected invalidRepository, got: \(error)")
            }
        }
    }

    func testStatusNonExistentPathThrows() async throws {
        let nonExistentPath = tempDir.appendingPathComponent("does-not-exist")

        do {
            _ = try await service.status(localPath: nonExistentPath)
            XCTFail("Should throw repositoryNotFound error")
        } catch let error as GitOperationError {
            if case .repositoryNotFound = error {
                // Expected
            } else {
                XCTFail("Expected repositoryNotFound, got: \(error)")
            }
        }
    }

    // MARK: - Progress Parsing Tests

    func testParseCloneProgressReceiving() {
        let line = "Receiving objects:  45% (123/456)"
        let progress = GitOperationsService.parseCloneProgress(line)
        XCTAssertEqual(progress.phase, .receiving)
        XCTAssertEqual(progress.percentage, 45)
    }

    func testParseCloneProgressResolving() {
        let line = "Resolving deltas: 100% (50/50), done."
        let progress = GitOperationsService.parseCloneProgress(line)
        XCTAssertEqual(progress.phase, .resolving)
        XCTAssertEqual(progress.percentage, 100)
    }

    func testParseCloneProgressCounting() {
        let line = "Counting objects: 100% (10/10), done."
        let progress = GitOperationsService.parseCloneProgress(line)
        XCTAssertEqual(progress.phase, .counting)
        XCTAssertEqual(progress.percentage, 100)
    }

    func testParseTransferProgress() {
        let line = "Writing objects:  75% (3/4)"
        let progress = GitOperationsService.parseTransferProgress(line)
        XCTAssertEqual(progress.percentage, 75)
        XCTAssertFalse(progress.isComplete)
    }

    func testParseTransferProgressComplete() {
        let line = "Writing objects: 100% (4/4), done."
        let progress = GitOperationsService.parseTransferProgress(line)
        XCTAssertEqual(progress.percentage, 100)
        XCTAssertTrue(progress.isComplete)
    }

    // MARK: - Git Model Tests

    func testGitCredentialsAuthenticatedURL() {
        let credentials = GitCredentials(oauthToken: "my-token", username: "oauth2")
        let remoteURL = URL(string: "https://gitlab.com/user/repo.git")!

        let authenticatedURL = credentials.authenticatedURL(for: remoteURL)
        XCTAssertNotNil(authenticatedURL)
        XCTAssertTrue(authenticatedURL!.absoluteString.contains("oauth2"))
        XCTAssertTrue(authenticatedURL!.absoluteString.contains("my-token"))
    }

    func testFileStatusEquatable() {
        let status1 = FileStatus(path: "file.txt", state: .modified)
        let status2 = FileStatus(path: "file.txt", state: .modified)
        let status3 = FileStatus(path: "other.txt", state: .added)

        XCTAssertEqual(status1, status2)
        XCTAssertNotEqual(status1, status3)
    }

    func testFileStatusIdentifiable() {
        let status = FileStatus(path: "src/main.swift", state: .modified)
        XCTAssertEqual(status.id, "src/main.swift")
    }

    func testGitOperationErrorEquatable() {
        XCTAssertEqual(GitOperationError.emptyCommit, GitOperationError.emptyCommit)
        XCTAssertEqual(
            GitOperationError.directoryConflict("/path"),
            GitOperationError.directoryConflict("/path")
        )
        XCTAssertNotEqual(
            GitOperationError.emptyCommit,
            GitOperationError.invalidCommitMessage("test")
        )
    }

    // MARK: - Helper Methods

    /// Creates a bare Git repository at the specified path.
    private func createBareRepo(at url: URL) async throws {
        try await runGitCommand(["init", "--bare", url.path])
    }

    /// Creates a working repository with an initial commit, connected to the bare repo.
    private func createWorkingRepo(at url: URL, bareRepoURL: URL) async throws {
        try await runGitCommand(["clone", bareRepoURL.path, url.path])

        // Configure user for commits
        try await runGitCommand(["config", "user.email", "test@example.com"], at: url)
        try await runGitCommand(["config", "user.name", "Test User"], at: url)

        // Create initial commit
        let readmeFile = url.appendingPathComponent("README.md")
        try "# Test Repository\n\nThis is a test repository.".write(
            to: readmeFile, atomically: true, encoding: .utf8
        )

        try await runGitCommand(["add", "README.md"], at: url)
        try await runGitCommand(["commit", "-m", "Initial commit"], at: url)
        try await runGitCommand(["push", "origin", "HEAD:main"], at: url)

        // Set up tracking
        try await runGitCommand(["branch", "--set-upstream-to=origin/main"], at: url)
    }

    /// Runs a git command and returns stdout.
    private func runGit(arguments: [String], at url: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Runs a git command (fire and forget, checks exit code).
    private func runGitCommand(_ arguments: [String], at url: URL? = nil) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        if let url = url {
            process.currentDirectoryURL = url
        }

        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrPipe = process.standardError as! Pipe
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
            // Don't throw for non-critical setup commands (like branch tracking)
            if !stderr.contains("fatal") || stderr.contains("warning") {
                return
            }
        }
    }
}
