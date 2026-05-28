import Foundation
import SwiftData
import SwiftUI

// MARK: - Repository Validation Error

/// Describes the reason a repository URL validation failed.
enum RepositoryValidationError: Error, LocalizedError {
    case emptyURL
    case invalidFormat
    case unreachable(String)
    case notFound
    case insufficientPermissions
    case alreadyAdded
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            return "Repository URL cannot be empty."
        case .invalidFormat:
            return "The URL format is invalid. Please provide a valid GitLab repository URL."
        case .unreachable(let detail):
            return "The repository URL is unreachable: \(detail)"
        case .notFound:
            return "Repository not found. Please verify the URL is correct."
        case .insufficientPermissions:
            return "Insufficient permissions to access this repository."
        case .alreadyAdded:
            return "This repository is already associated with the workspace."
        case .unknown(let detail):
            return "Failed to validate repository: \(detail)"
        }
    }
}

// MARK: - Repository Management ViewModel

/// ViewModel managing repository CRUD operations within a workspace.
@Observable
@MainActor
class RepositoryManagementViewModel {

    typealias RepositoryCloneHandler = (Repository, URL, GitCredentials) async -> Result<URL, Error>

    // MARK: - State

    /// The workspace being managed.
    private(set) var workspace: Workspace?

    /// Whether the add repository sheet is shown.
    var showAddSheet: Bool = false

    /// The URL input for adding a new repository.
    var newRepositoryURL: String = ""

    /// Whether a validation request is in progress.
    private(set) var isValidating: Bool = false

    /// Error message to display to the user.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    /// Whether the remove confirmation dialog is shown.
    var showRemoveConfirmation: Bool = false

    /// The repository pending removal.
    var repositoryPendingRemoval: Repository?

    /// Whether the local path picker is shown.
    var showLocalPathPicker: Bool = false

    /// The repository to set local path for.
    var repositoryForPathSetting: Repository?

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private var gitLabAPIClient: GitLabAPIClient?
    private var cloneTokenProvider: (() async throws -> String)?
    private let ideContextService: IDEContextService
    private let repositoryCloneHandler: RepositoryCloneHandler?

    // MARK: - Initialization

    init(
        ideContextService: IDEContextService? = nil,
        repositoryCloneHandler: RepositoryCloneHandler? = nil
    ) {
        self.ideContextService = ideContextService ?? IDEContextService()
        self.repositoryCloneHandler = repositoryCloneHandler
    }

    /// Configures the view model with dependencies.
    /// - Parameters:
    ///   - workspace: The workspace to manage repositories for.
    ///   - modelContext: The SwiftData model context.
    ///   - gitLabAPIClient: The GitLab API client for validation.
    func configure(
        workspace: Workspace,
        modelContext: ModelContext,
        gitLabAPIClient: GitLabAPIClient? = nil,
        cloneTokenProvider: (() async throws -> String)? = nil
    ) {
        self.workspace = workspace
        self.modelContext = modelContext
        self.gitLabAPIClient = gitLabAPIClient
        self.cloneTokenProvider = cloneTokenProvider
    }

    // MARK: - Repository List

    /// Returns the repositories associated with the current workspace.
    var repositories: [Repository] {
        workspace?.repositories ?? []
    }

    // MARK: - Add Repository

    /// Validates the repository URL via GitLab API and adds it to the workspace.
    /// - Returns: `true` if the repository was successfully added.
    @discardableResult
    func addRepository() async -> Bool {
        let trimmedURL = newRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic validation
        guard !trimmedURL.isEmpty else {
            showErrorMessage(RepositoryValidationError.emptyURL.localizedDescription)
            return false
        }

        guard isValidGitLabURL(trimmedURL) else {
            showErrorMessage(RepositoryValidationError.invalidFormat.localizedDescription)
            return false
        }

        // Check for duplicates
        if repositories.contains(where: { $0.url.lowercased() == trimmedURL.lowercased() }) {
            showErrorMessage(RepositoryValidationError.alreadyAdded.localizedDescription)
            return false
        }

        guard let gitLabAPIClient else {
            showErrorMessage("GitLab API client is not configured. Please connect your GitLab account first.")
            return false
        }

        // Validate via GitLab API
        isValidating = true
        defer { isValidating = false }

        do {
            let project = try await gitLabAPIClient.validateProjectAccess(url: trimmedURL)
            return await cloneAndCreateRepository(from: project)
        } catch let error as GitLabAPIError {
            let validationError = mapGitLabError(error, url: trimmedURL)
            showErrorMessage(validationError.localizedDescription)
            return false
        } catch {
            showErrorMessage(RepositoryValidationError.unknown(error.localizedDescription).localizedDescription)
            return false
        }
    }

    // MARK: - Remove Repository

    /// Initiates the removal flow by setting the pending repository and showing confirmation.
    func confirmRemoval(of repository: Repository) {
        repositoryPendingRemoval = repository
        showRemoveConfirmation = true
    }

    /// Executes the pending removal (disassociates without deleting remote).
    func executeRemoval() {
        guard let repository = repositoryPendingRemoval,
              let modelContext else { return }

        // Disassociate from workspace
        if let workspace {
            workspace.repositories.removeAll { $0.id == repository.id }
        }
        repository.workspace = nil

        // Delete the local model
        modelContext.delete(repository)

        do {
            try modelContext.save()
        } catch {
            showErrorMessage("Failed to remove repository: \(error.localizedDescription)")
        }

        repositoryPendingRemoval = nil
    }

    // MARK: - Local Path Management

    /// Initiates the local path setting flow for a repository.
    func setLocalPath(for repository: Repository) {
        repositoryForPathSetting = repository
        showLocalPathPicker = true
    }

    /// Updates the local path for a repository.
    /// - Parameters:
    ///   - repository: The repository to update.
    ///   - path: The local file system path.
    func updateLocalPath(for repository: Repository, path: String) {
        repository.localPath = path

        do {
            try modelContext?.save()
        } catch {
            showErrorMessage("Failed to save local path: \(error.localizedDescription)")
        }
    }

    /// Clears the local path for a repository.
    func clearLocalPath(for repository: Repository) {
        repository.localPath = nil

        do {
            try modelContext?.save()
        } catch {
            showErrorMessage("Failed to clear local path: \(error.localizedDescription)")
        }
    }

    // MARK: - IDE Integration

    /// Opens the workspace in the IDE using IDEContextService.
    func openInIDE() async {
        guard let workspace else { return }

        do {
            let missingRepositories = ideContextService.getMissingRepositories(workspace: workspace)
            if !missingRepositories.isEmpty {
                guard let cloneTokenProvider else {
                    showErrorMessage("A GitLab session is required to clone repositories before opening in Zed.")
                    return
                }

                let token = try await cloneTokenProvider()
                let rootDirectory = ideContextService.localRootDirectory(for: workspace)
                for (repository, _) in missingRepositories {
                    let result = await cloneRepository(
                        repository,
                        into: rootDirectory,
                        credentials: GitCredentials(oauthToken: token)
                    )
                    if case .failure(let error) = result {
                        showErrorMessage("Failed to clone \(repository.name): \(error.localizedDescription)")
                        return
                    }
                }

                try modelContext?.save()
            }

            try await ideContextService.openInIDE(workspace: workspace)
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    /// Checks local availability of all repositories.
    func checkLocalAvailability() -> [(Repository, Bool)] {
        guard let workspace else { return [] }
        return ideContextService.checkLocalAvailability(workspace: workspace).map { repo, availability in
            (repo, availability.isAvailable)
        }
    }

    // MARK: - Reset

    /// Resets the add repository form state.
    func resetAddForm() {
        newRepositoryURL = ""
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    /// Creates a Repository model from a validated GitLab project.
    private func cloneAndCreateRepository(from project: GitLabProject) async -> Bool {
        guard let workspace, let modelContext else {
            showErrorMessage("Unable to save repository.")
            return false
        }

        let repository = Repository(
            gitlabProjectId: project.id,
            name: project.name,
            url: project.httpUrlToRepo,
            defaultBranch: project.defaultBranch ?? "main"
        )

        guard let cloneTokenProvider else {
            showErrorMessage("A GitLab session is required to clone this repository locally.")
            return false
        }

        do {
            let token = try await cloneTokenProvider()
            let rootDirectory = ideContextService.localRootDirectory(for: workspace)
            let result = await cloneRepository(
                repository,
                into: rootDirectory,
                credentials: GitCredentials(oauthToken: token)
            )

            switch result {
            case .success(let checkoutURL):
                repository.localPath = checkoutURL.path
            case .failure(let error):
                showErrorMessage("Failed to clone repository locally: \(error.localizedDescription)")
                return false
            }
        } catch {
            showErrorMessage("Failed to access GitLab credentials for cloning: \(error.localizedDescription)")
            return false
        }

        repository.workspace = workspace
        workspace.repositories.append(repository)
        modelContext.insert(repository)

        do {
            try modelContext.save()
            newRepositoryURL = ""
            showAddSheet = false
            return true
        } catch {
            showErrorMessage("Failed to save repository: \(error.localizedDescription)")
            return false
        }
    }

    private func cloneRepository(
        _ repository: Repository,
        into rootDirectory: URL,
        credentials: GitCredentials
    ) async -> Result<URL, Error> {
        if let repositoryCloneHandler {
            return await repositoryCloneHandler(repository, rootDirectory, credentials)
        }

        let results = await ideContextService.cloneMissingRepos(
            repos: [repository],
            baseDirectory: rootDirectory,
            credentials: credentials,
            progressHandler: nil
        )

        guard let result = results.first else {
            return .failure(IDEContextError.repositoryNotCloned(repository.name))
        }

        return result.result
    }

    /// Validates that a URL looks like a valid GitLab repository URL.
    private func isValidGitLabURL(_ url: String) -> Bool {
        // Accept HTTPS URLs
        if url.hasPrefix("https://") || url.hasPrefix("http://") {
            return URL(string: url) != nil
        }

        // Accept SSH URLs (git@host:namespace/project.git)
        if url.contains("@") && url.contains(":") {
            return true
        }

        return false
    }

    /// Maps a GitLabAPIError to a user-friendly RepositoryValidationError.
    private func mapGitLabError(_ error: GitLabAPIError, url: String) -> RepositoryValidationError {
        switch error {
        case .invalidURL:
            return .invalidFormat
        case .notFound:
            return .notFound
        case .unauthorized, .forbidden:
            return .insufficientPermissions
        case .networkError(let underlying):
            return .unreachable(underlying.localizedDescription)
        case .maxRetriesExceeded:
            return .unreachable("Request timed out after multiple attempts.")
        default:
            let description = error.errorDescription ?? "An unexpected error occurred."
            return .unknown(description)
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
