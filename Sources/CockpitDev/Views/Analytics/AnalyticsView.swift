import SwiftUI
import SwiftData

/// Main analytics dashboard view displaying team performance metrics.
/// Provides filter controls and multiple chart sections for velocity,
/// workload, cycle time, throughput, and individual contributions.
struct AnalyticsView: View {

    let workspace: Workspace
    let syncRevision: Int
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = AnalyticsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.hasData {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.spacing24) {
                        filterBar
                        chartsGrid
                    }
                    .padding(DesignSystem.Spacing.spacing24)
                }
            } else {
                emptyStateView
            }
        }
        .onAppear {
            viewModel.configure(workspace: workspace, modelContext: modelContext)
        }
        .onChange(of: syncRevision) { _, _ in
            viewModel.configure(workspace: workspace, modelContext: modelContext)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analytics")
                        .font(DesignSystem.Typography.headingLarge)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Developer performance, delivery health, and schedule realization")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.spacing12) {
                    // Sprint range filter
                    Menu {
                        Button("All Sprints") {
                            viewModel.filter.startSprint = nil
                            viewModel.applyFilters()
                        }
                        Divider()
                        ForEach(viewModel.availableSprints, id: \.id) { sprint in
                            Button(sprint.name) {
                                viewModel.filter.startSprint = sprint
                                viewModel.applyFilters()
                            }
                        }
                    } label: {
                        filterChip(
                            icon: "calendar",
                            text: viewModel.filter.startSprint?.name ?? "Start Sprint"
                        )
                    }

                    Menu {
                        Button("All Sprints") {
                            viewModel.filter.endSprint = nil
                            viewModel.applyFilters()
                        }
                        Divider()
                        ForEach(viewModel.availableSprints, id: \.id) { sprint in
                            Button(sprint.name) {
                                viewModel.filter.endSprint = sprint
                                viewModel.applyFilters()
                            }
                        }
                    } label: {
                        filterChip(
                            icon: "calendar.badge.checkmark",
                            text: viewModel.filter.endSprint?.name ?? "End Sprint"
                        )
                    }

                    Menu {
                        Button("All Members") {
                            viewModel.filter.selectedMember = nil
                            viewModel.applyFilters()
                        }
                        Divider()
                        ForEach(viewModel.availableMembers, id: \.id) { member in
                            Button(member.displayName) {
                                viewModel.filter.selectedMember = member
                                viewModel.applyFilters()
                            }
                        }
                    } label: {
                        filterChip(
                            icon: "person",
                            text: viewModel.filter.selectedMember?.displayName ?? "Member"
                        )
                    }

                    Menu {
                        Button("All Labels") {
                            viewModel.filter.selectedLabel = nil
                            viewModel.applyFilters()
                        }
                        Divider()
                        ForEach(viewModel.availableLabels, id: \.self) { label in
                            Button(label) {
                                viewModel.filter.selectedLabel = label
                                viewModel.applyFilters()
                            }
                        }
                    } label: {
                        filterChip(
                            icon: "tag",
                            text: viewModel.filter.selectedLabel ?? "Label"
                        )
                    }
                }
            }
        }
    }

    private func filterChip(icon: String, text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(DesignSystem.Typography.caption)
            Image(systemName: "chevron.down")
                .font(.system(size: 9))
        }
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
        .padding(.vertical, DesignSystem.Spacing.spacing6)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Charts Grid

    private var chartsGrid: some View {
        VStack(spacing: DesignSystem.Spacing.spacing20) {
            summaryCards

            chartCard {
                DeadlineRiskView(
                    data: viewModel.deadlineRiskData,
                    onApprove: { ticket in
                        viewModel.approveDeadlineException(for: ticket)
                    },
                    onReject: { ticket in
                        viewModel.rejectDeadlineException(for: ticket)
                    }
                )
            }

            // Top row: Velocity + Throughput
            HStack(spacing: DesignSystem.Spacing.spacing20) {
                chartCard {
                    VelocityChartView(data: viewModel.velocityData)
                }
                chartCard {
                    ThroughputChartView(data: viewModel.throughputData)
                }
            }

            // Middle row: Workload Distribution + Cycle Time
            HStack(spacing: DesignSystem.Spacing.spacing20) {
                chartCard {
                    WorkloadDistributionView(
                        data: viewModel.workloadData,
                        threshold: workspace.maxStoryPointsThreshold
                    )
                }
                chartCard {
                    CycleTimeView(
                        data: viewModel.cycleTimeData,
                        workspaceAverage: viewModel.workspaceCycleTime
                    )
                }
            }

            // Bottom row: Individual Contributions (full width)
            chartCard {
                IndividualContributionView(data: viewModel.contributionData)
            }

            chartCard {
                DeveloperPerformanceView(data: viewModel.developerPerformanceData)
            }

            chartCard {
                ClosureRealizationView(data: viewModel.closureTrendData)
            }
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: DesignSystem.Spacing.spacing12),
            GridItem(.flexible(), spacing: DesignSystem.Spacing.spacing12),
            GridItem(.flexible(), spacing: DesignSystem.Spacing.spacing12),
            GridItem(.flexible(), spacing: DesignSystem.Spacing.spacing12)
        ], spacing: DesignSystem.Spacing.spacing12) {
            analyticsSummaryCard(
                title: "Committed",
                value: "\(viewModel.plannedStoryPoints) SP",
                subtitle: "\(viewModel.openStoryPoints) SP open",
                color: DesignSystem.Colors.accent
            )
            analyticsSummaryCard(
                title: "Completed",
                value: "\(viewModel.completedStoryPoints) SP",
                subtitle: completionSubtitle,
                color: DesignSystem.Colors.success
            )
            analyticsSummaryCard(
                title: "On-time",
                value: viewModel.onTimeCompletionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a",
                subtitle: "realized by due date",
                color: DesignSystem.Colors.warning
            )
            analyticsSummaryCard(
                title: "Deadline risk",
                value: "\(viewModel.lateTicketCount)",
                subtitle: "\(viewModel.approvedDeadlineExceptionCount) approved exceptions",
                color: viewModel.lateTicketCount > 0 ? DesignSystem.Colors.danger : DesignSystem.Colors.success
            )
        }
    }

    private var completionSubtitle: String {
        guard viewModel.plannedStoryPoints > 0 else { return "no committed SP" }
        let rate = Double(viewModel.completedStoryPoints) / Double(viewModel.plannedStoryPoints)
        return "\(Int((rate * 100).rounded()))% realization"
    }

    private var scheduleVarianceLabel: String {
        guard let value = viewModel.averageScheduleVarianceDays else { return "n/a" }
        if abs(value) < 0.1 { return "on time" }
        return value > 0 ? "+\(String(format: "%.1f", value))d" : "\(String(format: "%.1f", value))d"
    }

    private func analyticsSummaryCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            Text(title.uppercased())
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(subtitle)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(color.opacity(0.22), lineWidth: 1)
        }
    }

    private func chartCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(DesignSystem.Spacing.spacing16)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Analytics Data")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("No analytics data is available for the selected range. Complete tickets in sprints to see team performance metrics.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DeadlineRiskView: View {
    let data: [DeadlineRiskDataPoint]
    let onApprove: (Ticket) -> Void
    let onReject: (Ticket) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deadline Appeals")
                        .font(DesignSystem.Typography.headingSmall)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Late tickets and lead-approved schedule exceptions")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                Spacer()
                Text("\(data.filter { $0.appealStatus != .approved }.count) pending")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }

            if data.isEmpty {
                compactEmptyState("No deadline breaches")
            } else {
                VStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(data) { point in
                        deadlineRiskRow(point)
                    }
                }
            }
        }
    }

    private func deadlineRiskRow(_ point: DeadlineRiskDataPoint) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Text(point.title)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    statusBadge(point)
                }

                HStack(spacing: DesignSystem.Spacing.spacing10) {
                    metadata("person", point.assigneeName)
                    metadata("calendar", "Due \(shortDate(point.dueDate))")
                    metadata(point.isOpen ? "clock" : "checkmark.circle", closureLabel(point))
                    metadata("star", "\(point.storyPoints) SP")
                }
            }

            Spacer(minLength: DesignSystem.Spacing.spacing12)

            if point.appealStatus == .approved {
                Text(point.appealReason ?? "Lead-approved")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.success)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .trailing)
            } else {
                Button {
                    onApprove(point.ticket)
                } label: {
                    Label("Approve exception", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onReject(point.ticket)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .help("Reject appeal")
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .stroke(point.appealStatus == .approved ? DesignSystem.Colors.success.opacity(0.24) : DesignSystem.Colors.warning.opacity(0.32), lineWidth: 1)
        }
    }

    private func statusBadge(_ point: DeadlineRiskDataPoint) -> some View {
        let text: String
        let color: Color
        switch point.appealStatus {
        case .approved:
            text = "Approved exception"
            color = DesignSystem.Colors.success
        case .rejected:
            text = "\(point.daysLate)d late rejected"
            color = DesignSystem.Colors.danger
        case .none:
            text = point.isOpen ? "\(point.daysLate)d overdue" : "\(point.daysLate)d late"
            color = DesignSystem.Colors.warning
        }

        return Text(text)
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private func metadata(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .lineLimit(1)
        }
        .font(DesignSystem.Typography.caption)
        .foregroundStyle(DesignSystem.Colors.textSecondary)
    }

    private func closureLabel(_ point: DeadlineRiskDataPoint) -> String {
        if let closedAt = point.closedAt {
            return "Realized \(shortDate(closedAt))"
        }
        return "Still open"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

private struct DeveloperPerformanceView: View {
    let data: [DeveloperPerformanceDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer Performance")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Committed SP, completed SP, closure realization, and delivery reliability")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            if data.isEmpty {
                compactEmptyState("No developer performance data")
            } else {
                VStack(spacing: 0) {
                    performanceHeader
                    ForEach(data) { point in
                        performanceRow(point)
                    }
                }
            }
        }
    }

    private var performanceHeader: some View {
        HStack(spacing: 0) {
            Text("Developer")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Done")
                .frame(width: 86, alignment: .trailing)
            Text("SP")
                .frame(width: 92, alignment: .trailing)
            Text("Open")
                .frame(width: 72, alignment: .trailing)
            Text("Realization")
                .frame(width: 100, alignment: .trailing)
            Text("On-time")
                .frame(width: 86, alignment: .trailing)
            Text("Variance")
                .frame(width: 86, alignment: .trailing)
        }
        .font(DesignSystem.Typography.captionMedium)
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private func performanceRow(_ point: DeveloperPerformanceDataPoint) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(point.member.displayName.prefix(1)).uppercased())
                            .font(DesignSystem.Typography.captionMedium)
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(point.member.displayName)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Text("@\(point.member.username)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            metricText("\(point.completedTickets)/\(point.plannedTickets)", color: DesignSystem.Colors.success)
                .frame(width: 86, alignment: .trailing)
            metricText("\(point.completedStoryPoints)/\(point.committedStoryPoints)", color: DesignSystem.Colors.accent)
                .frame(width: 92, alignment: .trailing)
            metricText("\(point.openStoryPoints)", color: point.openStoryPoints > 0 ? DesignSystem.Colors.warning : DesignSystem.Colors.textTertiary)
                .frame(width: 72, alignment: .trailing)
            metricText(dayLabel(point.averageRealizationDays), color: DesignSystem.Colors.textPrimary)
                .frame(width: 100, alignment: .trailing)
            metricText(percentLabel(point.onTimeRate), color: DesignSystem.Colors.success)
                .frame(width: 86, alignment: .trailing)
            metricText(varianceLabel(point.averageScheduleVarianceDays), color: varianceColor(point.averageScheduleVarianceDays))
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.6))
                .frame(height: 1)
        }
    }

    private func metricText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func dayLabel(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(String(format: "%.1f", value))d"
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func varianceLabel(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        if abs(value) < 0.1 { return "0d" }
        return value > 0 ? "+\(String(format: "%.1f", value))d" : "\(String(format: "%.1f", value))d"
    }

    private func varianceColor(_ value: Double?) -> Color {
        guard let value else { return DesignSystem.Colors.textTertiary }
        return value > 0.5 ? DesignSystem.Colors.danger : DesignSystem.Colors.success
    }
}

private struct ClosureRealizationView: View {
    let data: [ClosureTrendDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Closure Realization")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Actual ticket closures by day, based on closed ticket updated time")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            if data.isEmpty {
                compactEmptyState("No closed ticket trend")
            } else {
                VStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(data.suffix(14)) { point in
                        trendRow(point, maxSP: max(data.map(\.storyPointsClosed).max() ?? 1, 1))
                    }
                }
            }
        }
    }

    private func trendRow(_ point: ClosureTrendDataPoint, maxSP: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            Text(shortDate(point.date))
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 72, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.Colors.background)
                    Capsule()
                        .fill(DesignSystem.Colors.success.opacity(0.75))
                        .frame(width: max(8, geometry.size.width * CGFloat(point.storyPointsClosed) / CGFloat(maxSP)))
                }
            }
            .frame(height: 9)

            Text("\(point.storyPointsClosed) SP")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 54, alignment: .trailing)
            Text("\(point.ticketsClosed) tickets")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

private func compactEmptyState(_ text: String) -> some View {
    HStack(spacing: DesignSystem.Spacing.spacing8) {
        Image(systemName: "chart.xyaxis.line")
            .foregroundStyle(DesignSystem.Colors.textTertiary)
        Text(text)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textTertiary)
    }
    .frame(maxWidth: .infinity, minHeight: 92)
}
