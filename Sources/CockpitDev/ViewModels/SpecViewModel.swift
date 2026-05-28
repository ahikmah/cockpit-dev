import Foundation
import SwiftData

/// ViewModel for managing OpenSpec specification tracking within a workspace.
///
/// Handles:
/// - Displaying the list of tracked specs with phase and availability
/// - Triggering spec discovery on branches
/// - Managing spec directory path configuration
/// - Providing spec detail data for rendering
@Observable
@MainActor
class SpecViewModel {

    // MARK: - Properties

    /// The workspace being managed.
    private(set) var workspace: Workspace

    /// The model context for persistence.
    private var modelContext: ModelContext?

    /// The spec tracking service for discovery operations.
    private var specTrackingService: SpecTrackingService?

    /// The GitLab API client for direct API calls.
    private var apiClient: GitLabAPIClient?

    /// Whether a scan is currently in progress.
    var isScanning: Bool = false

    /// Error message to display to the user.
    var errorMessage: String?

    /// The currently selected spec for detail view.
    var selectedSpec: OpenSpecEntry?

    /// The spec directory path being edited.
    var editingSpecPath: String

    /// Branches included in the latest scan.
    var scannedBranchNames: [String] = []

    /// Summary from the latest scan attempt.
    var scanSummary: String?

    /// Branch names available for remote spec scanning.
    var branchOptions: [String] = []

    /// Selected remote branch for scanning and reading.
    var selectedBranchName: String?

    /// Whether branch options are currently loading.
    var isLoadingBranches: Bool = false

    // MARK: - Computed Properties

    /// All specs for the workspace, sorted by name then branch.
    var specs: [OpenSpecEntry] {
        let visibleSpecs: [OpenSpecEntry] = if let selectedBranchName {
            workspace.specs.filter { $0.branchName == selectedBranchName }
        } else {
            []
        }

        return visibleSpecs.sorted { lhs, rhs in
            if lhs.specName == rhs.specName {
                return lhs.branchName < rhs.branchName
            }
            return lhs.specName < rhs.specName
        }
    }

    /// Available specs (branch still accessible).
    var availableSpecs: [OpenSpecEntry] {
        specs.filter { $0.isAvailable }
    }

    /// Unavailable specs (branch deleted or inaccessible).
    var unavailableSpecs: [OpenSpecEntry] {
        specs.filter { !$0.isAvailable }
    }

    /// Whether there are any specs with unread versions.
    var hasUnreadSpecs: Bool {
        specs.contains { $0.hasUnreadVersion }
    }

    /// The repository currently used for spec discovery.
    var primaryRepository: Repository? {
        workspace.repositories.first
    }

    /// Branch display text for the current repository configuration.
    var branchSummary: String {
        guard let repository = primaryRepository else {
            return "No repository selected"
        }

        return "Remote branch: \(selectedBranchName ?? repository.defaultBranch)"
    }

    /// Local checkout display text for branch context.
    var localCheckoutSummary: String {
        guard let repository = primaryRepository else {
            return "Local checkout: not configured"
        }

        guard let localPath = repository.localPath, !localPath.isEmpty else {
            return "Local checkout: not linked"
        }

        return "Local checkout: \(localPath)"
    }

    // MARK: - Initialization

    init(workspace: Workspace) {
        self.workspace = workspace
        self.selectedBranchName = workspace.repositories.first?.defaultBranch
        self.editingSpecPath = Self.normalizedSpecDirectoryPath(
            workspace.specDirectoryPath,
            repositoryName: workspace.repositories.first?.name
        )
    }

    /// Configures the view model with the required dependencies.
    func configure(modelContext: ModelContext, apiClient: GitLabAPIClient) {
        self.modelContext = modelContext
        self.apiClient = apiClient
        self.specTrackingService = SpecTrackingService(apiClient: apiClient, modelContext: modelContext)
    }

    // MARK: - Spec Directory Configuration

    /// Updates the spec directory path for the workspace.
    ///
    /// - Parameter path: The new spec directory path (e.g., ".kiro/specs").
    func updateSpecDirectoryPath(_ path: String) {
        let normalizedPath = Self.normalizedSpecDirectoryPath(
            path,
            repositoryName: primaryRepository?.name
        )
        workspace.specDirectoryPath = normalizedPath
        editingSpecPath = normalizedPath
        workspace.updatedAt = Date()
        try? modelContext?.save()
    }

    /// Normalizes a GitLab repository-tree path to the form expected by the API.
    static func normalizedSpecDirectoryPath(_ path: String, repositoryName: String? = nil) -> String {
        var components = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if let repositoryName,
           components.first?.caseInsensitiveCompare(repositoryName) == .orderedSame {
            components.removeFirst()
        }

        return components.joined(separator: "/")
    }

    // MARK: - Spec Discovery

    /// Loads available remote branches for the scan selector.
    func loadBranchOptions() async {
        guard let repository = primaryRepository,
              let apiClient,
              !isLoadingBranches else {
            return
        }

        isLoadingBranches = true
        defer { isLoadingBranches = false }

        do {
            let branches = try await apiClient.fetchBranches(projectId: repository.gitlabProjectId)
            branchOptions = branches.map(\.name)
            if let selectedBranchName, branchOptions.contains(selectedBranchName) {
                reconcileSelection()
                return
            }

            selectedBranchName = branchOptions.contains(repository.defaultBranch)
                ? repository.defaultBranch
                : branchOptions.first
            reconcileSelection()
        } catch {
            branchOptions = []
        }
    }

    /// Scans the selected remote branch for spec files.
    func scanForSpecs() async {
        guard let modelContext = modelContext,
              let specTrackingService = specTrackingService else {
            errorMessage = "Service not configured."
            return
        }

        guard let repository = workspace.repositories.first else {
            errorMessage = "No repository associated with this workspace."
            return
        }

        guard !workspace.specDirectoryPath.isEmpty else {
            errorMessage = "Spec directory path is not configured."
            return
        }

        guard let selectedBranchName else {
            errorMessage = "Select a remote branch before scanning."
            return
        }

        let normalizedPath = Self.normalizedSpecDirectoryPath(
            workspace.specDirectoryPath,
            repositoryName: repository.name
        )

        if normalizedPath != workspace.specDirectoryPath {
            workspace.specDirectoryPath = normalizedPath
            editingSpecPath = normalizedPath
            workspace.updatedAt = Date()
        }

        isScanning = true
        errorMessage = nil
        scanSummary = nil
        scannedBranchNames = []

        do {
            let projectId = repository.gitlabProjectId

            // Fetch all branches
            let branches = try await fetchBranches(projectId: projectId)
            branchOptions = branches.map(\.name)
            scannedBranchNames = [selectedBranchName]
            let beforeScanCount = specs.count

            try await specTrackingService.discoverSpecsOnBranch(
                branchName: selectedBranchName,
                workspace: workspace
            )

            try modelContext.save()
            reconcileSelection()

            if specs.isEmpty && beforeScanCount == 0 {
                errorMessage = "No specs found in \"\(workspace.specDirectoryPath)\" on branch \"\(selectedBranchName)\". Use a path relative to the repository root; if you copied a GitLab breadcrumb, omit the repository name segment."
            } else {
                scanSummary = "Scanned branch \"\(selectedBranchName)\"."
            }
        } catch {
            errorMessage = "Failed to scan for specs: \(error.localizedDescription)"
        }

        isScanning = false
    }

    /// Fetches branches from the GitLab API.
    private func fetchBranches(projectId: Int) async throws -> [GitLabBranch] {
        guard let apiClient = apiClient else {
            throw SpecTrackingError.noRepository
        }

        return try await apiClient.fetchBranches(projectId: projectId)
    }

    // MARK: - Spec Detail

    /// Gets the latest content for a spec entry.
    ///
    /// - Parameter spec: The spec entry to get content for.
    /// - Returns: The latest version content, or nil if no versions exist.
    func latestContent(for spec: OpenSpecEntry) -> String? {
        let sortedVersions = spec.versions.sorted { $0.detectedAt > $1.detectedAt }
        return sortedVersions.first?.content
    }

    func latestSnapshot(for spec: OpenSpecEntry) -> OpenSpecDocumentSnapshot? {
        guard let content = latestContent(for: spec) else {
            return nil
        }

        return OpenSpecDocumentSnapshot.decode(content, legacyPhase: spec.phase)
    }

    func taskProgress(for spec: OpenSpecEntry) -> OpenSpecTaskProgress? {
        latestSnapshot(for: spec)?.taskProgress
    }

    /// Selects a branch and drops any reader selection hidden by that branch.
    func selectBranch(_ branchName: String) {
        selectedBranchName = branchName
        reconcileSelection()
    }

    /// Keeps the selected detail item aligned with the currently visible queue.
    func reconcileSelection() {
        guard let selectedSpec else {
            return
        }

        guard specs.contains(where: { $0.id == selectedSpec.id }) else {
            self.selectedSpec = nil
            return
        }
    }

    /// Marks a spec's unread badge as read.
    ///
    /// - Parameter spec: The spec entry to mark as read.
    func markAsRead(_ spec: OpenSpecEntry) {
        guard spec.hasUnreadVersion else {
            return
        }

        spec.hasUnreadVersion = false
        try? modelContext?.save()
    }

    // MARK: - Phase Display

    /// Returns a human-readable label for a spec phase.
    static func phaseLabel(for phase: SpecPhase) -> String {
        switch phase {
        case .proposal:
            return "Proposal"
        case .design:
            return "Design"
        case .tasks:
            return "Tasks"
        }
    }

    /// Returns the SF Symbol icon name for a spec phase.
    static func phaseIcon(for phase: SpecPhase) -> String {
        switch phase {
        case .proposal:
            return "doc.text"
        case .design:
            return "pencil.and.ruler"
        case .tasks:
            return "checklist"
        }
    }
}
