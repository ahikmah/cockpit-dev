import Foundation

/// Snapshot of the risk and delivery signals a dev lead needs first.
struct DevLeadConsoleMetrics {
    struct OwnerLoadRow: Identifiable, Equatable {
        let id: UUID
        let memberName: String
        let storyPoints: Int
        let ratio: Double
        let isOverloaded: Bool
    }

    struct AttentionItem: Identifiable, Equatable {
        let id: UUID
        let title: String
        let subtitle: String
        let severity: Severity

        enum Severity: Equatable {
            case blocked
            case review
            case assign
        }
    }

    let openTicketCount: Int
    let blockedTicketCount: Int
    let staleMergeRequestCount: Int
    let overloadedMemberCount: Int
    let sprintProgressPercent: Int
    let attentionItems: [AttentionItem]
    let focusSprintName: String?
    let ownerLoadRows: [OwnerLoadRow]

    init(workspace: Workspace, mergeRequests: [MergeRequestEntry] = [], now: Date = Date()) {
        let openTickets = workspace.tickets.filter { $0.status != .done }
        let blockedTickets = openTickets.filter { ticket in
            ticket.blockedBy.contains { $0.status != .done }
        }
        let focusSprint = Self.focusSprint(in: workspace, now: now)
        let staleCutoff = now.addingTimeInterval(-86_400 * 2)
        let workspaceRepositoryIds = Set(workspace.repositories.map(\.id))
        let staleMergeRequests = mergeRequests
            .filter { mergeRequest in
                guard let repository = mergeRequest.repository else { return false }
                return workspaceRepositoryIds.contains(repository.id)
            }
            .filter { $0.state == .opened && $0.updatedAt < staleCutoff }

        let overloadedMembers = workspace.members.filter { member in
            guard let focusSprint else { return false }
            let assignedStoryPoints = workspace.tickets
                .filter { $0.sprint?.id == focusSprint.id && $0.assignee?.id == member.id && $0.status != .done }
                .compactMap(\.storyPoints)
                .reduce(0, +)
            return assignedStoryPoints > workspace.maxStoryPointsThreshold
        }

        let sprintTickets: [Ticket]
        if let focusSprint {
            sprintTickets = workspace.tickets.filter { $0.sprint?.id == focusSprint.id }
        } else {
            sprintTickets = []
        }
        let totalStoryPoints = sprintTickets.compactMap(\.storyPoints).reduce(0, +)
        let completedStoryPoints = sprintTickets
            .filter { $0.status == .done }
            .compactMap(\.storyPoints)
            .reduce(0, +)

        self.openTicketCount = openTickets.count
        self.blockedTicketCount = blockedTickets.count
        self.staleMergeRequestCount = staleMergeRequests.count
        self.overloadedMemberCount = overloadedMembers.count
        self.sprintProgressPercent = totalStoryPoints > 0
            ? Int((Double(completedStoryPoints) / Double(totalStoryPoints) * 100).rounded())
            : 0
        self.focusSprintName = focusSprint?.name
        self.ownerLoadRows = workspace.members.compactMap { member in
            let points = sprintTickets
                .filter { $0.assignee?.id == member.id }
                .compactMap(\.storyPoints)
                .reduce(0, +)

            guard points > 0 else { return nil }
            return OwnerLoadRow(
                id: member.id,
                memberName: member.displayName,
                storyPoints: points,
                ratio: min(1, Double(points) / Double(max(workspace.maxStoryPointsThreshold, 1))),
                isOverloaded: points > workspace.maxStoryPointsThreshold
            )
        }
        .sorted { $0.storyPoints > $1.storyPoints }

        let blockedItems = blockedTickets
            .sorted { ($0.storyPoints ?? 0) > ($1.storyPoints ?? 0) }
            .prefix(3)
            .map { ticket in
                AttentionItem(
                    id: ticket.id,
                    title: ticket.title,
                    subtitle: "Blocked by \(ticket.blockedBy.filter { $0.status != .done }.count) active dependency",
                    severity: .blocked
                )
            }

        let staleItems = staleMergeRequests
            .sorted { $0.updatedAt < $1.updatedAt }
            .prefix(2)
            .map { mergeRequest in
                AttentionItem(
                    id: mergeRequest.id,
                    title: mergeRequest.title,
                    subtitle: "MR idle since \(Self.relativeDayLabel(from: mergeRequest.updatedAt, to: now))",
                    severity: .review
                )
            }

        self.attentionItems = Array(blockedItems + staleItems).prefix(5).map { $0 }
    }

    private static func relativeDayLabel(from date: Date, to now: Date) -> String {
        let days = max(1, Calendar.current.dateComponents([.day], from: date, to: now).day ?? 1)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    private static func focusSprint(in workspace: Workspace, now: Date) -> Sprint? {
        let sprintsWithTickets = workspace.sprints.filter { sprint in
            workspace.tickets.contains { $0.sprint?.id == sprint.id }
        }

        if let activeSprint = sprintsWithTickets
            .filter({ $0.startDate <= now && $0.endDate >= now })
            .sorted(by: { $0.endDate < $1.endDate })
            .first {
            return activeSprint
        }

        if let latestSprintWithTickets = sprintsWithTickets
            .sorted(by: { $0.endDate > $1.endDate })
            .first {
            return latestSprintWithTickets
        }

        return workspace.sprints
            .filter { $0.startDate <= now && $0.endDate >= now }
            .sorted(by: { $0.endDate < $1.endDate })
            .first
    }
}
