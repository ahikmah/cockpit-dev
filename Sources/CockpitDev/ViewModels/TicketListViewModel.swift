import Foundation
import SwiftData

enum TicketListSort: String, CaseIterable, Identifiable {
    case planning = "Planning"
    case updated = "Updated"
    case issue = "Issue"
    case priority = "Priority"

    var id: String { rawValue }
}

@Observable
class TicketListViewModel {
    var workspace: Workspace?
    var searchText: String = ""
    var selectedSprint: Sprint?
    var selectedStatus: TicketStatus?
    var selectedAssignee: Member?
    var selectedPriority: TicketPriority?
    var sort: TicketListSort = .planning

    init(workspace: Workspace? = nil) {
        self.workspace = workspace
    }

    var filteredTickets: [Ticket] {
        guard let workspace else { return [] }

        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return workspace.tickets
            .filter { ticket in
                if let selectedSprint, ticket.sprint?.id != selectedSprint.id { return false }
                if let selectedStatus, ticket.status != selectedStatus { return false }
                if let selectedAssignee, ticket.assignee?.id != selectedAssignee.id { return false }
                if let selectedPriority, ticket.priority != selectedPriority { return false }
                guard !normalizedSearch.isEmpty else { return true }
                return ticket.title.lowercased().contains(normalizedSearch)
                    || ticket.labels.contains { $0.lowercased().contains(normalizedSearch) }
                    || ticket.descriptionText?.lowercased().contains(normalizedSearch) == true
                    || ticket.gitlabIssueIid.map { "#\($0)".contains(normalizedSearch) || "\($0)".contains(normalizedSearch) } == true
            }
            .sorted(by: sortOrder)
    }

    var activeFilterCount: Int {
        var count = 0
        if selectedSprint != nil { count += 1 }
        if selectedStatus != nil { count += 1 }
        if selectedAssignee != nil { count += 1 }
        if selectedPriority != nil { count += 1 }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        return count
    }

    func clearFilters() {
        searchText = ""
        selectedSprint = nil
        selectedStatus = nil
        selectedAssignee = nil
        selectedPriority = nil
    }

    private func sortOrder(_ lhs: Ticket, _ rhs: Ticket) -> Bool {
        switch sort {
        case .planning:
            return planningOrder(lhs, rhs)
        case .updated:
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return planningOrder(lhs, rhs)
        case .issue:
            switch (lhs.gitlabIssueIid, rhs.gitlabIssueIid) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return planningOrder(lhs, rhs)
            }
        case .priority:
            let lhsRank = lhs.priority?.sortRank ?? Int.max
            let rhsRank = rhs.priority?.sortRank ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return planningOrder(lhs, rhs)
        }
    }

    private func planningOrder(_ lhs: Ticket, _ rhs: Ticket) -> Bool {
        switch (lhs.sprint?.startDate, rhs.sprint?.startDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }

        switch (lhs.startDate, rhs.startDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }

        switch (lhs.endDate, rhs.endDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }

        switch (lhs.gitlabIssueIid, rhs.gitlabIssueIid) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

private extension TicketPriority {
    var sortRank: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}
