import SwiftUI

/// Dedicated panel showing all active dependency conflicts in a workspace.
/// Conflicts are automatically resolved and removed when the underlying condition no longer exists.
struct ConflictsPanelView: View {

    @Bindable var viewModel: DependencyViewModel

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()

            if viewModel.activeConflicts.isEmpty {
                emptyState
            } else {
                conflictList
            }
        }
        .frame(width: 560)
        .frame(minHeight: 400)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large))
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Dependency Conflicts")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("\(viewModel.activeConflicts.count) active conflict\(viewModel.activeConflicts.count == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                viewModel.autoResolveConflicts()
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.spacing24)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(DesignSystem.Colors.success)

            Text("No Active Conflicts")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("All dependencies are healthy. Conflicts will appear here when scheduling or status issues are detected.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.spacing48)
    }

    // MARK: - Conflict List

    private var conflictList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.spacing12) {
                // Schedule conflicts
                let scheduleConflicts = viewModel.activeConflicts.filter { $0.type == .schedule }
                if !scheduleConflicts.isEmpty {
                    sectionHeader("Schedule Conflicts", icon: "calendar.badge.exclamationmark", count: scheduleConflicts.count)
                    ForEach(scheduleConflicts) { conflict in
                        conflictCard(conflict)
                    }
                }

                // Status conflicts
                let statusConflicts = viewModel.activeConflicts.filter { $0.type == .status }
                if !statusConflicts.isEmpty {
                    sectionHeader("Status Conflicts", icon: "exclamationmark.triangle", count: statusConflicts.count)
                    ForEach(statusConflicts) { conflict in
                        conflictCard(conflict)
                    }
                }
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.Colors.warning)

            Text(title)
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("\(count)")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, DesignSystem.Spacing.spacing6)
                .padding(.vertical, DesignSystem.Spacing.spacing2)
                .background(
                    Capsule()
                        .fill(DesignSystem.Colors.warning)
                )

            Spacer()
        }
        .padding(.top, DesignSystem.Spacing.spacing8)
    }

    private func conflictCard(_ conflict: DependencyConflict) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Conflict type badge
            HStack(spacing: DesignSystem.Spacing.spacing6) {
                Image(systemName: conflict.type == .schedule ? "calendar.badge.exclamationmark" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(conflict.type == .schedule ? DesignSystem.Colors.warning : DesignSystem.Colors.danger)

                Text(conflict.type == .schedule ? "Schedule" : "Status")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(conflict.type == .schedule ? DesignSystem.Colors.warning : DesignSystem.Colors.danger)

                Spacer()
            }

            // Description
            Text(conflict.description)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Ticket references
            HStack(spacing: DesignSystem.Spacing.spacing16) {
                ticketReference(label: "Dependent", ticket: conflict.dependentTicket)
                Image(systemName: "arrow.left")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                ticketReference(label: "Blocker", ticket: conflict.blockerTicket)
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .fill(conflict.type == .schedule ? DesignSystem.Colors.dangerSoft.opacity(0.5) : DesignSystem.Colors.dangerSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.danger.opacity(0.3), lineWidth: 1)
        )
    }

    private func ticketReference(label: String, ticket: Ticket) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(ticket.title)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
        }
    }
}
