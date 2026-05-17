import Foundation
import SwiftData

@Model
class Sprint {
    @Attribute(.unique) var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var gitlabMilestoneId: Int?
    var workspace: Workspace?

    @Relationship(deleteRule: .nullify) var tickets: [Ticket]

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date,
        gitlabMilestoneId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.gitlabMilestoneId = gitlabMilestoneId
        self.tickets = []
    }
}
