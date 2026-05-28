import Foundation
import SwiftData
import SwiftUI

/// ViewModel managing workspace CRUD operations and list state.
@Observable
@MainActor
class WorkspaceListViewModel {

    // MARK: - State

    /// All workspaces loaded from SwiftData.
    private(set) var workspaces: [Workspace] = []

    /// The currently selected workspace.
    var selectedWorkspace: Workspace?

    /// Whether the create workspace sheet is shown.
    var showCreateSheet: Bool = false

    /// Whether the delete confirmation dialog is shown.
    var showDeleteConfirmation: Bool = false

    /// The workspace pending deletion (set before showing confirmation).
    var workspacePendingDeletion: Workspace?

    /// Error message to display to the user.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    // MARK: - Dependencies

    private var modelContext: ModelContext?

    // MARK: - Initialization

    init() {}

    /// Configures the view model with a SwiftData model context.
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchWorkspaces()
    }

    // MARK: - CRUD Operations

    /// Fetches all workspaces from SwiftData, sorted by creation date.
    func fetchWorkspaces() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Workspace>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            workspaces = try modelContext.fetch(descriptor)
            if let selectedId = selectedWorkspace?.id {
                selectedWorkspace = workspaces.first { $0.id == selectedId }
            }
        } catch {
            showErrorMessage("Failed to load workspaces: \(error.localizedDescription)")
        }
    }

    /// Creates a new workspace with the given name after validation.
    /// - Parameter name: The workspace name to create.
    /// - Returns: `true` if creation succeeded, `false` otherwise.
    @discardableResult
    func createWorkspace(name: String) -> Bool {
        guard let modelContext else {
            showErrorMessage("Unable to save workspace.")
            return false
        }

        // Validate name
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if let validationError = validateWorkspaceName(trimmedName) {
            showErrorMessage(validationError)
            return false
        }

        // Check for duplicate name
        if isDuplicateName(trimmedName) {
            showErrorMessage("A workspace with the name \"\(trimmedName)\" already exists. Please choose a different name.")
            return false
        }

        // Create workspace
        let workspace = Workspace(name: trimmedName)
        modelContext.insert(workspace)

        do {
            try modelContext.save()
            fetchWorkspaces()
            selectedWorkspace = workspace
            return true
        } catch {
            showErrorMessage("Failed to create workspace: \(error.localizedDescription)")
            return false
        }
    }

    /// Deletes the specified workspace after confirmation.
    /// - Parameter workspace: The workspace to delete.
    func deleteWorkspace(_ workspace: Workspace) {
        guard let modelContext else {
            showErrorMessage("Unable to delete workspace.")
            return
        }

        modelContext.delete(workspace)

        do {
            try modelContext.save()
            if selectedWorkspace?.id == workspace.id {
                selectedWorkspace = nil
            }
            fetchWorkspaces()
        } catch {
            showErrorMessage("Failed to delete workspace: \(error.localizedDescription)")
        }
    }

    /// Initiates the deletion flow by setting the pending workspace and showing confirmation.
    func confirmDeletion(of workspace: Workspace) {
        workspacePendingDeletion = workspace
        showDeleteConfirmation = true
    }

    /// Executes the pending deletion after user confirms.
    func executePendingDeletion() {
        guard let workspace = workspacePendingDeletion else { return }
        deleteWorkspace(workspace)
        workspacePendingDeletion = nil
    }

    // MARK: - Validation

    /// Validates a workspace name against the naming rules.
    /// - Parameter name: The name to validate.
    /// - Returns: An error message if invalid, or `nil` if valid.
    func validateWorkspaceName(_ name: String) -> String? {
        if name.isEmpty {
            return "Workspace name cannot be empty."
        }

        if name.count > AppConstants.maxWorkspaceNameLength {
            return "Workspace name must be 100 characters or fewer."
        }

        // Allowed characters: alphanumeric, spaces, hyphens, underscores
        let allowedCharacterSet = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -_"))

        if name.unicodeScalars.contains(where: { !allowedCharacterSet.contains($0) }) {
            return "Workspace name can only contain letters, numbers, spaces, hyphens, and underscores."
        }

        return nil
    }

    /// Checks if a workspace name already exists (case-insensitive).
    /// - Parameter name: The name to check.
    /// - Returns: `true` if a workspace with this name already exists.
    func isDuplicateName(_ name: String) -> Bool {
        workspaces.contains { $0.name.lowercased() == name.lowercased() }
    }

    // MARK: - Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
