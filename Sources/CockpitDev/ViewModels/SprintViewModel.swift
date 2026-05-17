import Foundation
import SwiftData
import SwiftUI

/// ViewModel managing sprint planning, tracking, progress computation,
/// and burndown chart data generation.
@Observable
class SprintViewModel {

    // MARK: - Published State

    /// The current workspace.
    var workspace: Workspace?

    /// All sprints in the workspace, sorted by start date.
    var sprints: [Sprint] = []

    /// The currently selected sprint for detail view.
    var selectedSprint: Sprint?

    /// Whether a network operation is in progress.
    var isLoading: Bool = false

    /// Error message to display.
    var errorMessage: String?

    /// Whether the error alert is shown.
    var showError: Bool = false

    /// Whether the create sprint sheet is shown.
    var showCreateSprint: Bool = false

    /// Whether the move-to-next-sprint confirmation is shown.
    var showMoveToNextSprint: Bool = false

    /// Whether the create-new-sprint-for-incomplete option is shown.
    var showCreateNewSprintForIncomplete: Bool = false

    // MARK: - Sprint Creation Form State

    /// Name for the new sprint.
    var newSprintName: String = ""

    /// Start date for the new sprint.
    var newSprintStartDate: Date = Date()

    /// End date for the new sprint.
    var newSprintEndDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    /// Validation error for the creation form.
    var formValidationError: String?

    // MARK: - Ticket Assignment State

    /// Whether the ticket assignment sheet is shown.
    var showTicketAssignment: Bool = false

    /// Tickets available for assignment (not assigned to any sprint).
    var unassignedTickets: [Ticket] = []

    // MARK: - Dependencies

    private let gitLabClient: GitLabAPIClient?
    private let modelContext: ModelContext?

    // MARK: - Initialization

    init(workspace: Workspace? = nil, gitLabClient: GitLabAPIClient? = nil, modelContext: ModelContext? = nil) {
        self.workspace = workspace
        self.gitLabClient = gitLabClient
        self.modelContext = modelContext
        if workspace != nil {
            refreshSprints()
        }
    }

    // MARK: - Sprint Queries

    /// Refreshes the sprint list from workspace data.
    func refreshSprints() {
        guard let workspace = workspace else {
            sprints = []
            return
        }
        sprints = workspace.sprints.sorted { $0.startDate < $1.startDate }
        refreshUnassignedTickets()
    }

    /// Refreshes the list of tickets not assigned to any sprint.
    func refreshUnassignedTickets() {
        guard let workspace = workspace else {
            unassignedTickets = []
            return
        }
        unassignedTickets = workspace.tickets.filter { $0.sprint == nil }
    }

    // MARK: - Sprint CRUD

    /// Validates the sprint creation form.
    /// - Returns: `true` if the form is valid.
    func validateSprintForm() -> Bool {
        formValidationError = nil

        let trimmedName = newSprintName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            formValidationError = "Sprint name is required."
            return false
        }

        if trimmedName.count > 100 {
            formValidationError = "Sprint name must be 100 characters or fewer."
            return false
        }

        if newSprintStartDate >= newSprintEndDate {
            formValidationError = "Start date must be before end date."
            return false
        }

        return true
    }

    /// Creates a new sprint and corresponding GitLab milestone.
    func createSprint() async {
        guard validateSprintForm() else { return }
        guard let workspace = workspace else { return }

        let trimmedName = newSprintName.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true
        defer { isLoading = false }

        // Create GitLab milestone if we have a project
        var milestoneId: Int?
        if let gitLabClient = gitLabClient,
           let firstRepo = workspace.repositories.first {
            do {
                let milestone = try await gitLabClient.createMilestone(
                    projectId: firstRepo.gitlabProjectId,
                    title: trimmedName,
                    startDate: newSprintStartDate,
                    dueDate: newSprintEndDate
                )
                milestoneId = milestone.id
            } catch {
                errorMessage = "Failed to create GitLab milestone: \(error.localizedDescription)"
                showError = true
                // Continue creating the sprint locally even if milestone creation fails
            }
        }

        // Create local sprint
        let sprint = Sprint(
            name: trimmedName,
            startDate: newSprintStartDate,
            endDate: newSprintEndDate,
            gitlabMilestoneId: milestoneId
        )
        sprint.workspace = workspace
        workspace.sprints.append(sprint)

        // Reset form
        newSprintName = ""
        newSprintStartDate = Date()
        newSprintEndDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        formValidationError = nil
        showCreateSprint = false

        refreshSprints()
    }

    // MARK: - Ticket Assignment

    /// Assigns a ticket to the selected sprint.
    func assignTicket(_ ticket: Ticket, to sprint: Sprint) {
        ticket.sprint = sprint
        ticket.updatedAt = Date()
        if !sprint.tickets.contains(where: { $0.id == ticket.id }) {
            sprint.tickets.append(ticket)
        }
        refreshSprints()
    }

    /// Unassigns a ticket from its current sprint.
    func unassignTicket(_ ticket: Ticket) {
        if let sprint = ticket.sprint {
            sprint.tickets.removeAll { $0.id == ticket.id }
        }
        ticket.sprint = nil
        ticket.updatedAt = Date()
        refreshSprints()
    }

    // MARK: - Progress Calculation

    /// Calculates the progress percentage for a sprint.
    /// Progress = (SP of done tickets / total SP) * 100
    /// - Parameter sprint: The sprint to calculate progress for.
    /// - Returns: Progress percentage (0-100), or 0 if no SP assigned.
    func progressPercentage(for sprint: Sprint) -> Double {
        let totalSP = totalStoryPoints(for: sprint)
        guard totalSP > 0 else { return 0 }
        let doneSP = doneStoryPoints(for: sprint)
        return (Double(doneSP) / Double(totalSP)) * 100.0
    }

    /// Total story points assigned to a sprint.
    func totalStoryPoints(for sprint: Sprint) -> Int {
        sprint.tickets.compactMap { $0.storyPoints }.reduce(0, +)
    }

    /// Story points of done tickets in a sprint.
    func doneStoryPoints(for sprint: Sprint) -> Int {
        sprint.tickets
            .filter { $0.status == .done }
            .compactMap { $0.storyPoints }
            .reduce(0, +)
    }

    /// Number of tickets in a sprint.
    func ticketCount(for sprint: Sprint) -> Int {
        sprint.tickets.count
    }

    /// Number of incomplete tickets in a sprint.
    func incompleteTicketCount(for sprint: Sprint) -> Int {
        sprint.tickets.filter { $0.status != .done }.count
    }

    /// Incomplete tickets in a sprint.
    func incompleteTickets(for sprint: Sprint) -> [Ticket] {
        sprint.tickets.filter { $0.status != .done }
    }

    // MARK: - Burndown Chart Data

    /// Data point for the burndown chart.
    struct BurndownDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let remainingStoryPoints: Int
        let idealRemaining: Double
    }

    /// Generates burndown chart data for a sprint.
    /// Shows remaining SP per day from start to end (or today if sprint is active).
    func burndownData(for sprint: Sprint) -> [BurndownDataPoint] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: sprint.startDate)
        let endOfDay = calendar.startOfDay(for: sprint.endDate)
        let today = calendar.startOfDay(for: Date())

        // Determine the last date to show data for
        let lastDate = min(today, endOfDay)

        guard startOfDay <= lastDate else { return [] }

        let totalSP = totalStoryPoints(for: sprint)
        let totalDays = max(1, calendar.dateComponents([.day], from: startOfDay, to: endOfDay).day ?? 1)

        var dataPoints: [BurndownDataPoint] = []
        var currentDate = startOfDay

        while currentDate <= lastDate {
            // Calculate remaining SP as of this date
            // For simplicity, we use current state for past dates
            // In a real implementation, we'd track daily snapshots
            let remainingSP = remainingStoryPointsAsOf(sprint: sprint, date: currentDate)
            let daysElapsed = calendar.dateComponents([.day], from: startOfDay, to: currentDate).day ?? 0
            let idealRemaining = Double(totalSP) * (1.0 - Double(daysElapsed) / Double(totalDays))

            dataPoints.append(BurndownDataPoint(
                date: currentDate,
                remainingStoryPoints: remainingSP,
                idealRemaining: max(0, idealRemaining)
            ))

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return dataPoints
    }

    /// Calculates remaining story points as of a given date.
    /// Uses current ticket state (simplified - a production app would track daily snapshots).
    private func remainingStoryPointsAsOf(sprint: Sprint, date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)

        if targetDate >= today {
            // For today or future, use current remaining
            return sprint.tickets
                .filter { $0.status != .done }
                .compactMap { $0.storyPoints }
                .reduce(0, +)
        } else {
            // For past dates, approximate: assume linear completion
            // In production, daily snapshots would be stored
            let totalSP = totalStoryPoints(for: sprint)
            let doneSP = doneStoryPoints(for: sprint)
            let startOfDay = calendar.startOfDay(for: sprint.startDate)
            let endOfDay = calendar.startOfDay(for: sprint.endDate)
            let totalDays = max(1, calendar.dateComponents([.day], from: startOfDay, to: endOfDay).day ?? 1)
            let daysElapsed = calendar.dateComponents([.day], from: startOfDay, to: targetDate).day ?? 0
            let progressRatio = Double(daysElapsed) / Double(totalDays)
            let estimatedDoneAtDate = Int(Double(doneSP) * progressRatio)
            return max(0, totalSP - estimatedDoneAtDate)
        }
    }

    // MARK: - Sprint Completion

    /// Checks if a sprint has reached its end date.
    func isSprintCompleted(_ sprint: Sprint) -> Bool {
        Date() >= sprint.endDate
    }

    /// Checks if a sprint is currently active (between start and end dates).
    func isSprintActive(_ sprint: Sprint) -> Bool {
        let now = Date()
        return now >= sprint.startDate && now < sprint.endDate
    }

    /// Gets the next sprint after the given sprint (by start date).
    func nextSprint(after sprint: Sprint) -> Sprint? {
        let sorted = sprints.sorted { $0.startDate < $1.startDate }
        guard let currentIndex = sorted.firstIndex(where: { $0.id == sprint.id }) else { return nil }
        let nextIndex = sorted.index(after: currentIndex)
        guard nextIndex < sorted.endIndex else { return nil }
        return sorted[nextIndex]
    }

    /// Moves incomplete tickets from the current sprint to the next sprint.
    func moveIncompleteToNextSprint(from sprint: Sprint) {
        guard let next = nextSprint(after: sprint) else {
            showCreateNewSprintForIncomplete = true
            return
        }

        let incomplete = incompleteTickets(for: sprint)
        for ticket in incomplete {
            ticket.sprint = next
            ticket.updatedAt = Date()
            if !next.tickets.contains(where: { $0.id == ticket.id }) {
                next.tickets.append(ticket)
            }
            sprint.tickets.removeAll { $0.id == ticket.id }
        }

        refreshSprints()
    }

    /// Creates a new sprint and moves incomplete tickets to it.
    func createNewSprintAndMoveIncomplete(from sprint: Sprint) async {
        // Set up form with defaults based on the completed sprint
        let calendar = Calendar.current
        let newStart = calendar.date(byAdding: .day, value: 1, to: sprint.endDate) ?? Date()
        let sprintDuration = calendar.dateComponents([.day], from: sprint.startDate, to: sprint.endDate).day ?? 14
        let newEnd = calendar.date(byAdding: .day, value: sprintDuration, to: newStart) ?? Date()

        newSprintName = "\(sprint.name) (continued)"
        newSprintStartDate = newStart
        newSprintEndDate = newEnd

        await createSprint()

        // Move incomplete tickets to the newly created sprint
        if let newSprint = sprints.last {
            let incomplete = incompleteTickets(for: sprint)
            for ticket in incomplete {
                ticket.sprint = newSprint
                ticket.updatedAt = Date()
                if !newSprint.tickets.contains(where: { $0.id == ticket.id }) {
                    newSprint.tickets.append(ticket)
                }
                sprint.tickets.removeAll { $0.id == ticket.id }
            }
        }

        showCreateNewSprintForIncomplete = false
        refreshSprints()
    }

    // MARK: - Helpers

    /// Formats a date for display.
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Formats progress as a string (e.g., "75%").
    func formattedProgress(for sprint: Sprint) -> String {
        let progress = progressPercentage(for: sprint)
        return "\(Int(progress))%"
    }

    /// Returns a status label for the sprint.
    func statusLabel(for sprint: Sprint) -> String {
        if isSprintCompleted(sprint) {
            return "Completed"
        } else if isSprintActive(sprint) {
            return "Active"
        } else {
            return "Upcoming"
        }
    }

    /// Returns a color for the sprint status.
    func statusColor(for sprint: Sprint) -> Color {
        if isSprintCompleted(sprint) {
            return DesignSystem.Colors.success
        } else if isSprintActive(sprint) {
            return DesignSystem.Colors.accent
        } else {
            return DesignSystem.Colors.textTertiary
        }
    }
}
