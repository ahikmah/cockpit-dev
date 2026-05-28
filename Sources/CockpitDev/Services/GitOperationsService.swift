import Foundation

// MARK: - GitOperationsService

/// Actor-based service for performing Git operations (clone, pull, push, commit, status).
///
/// Uses the system `git` command-line tool via `Process` for reliable Git operations
/// with progress reporting via @Sendable closures.
///
/// Implements Requirement 15: Git Operations
actor GitOperationsService {

    // MARK: - Properties

    /// The path to the git executable.
    private let gitPath: String

    // MARK: - Initialization

    /// Creates a GitOperationsService.
    /// - Parameter gitPath: Path to the git executable (default: /usr/bin/git)
    init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    // MARK: - Clone

    /// Clones a remote repository to a local path with progress reporting.
    ///
    /// - Parameters:
    ///   - remoteURL: The remote repository URL.
    ///   - localPath: The local directory to clone into.
    ///   - credentials: Git credentials for authentication.
    ///   - progressHandler: Closure called with progress updates.
    /// - Throws: `GitOperationError.directoryConflict` if the directory exists and is non-empty,
    ///           `GitOperationError.cloneFailed` if the clone operation fails.
    func clone(
        remoteURL: URL,
        localPath: URL,
        credentials: GitCredentials,
        progressHandler: @escaping @Sendable (CloneProgress) -> Void
    ) async throws {
        // Check for directory conflict
        try validateCloneDirectory(localPath)

        // Build authenticated URL
        guard let authenticatedURL = credentials.authenticatedURL(for: remoteURL) else {
            throw GitOperationError.cloneFailed("Failed to construct authenticated URL")
        }

        progressHandler(CloneProgress(
            phase: .counting,
            percentage: 0,
            message: "Starting clone..."
        ))

        let arguments = [
            "clone",
            "--progress",
            authenticatedURL.absoluteString,
            localPath.path
        ]

        let result = try await runGitWithProgress(
            arguments: arguments,
            workingDirectory: nil
        ) { line in
            let progress = Self.parseCloneProgress(line)
            progressHandler(progress)
        }

        if result.exitCode != 0 {
            let error = classifyError(result.stderr)
            throw error ?? GitOperationError.cloneFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        progressHandler(CloneProgress(
            phase: .done,
            percentage: 100,
            message: "Clone complete"
        ))
    }

    // MARK: - Pull

    /// Performs a pull (fetch + merge) operation with progress reporting.
    ///
    /// - Parameters:
    ///   - localPath: The local repository path.
    ///   - credentials: Git credentials for authentication.
    ///   - progressHandler: Closure called with progress updates.
    /// - Throws: `GitOperationError.pullFailed` if the operation fails,
    ///           `GitOperationError.mergeConflict` if there are merge conflicts.
    func pull(
        localPath: URL,
        credentials: GitCredentials,
        progressHandler: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        try validateRepository(at: localPath)

        // Configure credential helper for this operation
        let credentialEnv = buildCredentialEnvironment(credentials: credentials, remoteURL: nil, localPath: localPath)

        progressHandler(TransferProgress(
            percentage: 0,
            message: "Fetching from remote...",
            isComplete: false
        ))

        // Fetch
        let fetchResult = try await runGitWithProgress(
            arguments: ["fetch", "--progress", "origin"],
            workingDirectory: localPath.path,
            environment: credentialEnv
        ) { line in
            let progress = Self.parseTransferProgress(line)
            progressHandler(progress)
        }

        if fetchResult.exitCode != 0 {
            let error = classifyError(fetchResult.stderr)
            throw error ?? GitOperationError.pullFailed(fetchResult.stderr.isEmpty ? fetchResult.stdout : fetchResult.stderr)
        }

        progressHandler(TransferProgress(
            percentage: 50,
            message: "Merging changes...",
            isComplete: false
        ))

        // Merge
        let mergeResult = try await runGit(
            arguments: ["merge", "FETCH_HEAD"],
            workingDirectory: localPath.path
        )

        if mergeResult.exitCode != 0 {
            if mergeResult.stderr.contains("CONFLICT") || mergeResult.stdout.contains("CONFLICT") {
                throw GitOperationError.mergeConflict(mergeResult.stdout + "\n" + mergeResult.stderr)
            }
            let error = classifyError(mergeResult.stderr)
            throw error ?? GitOperationError.pullFailed(mergeResult.stderr.isEmpty ? mergeResult.stdout : mergeResult.stderr)
        }

        progressHandler(TransferProgress(
            percentage: 100,
            message: "Pull complete",
            isComplete: true
        ))
    }

    // MARK: - Push

    /// Pushes local commits to the remote repository with progress reporting.
    ///
    /// - Parameters:
    ///   - localPath: The local repository path.
    ///   - credentials: Git credentials for authentication.
    ///   - progressHandler: Closure called with progress updates.
    /// - Throws: `GitOperationError.pushFailed` if the operation fails.
    func push(
        localPath: URL,
        credentials: GitCredentials,
        progressHandler: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        try validateRepository(at: localPath)

        let credentialEnv = buildCredentialEnvironment(credentials: credentials, remoteURL: nil, localPath: localPath)

        progressHandler(TransferProgress(
            percentage: 0,
            message: "Pushing to remote...",
            isComplete: false
        ))

        let result = try await runGitWithProgress(
            arguments: ["push", "--progress", "origin", "HEAD"],
            workingDirectory: localPath.path,
            environment: credentialEnv
        ) { line in
            let progress = Self.parseTransferProgress(line)
            progressHandler(progress)
        }

        if result.exitCode != 0 {
            let error = classifyError(result.stderr)
            throw error ?? GitOperationError.pushFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        progressHandler(TransferProgress(
            percentage: 100,
            message: "Push complete",
            isComplete: true
        ))
    }

    // MARK: - Commit

    /// Stages specified files and creates a commit with the given message.
    ///
    /// - Parameters:
    ///   - localPath: The local repository path.
    ///   - files: Array of file paths (relative to repo root) to stage.
    ///   - message: The commit message (1-500 characters).
    ///   - author: The commit author information.
    /// - Throws: `GitOperationError.emptyCommit` if no files are provided,
    ///           `GitOperationError.invalidCommitMessage` if message is invalid,
    ///           `GitOperationError.commitFailed` if the commit fails.
    func commit(
        localPath: URL,
        files: [String],
        message: String,
        author: GitAuthor
    ) async throws {
        try validateRepository(at: localPath)

        // Validate commit message (1-500 characters)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw GitOperationError.invalidCommitMessage("Commit message cannot be empty.")
        }
        guard trimmedMessage.count <= 500 else {
            throw GitOperationError.invalidCommitMessage("Commit message must be 500 characters or fewer (currently \(trimmedMessage.count)).")
        }

        // Validate files are provided
        guard !files.isEmpty else {
            throw GitOperationError.emptyCommit
        }

        // Stage files
        let addResult = try await runGit(
            arguments: ["add"] + files,
            workingDirectory: localPath.path
        )

        if addResult.exitCode != 0 {
            throw GitOperationError.commitFailed("Failed to stage files: \(addResult.stderr)")
        }

        // Verify there are staged changes (prevent empty commits)
        let diffResult = try await runGit(
            arguments: ["diff", "--cached", "--quiet"],
            workingDirectory: localPath.path
        )

        // Exit code 0 means no differences (nothing staged)
        if diffResult.exitCode == 0 {
            throw GitOperationError.emptyCommit
        }

        // Create commit
        let commitResult = try await runGit(
            arguments: [
                "commit",
                "-m", trimmedMessage,
                "--author=\(author.name) <\(author.email)>"
            ],
            workingDirectory: localPath.path
        )

        if commitResult.exitCode != 0 {
            throw GitOperationError.commitFailed(commitResult.stderr.isEmpty ? commitResult.stdout : commitResult.stderr)
        }
    }

    // MARK: - Status

    /// Returns the status of files in the working directory.
    ///
    /// - Parameter localPath: The local repository path.
    /// - Returns: Array of `FileStatus` representing the state of each changed file.
    /// - Throws: `GitOperationError.statusFailed` if the status command fails.
    func status(localPath: URL) async throws -> [FileStatus] {
        try validateRepository(at: localPath)

        let result = try await runGit(
            arguments: ["status", "--porcelain=v1"],
            workingDirectory: localPath.path
        )

        if result.exitCode != 0 {
            throw GitOperationError.statusFailed(result.stderr)
        }

        return parseStatusOutput(result.stdout)
    }

    // MARK: - Private Helpers

    /// Validates that the clone target directory doesn't conflict.
    private func validateCloneDirectory(_ localPath: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: localPath.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                // Check if directory is non-empty
                let contents = try? fileManager.contentsOfDirectory(atPath: localPath.path)
                if let contents = contents, !contents.isEmpty {
                    throw GitOperationError.directoryConflict(localPath.path)
                }
            } else {
                // A file exists at this path
                throw GitOperationError.directoryConflict(localPath.path)
            }
        }
    }

    /// Validates that a path contains a valid Git repository.
    private func validateRepository(at localPath: URL) throws {
        let gitDir = localPath.appendingPathComponent(".git")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: localPath.path) else {
            throw GitOperationError.repositoryNotFound(localPath.path)
        }

        guard fileManager.fileExists(atPath: gitDir.path) else {
            throw GitOperationError.invalidRepository(localPath.path)
        }
    }

    /// Builds environment variables for credential injection.
    private func buildCredentialEnvironment(
        credentials: GitCredentials,
        remoteURL: URL?,
        localPath: URL?
    ) -> [String: String] {
        // Use GIT_ASKPASS with a helper script that provides the token
        // This avoids storing credentials in the URL or on disk
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"

        // Create a temporary credential helper script
        let helperScript = "!f() { echo \"username=\(credentials.username)\"; echo \"password=\(credentials.oauthToken)\"; }; f"
        env["GIT_CONFIG_COUNT"] = "1"
        env["GIT_CONFIG_KEY_0"] = "credential.helper"
        env["GIT_CONFIG_VALUE_0"] = helperScript

        return env
    }

    /// Classifies a git error output into a specific error type.
    private func classifyError(_ output: String) -> GitOperationError? {
        let lowercased = output.lowercased()

        if lowercased.contains("authentication") || lowercased.contains("401") ||
           lowercased.contains("could not read username") || lowercased.contains("invalid credentials") {
            return .authenticationFailed(output)
        }

        if lowercased.contains("could not resolve host") || lowercased.contains("network") ||
           lowercased.contains("unable to access") || lowercased.contains("connection refused") ||
           lowercased.contains("timed out") {
            return .networkError(output)
        }

        if lowercased.contains("conflict") || lowercased.contains("merge conflict") {
            return .mergeConflict(output)
        }

        return nil
    }

    /// Parses `git status --porcelain=v1` output into FileStatus array.
    private func parseStatusOutput(_ output: String) -> [FileStatus] {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        return lines.compactMap { line in
            guard line.count >= 3 else { return nil }

            let indexStatus = line[line.startIndex]
            let workTreeStatus = line[line.index(after: line.startIndex)]
            let filePath = String(line.dropFirst(3))

            // Determine the most relevant state
            let state: FileStatus.FileState
            if indexStatus == "?" && workTreeStatus == "?" {
                state = .untracked
            } else if indexStatus == "!" && workTreeStatus == "!" {
                state = .ignored
            } else if indexStatus == "U" || workTreeStatus == "U" ||
                      (indexStatus == "A" && workTreeStatus == "A") ||
                      (indexStatus == "D" && workTreeStatus == "D") {
                state = .unmerged
            } else if indexStatus == "A" || workTreeStatus == "A" {
                state = .added
            } else if indexStatus == "D" || workTreeStatus == "D" {
                state = .deleted
            } else if indexStatus == "R" || workTreeStatus == "R" {
                state = .renamed
            } else if indexStatus == "C" || workTreeStatus == "C" {
                state = .copied
            } else if indexStatus == "T" || workTreeStatus == "T" {
                state = .typeChanged
            } else if indexStatus == "M" || workTreeStatus == "M" {
                state = .modified
            } else {
                state = .modified // Default fallback
            }

            return FileStatus(path: filePath, state: state)
        }
    }

    // MARK: - Process Execution

    /// Result of a git command execution.
    private struct GitResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Runs a git command and returns the result.
    private func runGit(
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]? = nil
    ) async throws -> GitResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = arguments

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            if let environment = environment {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: GitResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                ))
            } catch {
                continuation.resume(throwing: GitOperationError.cloneFailed("Failed to launch git: \(error.localizedDescription)"))
            }
        }
    }

    /// Runs a git command with real-time progress parsing from stderr.
    private func runGitWithProgress(
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]? = nil,
        lineHandler: @Sendable @escaping (String) -> Void
    ) async throws -> GitResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = arguments

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            if let environment = environment {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stderrRecorder = GitOutputRecorder()

            // Read stderr for progress (git outputs progress to stderr)
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let line = String(data: data, encoding: .utf8) {
                    stderrRecorder.append(line)
                    // Parse each line for progress
                    let lines = line.components(separatedBy: CharacterSet.newlines)
                    for l in lines where !l.trimmingCharacters(in: .whitespaces).isEmpty {
                        lineHandler(l)
                    }
                }
            }

            do {
                try process.run()
                process.waitUntilExit()

                // Stop reading
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

                // Read any remaining stderr
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if let remaining = String(data: remainingStderr, encoding: .utf8), !remaining.isEmpty {
                    stderrRecorder.append(remaining)
                }

                let stderrOutput = stderrRecorder.joined()

                continuation.resume(returning: GitResult(
                    stdout: stdout,
                    stderr: stderrOutput,
                    exitCode: process.terminationStatus
                ))
            } catch {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: GitOperationError.cloneFailed("Failed to launch git: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Progress Parsing

    /// Parses clone progress output from git stderr.
    static func parseCloneProgress(_ line: String) -> CloneProgress {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract percentage from patterns like "Receiving objects:  45% (123/456)"
        let percentage = extractPercentage(from: trimmed)

        if trimmed.contains("Counting") {
            return CloneProgress(phase: .counting, percentage: percentage, message: trimmed)
        } else if trimmed.contains("Compressing") {
            return CloneProgress(phase: .compressing, percentage: percentage, message: trimmed)
        } else if trimmed.contains("Receiving") {
            return CloneProgress(phase: .receiving, percentage: percentage, message: trimmed)
        } else if trimmed.contains("Resolving") {
            return CloneProgress(phase: .resolving, percentage: percentage, message: trimmed)
        } else if trimmed.contains("Checking out") || trimmed.contains("checkout") {
            return CloneProgress(phase: .checkingOut, percentage: percentage, message: trimmed)
        } else {
            return CloneProgress(phase: .receiving, percentage: percentage, message: trimmed)
        }
    }

    /// Parses transfer progress output from git stderr.
    static func parseTransferProgress(_ line: String) -> TransferProgress {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let percentage = extractPercentage(from: trimmed)

        return TransferProgress(
            percentage: percentage,
            message: trimmed,
            isComplete: percentage == 100
        )
    }

    /// Extracts a percentage value from a git progress line.
    /// Matches patterns like "45%" or "45% (123/456)"
    private static func extractPercentage(from line: String) -> Int? {
        // Match pattern: number followed by %
        let pattern = #"(\d+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Int(line[range])
    }
}

private final class GitOutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []

    func append(_ chunk: String) {
        lock.lock()
        chunks.append(chunk)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks.joined()
    }
}
