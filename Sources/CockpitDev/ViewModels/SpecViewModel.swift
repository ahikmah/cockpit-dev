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

    // MARK: - Computed Properties

    /// All specs for the workspace, sorted by name then branch.
    var specs: [OpenSpecEntry] {
        workspace.specs.sorted { lhs, rhs in
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

    // MARK: - Initialization

    init(workspace: Workspace) {
        self.workspace = workspace
        self.editingSpecPath = workspace.specDirectoryPath
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
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.specDirectoryPath = trimmedPath
        editingSpecPath = trimmedPath
        workspace.updatedAt = Date()
        try? modelContext?.save()
    }

    // MARK: - Spec Discovery

    /// Scans all branches in the workspace repositories for spec files.
    ///
    /// This triggers a full discovery of specs across all branches,
    /// creating or updating OpenSpecEntry records as needed.
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

        isScanning = true
        errorMessage = nil

        do {
            let projectId = repository.gitlabProjectId

            // Fetch all branches
            let branches = try await fetchBranches(projectId: projectId)

            // Discover specs on each branch
            for branch in branches {
                do {
                    try await specTrackingService.discoverSpecsOnBranch(
                        branchName: branch.name,
                        workspace: workspace
                    )
                } catch {
                    // Continue scanning other branches even if one fails
                }
            }

            try modelContext.save()
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

    /// Marks a spec's unread badge as read.
    ///
    /// - Parameter spec: The spec entry to mark as read.
    func markAsRead(_ spec: OpenSpecEntry) {
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
