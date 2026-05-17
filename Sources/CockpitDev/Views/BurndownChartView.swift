import SwiftUI
import Charts

/// Displays a burndown chart for a sprint using Swift Charts.
/// Shows remaining story points (actual) vs ideal burndown line with daily data points.
struct BurndownChartView: View {
    let dataPoints: [SprintViewModel.BurndownDataPoint]
    let totalStoryPoints: Int

    var body: some View {
        if dataPoints.isEmpty {
            emptyChartState
        } else {
            chartContent
        }
    }

    // MARK: - Chart Content

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Legend
            HStack(spacing: DesignSystem.Spacing.spacing16) {
                legendItem(color: DesignSystem.Colors.accent, label: "Actual")
                legendItem(color: DesignSystem.Colors.textTertiary, label: "Ideal")
            }
            .padding(.bottom, DesignSystem.Spacing.spacing4)

            // Chart
            Chart {
                // Ideal burndown line
                ForEach(dataPoints) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Ideal SP", point.idealRemaining)
                    )
                    .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .interpolationMethod(.linear)
                }

                // Actual remaining SP line
                ForEach(dataPoints) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Remaining SP", point.remainingStoryPoints)
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }

                // Area fill under actual line
                ForEach(dataPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Remaining SP", point.remainingStoryPoints)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.accent.opacity(0.15),
                                DesignSystem.Colors.accent.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                // Data point markers
                ForEach(dataPoints) { point in
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Remaining SP", point.remainingStoryPoints)
                    )
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .symbolSize(20)
                }
            }
            .chartYScale(domain: 0...(max(totalStoryPoints, 1)))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(DesignSystem.Colors.border)
                    AxisValueLabel()
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(DesignSystem.Colors.border.opacity(0.5))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(DesignSystem.Colors.surface.opacity(0.3))
                    .border(DesignSystem.Colors.border.opacity(0.3), width: 0.5)
            }
        }
    }

    // MARK: - Empty State

    private var emptyChartState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DesignSystem.Colors.textTertiary)

            Text("No burndown data available")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Text("Data will appear once the sprint starts and tickets are assigned.")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.surface.opacity(0.3))
        .cornerRadius(DesignSystem.Radius.medium)
    }

    // MARK: - Legend

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 3)
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Helpers

    /// Determines the x-axis stride based on the number of data points.
    private var xAxisStride: Int {
        let count = dataPoints.count
        if count <= 7 {
            return 1
        } else if count <= 14 {
            return 2
        } else if count <= 30 {
            return 5
        } else {
            return 7
        }
    }
}
