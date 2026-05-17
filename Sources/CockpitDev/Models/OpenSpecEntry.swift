import Foundation
import SwiftData

@Model
class OpenSpecEntry {
    @Attribute(.unique) var id: UUID
    var specName: String
    var branchName: String
    var phase: SpecPhase
    var isAvailable: Bool
    var hasUnreadVersion: Bool
    var workspace: Workspace?

    @Relationship(deleteRule: .cascade) var versions: [DocSpecVersion]

    init(
        id: UUID = UUID(),
        specName: String,
        branchName: String,
        phase: SpecPhase = .proposal,
        isAvailable: Bool = true,
        hasUnreadVersion: Bool = false
    ) {
        self.id = id
        self.specName = specName
        self.branchName = branchName
        self.phase = phase
        self.isAvailable = isAvailable
        self.hasUnreadVersion = hasUnreadVersion
        self.versions = []
    }
}
