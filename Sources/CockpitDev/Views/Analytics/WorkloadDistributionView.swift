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
        Chart(data) { point in
            BarMark(
                x: .value("Member", point.member.displayName),
                y: .value("Story Points", point.assignedStoryPoints)
            )
            .foregroundStyle(point.isOverloaded ? DesignSystem.Colors.danger : DesignSystem.Colors.accent)
            .cornerRadius(4)
            .annotation(position: .top, alignment: .center) {
                if point.isOverloaded {
                    overloadBadge
                }
            }

            // Threshold rule line
            RuleMark(y: .value("Threshold", threshold))
                .foregroundStyle(DesignSystem.Colors.danger.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DesignSystem.Colors.border)
                AxisValueLabel()
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(minHeight: 160)
    }

    // MARK: - Overload Badge

    private var overloadBadge: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(DesignSystem.Colors.danger)
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
