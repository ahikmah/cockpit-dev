import Foundation
import SwiftData

// MARK: - Notification View Model

/// View model managing the notification center UI state and interactions.
@Observable
class NotificationViewModel {

    // MARK: - Properties

    private(set) var notifications: [AppNotification] = []
    private(set) var unreadCount: Int = 0
    private(set) var isPermissionDenied: Bool = false

    private var notificationService: NotificationService?
    private var workspace: Workspace?

    // MARK: - Configuration

    /// Configure the view model with a notification service and workspace.
    func configure(service: NotificationService, workspace: Workspace) {
        self.notificationService = service
        self.workspace = workspace
        refresh()
    }

    // MARK: - Actions

    /// Refreshes the notification list from the workspace.
    func refresh() {
        guard let service = notificationService, let workspace = workspace else { return }
        notifications = service.getNotifications(workspace: workspace)
        unreadCount = service.unreadCount(workspace: workspace)
        isPermissionDenied = service.isPermissionDenied
    }

    /// Marks a single notification as read.
    func markAsRead(_ notification: AppNotification) {
        notificationService?.markAsRead(notification)
        refresh()
    }

    /// Marks all notifications as read.
    func markAllAsRead() {
        guard let workspace = workspace else { return }
        notificationService?.markAllAsRead(workspace: workspace)
        refresh()
    }

    /// Returns the deep link target for a notification.
    func deepLinkTarget(for notification: AppNotification) -> DeepLinkTarget? {
        return notificationService?.deepLinkTarget(for: notification)
    }

    // MARK: - Notification Type Configuration

    /// Checks if a notification type is enabled for the current workspace.
    func isTypeEnabled(_ type: NotificationEventType) -> Bool {
        guard let service = notificationService, let workspace = workspace else { return true }
        return service.isEnabled(type, workspace: workspace)
    }

    /// Toggles a notification type for the current workspace.
    func setTypeEnabled(_ type: NotificationEventType, enabled: Bool) {
        guard let service = notificationService, let workspace = workspace else { return }
        service.setEnabled(type, enabled: enabled, workspace: workspace)
    }
}
