import SwiftUI
import SwiftData

// MARK: - Notification Center Sheet

/// Displays the in-app notification center as a sheet.
/// Shows a chronological list of all notification events for the current workspace.
struct NotificationCenterSheet: View {

    let workspace: Workspace
    @State private var viewModel = NotificationViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Callback when a notification is tapped for deep linking.
    var onNavigate: ((DeepLinkTarget) -> Void)?

    /// The notification service injected from the environment.
    var notificationService: NotificationService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Permission denied banner
            if viewModel.isPermissionDenied {
                permissionDeniedBanner
            }

            // Notification list
            if viewModel.notifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .frame(minWidth: 420, maxWidth: 420, minHeight: 400, maxHeight: 600)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large))
        .onAppear {
            viewModel.configure(service: notificationService, workspace: workspace)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text("Notifications")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                if viewModel.unreadCount > 0 {
                    Text("\(viewModel.unreadCount) unread")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            Spacer()

            if viewModel.unreadCount > 0 {
                Button("Mark all read") {
                    viewModel.markAllAsRead()
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.accent)
                .buttonStyle(.plain)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing20)
        .padding(.vertical, DesignSystem.Spacing.spacing16)
    }

    // MARK: - Permission Denied Banner

    private var permissionDeniedBanner: some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.Colors.warning)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text("System notifications unavailable")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Enable in System Settings → Notifications → Cockpit Dev")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button("Open Settings") {
                openSystemNotificationSettings()
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.warning.opacity(0.08))
    }

    // MARK: - Notification List

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.notifications, id: \.id) { notification in
                    NotificationRowView(notification: notification) {
                        viewModel.markAsRead(notification)
                        if let target = viewModel.deepLinkTarget(for: notification) {
                            onNavigate?(target)
                            dismiss()
                        }
                    }

                    if notification.id != viewModel.notifications.last?.id {
                        Divider()
                            .padding(.leading, DesignSystem.Spacing.spacing48)
                    }
                }
            }
            .padding(.vertical, DesignSystem.Spacing.spacing4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No notifications yet")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("You'll see notifications for merge requests, conflicts, and sprint events here.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.spacing32)
    }

    // MARK: - Helpers

    private func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Notification Row View

/// A single notification entry in the notification center.
struct NotificationRowView: View {

    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing12) {
                // Event type icon
                eventIcon
                    .frame(width: 28, height: 28)

                // Content
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                    Text(notification.title)
                        .font(notification.isRead
                            ? DesignSystem.Typography.bodyRegular
                            : DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    Text(notification.message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)

                    Text(notification.createdAt.relativeDescription)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }

                Spacer()

                // Unread indicator
                if !notification.isRead {
                    Circle()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing16)
            .padding(.vertical, DesignSystem.Spacing.spacing12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            notification.isRead
                ? Color.clear
                : DesignSystem.Colors.accentSoft.opacity(0.3)
        )
    }

    @ViewBuilder
    private var eventIcon: some View {
        let (iconName, color) = iconInfo(for: notification.eventType)
        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
            .fill(color.opacity(0.12))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
            }
    }

    private func iconInfo(for eventType: NotificationEventType) -> (String, Color) {
        switch eventType {
        case .newMergeRequest:
            return ("arrow.triangle.merge", DesignSystem.Colors.accent)
        case .mrApproval:
            return ("checkmark.circle.fill", DesignSystem.Colors.success)
        case .dependencyConflict:
            return ("exclamationmark.triangle.fill", DesignSystem.Colors.danger)
        case .sprintCompletion:
            return ("flag.checkered", DesignSystem.Colors.warning)
        }
    }
}

// MARK: - Date Extension

extension Date {
    /// Returns a human-readable relative time description.
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
