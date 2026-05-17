import SwiftUI
import Charts

/// Displays team velocity as a bar chart showing completed story points per sprint.
/// Shows up to 12 most recent sprints.
struct VelocityChartView: View {

    let data: [VelocityDataPoint]

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
                Text("Velocity")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Completed story points per sprint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Average velocity badge
            if !data.isEmpty {
                let average = data.map(\.completedStoryPoints).reduce(0, +) / max(data.count, 1)
                Text("Avg: \(average) SP")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.spacing8)
                    .padding(.vertical, DesignSystem.Spacing.spacing4)
                    .background(DesignSystem.Colors.accentSoft)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart(data) { point in
            BarMark(
                x: .value("Sprint", point.sprintName),
                y: .value("Story Points", point.completedStoryPoints)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [DesignSystem.Colors.accent, DesignSystem.Colors.accent.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(4)
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
            Image(systemName: "chart.bar")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("No velocity data")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
