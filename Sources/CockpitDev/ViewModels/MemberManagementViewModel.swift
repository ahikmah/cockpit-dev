import Foundation
import SwiftData
import SwiftUI

// MARK: - Member Management Errors

/// Errors that can occur during member management operations.
enum MemberManagementError: Error, LocalizedError {
    case duplicateMember(String)
    case lastOwnerProtection
    case insufficientPermissions
    case searchQueryTooShort
    case memberNotFound
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .duplicateMember(let username):
            return "\(username) is already a member of this workspace."
        case .lastOwnerProtection:
            return "Cannot change or remove the last Owner. A workspace must have at least one Owner."
        case .insufficientPermissions:
            return "Insufficient permissions. Only Owners and Admins can perform this action."
        case .searchQueryTooShort:
            return "Please enter at least 2 characters to search."
        case .memberNotFound:
            return "Member not found."
        case .unknown(let detail):
            return "An error occurred: \(detail)"
        }
    }
}

// MARK: - Member Management ViewModel

/// ViewModel managing team member operations within a workspace.
/// Handles invite flow, role changes, skill profile configuration, and member removal.
@Observable
@MainActor
class MemberManagementViewModel {

    // MARK: - State

    /// The workspace being managed.
    private(set) var workspace: Workspace?

    /// Whether the invite sheet is shown.
    var showInviteSheet: Bool = false

    /// The search query for GitLab user search.
    var searchQuery: String = ""

    /// Search results from GitLab user search.
    private(set) var searchResults: [GitLabUser] = []

    /// Whether a search is in progress.
    private(set) var isSearching: Bool = false

    /// Error message to display to the user.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    /// Whether the remove confirmation dialog is shown.
    var showRemoveConfirmation: Bool = false

    /// The member pending removal.
    var memberPendingRemoval: Member?

    /// The current user's role in the workspace (for permission checks).
    private(set) var currentUserRole: MemberRole = .viewer

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private var gitLabAPIClient: GitLabAPIClient?

    // MARK: - Initialization

    init() {}

    /// Configures the view model with dependencies.
    /// - Parameters:
    ///   - workspace: The workspace to manage members for.
    ///   - modelContext: The SwiftData model context.
    ///   - gitLabAPIClient: The GitLab API client for user search.
    ///   - currentUserRole: The role of the current user in this workspace.
    func configure(
        workspace: Workspace,
        modelContext: ModelContext,
        gitLabAPIClient: GitLabAPIClient? = nil,
        currentUserRole: MemberRole = .owner
    ) {
        self.workspace = workspace
        self.modelContext = modelContext
        self.gitLabAPIClient = gitLabAPIClient
        self.currentUserRole = currentUserRole
    }

    // MARK: - Member List

    /// Returns the members associated with the current workspace.
    var members: [Member] {
        workspace?.members ?? []
    }

    /// Returns whether the current user can manage members (Owner or Admin).
    var canManageMembers: Bool {
        currentUserRole == .owner || currentUserRole == .admin
    }

    /// Returns whether the current user is a Viewer (cannot modify workspace data).
    var isViewer: Bool {
        currentUserRole == .viewer
    }

    // MARK: - Search GitLab Users

    /// Searches GitLab users by query string.
    /// Requires minimum 2 characters and returns max 20 results.
    func searchUsers() async {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.count >= 2 else {
            searchResults = []
            return
        }

        guard let gitLabAPIClient else {
            showErrorMessage("GitLab API client is not configured. Please connect your GitLab account first.")
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await gitLabAPIClient.searchUsers(query: trimmedQuery)
            // Max 20 results as per requirement
            searchResults = Array(results.prefix(20))
        } catch {
            showErrorMessage("Failed to search users: \(error.localizedDescription)")
            searchResults = []
        }
    }

    // MARK: - Invite Member

    /// Invites a GitLab user as a member of the workspace.
    /// - Parameter user: The GitLab user to invite.
    /// - Returns: `true` if the member was successfully added.
    @discardableResult
    func inviteMember(_ user: GitLabUser) -> Bool {
        // Permission check: only Owner/Admin can invite
        guard canManageMembers else {
            showErrorMessage(MemberManagementError.insufficientPermissions.localizedDescription)
            return false
        }

        // Viewer enforcement
        guard !isViewer else {
            showErrorMessage(MemberManagementError.insufficientPermissions.localizedDescription)
            return false
        }

        // Duplicate detection
        if isDuplicateMember(gitlabUserId: user.id) {
            showErrorMessage(MemberManagementError.duplicateMember(user.username).localizedDescription)
            return false
        }

        guard let workspace, let modelContext else {
            showErrorMessage("Unable to save member.")
            return false
        }

        // Create member with default "member" role
        let member = Member(
            gitlabUserId: user.id,
            username: user.username,
            displayName: user.name,
            avatarURL: user.avatarUrl,
            email: user.email,
            role: .member
        )

        member.workspace = workspace
        workspace.members.append(member)
        modelContext.insert(member)

        do {
            try modelContext.save()
            // Clear search state
            searchQuery = ""
            searchResults = []
            return true
        } catch {
            showErrorMessage("Failed to add member: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Role Change

    /// Changes a member's role.
    /// - Parameters:
    ///   - member: The member whose role to change.
    ///   - newRole: The new role to assign.
    /// - Returns: `true` if the role was successfully changed.
    @discardableResult
    func changeRole(of member: Member, to newRole: MemberRole) -> Bool {
        // Permission check
        guard canManageMembers else {
            showErrorMessage(MemberManagementError.insufficientPermissions.localizedDescription)
            return false
        }

        // Last-owner protection
        if member.role == .owner && newRole != .owner {
            let ownerCount = members.filter { $0.role == .owner }.count
            if ownerCount <= 1 {
                showErrorMessage(MemberManagementError.lastOwnerProtection.localizedDescription)
                return false
            }
        }

        member.role = newRole

        do {
            try modelContext?.save()
            return true
        } catch {
            showErrorMessage("Failed to change role: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Remove Member

    /// Initiates the removal flow by setting the pending member and showing confirmation.
    func confirmRemoval(of member: Member) {
        // Permission check
        guard canManageMembers else {
            showErrorMessage(MemberManagementError.insufficientPermissions.localizedDescription)
            return
        }

        // Last-owner protection
        if member.role == .owner {
            let ownerCount = members.filter { $0.role == .owner }.count
            if ownerCount <= 1 {
                showErrorMessage(MemberManagementError.lastOwnerProtection.localizedDescription)
                return
            }
        }

        memberPendingRemoval = member
        showRemoveConfirmation = true
    }

    /// Executes the pending removal with ticket unassignment cascade.
    func executeRemoval() {
        guard let member = memberPendingRemoval,
              let workspace,
              let modelContext else { return }

        // Unassign from all tickets in workspace (cascade)
        for ticket in workspace.tickets where ticket.assignee?.id == member.id {
            ticket.assignee = nil
        }

        // Remove from workspace
        workspace.members.removeAll { $0.id == member.id }
        member.workspace = nil

        // Delete the member model
        modelContext.delete(member)

        do {
            try modelContext.save()
        } catch {
            showErrorMessage("Failed to remove member: \(error.localizedDescription)")
        }

        memberPendingRemoval = nil
    }

    // MARK: - Skill Profile

    /// Updates a member's skill profile.
    /// - Parameters:
    ///   - member: The member to update.
    ///   - profile: The new skill profile (or nil to clear).
    /// - Returns: `true` if the profile was successfully updated.
    @discardableResult
    func updateSkillProfile(of member: Member, to profile: SkillProfile?) -> Bool {
        // Permission check
        guard canManageMembers else {
            showErrorMessage(MemberManagementError.insufficientPermissions.localizedDescription)
            return false
        }

        member.skillProfile = profile

        do {
            try modelContext?.save()
            return true
        } catch {
            showErrorMessage("Failed to update skill profile: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Viewer Enforcement

    /// Checks if the current user has permission to modify workspace data.
    /// Returns false and shows error if user is a Viewer.
    func checkModifyPermission() -> Bool {
        if isViewer {
            showErrorMessage(MemberManagementError.insufficientPermissions.localizedDescription)
            return false
        }
        return true
    }

    // MARK: - Duplicate Detection

    /// Checks if a GitLab user is already a member of the workspace.
    /// - Parameter gitlabUserId: The GitLab user ID to check.
    /// - Returns: `true` if the user is already a member.
    func isDuplicateMember(gitlabUserId: Int) -> Bool {
        members.contains { $0.gitlabUserId == gitlabUserId }
    }

    // MARK: - Reset

    /// Resets the invite form state.
    func resetInviteForm() {
        searchQuery = ""
        searchResults = []
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
