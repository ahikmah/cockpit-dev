import Foundation
import SwiftData
import SwiftUI

/// ViewModel managing the PRD breakdown workflow including AI analysis,
/// preview editing, confirmation, and re-evaluation flows.
@Observable
@MainActor
class PRDBreakdownViewModel {

    // MARK: - State

    /// The PRD content input by the user.
    var prdContent: String = ""

    /// Generated tickets from AI breakdown.
    var generatedTickets: [GeneratedTicket] = []

    /// Re-evaluation result when comparing updated PRD.
    var reEvaluationResult: ReEvaluationResult?

    /// Whether the AI is currently processing.
    var isProcessing: Bool = false

    /// Whether the breakdown has been completed and tickets are in preview.
    var showPreview: Bool = false

    /// Whether the re-evaluation comparison is shown.
    var showReEvaluation: Bool = false

    /// Error message to display.
    var errorMessage: String?

    /// Whether an error alert is shown.
    var showError: Bool = false

    /// Whether the confirmation was successful.
    var confirmationSuccess: Bool = false

    /// Whether the edit ticket sheet is shown.
    var showEditSheet: Bool = false

    /// Whether the add ticket sheet is shown.
    var showAddSheet: Bool = false

    /// The ticket currently being edited.
    var editingTicket: GeneratedTicket?

    /// Index of the ticket being edited.
    var editingIndex: Int?

    /// Progress message during processing.
    var progressMessage: String = ""

    // MARK: - Dependencies

    private var aiService: AIService?
    private var modelContext: ModelContext?
    private var syncEngine: SyncEngine?
    private var workspace: Workspace?

    // MARK: - Initialization

    init() {}

    /// Configures the view model with dependencies.
    func configure(
        aiService: AIService,
        modelContext: ModelContext,
        syncEngine: SyncEngine?,
        workspace: Workspace?
    ) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.syncEngine = syncEngine
        self.workspace = workspace
    }

    // MARK: - PRD Breakdown

    /// Initiates the AI breakdown of the PRD content.
    func breakdownPRD() async {
        guard !prdContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showErrorMessage("Please provide PRD content to analyze.")
            return
        }

        guard let aiService = aiService else {
            showErrorMessage("AI Service not configured.")
            return
        }

        isProcessing = true
        progressMessage = "Analyzing PRD with AI..."
        errorMessage = nil

        do {
            let tickets = try await aiService.breakdownPRD(content: prdContent)
            generatedTickets = tickets
            showPreview = true
            progressMessage = ""
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isProcessing = false
    }

    /// Retries the PRD breakdown after a failure.
    func retryBreakdown() async {
        await breakdownPRD()
    }

    // MARK: - Preview Editing

    /// Removes a ticket from the preview list.
    func removeTicket(at index: Int) {
        guard index >= 0 && index < generatedTickets.count else { return }
        generatedTickets.remove(at: index)
    }

    /// Removes tickets at the specified offsets.
    func removeTickets(at offsets: IndexSet) {
        generatedTickets.remove(atOffsets: offsets)
    }

    /// Starts editing a ticket at the specified index.
    func startEditing(at index: Int) {
        guard index >= 0 && index < generatedTickets.count else { return }
        editingTicket = generatedTickets[index]
        editingIndex = index
        showEditSheet = true
    }

    /// Saves the edited ticket back to the list.
    func saveEditedTicket(_ ticket: GeneratedTicket) {
        guard let index = editingIndex, index >= 0 && index < generatedTickets.count else { return }
        generatedTickets[index] = ticket
        editingTicket = nil
        editingIndex = nil
        showEditSheet = false
    }

    /// Starts adding a new ticket.
    func startAddingTicket() {
        showAddSheet = true
    }

    /// Adds a new ticket to the preview list.
    func addTicket(_ ticket: GeneratedTicket) {
        generatedTickets.append(ticket)
        showAddSheet = false
    }

    // MARK: - Confirmation Flow

    /// Confirms the generated tickets, creating them in the workspace and syncing to GitLab.
    func confirmTickets() async {
        guard let modelContext = modelContext, let workspace = workspace else {
            showErrorMessage("Workspace not configured.")
            return
        }

        isProcessing = true
        progressMessage = "Creating tickets..."

        do {
            for generatedTicket in generatedTickets {
                let ticket = Ticket(
                    title: generatedTicket.title,
                    descriptionText: generatedTicket.description,
                    status: .backlog,
                    priority: generatedTicket.priority,
                    storyPoints: generatedTicket.estimatedStoryPoints,
                    labels: [generatedTicket.skillClassification.rawValue]
                )
                ticket.workspace = workspace
                modelContext.insert(ticket)

                // Sync to GitLab
                if let syncEngine = syncEngine {
                    try? await syncEngine.pushTicketToGitLab(ticket)
                }
            }

            try modelContext.save()
            confirmationSuccess = true
            progressMessage = "Successfully created \(generatedTickets.count) tickets."
        } catch {
            showErrorMessage("Failed to create tickets: \(error.localizedDescription)")
        }

        isProcessing = false
    }

    // MARK: - Re-Evaluation

    /// Re-evaluates an updated PRD against existing workspace tickets.
    func reEvaluatePRD() async {
        guard !prdContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showErrorMessage("Please provide updated PRD content.")
            return
        }

        guard let aiService = aiService, let workspace = workspace else {
            showErrorMessage("AI Service or workspace not configured.")
            return
        }

        isProcessing = true
        progressMessage = "Re-evaluating PRD changes..."

        let existingTitles = workspace.tickets.map { $0.title }

        do {
            let result = try await aiService.reEvaluate(
                updatedPRD: prdContent,
                existingTicketTitles: existingTitles
            )
            reEvaluationResult = result
            showReEvaluation = true
            progressMessage = ""
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isProcessing = false
    }

    /// Applies the re-evaluation result, creating new tickets and updating changed ones.
    func applyReEvaluation() async {
        guard let result = reEvaluationResult,
              let modelContext = modelContext,
              let workspace = workspace else {
            return
        }

        isProcessing = true
        progressMessage = "Applying changes..."

        do {
            // Create new tickets
            for generatedTicket in result.newTickets {
                let ticket = Ticket(
                    title: generatedTicket.title,
                    descriptionText: generatedTicket.description,
                    status: .backlog,
                    priority: generatedTicket.priority,
                    storyPoints: generatedTicket.estimatedStoryPoints,
                    labels: [generatedTicket.skillClassification.rawValue]
                )
                ticket.workspace = workspace
                modelContext.insert(ticket)

                if let syncEngine = syncEngine {
                    try? await syncEngine.pushTicketToGitLab(ticket)
                }
            }

            // Update changed tickets
            for changed in result.changedTickets {
                if let existingTicket = workspace.tickets.first(where: { $0.title == changed.existingTitle }) {
                    existingTicket.title = changed.suggested.title
                    existingTicket.descriptionText = changed.suggested.description
                    existingTicket.priority = changed.suggested.priority
                    existingTicket.storyPoints = changed.suggested.estimatedStoryPoints
                    existingTicket.updatedAt = Date()

                    if let syncEngine = syncEngine {
                        try? await syncEngine.pushTicketToGitLab(existingTicket)
                    }
                }
            }

            try modelContext.save()
            confirmationSuccess = true
            progressMessage = "Re-evaluation applied successfully."
        } catch {
            showErrorMessage("Failed to apply re-evaluation: \(error.localizedDescription)")
        }

        isProcessing = false
    }

    // MARK: - Reset

    /// Resets the view model to its initial state.
    func reset() {
        prdContent = ""
        generatedTickets = []
        reEvaluationResult = nil
        isProcessing = false
        showPreview = false
        showReEvaluation = false
        errorMessage = nil
        showError = false
        confirmationSuccess = false
        progressMessage = ""
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
        progressMessage = ""
    }
}
