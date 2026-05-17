import Foundation
import UserNotifications
import SwiftData

// MARK: - Notification Permission Status

/// Represents the current state of notification permissions.
enum NotificationPermissionStatus {
    case notDetermined
    case authorized
    case denied
    case provisional
}

// MARK: - Notification Center Protocol

/// Protocol abstracting UNUserNotificationCenter for testability.
protocol NotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func notificationSettings() async -> UNNotificationSettings
    func add(_ request: UNNotificationRequest) async throws
}

/// Conformance for the real UNUserNotificationCenter.
extension UNUserNotificationCenter: NotificationCenterProtocol {
    func notificationSettings() async -> UNNotificationSettings {
        await self.notificationSettings()
    }
}

// MARK: - Notification Service

/// Manages macOS native notifications and in-app notification center.
/// Handles permission requests, notification delivery, deep linking,
/// and maintains a capped in-app notification history (max 500 per workspace).
@Observable
class NotificationService {

    // MARK: - Properties

    private(set) var permissionStatus: NotificationPermissionStatus = .notDetermined
    private(set) var isPermissionDenied: Bool = false

    private let notificationCenter: NotificationCenterProtocol?
    private var modelContext: ModelContext?

    // MARK: - Initialization

    /// Initialize with a real UNUserNotificationCenter (production use).
    init(notificationCenter: NotificationCenterProtocol? = nil) {
        self.notificationCenter = notificationCenter
    }

    /// Configure the service with a SwiftData model context.
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Permission Management

    /// Requests notification permission from the user via UNUserNotificationCenter.
    /// Returns true if permission was granted, false otherwise.
    @discardableResult
    func requestPermission() async -> Bool {
        guard let notificationCenter = notificationCenter else {
            permissionStatus = .denied
            isPermissionDenied = true
            return false
        }
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await updatePermissionStatus()
            return granted
        } catch {
            await updatePermissionStatus()
            return false
        }
    }

    /// Checks the current notification permission status from the system.
    func checkPermissionStatus() async -> NotificationPermissionStatus {
        guard let notificationCenter = notificationCenter else {
            permissionStatus = .denied
            isPermissionDenied = true
            return .denied
        }
        let settings = await notificationCenter.notificationSettings()
        let status = mapAuthorizationStatus(settings.authorizationStatus)
        permissionStatus = status
        isPermissionDenied = (status == .denied)
        return status
    }

    // MARK: - Notification Delivery

    /// Delivers a notification for a notifiable event.
    /// Creates both a native macOS notification (if permitted) and an in-app notification entry.
    /// Enforces the 500-notification cap per workspace with oldest eviction.
    func deliver(
        event: NotificationEventType,
        title: String,
        message: String,
        workspace: Workspace,
        relatedItemId: UUID? = nil,
        relatedItemType: String? = nil
    ) async {
        // Check if this notification type is enabled for the workspace
        guard isEnabled(event, workspace: workspace) else { return }

        // Create in-app notification entry
        let notification = AppNotification(
            eventType: event,
            title: title,
            message: message,
            relatedItemId: relatedItemId,
            relatedItemType: relatedItemType
        )
        notification.workspace = workspace

        if let modelContext = modelContext {
            modelContext.insert(notification)
            evictOldestIfNeeded(workspace: workspace, modelContext: modelContext)
            try? modelContext.save()
        }

        // Deliver native notification if permission is granted
        if permissionStatus == .authorized || permissionStatus == .provisional {
            await deliverNativeNotification(
                event: event,
                title: title,
                message: message,
                workspaceId: workspace.id,
                relatedItemId: relatedItemId,
                relatedItemType: relatedItemType
            )
        }
    }

    // MARK: - Notification Queries

    /// Returns all notifications for a workspace, sorted by creation date (newest first).
    func getNotifications(workspace: Workspace) -> [AppNotification] {
        return workspace.notifications.sorted { $0.createdAt > $1.createdAt }
    }

    /// Returns the count of unread notifications for a workspace.
    func unreadCount(workspace: Workspace) -> Int {
        return workspace.notifications.filter { !$0.isRead }.count
    }

    /// Marks a notification as read.
    func markAsRead(_ notification: AppNotification) {
        notification.isRead = true
        try? modelContext?.save()
    }

    /// Marks all notifications in a workspace as read.
    func markAllAsRead(workspace: Workspace) {
        for notification in workspace.notifications where !notification.isRead {
            notification.isRead = true
        }
        try? modelContext?.save()
    }

    // MARK: - Per-Workspace Configuration

    /// Checks if a notification type is enabled for a workspace.
    /// All types are enabled by default.
    func isEnabled(_ type: NotificationEventType, workspace: Workspace) -> Bool {
        return workspace.notificationSettings[type.rawValue] ?? true
    }

    /// Sets whether a notification type is enabled for a workspace.
    func setEnabled(_ type: NotificationEventType, enabled: Bool, workspace: Workspace) {
        workspace.notificationSettings[type.rawValue] = enabled
        workspace.updatedAt = Date()
        try? modelContext?.save()
    }

    // MARK: - Deep Linking

    /// Determines the navigation target for a notification click.
    /// Returns the appropriate workspace tab and item to navigate to.
    func deepLinkTarget(for notification: AppNotification) -> DeepLinkTarget? {
        switch notification.eventType {
        case .newMergeRequest, .mrApproval:
            return DeepLinkTarget(
                tab: .mergeRequests,
                itemId: notification.relatedItemId,
                itemType: notification.relatedItemType
            )
        case .dependencyConflict:
            return DeepLinkTarget(
                tab: .board,
                itemId: notification.relatedItemId,
                itemType: "conflict"
            )
        case .sprintCompletion:
            return DeepLinkTarget(
                tab: .sprints,
                itemId: notification.relatedItemId,
                itemType: notification.relatedItemType
            )
        }
    }

    // MARK: - Private Helpers

    private func updatePermissionStatus() async {
        _ = await checkPermissionStatus()
    }

    private func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> NotificationPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .provisional:
            return .provisional
        @unknown default:
            return .notDetermined
        }
    }

    /// Delivers a native macOS notification via UNUserNotificationCenter.
    private func deliverNativeNotification(
        event: NotificationEventType,
        title: String,
        message: String,
        workspaceId: UUID,
        relatedItemId: UUID?,
        relatedItemType: String?
    ) async {
        guard let notificationCenter = notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.categoryIdentifier = event.rawValue

        // Attach deep link info for notification click handling
        var userInfo: [String: String] = [
            "workspaceId": workspaceId.uuidString,
            "eventType": event.rawValue
        ]
        if let relatedItemId = relatedItemId {
            userInfo["relatedItemId"] = relatedItemId.uuidString
        }
        if let relatedItemType = relatedItemType {
            userInfo["relatedItemType"] = relatedItemType
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            // Silently fail for native notification delivery errors
            // The in-app notification is already stored
        }
    }

    /// Evicts the oldest notifications when the workspace exceeds the max cap.
    private func evictOldestIfNeeded(workspace: Workspace, modelContext: ModelContext) {
        let maxNotifications = AppConstants.maxNotifications
        let currentCount = workspace.notifications.count

        guard currentCount > maxNotifications else { return }

        // Sort by creation date ascending (oldest first)
        let sorted = workspace.notifications.sorted { $0.createdAt < $1.createdAt }
        let countToRemove = currentCount - maxNotifications

        for i in 0..<countToRemove {
            modelContext.delete(sorted[i])
        }
    }
}

// MARK: - Deep Link Target

/// Represents a navigation target for notification deep linking.
struct DeepLinkTarget {
    let tab: WorkspaceTab
    let itemId: UUID?
    let itemType: String?
}
