import SwiftUI

/// Displays individual contribution metrics per member including
/// tickets completed, merge requests merged, and review comments.
struct IndividualContributionView: View {

    let data: [ContributionDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            headerView

            if data.isEmpty {
                emptyState
            } else {
                contributionTable
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
            Text("Individual Contributions")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Tickets, merge requests, and reviews per member")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Table

    private var contributionTable: some View {
        VStack(spacing: 0) {
            // Table header
            HStack(spacing: 0) {
                Text("Member")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Tickets")
                    .frame(width: 80, alignment: .center)
                Text("MRs")
                    .frame(width: 80, alignment: .center)
                Text("Reviews")
                    .frame(width: 80, alignment: .center)
            }
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.vertical, DesignSystem.Spacing.spacing8)
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .background(DesignSystem.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

            // Table rows
            ForEach(data) { point in
                contributionRow(point)
            }
        }
    }

    private func contributionRow(_ point: ContributionDataPoint) -> some View {
        HStack(spacing: 0) {
            // Member name
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String(point.member.displayName.prefix(1)).uppercased())
                            .font(DesignSystem.Typography.captionMedium)
                            .foregroundStyle(DesignSystem.Colors.accent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(point.member.displayName)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("@\(point.member.username)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Tickets completed
            metricBadge(value: point.ticketsCompleted, color: DesignSystem.Colors.success)
                .frame(width: 80)

            // MRs merged
            metricBadge(value: point.mergeRequestsMerged, color: DesignSystem.Colors.accent)
                .frame(width: 80)

            // Review comments
            metricBadge(value: point.reviewComments, color: DesignSystem.Colors.warning)
                .frame(width: 80)
        }
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
    }

    private func metricBadge(value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(DesignSystem.Typography.bodyMedium)
            .foregroundStyle(value > 0 ? color : DesignSystem.Colors.textTertiary)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, DesignSystem.Spacing.spacing4)
            .background(value > 0 ? color.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "person.3")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("No contribution data available")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}
