import SwiftUI

/// Dev-lead oriented overview for risk, delivery health, and ownership load.
struct DevLeadConsoleView: View {
    let workspace: Workspace
    let mergeRequests: [MergeRequestEntry]
    let syncRevision: Int
    let planningSyncError: String?
    let isRefreshingPlanningMetadata: Bool
    let onRefreshPlanningMetadata: () -> Void

    private var metrics: DevLeadConsoleMetrics {
        DevLeadConsoleMetrics(workspace: workspace, mergeRequests: mergeRequests)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                header
                metricGrid

                HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing16) {
                    attentionQueue
                    deliveryMap
                }

                ownerLoad
            }
            .padding(DesignSystem.Spacing.spacing20)
        }
        .background(DesignSystem.Colors.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Today")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Risks, queue, and execution state across \(workspace.name)")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                onRefreshPlanningMetadata()
            } label: {
                Label(isRefreshingPlanningMetadata ? "Syncing" : "Refresh", systemImage: "arrow.clockwise")
                    .font(DesignSystem.Typography.captionMedium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.accent)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(DesignSystem.Colors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            .disabled(isRefreshingPlanningMetadata)
            .help("Refresh GitLab and planning metadata")

            syncBadge
        }
    }

    private var syncBadge: some View {
        let hasError = planningSyncError != nil
        let text = hasError ? "Sync issue" : "Synced"
        let icon = hasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        let color = hasError ? DesignSystem.Colors.warning : DesignSystem.Colors.success
        let surface = hasError ? DesignSystem.Colors.warningSoft : DesignSystem.Colors.successSoft

        return Label(text, systemImage: icon)
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            .help(planningSyncError ?? "Workspace data is loaded from the local synced store.")
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignSystem.Spacing.spacing12), count: 4), spacing: DesignSystem.Spacing.spacing12) {
            metricCard(title: "Blocked", value: "\(metrics.blockedTicketCount)", detail: "tickets", color: DesignSystem.Colors.danger, surface: DesignSystem.Colors.dangerSoft)
            metricCard(title: "Stale MRs", value: "\(metrics.staleMergeRequestCount)", detail: "need review", color: DesignSystem.Colors.warning, surface: DesignSystem.Colors.warningSoft)
            metricCard(title: "Sprint", value: "\(metrics.sprintProgressPercent)%", detail: "complete", color: DesignSystem.Colors.success, surface: DesignSystem.Colors.successSoft)
            metricCard(title: "Load", value: "\(metrics.overloadedMemberCount)", detail: "over limit", color: DesignSystem.Colors.accent, surface: DesignSystem.Colors.accentSoft)
        }
    }

    private func metricCard(title: String, value: String, detail: String, color: Color, surface: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.spacing6) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(color)

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(surface)
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        }
    }

    private var attentionQueue: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Attention Queue", detail: "ranked by risk")

            if metrics.attentionItems.isEmpty {
                emptyPanel(title: "No active risks", subtitle: "Blocked tickets and stale merge requests will appear here.")
            } else {
                ForEach(metrics.attentionItems) { item in
                    attentionRow(item)
                    if item.id != metrics.attentionItems.last?.id {
                        Divider()
                    }
                }
            }
        }
        .consolePanel()
    }

    private var deliveryMap: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Delivery Map", detail: "current workspace")

            VStack(spacing: DesignSystem.Spacing.spacing12) {
                deliveryRow(label: "Open", value: metrics.openTicketCount, color: DesignSystem.Colors.accent)
                deliveryRow(label: "Blocked", value: metrics.blockedTicketCount, color: DesignSystem.Colors.danger)
                deliveryRow(label: "MR Review", value: metrics.staleMergeRequestCount, color: DesignSystem.Colors.warning)
                deliveryRow(label: "Overloaded", value: metrics.overloadedMemberCount, color: DesignSystem.Colors.success)
            }
            .padding(DesignSystem.Spacing.spacing12)
        }
        .consolePanel()
    }

    private var ownerLoad: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Owner Load", detail: metrics.focusSprintName ?? "no sprint")

            let rows = metrics.ownerLoadRows
            if rows.isEmpty {
                emptyPanel(title: "No assigned sprint work", subtitle: "Assign tickets to members in a synced sprint to see load.")
            } else {
                VStack(spacing: DesignSystem.Spacing.spacing12) {
                    ForEach(rows) { row in
                        ownerLoadRow(row)
                    }
                }
                .padding(DesignSystem.Spacing.spacing12)
            }
        }
        .consolePanel()
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

            Text(detail)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.surface)
    }

    private func attentionRow(_ item: DevLeadConsoleMetrics.AttentionItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing12) {
            Circle()
                .fill(severityColor(item.severity))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text(item.title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(severityLabel(item.severity))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(severityColor(item.severity))
                .padding(.horizontal, DesignSystem.Spacing.spacing6)
                .padding(.vertical, DesignSystem.Spacing.spacing4)
                .background(severitySurface(item.severity))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .padding(DesignSystem.Spacing.spacing12)
    }

    private func deliveryRow(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            Text(label)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 72, alignment: .leading)

            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                    .fill(color.opacity(0.22))
                    .frame(width: max(8, min(geometry.size.width, CGFloat(value) * 16)))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                            .stroke(color.opacity(0.45), lineWidth: 1)
                    }
            }
            .frame(height: 20)

            Text("\(value)")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func ownerLoadRow(_ row: DevLeadConsoleMetrics.OwnerLoadRow) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            HStack {
                Text(row.memberName)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("\(row.storyPoints) SP")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(row.isOverloaded ? DesignSystem.Colors.danger : DesignSystem.Colors.textSecondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.Colors.background)

                    Capsule()
                        .fill(row.isOverloaded ? DesignSystem.Colors.danger : DesignSystem.Colors.accent)
                        .frame(width: geometry.size.width * CGFloat(row.ratio))
                }
            }
            .frame(height: 6)
        }
    }

    private func emptyPanel(title: String, subtitle: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing4) {
            Text(title)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(subtitle)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(DesignSystem.Spacing.spacing16)
    }

    private func severityColor(_ severity: DevLeadConsoleMetrics.AttentionItem.Severity) -> Color {
        switch severity {
        case .blocked: return DesignSystem.Colors.danger
        case .review: return DesignSystem.Colors.warning
        case .assign: return DesignSystem.Colors.accent
        }
    }

    private func severitySurface(_ severity: DevLeadConsoleMetrics.AttentionItem.Severity) -> Color {
        switch severity {
        case .blocked: return DesignSystem.Colors.dangerSoft
        case .review: return DesignSystem.Colors.warningSoft
        case .assign: return DesignSystem.Colors.accentSoft
        }
    }

    private func severityLabel(_ severity: DevLeadConsoleMetrics.AttentionItem.Severity) -> String {
        switch severity {
        case .blocked: return "Blocked"
        case .review: return "Review"
        case .assign: return "Assign"
        }
    }
}

private extension View {
    func consolePanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(DesignSystem.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            }
    }
}
