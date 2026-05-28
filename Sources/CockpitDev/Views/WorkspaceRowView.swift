import SwiftUI
import SwiftData

/// A sidebar row displaying a workspace's name, repository count, member count,
/// and an unread notification badge.
struct WorkspaceRowView: View {

    let workspace: Workspace
    let isSelected: Bool

    /// Number of unread notifications for this workspace.
    private var unreadNotificationCount: Int {
        workspace.notifications.filter { !$0.isRead }.count
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Workspace icon
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .fill(isSelected ? DesignSystem.Colors.accentSoft : DesignSystem.Colors.sidebarIcon)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(workspace.name.prefix(1).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                        .stroke(DesignSystem.Colors.border.opacity(isSelected ? 0.15 : 0.8), lineWidth: 1)
                }

            // Name and metadata
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text(workspace.name)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                Text("\(workspace.repositories.count) repos · \(workspace.members.count) members")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
            }

            Spacer()

            // Notification badge
            if unreadNotificationCount > 0 {
                notificationBadge
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .fill(isSelected ? DesignSystem.Colors.sidebarSelected : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(isSelected ? DesignSystem.Colors.border.opacity(0.75) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Notification Badge

    private var notificationBadge: some View {
        Text(unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.danger)
            )
            .accessibilityLabel("\(unreadNotificationCount) unread notifications")
    }
}

#Preview {
    VStack(spacing: 4) {
        WorkspaceRowView(
            workspace: Workspace(name: "Cockpit Dev"),
            isSelected: true
        )
        WorkspaceRowView(
            workspace: Workspace(name: "Another Project"),
            isSelected: false
        )
    }
    .padding()
    .frame(width: 236)
}
