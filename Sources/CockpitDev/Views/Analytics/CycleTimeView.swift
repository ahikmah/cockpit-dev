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
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            ForEach(data) { point in
                cycleRow(point, maxValue: max(data.map(\.averageDays).max() ?? 1, workspaceAverage, 1))
            }
        }
        .frame(minHeight: 160, alignment: .top)
    }

    private func cycleRow(_ point: CycleTimeDataPoint, maxValue: Double) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing10) {
            Text(point.label)
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
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.6).opacity(0.72))
                        .frame(width: max(8, geometry.size.width * point.averageDays / maxValue))

                    if workspaceAverage > 0 {
                        Rectangle()
                            .fill(DesignSystem.Colors.warning.opacity(0.85))
                            .frame(width: 1, height: 14)
                            .offset(x: min(geometry.size.width - 1, geometry.size.width * workspaceAverage / maxValue))
                    }
                }
            }
            .frame(height: 9)

            Text("\(String(format: "%.1f", point.averageDays))d")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 54, alignment: .trailing)
        }
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
