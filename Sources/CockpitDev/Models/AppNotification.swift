import Foundation
import SwiftData

@Model
class AppNotification {
    @Attribute(.unique) var id: UUID
    var eventType: NotificationEventType
    var title: String
    var message: String
    var relatedItemId: UUID?
    var relatedItemType: String?
    var isRead: Bool
    var createdAt: Date
    var workspace: Workspace?

    init(
        id: UUID = UUID(),
        eventType: NotificationEventType,
        title: String,
        message: String,
        relatedItemId: UUID? = nil,
        relatedItemType: String? = nil,
        isRead: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventType = eventType
        self.title = title
        self.message = message
        self.relatedItemId = relatedItemId
        self.relatedItemType = relatedItemType
        self.isRead = isRead
        self.createdAt = createdAt
    }
}
