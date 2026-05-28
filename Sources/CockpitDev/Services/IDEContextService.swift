import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif

// MARK: - IDE Context Errors

/// Errors that can occur during IDE context operations.
enum IDEContextError: Error, LocalizedError {
    case noRepositories
    case workspaceFileGenerationFailed(String)
    case launchFailed(String)
    case repositoryNotCloned(String)
    case allClonesFailed([String])

    var errorDescription: String? {
        switch self {
        case .noRepositories:
            return "No repositories are available in this workspace."
        case .workspaceFileGenerationFailed(let reason):
            return "Failed to generate workspace file: \(reason)"
        case .launchFailed(let reason):
            return "Failed to open in IDE: \(reason)"
        case .repositoryNotCloned(let name):
            return "Repository '\(name)' is not cloned locally."
        case .allClonesFailed(let failures):
            let names = failures.joined(separator: ", ")
            return "All repository clones failed: \(names)"
        }
    }
}

// MARK: - Repository Availability

/// Represents the local availability status of a repository.
enum RepositoryAvailability: Equatable {
    /// Repository has a local path and the path exists on disk.
    case available
    /// Repository has never been cloned (no local path set).
    case notCloned
    /// Repository had a local path but the path no longer exists (stale).
    case stalePath(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

// MARK: - Clone Result

/// Result of a batch clone operation for a single repository.
struct CloneOperationResult: Sendable {
    let repositoryId: UUID
    let repositoryName: String
    let result: Result<URL, Error>

    var isSuccess: Bool {
        if case .success = result { return true }
        return false
    }

    var clonedURL: URL? {
        if case .success(let url) = result { return url }
        return nil
    }

    var error: Error? {
        if case .failure(let error) = result { return error }
        return nil
    }
}

/// Sendable repository identity used by clone progress callbacks.
struct RepositoryProgressContext: Sendable {
    let id: UUID
    let name: String
}

// MARK: - IDE Context Service

/// Service responsible for generating VS Code multi-root workspace files
/// and launching the IDE with all workspace repositories.
///
/// Implements Requirement 14: Multi-Repo IDE Context
///
/// Key behaviors:
/// - Generates .code-workspace JSON files listing all repository local paths
/// - Launches the system-default application for .code-workspace files via NSWorkspace
/// - Detects missing/stale repository paths and offers re-clone
/// - Performs batch clone with per-repo progress and partial failure handling
/// - Guards against zero-repos workspaces (shows message, doesn't generate file)
@MainActor
class IDEContextService {

    // MARK: - Dependencies

    private let gitOperationsService: GitOperationsService
    private let fileManager: FileManager
    private let zedLauncher: (URL) -> Bool

    // MARK: - Initialization

    /// Creates an IDEContextService.
    /// - Parameters:
    ///   - gitOperationsService: The service used for cloning repositories.
    ///   - fileManager: The file manager for path existence checks (default: .default).
    init(
        gitOperationsService: GitOperationsService = GitOperationsService(),
        fileManager: FileManager = .default,
        zedLauncher: ((URL) -> Bool)? = nil
    ) {
        self.gitOperationsService = gitOperationsService
        self.fileManager = fileManager
        self.zedLauncher = zedLauncher ?? Self.openDirectoryInZed
    }

    // MARK: - Workspace Local Root

    /// Returns the shared local folder that contains all repositories in a workspace.
    func localRootDirectory(for workspace: Workspace) -> URL {
        if let configuredRoot = workspace.localRootPath, !configuredRoot.isEmpty {
            return URL(fileURLWithPath: configuredRoot, isDirectory: true)
        }

        if let existingPath = workspace.repositories.compactMap(\.localPath).first {
            let inferredRoot = URL(fileURLWithPath: existingPath, isDirectory: true)
                .deletingLastPathComponent()
            workspace.localRootPath = inferredRoot.path
            return inferredRoot
        }

        let sanitizedName = workspace.name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/CockpitDev", isDirectory: true)
            .appendingPathComponent(sanitizedName, isDirectory: true)
        workspace.localRootPath = root.path
        return root
    }

    // MARK: - Generate Workspace File

    /// Generates a .code-workspace file containing all locally-available repository paths.
    ///
    /// The generated file follows the VS Code multi-root workspace format:
    /// ```json
    /// {
    ///   "folders": [
    ///     { "path": "/path/to/repo1" },
    ///     { "path": "/path/to/repo2" }
    ///   ],
    ///   "settings": {}
    /// }
    /// ```
    ///
    /// - Parameter workspace: The workspace whose repositories to include.
    /// - Returns: The URL of the generated .code-workspace file.
    /// - Throws: `IDEContextError.noRepositories` if no repositories have valid local paths,
    ///           `IDEContextError.workspaceFileGenerationFailed` if serialization or write fails.
    func generateWorkspaceFile(workspace: Workspace) throws -> URL {
        // Zero-repos guard: don't generate file if workspace has no repositories at all
        guard !workspace.repositories.isEmpty else {
            throw IDEContextError.noRepositories
        }

        // Filter to repos that are locally available (path set AND exists on disk)
        let availableRepos = workspace.repositories.filter { repo in
            guard let localPath = repo.localPath else { return false }
            return fileManager.fileExists(atPath: localPath)
        }

        guard !availableRepos.isEmpty else {
            throw IDEContextError.noRepositories
        }

        // Build the folders array for the .code-workspace JSON
        let folders: [[String: String]] = availableRepos.compactMap { repo in
            guard let path = repo.localPath else { return nil }
            return ["path": path]
        }

        let workspaceConfig: [String: Any] = [
            "folders": folders,
            "settings": [String: Any]()
        ]

        // Write to a temp directory with a sanitized filename
        let tempDir = fileManager.temporaryDirectory
        let sanitizedName = workspace.name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let fileName = "\(sanitizedName).code-workspace"
        let fileURL = tempDir.appendingPathComponent(fileName)

        guard JSONSerialization.isValidJSONObject(workspaceConfig) else {
            throw IDEContextError.workspaceFileGenerationFailed("Invalid workspace configuration structure.")
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: workspaceConfig, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw IDEContextError.workspaceFileGenerationFailed(error.localizedDescription)
        }

        return fileURL
    }

    // MARK: - Open in IDE

    /// Opens the shared local workspace directory in Zed.
    ///
    /// This method:
    /// 1. Checks that the workspace has repositories (zero-repos guard)
    /// 2. Resolves the shared local root directory
    /// 3. Launches that folder using Zed
    ///
    /// - Parameter workspace: The workspace to open.
    /// - Throws: `IDEContextError.noRepositories` if no repos are available,
    ///           `IDEContextError.launchFailed` if the system cannot open the file.
    func openInIDE(workspace: Workspace) async throws {
        // Zero-repos guard
        guard !workspace.repositories.isEmpty else {
            throw IDEContextError.noRepositories
        }

        let hasAvailableRepository = workspace.repositories.contains { repository in
            guard let localPath = repository.localPath else { return false }
            return fileManager.fileExists(atPath: localPath)
        }
        guard hasAvailableRepository else {
            throw IDEContextError.noRepositories
        }

        let rootURL = localRootDirectory(for: workspace)

        #if os(macOS)
        let opened = zedLauncher(rootURL)
        if !opened {
            throw IDEContextError.launchFailed(
                "Could not open the workspace in Zed. Ensure Zed is installed in Applications."
            )
        }
        #endif
    }

    // MARK: - Check Local Availability

    /// Checks which repositories in the workspace are available locally.
    ///
    /// Returns detailed availability status for each repository:
    /// - `.available`: local path exists on disk
    /// - `.notCloned`: no local path has been set (never cloned)
    /// - `.stalePath(path)`: local path was set but no longer exists on disk (stale)
    ///
    /// - Parameter workspace: The workspace to check.
    /// - Returns: An array of tuples with each repository and its availability status.
    func checkLocalAvailability(workspace: Workspace) -> [(Repository, RepositoryAvailability)] {
        workspace.repositories.map { repo in
            let availability = checkAvailability(for: repo)
            return (repo, availability)
        }
    }

    /// Checks availability for a single repository.
    /// - Parameter repo: The repository to check.
    /// - Returns: The availability status.
    func checkAvailability(for repo: Repository) -> RepositoryAvailability {
        guard let localPath = repo.localPath else {
            return .notCloned
        }

        if fileManager.fileExists(atPath: localPath) {
            return .available
        } else {
            return .stalePath(localPath)
        }
    }

    /// Returns repositories that are missing locally (not cloned or stale path).
    /// - Parameter workspace: The workspace to check.
    /// - Returns: Array of repositories that need cloning, along with their status.
    func getMissingRepositories(workspace: Workspace) -> [(Repository, RepositoryAvailability)] {
        checkLocalAvailability(workspace: workspace).filter { !$0.1.isAvailable }
    }

    /// Returns repositories with stale paths (previously cloned but path no longer exists).
    /// - Parameter workspace: The workspace to check.
    /// - Returns: Array of repositories with stale paths and their previous path.
    func getStaleRepositories(workspace: Workspace) -> [(Repository, String)] {
        checkLocalAvailability(workspace: workspace).compactMap { repo, availability in
            if case .stalePath(let path) = availability {
                return (repo, path)
            }
            return nil
        }
    }

    // MARK: - Clone Missing Repos

    /// Clones missing repositories in batch with per-repo progress reporting.
    ///
    /// This method:
    /// - Clones each repository sequentially with individual progress callbacks
    /// - Handles partial failures: if some repos fail, continues with the rest
    /// - Updates each repository's `localPath` on successful clone
    /// - Returns results for all repos (success with URL or failure with error)
    ///
    /// - Parameters:
    ///   - repos: The repositories to clone.
    ///   - baseDirectory: The base directory under which repos will be cloned (each in a subdirectory).
    ///   - credentials: Git credentials for authentication.
    ///   - progressHandler: Called with (repository, progress) for each repo during clone.
    /// - Returns: Array of results for each repository (success URL or failure error).
    func cloneMissingRepos(
        repos: [Repository],
        baseDirectory: URL,
        credentials: GitCredentials,
        progressHandler: (@Sendable (RepositoryProgressContext, CloneProgress) -> Void)? = nil
    ) async -> [CloneOperationResult] {
        var results: [CloneOperationResult] = []

        for repo in repos {
            let repoDir = baseDirectory.appendingPathComponent(repo.name)
            let progressContext = RepositoryProgressContext(id: repo.id, name: repo.name)

            do {
                // Ensure base directory exists
                try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

                guard let remoteURL = URL(string: repo.url) else {
                    let error = IDEContextError.workspaceFileGenerationFailed("Invalid repository URL: \(repo.url)")
                    results.append(CloneOperationResult(
                        repositoryId: repo.id,
                        repositoryName: repo.name,
                        result: .failure(error)
                    ))
                    continue
                }

                try await gitOperationsService.clone(
                    remoteURL: remoteURL,
                    localPath: repoDir,
                    credentials: credentials,
                    progressHandler: { progress in
                        progressHandler?(progressContext, progress)
                    }
                )

                // Update the repository's local path on success
                repo.localPath = repoDir.path

                results.append(CloneOperationResult(
                    repositoryId: repo.id,
                    repositoryName: repo.name,
                    result: .success(repoDir)
                ))
            } catch {
                results.append(CloneOperationResult(
                    repositoryId: repo.id,
                    repositoryName: repo.name,
                    result: .failure(error)
                ))
            }
        }

        return results
    }

    /// Convenience method matching the design interface signature.
    /// Clones missing repos and returns results as (Repository, Result<URL, Error>) tuples.
    ///
    /// - Parameters:
    ///   - repos: The repositories to clone.
    ///   - baseDirectory: The base directory for cloning.
    ///   - credentials: Git credentials for authentication.
    /// - Returns: Array of tuples with repository and clone result.
    /// - Throws: `IDEContextError.allClonesFailed` only if every single clone fails.
    func cloneMissingRepos(
        repos: [Repository],
        baseDirectory: URL,
        credentials: GitCredentials
    ) async throws -> [(Repository, Result<URL, Error>)] {
        let results = await cloneMissingRepos(
            repos: repos,
            baseDirectory: baseDirectory,
            credentials: credentials,
            progressHandler: nil
        )

        // Map results back to the design interface format
        let mapped: [(Repository, Result<URL, Error>)] = results.compactMap { result in
            guard let repo = repos.first(where: { $0.id == result.repositoryId }) else {
                return nil
            }
            return (repo, result.result)
        }

        // If ALL clones failed, throw an error
        let allFailed = mapped.allSatisfy { _, result in
            if case .failure = result { return true }
            return false
        }

        if allFailed && !mapped.isEmpty {
            let failures = mapped.compactMap { repo, result -> String? in
                if case .failure(let error) = result {
                    return "\(repo.name) (\(error.localizedDescription))"
                }
                return nil
            }
            throw IDEContextError.allClonesFailed(failures)
        }

        return mapped
    }

    // MARK: - Full Open in IDE Flow (with clone prompt)

    /// Performs the full "Open in IDE" flow including missing repo detection and cloning.
    ///
    /// This method:
    /// 1. Checks for zero repos (guard)
    /// 2. Checks local availability of all repos
    /// 3. If repos are missing/stale, returns info for the UI to prompt the user
    /// 4. After cloning (if needed), generates workspace file and opens IDE
    ///
    /// - Parameters:
    ///   - workspace: The workspace to open.
    ///   - baseDirectory: The base directory for cloning missing repos.
    ///   - credentials: Git credentials for authentication.
    ///   - shouldCloneMissing: Whether to clone missing repos (true if user confirmed).
    ///   - progressHandler: Called with per-repo clone progress.
    /// - Returns: The results of any clone operations performed.
    /// - Throws: `IDEContextError` if the operation cannot proceed.
    func openInIDEWithCloning(
        workspace: Workspace,
        baseDirectory: URL,
        credentials: GitCredentials,
        shouldCloneMissing: Bool = true,
        progressHandler: (@Sendable (RepositoryProgressContext, CloneProgress) -> Void)? = nil
    ) async throws -> [CloneOperationResult] {
        // Zero-repos guard
        guard !workspace.repositories.isEmpty else {
            throw IDEContextError.noRepositories
        }

        var cloneResults: [CloneOperationResult] = []

        if shouldCloneMissing {
            // Find repos that need cloning (not cloned or stale path)
            let missing = getMissingRepositories(workspace: workspace)
            let reposToClone = missing.map { $0.0 }

            if !reposToClone.isEmpty {
                cloneResults = await cloneMissingRepos(
                    repos: reposToClone,
                    baseDirectory: baseDirectory,
                    credentials: credentials,
                    progressHandler: progressHandler
                )
            }
        }

        // After cloning, try to open in IDE (will use whatever repos are now available)
        try await openInIDE(workspace: workspace)

        return cloneResults
    }

    #if os(macOS)
    private static func openDirectoryInZed(_ directory: URL) -> Bool {
        let workspace = NSWorkspace.shared
        let zedURL = workspace.urlForApplication(withBundleIdentifier: "dev.zed.Zed")
            ?? URL(fileURLWithPath: "/Applications/Zed.app", isDirectory: true)

        guard FileManager.default.fileExists(atPath: zedURL.path) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        workspace.open(
            [directory],
            withApplicationAt: zedURL,
            configuration: configuration
        )
        return true
    }
    #endif
}
