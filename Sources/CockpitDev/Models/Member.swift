import Foundation
import SwiftData

@Model
class Member {
    @Attribute(.unique) var id: UUID
    var gitlabUserId: Int
    var username: String
    var displayName: String
    var avatarURL: String?
    var email: String?
    var role: MemberRole
    var skillProfile: SkillProfile?
    var workspace: Workspace?

    init(
        id: UUID = UUID(),
        gitlabUserId: Int,
        username: String,
        displayName: String,
        avatarURL: String? = nil,
        email: String? = nil,
        role: MemberRole = .member,
        skillProfile: SkillProfile? = nil
    ) {
        self.id = id
        self.gitlabUserId = gitlabUserId
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.email = email
        self.role = role
        self.skillProfile = skillProfile
    }
}
