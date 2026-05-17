import Foundation
import SwiftData

@Model
class DocSpecVersion {
    @Attribute(.unique) var id: UUID
    var contentHash: String
    var content: String
    var authorName: String
    var commitTimestamp: Date
    var detectedAt: Date
    var spec: OpenSpecEntry?

    init(
        id: UUID = UUID(),
        contentHash: String,
        content: String,
        authorName: String,
        commitTimestamp: Date,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.contentHash = contentHash
        self.content = content
        self.authorName = authorName
        self.commitTimestamp = commitTimestamp
        self.detectedAt = detectedAt
    }
}
