import Foundation
import SwiftData

@Model
class Document {
    @Attribute(.unique) var id: UUID
    var name: String
    var filePath: String
    var fileSize: Int64
    var folderPath: String?
    var addedAt: Date
    var addedByMember: Member?
    var workspace: Workspace?

    init(
        id: UUID = UUID(),
        name: String,
        filePath: String,
        fileSize: Int64,
        folderPath: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.fileSize = fileSize
        self.folderPath = folderPath
        self.addedAt = addedAt
    }
}
