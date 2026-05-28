import Foundation
import SwiftData

@Model
class Ticket {
    @Attribute(.unique) var id: UUID
    var gitlabIssueId: Int?
    var gitlabIssueIid: Int?
    var title: String
    var descriptionText: String?
    var status: TicketStatus
    var priority: TicketPriority?
    var storyPoints: Int?
    var startDate: Date?
    var endDate: Date?
    var branchName: String?
    var labels: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var localVersion: Int
    var deadlineAppealStatusRaw: String = DeadlineAppealStatus.none.rawValue
    var deadlineAppealReason: String?
    var deadlineAppealDecidedAt: Date?
    var deadlineAppealDecidedBy: String?
    var realizedAt: Date?
    var realizationSourceRaw: String?
    var realizationReference: String?

    var assignee: Member?
    var sprint: Sprint?
    var workspace: Workspace?

    @Relationship var blockedBy: [Ticket]
    @Relationship var blocks: [Ticket]

    init(
        id: UUID = UUID(),
        gitlabIssueId: Int? = nil,
        gitlabIssueIid: Int? = nil,
        title: String,
        descriptionText: String? = nil,
        status: TicketStatus = .backlog,
        priority: TicketPriority? = nil,
        storyPoints: Int? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        branchName: String? = nil,
        labels: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        localVersion: Int = 0,
        deadlineAppealStatus: DeadlineAppealStatus = .none,
        deadlineAppealReason: String? = nil,
        deadlineAppealDecidedAt: Date? = nil,
        deadlineAppealDecidedBy: String? = nil,
        realizedAt: Date? = nil,
        realizationSource: TicketRealizationSource? = nil,
        realizationReference: String? = nil
    ) {
        self.id = id
        self.gitlabIssueId = gitlabIssueId
        self.gitlabIssueIid = gitlabIssueIid
        self.title = title
        self.descriptionText = descriptionText
        self.status = status
        self.priority = priority
        self.storyPoints = storyPoints
        self.startDate = startDate
        self.endDate = endDate
        self.branchName = branchName
        self.labels = labels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
        self.localVersion = localVersion
        self.deadlineAppealStatusRaw = deadlineAppealStatus.rawValue
        self.deadlineAppealReason = deadlineAppealReason
        self.deadlineAppealDecidedAt = deadlineAppealDecidedAt
        self.deadlineAppealDecidedBy = deadlineAppealDecidedBy
        self.realizedAt = realizedAt
        self.realizationSourceRaw = realizationSource?.rawValue
        self.realizationReference = realizationReference
        self.blockedBy = []
        self.blocks = []
    }

    var deadlineAppealStatus: DeadlineAppealStatus {
        get {
            DeadlineAppealStatus(rawValue: deadlineAppealStatusRaw) ?? .none
        }
        set {
            deadlineAppealStatusRaw = newValue.rawValue
        }
    }

    var realizationSource: TicketRealizationSource? {
        get {
            guard let realizationSourceRaw else { return nil }
            return TicketRealizationSource(rawValue: realizationSourceRaw)
        }
        set {
            realizationSourceRaw = newValue?.rawValue
        }
    }
}
