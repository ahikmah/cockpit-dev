import Foundation
import SwiftData
import CryptoKit

// MARK: - Spec Tracking Errors

/// Errors that can occur during spec tracking operations.
enum SpecTrackingError: Error, LocalizedError {
    case noRepository
    case noProjectId
    case fetchFailed(Error)
    case branchNotFound(String)
    case specDirectoryNotConfigured

    var errorDescription: String? {
        switch self {
        case .noRepository:
            return "No repository associated with this workspace."
        case .noProjectId:
            return "No GitLab project ID available."
        case .fetchFailed(let error):
            return "Failed to fetch spec files: \(error.localizedDescription)"
        case .branchNotFound(let branch):
            return "Branch '\(branch)' not found or inaccessible."
        case .specDirectoryNotConfigured:
            return "Spec directory path is not configured for this workspace."
        }
    }
}

// MARK: - Spec File Info

/// Represents a discovered spec file on a branch.
struct SpecFileInfo {
    let specName: String
    let filePath: String
    let phase: SpecPhase
    let branchName: String
}

// MARK: - Spec Tracking Service

/// Service responsible for detecting and tracking OpenSpec specification files
/// from developer branches via push webhook events and periodic scanning.
///
/// The service:
/// - Detects push events that modify spec directory files
/// - Discovers spec files on branches
/// - Creates/updates OpenSpecEntry records with phase detection
/// - Handles branch deletion (marks specs unavailable)
/// - Detects changes within 120 seconds of push events
@Observable
@MainActor
class SpecTrackingService {

    // MARK: - Properties

    /// The GitLab API client for fetching file content and branches.
    private let apiClient: GitLabAPIClient

    /// The SwiftData model context for persistence.
    private let modelContext: ModelContext

    /// Whether the service is currently processing a push event.
    var isProcessing: Bool = false

    /// Last error encountered during processing.
    var lastError: SpecTrackingError?

    // MARK: - Initialization

    init(apiClient: GitLabAPIClient, modelContext: ModelContext) {
        self.apiClient = apiClient
        self.modelContext = modelContext
    }

    // MARK: - Push Hook Detection

    /// Handles a push webhook event, detecting spec file changes.
    ///
    /// This method checks if the push event contains changes to files within
    /// the workspace's configured spec directory path. If so, it triggers
    /// spec discovery on the affected branch.
    ///
    /// - Parameters:
    ///   - payload: The push webhook payload.
    ///   - workspace: The workspace to check against.
    func handlePushEvent(_ payload: PushWebhookPayload, workspace: Workspace) async throws {
        let specPath = workspace.specDirectoryPath
        guard !specPath.isEmpty else {
            throw SpecTrackingError.specDirectoryNotConfigured
        }

        let branchName = payload.branchName

        // Handle branch deletion
        if payload.isBranchDeletion {
            markBranchSpecsUnavailable(branchName: branchName, workspace: workspace)
            return
        }

        // Check if any commits touch the spec directory
        let hasSpecChanges = pushContainsSpecChanges(payload: payload, specPath: specPath)

        if hasSpecChanges || payload.isBranchCreation {
            // Discover specs on this branch
            try await discoverSpecsOnBranch(
                branchName: branchName,
                workspace: workspace
            )
        }
    }

    /// Checks whether a push event contains changes to spec files.
    ///
    /// - Parameters:
    ///   - payload: The push webhook payload.
    ///   - specPath: The configured spec directory path.
    /// - Returns: `true` if any commit in the push modifies files in the spec directory.
    func pushContainsSpecChanges(payload: PushWebhookPayload, specPath: String) -> Bool {
        guard let commits = payload.commits else { return false }

        let normalizedSpecPath = specPath.hasSuffix("/") ? specPath : specPath + "/"

        for commit in commits {
            let allFiles = (commit.added ?? []) + (commit.modified ?? []) + (commit.removed ?? [])
            for file in allFiles {
                if file.hasPrefix(normalizedSpecPath) || file.hasPrefix(specPath) {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Spec Discovery

    /// Discovers spec files on a specific branch and creates/updates OpenSpecEntry records.
    ///
    /// This method uses the GitLab API to list files in the spec directory on the given branch,
    /// determines the phase of each spec, and creates or updates corresponding entries.
    ///
    /// - Parameters:
    ///   - branchName: The branch to scan for specs.
    ///   - workspace: The workspace containing the spec configuration.
    func discoverSpecsOnBranch(branchName: String, workspace: Workspace) async throws {
        guard let repository = workspace.repositories.first else {
            throw SpecTrackingError.noRepository
        }

        let projectId = repository.gitlabProjectId
        let specPath = workspace.specDirectoryPath

        guard !specPath.isEmpty else {
            throw SpecTrackingError.specDirectoryNotConfigured
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Fetch the tree of the spec directory on this branch
            let specFiles = try await fetchSpecTree(
                projectId: projectId,
                specPath: specPath,
                branchName: branchName
            )

            // Process discovered specs
            for specFile in specFiles {
                try await processDiscoveredSpec(
                    specFile: specFile,
                    workspace: workspace,
                    projectId: projectId
                )
            }

            try modelContext.save()
            lastError = nil

        } catch {
            lastError = .fetchFailed(error)
            throw SpecTrackingError.fetchFailed(error)
        }
    }

    /// Fetches the spec directory tree from GitLab and identifies spec entries.
    ///
    /// Spec directories are expected to follow the structure:
    /// `<specPath>/<specName>/` containing proposal.md, design.md, tasks.md, and specs/.
    ///
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - specPath: The base spec directory path.
    ///   - branchName: The branch to scan.
    /// - Returns: An array of discovered spec file info.
    private func fetchSpecTree(projectId: Int, specPath: String, branchName: String) async throws -> [SpecFileInfo] {
        var specFiles: [SpecFileInfo] = []

        // Use GitLab Repository Tree API to list directories in the spec path
        let treeItems = try await fetchRepositoryTree(
            projectId: projectId,
            path: specPath,
            ref: branchName
        )

        // Each subdirectory in the spec path is a spec
        for item in treeItems where item.type == "tree" {
            let specName = item.name
            let specDirPath = item.path

            // Determine phase by checking which files exist
            let phase = try await detectSpecPhase(
                projectId: projectId,
                specDirPath: specDirPath,
                branchName: branchName
            )

            specFiles.append(SpecFileInfo(
                specName: specName,
                filePath: specDirPath,
                phase: phase,
                branchName: branchName
            ))
        }

        return specFiles
    }

    /// Detects the phase of a spec based on which files exist in its directory.
    ///
    /// Phase detection logic:
    /// - If `tasks.md` exists → `.tasks`
    /// - If `design.md` exists → `.design`
    /// - Otherwise → `.proposal`
    ///
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - specDirPath: The path to the spec directory.
    ///   - branchName: The branch to check.
    /// - Returns: The detected spec phase.
    func detectSpecPhase(projectId: Int, specDirPath: String, branchName: String) async throws -> SpecPhase {
        let specContents = try await fetchRepositoryTree(
            projectId: projectId,
            path: specDirPath,
            ref: branchName
        )

        let fileNames = Set(specContents.map { $0.name.lowercased() })

        if fileNames.contains("tasks.md") {
            return .tasks
        } else if fileNames.contains("design.md") {
            return .design
        } else {
            return .proposal
        }
    }

    // MARK: - OpenSpecEntry Management

    /// Processes a discovered spec file, creating or updating the corresponding OpenSpecEntry.
    ///
    /// - Parameters:
    ///   - specFile: The discovered spec file info.
    ///   - workspace: The workspace to associate the entry with.
    ///   - projectId: The GitLab project ID for fetching content.
    private func processDiscoveredSpec(specFile: SpecFileInfo, workspace: Workspace, projectId: Int) async throws {
        guard let snapshot = await fetchDocumentSnapshot(for: specFile, projectId: projectId) else {
            return
        }

        // Check if an entry already exists for this spec on this branch
        let existingEntry = findExistingEntry(
            specName: specFile.specName,
            branchName: specFile.branchName,
            workspace: workspace
        )

        if let entry = existingEntry {
            // Update existing entry
            entry.phase = specFile.phase
            entry.isAvailable = true

            // Fetch latest content to check for changes
            try await checkForContentChanges(
                entry: entry,
                specFile: specFile,
                projectId: projectId,
                snapshot: snapshot
            )
        } else {
            // Create new entry
            let entry = OpenSpecEntry(
                specName: specFile.specName,
                branchName: specFile.branchName,
                phase: specFile.phase,
                isAvailable: true,
                hasUnreadVersion: true
            )
            entry.workspace = workspace
            modelContext.insert(entry)

            // Fetch initial content and create first version
            try await createInitialVersion(
                entry: entry,
                specFile: specFile,
                projectId: projectId,
                snapshot: snapshot
            )
        }
    }

    /// Finds an existing OpenSpecEntry for the given spec name and branch.
    private func findExistingEntry(specName: String, branchName: String, workspace: Workspace) -> OpenSpecEntry? {
        return workspace.specs.first { entry in
            entry.specName == specName && entry.branchName == branchName
        }
    }

    /// Checks if the spec content has changed and creates a new version if so.
    ///
    /// Extracts git commit metadata (author name, timestamp) from the last commit
    /// that modified the spec file. Falls back to "Unknown" author and current detection
    /// time if metadata is unavailable.
    private func checkForContentChanges(
        entry: OpenSpecEntry,
        specFile: SpecFileInfo,
        projectId: Int,
        snapshot: OpenSpecDocumentSnapshot
    ) async throws {
        do {
            let content = try snapshot.encodedContent()
            let contentHash = computeContentHash(content)

            // Check if content has changed from the latest version
            let latestVersion = entry.versions
                .sorted { $0.detectedAt > $1.detectedAt }
                .first

            if latestVersion?.contentHash != contentHash {
                // Extract git commit metadata for the file
                let (authorName, commitTimestamp) = await extractCommitMetadata(
                    projectId: projectId,
                    filePath: "\(specFile.filePath)/\(primaryFileName(for: specFile.phase))",
                    ref: specFile.branchName
                )

                // Content changed - create new version with commit metadata
                let version = DocSpecVersion(
                    contentHash: contentHash,
                    content: content,
                    authorName: authorName,
                    commitTimestamp: commitTimestamp,
                    detectedAt: Date()
                )
                version.spec = entry
                entry.versions.append(version)
                entry.hasUnreadVersion = true
                modelContext.insert(version)
            }
        } catch {
            // File might not exist yet for this phase - that's okay
        }
    }

    /// Creates the initial version for a newly discovered spec entry.
    ///
    /// Extracts git commit metadata when available, falling back to "Unknown" author
    /// and current time if metadata cannot be retrieved.
    private func createInitialVersion(
        entry: OpenSpecEntry,
        specFile: SpecFileInfo,
        projectId: Int,
        snapshot: OpenSpecDocumentSnapshot
    ) async throws {
        do {
            let content = try snapshot.encodedContent()
            let contentHash = computeContentHash(content)

            // Extract git commit metadata for the file
            let (authorName, commitTimestamp) = await extractCommitMetadata(
                projectId: projectId,
                filePath: "\(specFile.filePath)/\(primaryFileName(for: specFile.phase))",
                ref: specFile.branchName
            )

            let version = DocSpecVersion(
                contentHash: contentHash,
                content: content,
                authorName: authorName,
                commitTimestamp: commitTimestamp,
                detectedAt: Date()
            )
            version.spec = entry
            entry.versions.append(version)
            modelContext.insert(version)
        } catch {
            // File might not exist - entry still created without initial version
        }
    }

    private func fetchDocumentSnapshot(
        for specFile: SpecFileInfo,
        projectId: Int
    ) async -> OpenSpecDocumentSnapshot? {
        guard let rootItems = try? await fetchRepositoryTree(
            projectId: projectId,
            path: specFile.filePath,
            ref: specFile.branchName
        ) else {
            return nil
        }

        let rootFiles = Set(rootItems.filter { $0.type == "blob" }.map(\.name))
        let proposal = await fetchOptionalContent(
            named: "proposal.md",
            ifPresentIn: rootFiles,
            directoryPath: specFile.filePath,
            projectId: projectId,
            ref: specFile.branchName
        )
        let design = await fetchOptionalContent(
            named: "design.md",
            ifPresentIn: rootFiles,
            directoryPath: specFile.filePath,
            projectId: projectId,
            ref: specFile.branchName
        )
        let tasks = await fetchOptionalContent(
            named: "tasks.md",
            ifPresentIn: rootFiles,
            directoryPath: specFile.filePath,
            projectId: projectId,
            ref: specFile.branchName
        )

        let specsPath = "\(specFile.filePath)/specs"
        var specDocuments: [OpenSpecDocumentSnapshot.SpecDocument] = []
        if rootItems.contains(where: { $0.type == "tree" && $0.name == "specs" }),
           let specItems = try? await fetchRepositoryTree(
               projectId: projectId,
               path: specsPath,
               ref: specFile.branchName
           ) {
            for item in specItems {
                if item.type == "blob", item.name.hasSuffix(".md"),
                   let content = try? await apiClient.fetchFileContent(
                       projectId: projectId,
                       filePath: item.path,
                       ref: specFile.branchName
                   ) {
                    specDocuments.append(.init(path: String(item.path.dropFirst(specFile.filePath.count + 1)), content: content))
                } else if item.type == "tree",
                          let nestedItems = try? await fetchRepositoryTree(
                              projectId: projectId,
                              path: item.path,
                              ref: specFile.branchName
                          ),
                          let specItem = nestedItems.first(where: { $0.type == "blob" && $0.name == "spec.md" }),
                          let content = try? await apiClient.fetchFileContent(
                              projectId: projectId,
                              filePath: specItem.path,
                              ref: specFile.branchName
                          ) {
                    specDocuments.append(.init(path: String(specItem.path.dropFirst(specFile.filePath.count + 1)), content: content))
                }
            }
        }

        let snapshot = OpenSpecDocumentSnapshot(
            proposal: proposal,
            design: design,
            tasks: tasks,
            specs: specDocuments.sorted { $0.path < $1.path }
        )
        return snapshot.hasContent ? snapshot : nil
    }

    private func fetchOptionalContent(
        named fileName: String,
        ifPresentIn fileNames: Set<String>,
        directoryPath: String,
        projectId: Int,
        ref: String
    ) async -> String? {
        guard fileNames.contains(fileName) else {
            return nil
        }

        return try? await apiClient.fetchFileContent(
            projectId: projectId,
            filePath: "\(directoryPath)/\(fileName)",
            ref: ref
        )
    }

    // MARK: - Branch Deletion Handling

    /// Marks all specs on a deleted branch as unavailable.
    ///
    /// - Parameters:
    ///   - branchName: The name of the deleted branch.
    ///   - workspace: The workspace containing the specs.
    func markBranchSpecsUnavailable(branchName: String, workspace: Workspace) {
        let affectedSpecs = workspace.specs.filter { $0.branchName == branchName }
        for spec in affectedSpecs {
            spec.isAvailable = false
        }
        try? modelContext.save()
    }

    // MARK: - Helpers

    /// Returns the primary file name for a given spec phase.
    func primaryFileName(for phase: SpecPhase) -> String {
        switch phase {
        case .proposal:
            return "proposal.md"
        case .design:
            return "design.md"
        case .tasks:
            return "tasks.md"
        }
    }

    /// Computes a SHA-256 hash of the given content string.
    func computeContentHash(_ content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Fetches the repository tree (directory listing) from GitLab.
    private func fetchRepositoryTree(projectId: Int, path: String, ref: String) async throws -> [GitLabTreeItem] {
        return try await apiClient.fetchRepositoryTree(projectId: projectId, path: path, ref: ref)
    }

    // MARK: - Git Commit Metadata Extraction

    /// Extracts the git commit metadata (author name and timestamp) for the most recent
    /// commit that modified the given file on the specified branch.
    ///
    /// Falls back to "Unknown" author and current detection time if the metadata
    /// cannot be retrieved (e.g., API failure, missing data).
    ///
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - filePath: The path to the file in the repository.
    ///   - ref: The branch or ref to check.
    /// - Returns: A tuple of (authorName, commitTimestamp).
    func extractCommitMetadata(projectId: Int, filePath: String, ref: String) async -> (String, Date) {
        do {
            let commits = try await apiClient.fetchFileCommits(
                projectId: projectId,
                filePath: filePath,
                ref: ref,
                perPage: 1
            )

            if let latestCommit = commits.first {
                let authorName = latestCommit.authorName
                let commitTimestamp = latestCommit.committedDate ?? Date()
                return (authorName, commitTimestamp)
            }
        } catch {
            // Metadata unavailable - fall back to defaults
        }

        // Fallback: "Unknown" author and detection time
        return ("Unknown", Date())
    }
}
