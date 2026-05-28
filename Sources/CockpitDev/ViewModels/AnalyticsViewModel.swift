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

/// Per-developer delivery performance based on planning metadata and realized closures.
struct DeveloperPerformanceDataPoint: Identifiable {
    let id = UUID()
    let member: Member
    let plannedTickets: Int
    let completedTickets: Int
    let committedStoryPoints: Int
    let completedStoryPoints: Int
    let openStoryPoints: Int
    let averageRealizationDays: Double?
    let onTimeRate: Double?
    let averageScheduleVarianceDays: Double?

    var completionRate: Double {
        guard plannedTickets > 0 else { return 0 }
        return Double(completedTickets) / Double(plannedTickets)
    }
}

/// Ticket closures grouped by day for realized delivery trend.
struct ClosureTrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let ticketsClosed: Int
    let storyPointsClosed: Int
}

/// Deadline risk item for tickets that missed due date or have a lead-approved exception.
struct DeadlineRiskDataPoint: Identifiable {
    let id = UUID()
    let ticket: Ticket
    let title: String
    let assigneeName: String
    let dueDate: Date
    let closedAt: Date?
    let daysLate: Int
    let storyPoints: Int
    let isOpen: Bool
    let appealStatus: DeadlineAppealStatus
    let appealReason: String?
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
    var developerPerformanceData: [DeveloperPerformanceDataPoint] = []
    var closureTrendData: [ClosureTrendDataPoint] = []
    var deadlineRiskData: [DeadlineRiskDataPoint] = []
    var workspaceCycleTime: Double = 0.0
    var plannedStoryPoints: Int = 0
    var completedStoryPoints: Int = 0
    var openStoryPoints: Int = 0
    var lateTicketCount: Int = 0
    var approvedDeadlineExceptionCount: Int = 0
    var averageScheduleVarianceDays: Double?
    var onTimeCompletionRate: Double?

    var filter = AnalyticsFilter()
    var availableSprints: [Sprint] = []
    var availableMembers: [Member] = []
    var availableLabels: [String] = []

    var hasData: Bool {
        !velocityData.isEmpty || !workloadData.isEmpty || !throughputData.isEmpty || !developerPerformanceData.isEmpty
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
        computeDeveloperPerformance()
        computeClosureTrend()
        computeDeadlineRisks()
        computeSummaryMetrics()
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

    // MARK: - Developer Performance

    private func computeDeveloperPerformance() {
        guard let workspace else {
            developerPerformanceData = []
            return
        }

        let members = filteredMembers(from: workspace)
        let tickets = filteredTickets(from: workspace)

        developerPerformanceData = members.map { member in
            let memberTickets = tickets.filter { $0.assignee?.id == member.id }
            let completedTickets = memberTickets.filter { $0.status == .done }
            let accountableCompletedTickets = completedTickets.filter { $0.deadlineAppealStatus != .approved }
            let committedSP = memberTickets.compactMap(\.storyPoints).reduce(0, +)
            let completedSP = completedTickets.compactMap(\.storyPoints).reduce(0, +)
            let openSP = memberTickets
                .filter { $0.status != .done }
                .compactMap(\.storyPoints)
                .reduce(0, +)

            let realizationDays = completedTickets.compactMap(realizationDays(for:))
            let variances = accountableCompletedTickets.compactMap(scheduleVarianceDays(for:))
            let ticketsWithDueDate = accountableCompletedTickets.filter { $0.endDate != nil }
            let onTimeCount = ticketsWithDueDate.filter(isCompletedOnTime).count

            return DeveloperPerformanceDataPoint(
                member: member,
                plannedTickets: memberTickets.count,
                completedTickets: completedTickets.count,
                committedStoryPoints: committedSP,
                completedStoryPoints: completedSP,
                openStoryPoints: openSP,
                averageRealizationDays: average(realizationDays),
                onTimeRate: ticketsWithDueDate.isEmpty ? nil : Double(onTimeCount) / Double(ticketsWithDueDate.count),
                averageScheduleVarianceDays: average(variances)
            )
        }
        .filter { $0.plannedTickets > 0 || $0.committedStoryPoints > 0 }
        .sorted {
            if $0.completedStoryPoints == $1.completedStoryPoints {
                return $0.committedStoryPoints > $1.committedStoryPoints
            }
            return $0.completedStoryPoints > $1.completedStoryPoints
        }
    }

    private func computeClosureTrend() {
        guard let workspace else {
            closureTrendData = []
            return
        }

        let calendar = Calendar.current
        let closedTickets = filteredTickets(from: workspace)
            .filter { $0.status == .done }

        let grouped = Dictionary(grouping: closedTickets) { ticket in
            calendar.startOfDay(for: completionDate(for: ticket))
        }

        closureTrendData = grouped
            .map { date, tickets in
                ClosureTrendDataPoint(
                    date: date,
                    ticketsClosed: tickets.count,
                    storyPointsClosed: tickets.compactMap(\.storyPoints).reduce(0, +)
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func computeDeadlineRisks() {
        guard let workspace else {
            deadlineRiskData = []
            lateTicketCount = 0
            approvedDeadlineExceptionCount = 0
            return
        }

        deadlineRiskData = filteredTickets(from: workspace)
            .compactMap { ticket in
                guard let dueDate = ticket.endDate else { return nil }
                let lateDays = daysLate(for: ticket, dueDate: dueDate)
                let hasApprovedException = ticket.deadlineAppealStatus == .approved
                guard lateDays > 0 || hasApprovedException else { return nil }

                return DeadlineRiskDataPoint(
                    ticket: ticket,
                    title: ticket.title,
                    assigneeName: ticket.assignee?.displayName ?? "Unassigned",
                    dueDate: dueDate,
                    closedAt: ticket.status == .done ? completionDate(for: ticket) : nil,
                    daysLate: lateDays,
                    storyPoints: ticket.storyPoints ?? 0,
                    isOpen: ticket.status != .done,
                    appealStatus: ticket.deadlineAppealStatus,
                    appealReason: ticket.deadlineAppealReason
                )
            }
            .sorted {
                if $0.appealStatus == $1.appealStatus {
                    if $0.daysLate == $1.daysLate {
                        return $0.dueDate < $1.dueDate
                    }
                    return $0.daysLate > $1.daysLate
                }
                return $0.appealStatus != .approved && $1.appealStatus == .approved
            }

        lateTicketCount = deadlineRiskData.filter { $0.appealStatus != .approved }.count
        approvedDeadlineExceptionCount = deadlineRiskData.filter { $0.appealStatus == .approved }.count
    }

    private func computeSummaryMetrics() {
        guard let workspace else {
            plannedStoryPoints = 0
            completedStoryPoints = 0
            openStoryPoints = 0
            averageScheduleVarianceDays = nil
            onTimeCompletionRate = nil
            return
        }

        let tickets = filteredTickets(from: workspace)
        let completedTickets = tickets.filter { $0.status == .done }
        let accountableCompletedTickets = completedTickets.filter { $0.deadlineAppealStatus != .approved }
        plannedStoryPoints = tickets.compactMap(\.storyPoints).reduce(0, +)
        completedStoryPoints = completedTickets.compactMap(\.storyPoints).reduce(0, +)
        openStoryPoints = tickets.filter { $0.status != .done }.compactMap(\.storyPoints).reduce(0, +)
        averageScheduleVarianceDays = average(accountableCompletedTickets.compactMap(scheduleVarianceDays(for:)))

        let completedWithDueDate = accountableCompletedTickets.filter { $0.endDate != nil }
        if completedWithDueDate.isEmpty {
            onTimeCompletionRate = nil
        } else {
            let onTimeCount = completedWithDueDate.filter(isCompletedOnTime).count
            onTimeCompletionRate = Double(onTimeCount) / Double(completedWithDueDate.count)
        }
    }

    func approveDeadlineException(for ticket: Ticket, reason: String = "Lead-approved reprioritization") {
        ticket.deadlineAppealStatus = .approved
        ticket.deadlineAppealReason = reason
        ticket.deadlineAppealDecidedAt = Date()
        ticket.deadlineAppealDecidedBy = "Lead"
        try? modelContext?.save()
        computeAllMetrics()
    }

    func rejectDeadlineException(for ticket: Ticket) {
        ticket.deadlineAppealStatus = .rejected
        ticket.deadlineAppealDecidedAt = Date()
        ticket.deadlineAppealDecidedBy = "Lead"
        try? modelContext?.save()
        computeAllMetrics()
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

    private func filteredMembers(from workspace: Workspace) -> [Member] {
        if let selectedMember = filter.selectedMember {
            return [selectedMember]
        }
        return workspace.members.sorted { $0.displayName < $1.displayName }
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

        let endTime = completionDate(for: ticket)
        let interval = endTime.timeIntervalSince(startTime)

        // Only count positive intervals (ticket was updated after creation/start)
        guard interval > 0 else { return nil }

        return interval / (60 * 60 * 24) // Convert to days
    }

    private func realizationDays(for ticket: Ticket) -> Double? {
        guard ticket.status == .done else { return nil }
        let start = ticket.startDate ?? ticket.createdAt
        let interval = completionDate(for: ticket).timeIntervalSince(start)
        guard interval >= 0 else { return nil }
        return max(interval / 86_400, 0.1)
    }

    private func scheduleVarianceDays(for ticket: Ticket) -> Double? {
        guard ticket.status == .done, let endDate = ticket.endDate else { return nil }
        let calendar = Calendar.current
        let closedDay = calendar.startOfDay(for: completionDate(for: ticket))
        let dueDay = calendar.startOfDay(for: endDate)
        return Double(calendar.dateComponents([.day], from: dueDay, to: closedDay).day ?? 0)
    }

    private func isCompletedOnTime(_ ticket: Ticket) -> Bool {
        guard ticket.status == .done, let endDate = ticket.endDate else { return false }
        return completionDate(for: ticket) <= dueDateCutoff(for: endDate)
    }

    private func daysLate(for ticket: Ticket, dueDate: Date) -> Int {
        let reference = ticket.status == .done ? completionDate(for: ticket) : Date()
        let cutoff = dueDateCutoff(for: dueDate)
        guard reference > cutoff else { return 0 }
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: cutoff)
        let to = calendar.startOfDay(for: reference)
        return max(1, calendar.dateComponents([.day], from: from, to: to).day ?? 1)
    }

    private func dueDateCutoff(for date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDueDate = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDueDate) ?? date
    }

    private func completionDate(for ticket: Ticket) -> Date {
        ticket.realizedAt ?? ticket.updatedAt
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
