import Foundation
import SwiftData

@Model
class Workspace {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var gitlabInstanceURL: String
    var specDirectoryPath: String
    var localRootPath: String?
    var kanbanColumns: [String]
    var maxStoryPointsThreshold: Int
    var notificationSettings: [String: Bool]

    @Relationship(deleteRule: .cascade) var repositories: [Repository]
    @Relationship(deleteRule: .cascade) var members: [Member]
    @Relationship(deleteRule: .cascade) var tickets: [Ticket]
    @Relationship(deleteRule: .cascade) var sprints: [Sprint]
    @Relationship(deleteRule: .cascade) var documents: [Document]
    @Relationship(deleteRule: .cascade) var specs: [OpenSpecEntry]
    @Relationship(deleteRule: .cascade) var notifications: [AppNotification]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        gitlabInstanceURL: String = AppConstants.defaultGitLabInstanceURL,
        specDirectoryPath: String = ".kiro/specs",
        localRootPath: String? = nil,
        kanbanColumns: [String] = AppConstants.defaultKanbanColumns,
        maxStoryPointsThreshold: Int = AppConstants.maxStoryPointsThreshold,
        notificationSettings: [String: Bool] = [:]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.gitlabInstanceURL = gitlabInstanceURL
        self.specDirectoryPath = specDirectoryPath
        self.localRootPath = localRootPath
        self.kanbanColumns = kanbanColumns
        self.maxStoryPointsThreshold = maxStoryPointsThreshold
        self.notificationSettings = notificationSettings
        self.repositories = []
        self.members = []
        self.tickets = []
        self.sprints = []
        self.documents = []
        self.specs = []
        self.notifications = []
    }
}
