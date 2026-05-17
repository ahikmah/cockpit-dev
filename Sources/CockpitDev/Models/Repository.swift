import Foundation
import SwiftData

@Model
class Repository {
    @Attribute(.unique) var id: UUID
    var gitlabProjectId: Int
    var name: String
    var url: String
    var localPath: String?
    var defaultBranch: String
    var workspace: Workspace?

    init(
        id: UUID = UUID(),
        gitlabProjectId: Int,
        name: String,
        url: String,
        localPath: String? = nil,
        defaultBranch: String = "main"
    ) {
        self.id = id
        self.gitlabProjectId = gitlabProjectId
        self.name = name
        self.url = url
        self.localPath = localPath
        self.defaultBranch = defaultBranch
    }
}
