import SwiftUI
import Charts

/// Displays average cycle time (in-progress to done) per member and workspace.
/// Cycle time is measured in days.
struct CycleTimeView: View {

    let data: [CycleTimeDataPoint]
    let workspaceAverage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            headerView

            if data.isEmpty {
                emptyChart
            } else {
                chart
            }
        }
        .frame(minHeight: 220)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text("Cycle Time")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Average days from in-progress to done")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Workspace average badge
            if workspaceAverage > 0 {
                Text("Workspace avg: \(String(format: "%.1f", workspaceAverage))d")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.success)
                    .padding(.horizontal, DesignSystem.Spacing.spacing8)
                    .padding(.vertical, DesignSystem.Spacing.spacing4)
                    .background(DesignSystem.Colors.success.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(data) { point in
                BarMark(
                    x: .value("Member", point.label),
                    y: .value("Days", point.averageDays)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.8, blue: 0.6), Color(red: 0.2, green: 0.8, blue: 0.6).opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(4)
            }

            // Workspace average line
            if workspaceAverage > 0 {
                RuleMark(y: .value("Average", workspaceAverage))
                    .foregroundStyle(DesignSystem.Colors.warning.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("avg")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
            }
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

    // MARK: - Empty State

    private var emptyChart: some View {
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "clock")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("No cycle time data available")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
