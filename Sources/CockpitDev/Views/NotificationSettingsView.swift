import SwiftUI
import SwiftData

// MARK: - Notification Settings View

/// Per-workspace notification type configuration view.
/// Allows users to enable/disable specific notification types.
struct NotificationSettingsView: View {

    let workspace: Workspace
    var notificationService: NotificationService

    @State private var viewModel = NotificationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing24) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Notifications")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Configure which events trigger notifications for this workspace.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            // Permission status banner
            if viewModel.isPermissionDenied {
                permissionDeniedBanner
            }

            // Notification type toggles
            VStack(spacing: 0) {
                ForEach(NotificationEventType.allCases, id: \.rawValue) { eventType in
                    notificationTypeRow(eventType)

                    if eventType != NotificationEventType.allCases.last {
                        Divider()
                            .padding(.leading, DesignSystem.Spacing.spacing48)
                    }
                }
            }
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )

            Spacer()
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onAppear {
            viewModel.configure(service: notificationService, workspace: workspace)
        }
    }

    // MARK: - Permission Denied Banner

    private var permissionDeniedBanner: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 16))
                .foregroundStyle(DesignSystem.Colors.warning)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text("System notifications are disabled")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Native notifications won't be delivered. Enable in System Settings → Notifications → Cockpit Dev.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(DesignSystem.Colors.accent)
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
    }

    // MARK: - Notification Type Row

    private func notificationTypeRow(_ eventType: NotificationEventType) -> some View {
        let isEnabled = viewModel.isTypeEnabled(eventType)

        return HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Icon
            eventIcon(for: eventType)
                .frame(width: 32, height: 32)

            // Label and description
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text(eventType.displayName)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(eventType.settingsDescription)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    viewModel.setTypeEnabled(eventType, enabled: newValue)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
    }

    @ViewBuilder
    private func eventIcon(for eventType: NotificationEventType) -> some View {
        let (iconName, color) = iconInfo(for: eventType)
        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
            .fill(color.opacity(0.12))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .medium))
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

// MARK: - NotificationEventType Display Extensions

extension NotificationEventType {
    /// Human-readable display name for the notification type.
    var displayName: String {
        switch self {
        case .newMergeRequest:
            return "New Merge Request"
        case .mrApproval:
            return "MR Approval"
        case .dependencyConflict:
            return "Dependency Conflict"
        case .sprintCompletion:
            return "Sprint Completion"
        }
    }

    /// Description shown in notification settings.
    var settingsDescription: String {
        switch self {
        case .newMergeRequest:
            return "When a new merge request is created in a workspace repository"
        case .mrApproval:
            return "When a merge request you authored is approved"
        case .dependencyConflict:
            return "When a dependency conflict is detected between tickets"
        case .sprintCompletion:
            return "When a sprint reaches its end date"
        }
    }
}
