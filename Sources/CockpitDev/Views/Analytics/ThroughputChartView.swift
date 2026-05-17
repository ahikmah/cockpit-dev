import SwiftUI
import Charts

/// Displays throughput trend showing tickets completed per sprint.
/// Shows up to 12 most recent sprints as a line + area chart.
struct ThroughputChartView: View {

    let data: [ThroughputDataPoint]

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
                Text("Throughput")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Tickets completed per sprint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Total tickets badge
            if !data.isEmpty {
                let total = data.map(\.ticketsCompleted).reduce(0, +)
                Text("Total: \(total)")
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
            LineMark(
                x: .value("Sprint", point.sprintName),
                y: .value("Tickets", point.ticketsCompleted)
            )
            .foregroundStyle(Color(red: 0.56, green: 0.35, blue: 0.97))
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Sprint", point.sprintName),
                y: .value("Tickets", point.ticketsCompleted)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.56, green: 0.35, blue: 0.97).opacity(0.15),
                        Color(red: 0.56, green: 0.35, blue: 0.97).opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Sprint", point.sprintName),
                y: .value("Tickets", point.ticketsCompleted)
            )
            .foregroundStyle(Color(red: 0.56, green: 0.35, blue: 0.97))
            .symbolSize(30)
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
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("No throughput data")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
