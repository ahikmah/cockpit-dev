import Foundation
import SwiftData
import SwiftUI

// MARK: - Analytics Data Structures

/// Represents velocity data for a single sprint.
struct VelocityDataPoint: Identifiable {
    let id = UUID()
    let sprintName: String
    let completedStoryPoints: Int
}

/// Represents workload data for a single member.
struct WorkloadDataPoint: Identifiable {
    let id = UUID()
    let member: Member
    let assignedStoryPoints: Int
    let isOverloaded: Bool
}

/// Represents cycle time data for a member or workspace.
struct CycleTimeDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let averageDays: Double
}

/// Represents throughput data for a single sprint.
struct ThroughputDataPoint: Identifiable {
    let id = UUID()
    let sprintName: String
    let ticketsCompleted: Int
}

/// Represents individual contribution metrics for a member.
struct ContributionDataPoint: Identifiable {
    let id = UUID()
    let member: Member
    let ticketsCompleted: Int
    let mergeRequestsMerged: Int
    let reviewComments: Int
}

// MARK: - Analytics Filter

/// Filter state for the analytics dashboard.
struct AnalyticsFilter {
    var startSprint: Sprint?
    var endSprint: Sprint?
    var selectedMember: Member?
    var selectedLabel: String?
}

// MARK: - AnalyticsViewModel

/// ViewModel that computes team analytics metrics from SwiftData.
/// Provides velocity, workload distribution, cycle time, throughput,
/// and individual contribution data for the analytics dashboard.
@Observable
class AnalyticsViewModel {

    // MARK: - Published Data

    var velocityData: [VelocityDataPoint] = []
    var workloadData: [WorkloadDataPoint] = []
    var cycleTimeData: [CycleTimeDataPoint] = []
    var throughputData: [ThroughputDataPoint] = []
    var contributionData: [ContributionDataPoint] = []
    var workspaceCycleTime: Double = 0.0

    var filter = AnalyticsFilter()
    var availableSprints: [Sprint] = []
    var availableMembers: [Member] = []
    var availableLabels: [String] = []

    var hasData: Bool {
        !velocityData.isEmpty || !workloadData.isEmpty || !throughputData.isEmpty
    }

    // MARK: - Private

    private var workspace: Workspace?
    private var modelContext: ModelContext?

    // MARK: - Configuration

    /// Configures the view model with a workspace and model context, then computes all metrics.
    func configure(workspace: Workspace, modelContext: ModelContext) {
        self.workspace = workspace
        self.modelContext = modelContext
        loadFilterOptions()
        computeAllMetrics()
    }

    /// Recomputes all metrics when filters change.
    func applyFilters() {
        computeAllMetrics()
    }

    // MARK: - Filter Options

    private func loadFilterOptions() {
        guard let workspace else { return }

        // Sort sprints by start date (most recent first for display, oldest first for charts)
        availableSprints = workspace.sprints.sorted { $0.startDate < $1.startDate }
        availableMembers = workspace.members.sorted { $0.displayName < $1.displayName }

        // Collect unique labels from all tickets
        var labelSet = Set<String>()
        for ticket in workspace.tickets {
            for label in ticket.labels {
                labelSet.insert(label)
            }
        }
        availableLabels = labelSet.sorted()
    }

    // MARK: - Compute All Metrics

    private func computeAllMetrics() {
        computeVelocity()
        computeWorkloadDistribution()
        computeCycleTime()
        computeThroughput()
        computeContributions()
    }

    // MARK: - Velocity (Req 13.2)

    /// Calculates total story points completed per sprint for up to 12 most recent sprints.
    private func computeVelocity() {
        guard let workspace else {
            velocityData = []
            return
        }

        let sprints = filteredSprints(from: workspace)
        let recentSprints = Array(sprints.suffix(12))

        velocityData = recentSprints.map { sprint in
            let completedSP = ticketsForSprint(sprint)
                .filter { $0.status == .done }
                .compactMap { $0.storyPoints }
                .reduce(0, +)

            return VelocityDataPoint(
                sprintName: sprint.name,
                completedStoryPoints: completedSP
            )
        }
    }

    // MARK: - Workload Distribution (Req 13.3, 13.7)

    /// Calculates assigned story points per member in the current sprint.
    private func computeWorkloadDistribution() {
        guard let workspace else {
            workloadData = []
            return
        }

        let currentSprint = findCurrentSprint(in: workspace)
        let threshold = workspace.maxStoryPointsThreshold

        let members: [Member]
        if let selectedMember = filter.selectedMember {
            members = [selectedMember]
        } else {
            members = workspace.members
        }

        workloadData = members.map { member in
            let assignedSP: Int
            if let sprint = currentSprint {
                assignedSP = ticketsForSprint(sprint)
                    .filter { $0.assignee?.id == member.id }
                    .compactMap { $0.storyPoints }
                    .reduce(0, +)
            } else {
                assignedSP = 0
            }

            return WorkloadDataPoint(
                member: member,
                assignedStoryPoints: assignedSP,
                isOverloaded: assignedSP > threshold
            )
        }.sorted { $0.assignedStoryPoints > $1.assignedStoryPoints }
    }

    // MARK: - Cycle Time (Req 13.4)

    /// Calculates average time from "in progress" to "done" per member and workspace.
    private func computeCycleTime() {
        guard let workspace else {
            cycleTimeData = []
            workspaceCycleTime = 0.0
            return
        }

        let doneTickets = filteredTickets(from: workspace)
            .filter { $0.status == .done }

        // Workspace-level cycle time
        let allCycleTimes = doneTickets.compactMap { computeTicketCycleTime($0) }
        workspaceCycleTime = allCycleTimes.isEmpty ? 0.0 : allCycleTimes.reduce(0, +) / Double(allCycleTimes.count)

        // Per-member cycle time
        let members: [Member]
        if let selectedMember = filter.selectedMember {
            members = [selectedMember]
        } else {
            members = workspace.members
        }

        cycleTimeData = members.compactMap { member in
            let memberTickets = doneTickets.filter { $0.assignee?.id == member.id }
            let memberCycleTimes = memberTickets.compactMap { computeTicketCycleTime($0) }

            guard !memberCycleTimes.isEmpty else { return nil }

            let average = memberCycleTimes.reduce(0, +) / Double(memberCycleTimes.count)
            return CycleTimeDataPoint(
                label: member.displayName,
                averageDays: average
            )
        }
    }

    // MARK: - Throughput (Req 13.5)

    /// Calculates tickets completed per sprint for up to 12 most recent sprints.
    private func computeThroughput() {
        guard let workspace else {
            throughputData = []
            return
        }

        let sprints = filteredSprints(from: workspace)
        let recentSprints = Array(sprints.suffix(12))

        throughputData = recentSprints.map { sprint in
            let completedCount = ticketsForSprint(sprint)
                .filter { $0.status == .done }
                .count

            return ThroughputDataPoint(
                sprintName: sprint.name,
                ticketsCompleted: completedCount
            )
        }
    }

    // MARK: - Individual Contributions (Req 13.6)

    /// Calculates tickets completed, MRs merged, and review comments per member.
    private func computeContributions() {
        guard let workspace else {
            contributionData = []
            return
        }

        let members: [Member]
        if let selectedMember = filter.selectedMember {
            members = [selectedMember]
        } else {
            members = workspace.members
        }

        let tickets = filteredTickets(from: workspace)

        // Collect all MRs from workspace repositories via ModelContext query
        let allMRs = fetchMergeRequests(for: workspace)

        contributionData = members.map { member in
            // Tickets completed by this member
            let ticketsCompleted = tickets
                .filter { $0.assignee?.id == member.id && $0.status == .done }
                .count

            // MRs merged by this member (match by username)
            let mrsMerged = allMRs
                .filter { $0.authorUsername == member.username && $0.state == .merged }
                .count

            // Review comments: count MRs where this member is NOT the author
            // but the MR is merged (approximation for review participation)
            let reviewComments = allMRs
                .filter { $0.authorUsername != member.username && $0.state == .merged }
                .count

            return ContributionDataPoint(
                member: member,
                ticketsCompleted: ticketsCompleted,
                mergeRequestsMerged: mrsMerged,
                reviewComments: reviewComments
            )
        }.sorted { $0.ticketsCompleted > $1.ticketsCompleted }
    }

    // MARK: - Helpers

    /// Fetches MergeRequestEntries associated with the workspace's repositories.
    private func fetchMergeRequests(for workspace: Workspace) -> [MergeRequestEntry] {
        guard let modelContext else { return [] }

        let repoIds = workspace.repositories.map { $0.id }
        guard !repoIds.isEmpty else { return [] }

        do {
            let descriptor = FetchDescriptor<MergeRequestEntry>()
            let allMRs = try modelContext.fetch(descriptor)
            return allMRs.filter { mr in
                guard let repo = mr.repository else { return false }
                return repoIds.contains(repo.id)
            }
        } catch {
            return []
        }
    }

    /// Returns sprints filtered by the current filter range, sorted by start date.
    private func filteredSprints(from workspace: Workspace) -> [Sprint] {
        var sprints = workspace.sprints.sorted { $0.startDate < $1.startDate }

        if let startSprint = filter.startSprint {
            sprints = sprints.filter { $0.startDate >= startSprint.startDate }
        }
        if let endSprint = filter.endSprint {
            sprints = sprints.filter { $0.startDate <= endSprint.startDate }
        }

        return sprints
    }

    /// Returns tickets filtered by current filter criteria.
    private func filteredTickets(from workspace: Workspace) -> [Ticket] {
        var tickets = workspace.tickets

        if let selectedMember = filter.selectedMember {
            tickets = tickets.filter { $0.assignee?.id == selectedMember.id }
        }

        if let selectedLabel = filter.selectedLabel, !selectedLabel.isEmpty {
            tickets = tickets.filter { $0.labels.contains(selectedLabel) }
        }

        // Filter by sprint range
        if let startSprint = filter.startSprint {
            tickets = tickets.filter { ticket in
                guard let sprint = ticket.sprint else { return false }
                return sprint.startDate >= startSprint.startDate
            }
        }
        if let endSprint = filter.endSprint {
            tickets = tickets.filter { ticket in
                guard let sprint = ticket.sprint else { return false }
                return sprint.startDate <= endSprint.startDate
            }
        }

        return tickets
    }

    /// Returns tickets for a specific sprint, applying label filter if set.
    private func ticketsForSprint(_ sprint: Sprint) -> [Ticket] {
        var tickets = sprint.tickets

        if let selectedMember = filter.selectedMember {
            tickets = tickets.filter { $0.assignee?.id == selectedMember.id }
        }

        if let selectedLabel = filter.selectedLabel, !selectedLabel.isEmpty {
            tickets = tickets.filter { $0.labels.contains(selectedLabel) }
        }

        return tickets
    }

    /// Finds the current sprint (today falls between start and end date).
    private func findCurrentSprint(in workspace: Workspace) -> Sprint? {
        let today = Date()
        return workspace.sprints.first { sprint in
            sprint.startDate <= today && sprint.endDate >= today
        }
    }

    /// Computes cycle time in days for a single ticket.
    /// Uses updatedAt as proxy for "done" transition time and createdAt as proxy for start.
    /// A more accurate implementation would track status change timestamps.
    private func computeTicketCycleTime(_ ticket: Ticket) -> Double? {
        // Use the ticket's start date (when moved to in-progress) and updatedAt (when moved to done)
        // If startDate is available, use it as the "in progress" marker
        // Otherwise fall back to createdAt
        let startTime: Date
        if let ticketStart = ticket.startDate {
            startTime = ticketStart
        } else {
            startTime = ticket.createdAt
        }

        let endTime = ticket.updatedAt
        let interval = endTime.timeIntervalSince(startTime)

        // Only count positive intervals (ticket was updated after creation/start)
        guard interval > 0 else { return nil }

        return interval / (60 * 60 * 24) // Convert to days
    }
}
