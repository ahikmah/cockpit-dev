import SwiftUI
import Charts

/// Displays workload distribution showing assigned story points per member
/// in the current sprint. Highlights members exceeding the overload threshold.
struct WorkloadDistributionView: View {

    let data: [WorkloadDataPoint]
    let threshold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            headerView

            if data.isEmpty {
                emptyChart
            } else {
                chart
                legendView
            }
        }
        .frame(minHeight: 220)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text("Workload Distribution")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Assigned SP per member (current sprint)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Threshold indicator
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Circle()
                    .fill(DesignSystem.Colors.danger)
                    .frame(width: 6, height: 6)
                Text("Threshold: \(threshold) SP")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            ForEach(data) { point in
                workloadRow(point, maxValue: max(max(data.map(\.assignedStoryPoints).max() ?? 1, threshold), 1))
            }
        }
        .frame(minHeight: 160, alignment: .top)
    }

    private func workloadRow(_ point: WorkloadDataPoint, maxValue: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing10) {
            Text(point.member.displayName)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 180, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.Colors.background)

                    Capsule()
                        .fill(point.isOverloaded ? DesignSystem.Colors.danger.opacity(0.75) : DesignSystem.Colors.accent.opacity(0.75))
                        .frame(width: max(8, geometry.size.width * CGFloat(point.assignedStoryPoints) / CGFloat(maxValue)))

                    Rectangle()
                        .fill(DesignSystem.Colors.danger.opacity(0.8))
                        .frame(width: 1, height: 14)
                        .offset(x: min(geometry.size.width - 1, geometry.size.width * CGFloat(threshold) / CGFloat(maxValue)))
                }
            }
            .frame(height: 9)

            Text("\(point.assignedStoryPoints) SP")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(point.isOverloaded ? DesignSystem.Colors.danger : DesignSystem.Colors.textPrimary)
                .frame(width: 54, alignment: .trailing)
        }
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: DesignSystem.Spacing.spacing16) {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 12, height: 12)
                Text("Normal")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            HStack(spacing: DesignSystem.Spacing.spacing4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignSystem.Colors.danger)
                    .frame(width: 12, height: 12)
                Text("Overloaded")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyChart: some View {
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "person.3")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("No workload data for current sprint")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
