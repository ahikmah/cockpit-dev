import Foundation

/// Centralized validation utility for Cockpit Dev business rules.
///
/// Consolidates all validation logic into a single, testable utility.
/// ViewModels and Services can delegate to these static methods for consistent
/// validation behavior across the application.
///
/// **Validates:** Requirements 1, 6, 12, 15, 16, 20
/// **Design:** Properties 1-5
enum Validators {

    // MARK: - Validation Result

    /// Represents the result of a validation operation.
    enum ValidationResult: Equatable {
        case valid
        case invalid(String)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        var errorMessage: String? {
            if case .invalid(let message) = self { return message }
            return nil
        }
    }

    // MARK: - Workspace Name Validation (Requirement 1, Property 1)

    /// Validates a workspace name against naming rules.
    ///
    /// Rules:
    /// - Must be 1-100 characters
    /// - Allowed characters: alphanumeric, spaces, hyphens, underscores
    ///
    /// - Parameter name: The workspace name to validate.
    /// - Returns: A `ValidationResult` indicating validity.
    static func validateWorkspaceName(_ name: String) -> ValidationResult {
        if name.isEmpty {
            return .invalid("Workspace name cannot be empty.")
        }

        if name.count > AppConstants.maxWorkspaceNameLength {
            return .invalid("Workspace name must be \(AppConstants.maxWorkspaceNameLength) characters or fewer.")
        }

        let allowedCharacterSet = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -_"))

        if name.unicodeScalars.contains(where: { !allowedCharacterSet.contains($0) }) {
            return .invalid("Workspace name can only contain letters, numbers, spaces, hyphens, and underscores.")
        }

        return .valid
    }

    /// Checks if a workspace name is unique among existing names (case-insensitive).
    ///
    /// - Parameters:
    ///   - name: The name to check.
    ///   - existingNames: The list of existing workspace names.
    /// - Returns: A `ValidationResult` indicating uniqueness.
    static func validateWorkspaceNameUniqueness(_ name: String, existingNames: [String]) -> ValidationResult {
        let lowercasedName = name.lowercased()
        if existingNames.contains(where: { $0.lowercased() == lowercasedName }) {
            return .invalid("A workspace with the name \"\(name)\" already exists. Please choose a different name.")
        }
        return .valid
    }

    // MARK: - Sprint Date Validation (Requirement 12, Property 5)

    /// Validates that sprint start date is strictly before end date.
    ///
    /// - Parameters:
    ///   - startDate: The sprint start date.
    ///   - endDate: The sprint end date.
    /// - Returns: A `ValidationResult` indicating validity.
    static func validateSprintDates(startDate: Date, endDate: Date) -> ValidationResult {
        if startDate >= endDate {
            return .invalid("Start date must be before end date.")
        }
        return .valid
    }

    // MARK: - Story Points Validation (Requirement 6, Property 4)

    /// Validates that a story points value is in the allowed Fibonacci set.
    ///
    /// Allowed values: 1, 2, 3, 5, 8, 13, 21
    ///
    /// - Parameter value: The story points value to validate.
    /// - Returns: A `ValidationResult` indicating validity.
    static func validateStoryPoints(_ value: Int) -> ValidationResult {
        guard AppConstants.fibonacciSequence.contains(value) else {
            let allowed = AppConstants.fibonacciSequence.map(String.init).joined(separator: ", ")
            return .invalid("Story points must be a Fibonacci value: \(allowed).")
        }
        return .valid
    }

    /// Checks if a story points value is non-standard (not in the Fibonacci set).
    ///
    /// Used for external values from GitLab that may not conform to the local constraint.
    ///
    /// - Parameter value: The story points value to check.
    /// - Returns: `true` if the value is non-standard.
    static func isNonStandardStoryPoints(_ value: Int) -> Bool {
        return !AppConstants.fibonacciSequence.contains(value)
    }

    // MARK: - Commit Message Validation (Requirement 15)

    /// Validates a commit message against length constraints.
    ///
    /// Rules:
    /// - Must be 1-500 characters (after trimming whitespace)
    ///
    /// - Parameter message: The commit message to validate.
    /// - Returns: A `ValidationResult` indicating validity.
    static func validateCommitMessage(_ message: String) -> ValidationResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .invalid("Commit message cannot be empty.")
        }

        if trimmed.count > AppConstants.maxCommitMessageLength {
            return .invalid("Commit message must be \(AppConstants.maxCommitMessageLength) characters or fewer (currently \(trimmed.count)).")
        }

        return .valid
    }

    // MARK: - File Size Validation (Requirement 16)

    /// Validates that a file size does not exceed the maximum allowed size (100 MB).
    ///
    /// - Parameter fileSize: The file size in bytes.
    /// - Returns: A `ValidationResult` indicating validity.
    static func validateFileSize(_ fileSize: Int64) -> ValidationResult {
        if fileSize < 0 {
            return .invalid("File size cannot be negative.")
        }

        if fileSize > AppConstants.maxFileSizeBytes {
            let maxMB = AppConstants.maxFileSizeBytes / (1024 * 1024)
            return .invalid("File exceeds the maximum size of \(maxMB) MB.")
        }

        return .valid
    }

    // MARK: - Role Permission Checks (Requirements 1, 3, 20)

    /// Checks if a role has management permissions (Owner or Admin).
    ///
    /// Management actions include: inviting/removing members, changing roles,
    /// configuring columns, managing workspace settings.
    ///
    /// - Parameter role: The member role to check.
    /// - Returns: `true` if the role has management permissions.
    static func canManage(role: MemberRole) -> Bool {
        return role == .owner || role == .admin
    }

    /// Validates that a role has permission to perform a management action.
    ///
    /// - Parameter role: The member role to check.
    /// - Returns: A `ValidationResult` indicating permission.
    static func validateManagementPermission(role: MemberRole) -> ValidationResult {
        if canManage(role: role) {
            return .valid
        }
        return .invalid("Insufficient permissions. Only Owner and Admin roles can perform this action.")
    }

    /// Validates that a role change does not remove the last owner.
    ///
    /// - Parameters:
    ///   - currentRole: The member's current role.
    ///   - newRole: The proposed new role.
    ///   - ownerCount: The current number of owners in the workspace.
    /// - Returns: A `ValidationResult` indicating validity.
    static func validateRoleChange(currentRole: MemberRole, newRole: MemberRole, ownerCount: Int) -> ValidationResult {
        if currentRole == .owner && newRole != .owner && ownerCount <= 1 {
            return .invalid("A workspace must have at least one Owner. Cannot change the last Owner's role.")
        }
        return .valid
    }

    /// Validates that a viewer is not attempting to modify workspace data.
    ///
    /// - Parameter role: The member role to check.
    /// - Returns: A `ValidationResult` indicating permission.
    static func validateModifyPermission(role: MemberRole) -> ValidationResult {
        if role == .viewer {
            return .invalid("Viewers cannot modify workspace data.")
        }
        return .valid
    }
}
