import Foundation
import SwiftData
import SwiftUI

// MARK: - IDE Context ViewModel

/// ViewModel managing the "Open in IDE" flow including missing repo detection,
/// clone prompt UI state, batch clone progress, and partial failure handling.
///
/// Implements Requirement 14: Multi-Repo IDE Context
@Observable
@MainActor
class IDEContextViewModel {

    // MARK: - State

    /// The workspace being managed.
    private(set) var workspace: Workspace?

    /// Whether the clone confirmation sheet is shown.
    var showClonePrompt: Bool = false

    /// Whether a clone operation is in progress.
    private(set) var isCloning: Bool = false

    /// Whether the IDE was successfully launched.
    private(set) var didLaunchIDE: Bool = false

    /// Per-repository clone progress (repo ID → progress).
    private(set) var cloneProgress: [UUID: CloneProgress] = [:]

    /// Results of the last batch clone operation.
    private(set) var cloneResults: [CloneOperationResult] = []

    /// Repositories that are missing locally (need cloning).
    private(set) var missingRepositories: [(Repository, RepositoryAvailability)] = []

    /// Repositories with stale paths (previously cloned, path no longer exists).
    private(set) var staleRepositories: [(Repository, String)] = []

    /// Error message to display.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    /// Whether the "no repos" message is shown.
    var showNoReposMessage: Bool = false

    /// The base directory for cloning repos.
    var cloneBaseDirectory: URL?

    /// Whether the directory picker is shown.
    var showDirectoryPicker: Bool = false

    // MARK: - Dependencies

    private let ideContextService: IDEContextService
    private var modelContext: ModelContext?

    // MARK: - Initialization

    init(ideContextService: IDEContextService? = nil) {
        self.ideContextService = ideContextService ?? IDEContextService()
    }

    /// Configures the view model with dependencies.
    func configure(workspace: Workspace, modelContext: ModelContext) {
        self.workspace = workspace
        self.modelContext = modelContext
    }

    // MARK: - Computed Properties

    /// Whether there are any failed clones in the results.
    var hasCloneFailures: Bool {
        cloneResults.contains { !$0.isSuccess }
    }

    /// The failed clone results.
    var failedClones: [CloneOperationResult] {
        cloneResults.filter { !$0.isSuccess }
    }

    /// The successful clone results.
    var successfulClones: [CloneOperationResult] {
        cloneResults.filter { $0.isSuccess }
    }

    /// Total number of repos being cloned.
    var totalReposToClone: Int {
        missingRepositories.count
    }

    /// Number of repos that have completed cloning (success or failure).
    var completedCloneCount: Int {
        cloneResults.count
    }

    /// Overall progress percentage (0-100) across all repos.
    var overallProgress: Double {
        guard totalReposToClone > 0 else { return 0 }
        let completedWeight = Double(completedCloneCount) / Double(totalReposToClone) * 100.0
        return min(completedWeight, 100.0)
    }

    // MARK: - Actions

    /// Initiates the "Open in IDE" flow.
    ///
    /// Checks local availability and either opens directly or shows clone prompt.
    func openInIDE() async {
        guard let workspace else { return }

        // Zero-repos guard
        guard !workspace.repositories.isEmpty else {
            showNoReposMessage = true
            return
        }

        // Reset state
        resetState()

        // Check availability
        missingRepositories = ideContextService.getMissingRepositories(workspace: workspace)
        staleRepositories = ideContextService.getStaleRepositories(workspace: workspace)

        if missingRepositories.isEmpty {
            // All repos available, open directly
            await launchIDE()
        } else {
            // Show clone prompt
            showClonePrompt = true
        }
    }

    /// Confirms cloning and proceeds with the "Open in IDE" flow.
    ///
    /// - Parameter baseDirectory: The directory to clone repos into.
    func confirmCloneAndOpen(baseDirectory: URL, credentials: GitCredentials) async {
        guard let workspace else { return }

        showClonePrompt = false
        isCloning = true
        cloneProgress = [:]
        cloneResults = []

        let reposToClone = missingRepositories.map { $0.0 }

        // Perform batch clone with per-repo progress
        let results = await ideContextService.cloneMissingRepos(
            repos: reposToClone,
            baseDirectory: baseDirectory,
            credentials: credentials,
            progressHandler: { [weak self] repo, progress in
                Task { @MainActor [weak self] in
                    self?.cloneProgress[repo.id] = progress
                }
            }
        )

        cloneResults = results
        isCloning = false

        // Save model context to persist updated localPath values
        try? modelContext?.save()

        // Refresh missing repos list
        missingRepositories = ideContextService.getMissingRepositories(workspace: workspace)

        // Handle results
        let successCount = results.filter { $0.isSuccess }.count
        let failureCount = results.filter { !$0.isSuccess }.count

        if failureCount > 0 && successCount == 0 {
            // All clones failed
            let failureMessages = results.compactMap { result -> String? in
                guard let error = result.error else { return nil }
                return "\(result.repositoryName): \(error.localizedDescription)"
            }
            showErrorMessage("All repository clones failed:\n\(failureMessages.joined(separator: "\n"))")
        } else if failureCount > 0 {
            // Partial failure: show error for failed, continue with rest
            let failureMessages = results.compactMap { result -> String? in
                guard let error = result.error else { return nil }
                return "\(result.repositoryName): \(error.localizedDescription)"
            }
            showErrorMessage("Some repositories failed to clone:\n\(failureMessages.joined(separator: "\n"))\n\nOpening IDE with available repositories.")
            // Still try to open IDE with whatever repos are available
            await launchIDE()
        } else {
            // All succeeded, open IDE
            await launchIDE()
        }
    }

    /// Skips cloning and opens IDE with only available repos.
    func skipCloneAndOpen() async {
        showClonePrompt = false
        await launchIDE()
    }

    /// Launches the IDE with the current workspace.
    private func launchIDE() async {
        guard let workspace else { return }

        do {
            try await ideContextService.openInIDE(workspace: workspace)
            didLaunchIDE = true
        } catch let error as IDEContextError {
            switch error {
            case .noRepositories:
                showNoReposMessage = true
            default:
                showErrorMessage(error.localizedDescription)
            }
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    /// Checks local availability and returns the status.
    func refreshAvailability() {
        guard let workspace else { return }
        missingRepositories = ideContextService.getMissingRepositories(workspace: workspace)
        staleRepositories = ideContextService.getStaleRepositories(workspace: workspace)
    }

    // MARK: - Private Helpers

    private func resetState() {
        showClonePrompt = false
        showNoReposMessage = false
        showError = false
        errorMessage = nil
        isCloning = false
        didLaunchIDE = false
        cloneProgress = [:]
        cloneResults = []
        missingRepositories = []
        staleRepositories = []
    }

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
