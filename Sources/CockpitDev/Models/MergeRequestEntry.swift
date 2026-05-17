import Foundation
import SwiftData

@Model
class MergeRequestEntry {
    @Attribute(.unique) var id: UUID
    var gitlabMrId: Int
    var gitlabMrIid: Int
    var title: String
    var authorUsername: String
    var sourceBranch: String
    var targetBranch: String
    var pipelineStatus: PipelineStatus?
    var state: MRState
    var createdAt: Date
    var updatedAt: Date
    var repository: Repository?

    init(
        id: UUID = UUID(),
        gitlabMrId: Int,
        gitlabMrIid: Int,
        title: String,
        authorUsername: String,
        sourceBranch: String,
        targetBranch: String,
        pipelineStatus: PipelineStatus? = nil,
        state: MRState = .opened,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.gitlabMrId = gitlabMrId
        self.gitlabMrIid = gitlabMrIid
        self.title = title
        self.authorUsername = authorUsername
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.pipelineStatus = pipelineStatus
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
