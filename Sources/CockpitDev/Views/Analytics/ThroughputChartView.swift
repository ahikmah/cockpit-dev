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
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            ForEach(data) { point in
                metricRow(
                    label: point.sprintName,
                    value: point.ticketsCompleted,
                    maxValue: max(data.map(\.ticketsCompleted).max() ?? 1, 1),
                    color: Color(red: 0.56, green: 0.35, blue: 0.97)
                )
            }
        }
        .frame(minHeight: 160, alignment: .top)
    }

    private func metricRow(label: String, value: Int, maxValue: Int, color: Color) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing10) {
            Text(label)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 180, alignment: .leading)

            GeometryReader { geometry in
                Capsule()
                    .fill(color.opacity(0.72))
                    .frame(width: max(8, geometry.size.width * CGFloat(value) / CGFloat(maxValue)))
            }
            .frame(height: 9)

            Text("\(value)")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 38, alignment: .trailing)
        }
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
