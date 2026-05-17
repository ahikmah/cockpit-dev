import Foundation
import SwiftData
import SwiftUI

// MARK: - Suggestion Decision

/// Represents the user's decision for each assignment suggestion.
enum SuggestionDecision: Equatable {
    case accepted
    case modified(Member)
    case rejected
}

// MARK: - AutoAssignViewModel

/// ViewModel managing the auto-assign workflow including computation,
/// review, modification, and confirmation of ticket assignments.
@Observable
@MainActor
class AutoAssignViewModel {

    // MARK: - State

    /// The computed assignment suggestions.
    var suggestions: [AssignmentSuggestion] = []

    /// User decisions for each suggestion (keyed by suggestion ID).
    var decisions: [UUID: SuggestionDecision] = [:]

    /// Whether the auto-assign computation is in progress.
    var isProcessing: Bool = false

    /// Whether suggestions are ready for review.
    var showSuggestions: Bool = false

    /// Whether the confirmation was successful.
    var confirmationSuccess: Bool = false

    /// Error message to display.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    /// Progress message during processing.
    var progressMessage: String = ""

    /// Whether the member picker is shown for modifying a suggestion.
    var showMemberPicker: Bool = false

    /// The suggestion currently being modified.
    var modifyingSuggestionId: UUID?

    // MARK: - Dependencies

    private let autoAssignService = AutoAssignService()
    private var modelContext: ModelContext?
    private var syncEngine: SyncEngine?
    private var workspace: Workspace?

    // MARK: - Initialization

    init() {}

    /// Configures the view model with dependencies.
    func configure(
        modelContext: ModelContext,
        syncEngine: SyncEngine?,
        workspace: Workspace?
    ) {
        self.modelContext = modelContext
        self.syncEngine = syncEngine
        self.workspace = workspace
    }

    // MARK: - Computed Properties

    /// Suggestions that have assignable members (not skipped/unassignable).
    var assignableSuggestions: [AssignmentSuggestion] {
        suggestions.filter { $0.suggestedMember != nil }
    }

    /// Suggestions that are unassignable or skipped.
    var unassignableSuggestions: [AssignmentSuggestion] {
        suggestions.filter { $0.suggestedMember == nil }
    }

    /// Number of accepted suggestions.
    var acceptedCount: Int {
        decisions.values.filter { $0 == .accepted || isModified($0) }.count
    }

    /// Number of rejected suggestions.
    var rejectedCount: Int {
        decisions.values.filter { $0 == .rejected }.count
    }

    // MARK: - Auto-Assign Computation

    /// Runs the auto-assign algorithm for the given tickets in the current sprint.
    func computeAssignments(tickets: [Ticket], sprint: Sprint) {
        guard let workspace = workspace else {
            showErrorMessage("Workspace not configured.")
            return
        }

        isProcessing = true
        progressMessage = "Computing assignments..."

        let members = workspace.members
        let maxThreshold = workspace.maxStoryPointsThreshold

        suggestions = autoAssignService.computeAssignments(
            tickets: tickets,
            members: members,
            sprint: sprint,
            maxThreshold: maxThreshold
        )

        // Default all assignable suggestions to accepted
        for suggestion in suggestions where suggestion.suggestedMember != nil {
            decisions[suggestion.id] = .accepted
        }

        showSuggestions = true
        isProcessing = false
        progressMessage = ""
    }

    // MARK: - User Actions

    /// Accepts a suggestion.
    func accept(suggestionId: UUID) {
        decisions[suggestionId] = .accepted
    }

    /// Rejects a suggestion.
    func reject(suggestionId: UUID) {
        decisions[suggestionId] = .rejected
    }

    /// Starts modifying a suggestion (opens member picker).
    func startModifying(suggestionId: UUID) {
        modifyingSuggestionId = suggestionId
        showMemberPicker = true
    }

    /// Completes modification by assigning a different member.
    func modifyAssignment(suggestionId: UUID, newMember: Member) {
        decisions[suggestionId] = .modified(newMember)
        showMemberPicker = false
        modifyingSuggestionId = nil
    }

    /// Accepts all assignable suggestions.
    func acceptAll() {
        for suggestion in assignableSuggestions {
            decisions[suggestion.id] = .accepted
        }
    }

    /// Rejects all assignable suggestions.
    func rejectAll() {
        for suggestion in assignableSuggestions {
            decisions[suggestion.id] = .rejected
        }
    }

    // MARK: - Confirmation Flow

    /// Confirms the accepted/modified suggestions, updating assignees and syncing to GitLab.
    func confirmAssignments() async {
        guard let modelContext = modelContext else {
            showErrorMessage("Model context not configured.")
            return
        }

        isProcessing = true
        progressMessage = "Applying assignments..."

        var appliedCount = 0

        for suggestion in suggestions {
            guard let decision = decisions[suggestion.id] else { continue }

            let memberToAssign: Member?
            switch decision {
            case .accepted:
                memberToAssign = suggestion.suggestedMember
            case .modified(let member):
                memberToAssign = member
            case .rejected:
                continue
            }

            guard let member = memberToAssign else { continue }

            // Update the ticket's assignee
            suggestion.ticket.assignee = member
            suggestion.ticket.updatedAt = Date()
            appliedCount += 1

            // Sync to GitLab
            if let syncEngine = syncEngine {
                try? await syncEngine.pushTicketToGitLab(suggestion.ticket)
            }
        }

        do {
            try modelContext.save()
            confirmationSuccess = true
            progressMessage = "Successfully assigned \(appliedCount) tickets."
        } catch {
            showErrorMessage("Failed to save assignments: \(error.localizedDescription)")
        }

        isProcessing = false
    }

    // MARK: - Reset

    /// Resets the view model to its initial state.
    func reset() {
        suggestions = []
        decisions = [:]
        isProcessing = false
        showSuggestions = false
        confirmationSuccess = false
        errorMessage = nil
        showError = false
        progressMessage = ""
        showMemberPicker = false
        modifyingSuggestionId = nil
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        progressMessage = ""
    }

    private func isModified(_ decision: SuggestionDecision) -> Bool {
        if case .modified = decision { return true }
        return false
    }
}
