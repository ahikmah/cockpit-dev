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
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            // Workspace icon
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .fill(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay {
                    Text(workspace.name.prefix(1).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : DesignSystem.Colors.accent)
                }

            // Name and metadata
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text(workspace.name)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Label("\(workspace.repositories.count)", systemImage: "folder.fill")
                    Label("\(workspace.members.count)", systemImage: "person.2.fill")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Spacer()

            // Notification badge
            if unreadNotificationCount > 0 {
                notificationBadge
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
        .padding(.vertical, DesignSystem.Spacing.spacing6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .fill(isSelected ? DesignSystem.Colors.accentSoft : Color.clear)
        )
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
                    .fill(DesignSystem.Colors.accent)
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
    .frame(width: 240)
}
