import SwiftUI
import SwiftData

/// Displays an offline mode banner when the app cannot reach GitLab.
/// Shows the number of queued sync operations and provides a retry action.
struct OfflineBannerView: View {

    /// The sync engine to monitor for online/offline status.
    let syncEngine: SyncEngine

    /// Action to trigger manual reconnection attempt.
    var onRetry: (() -> Void)?

    var body: some View {
        if !syncEngine.isOnline {
            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.warning)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                    Text("Offline Mode")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    if syncEngine.offlineQueue.isEmpty {
                        Text("Changes will sync when connection is restored.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    } else {
                        Text("\(syncEngine.offlineQueue.count) operation\(syncEngine.offlineQueue.count == 1 ? "" : "s") queued for sync")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                Spacer()

                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: DesignSystem.Spacing.spacing4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                            Text("Retry")
                                .font(DesignSystem.Typography.captionMedium)
                        }
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.spacing12)
                        .padding(.vertical, DesignSystem.Spacing.spacing6)
                        .background(DesignSystem.Colors.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing16)
            .padding(.vertical, DesignSystem.Spacing.spacing8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal, DesignSystem.Spacing.spacing16)
            .padding(.top, DesignSystem.Spacing.spacing8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(DesignSystem.Motion.normal, value: syncEngine.isOnline)
        }
    }
}

// MARK: - Sync Queue Detail View

/// Shows detailed information about queued sync operations.
struct SyncQueueDetailView: View {

    let syncEngine: SyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            HStack {
                Text("Sync Queue")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("\(syncEngine.offlineQueue.count) items")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            if syncEngine.offlineQueue.isEmpty {
                Text("No pending operations.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            } else {
                ForEach(syncEngine.offlineQueue) { operation in
                    HStack(spacing: DesignSystem.Spacing.spacing8) {
                        Image(systemName: operation.operationType == .push ? "arrow.up.circle" : "arrow.down.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(operation.operationType == .push ? DesignSystem.Colors.accent : DesignSystem.Colors.success)

                        Text(operation.operationType == .push ? "Push" : "Pull")
                            .font(DesignSystem.Typography.captionMedium)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        Spacer()

                        Text(operation.queuedAt, style: .relative)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .padding(.vertical, DesignSystem.Spacing.spacing4)
                }
            }
        }
        .padding(DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
    }
}

#Preview("Offline Banner") {
    struct PreviewWrapper: View {
        @State var engine: SyncEngine = {
            let client = GitLabAPIClient(
                baseURL: URL(string: "https://gitlab.example.com")!,
                tokenProvider: { "token" }
            )
            let schema = Schema([Workspace.self, Repository.self, Member.self, Ticket.self, Sprint.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let engine = SyncEngine(apiClient: client, modelContext: context)
            engine.isOnline = false
            engine.enqueueOperation(ticketId: UUID(), type: .push)
            engine.enqueueOperation(ticketId: UUID(), type: .pull)
            return engine
        }()

        var body: some View {
            VStack {
                OfflineBannerView(syncEngine: engine) {
                    engine.setOnlineStatus(true)
                }
                Spacer()
            }
            .frame(width: 600, height: 200)
        }
    }

    return PreviewWrapper()
}
