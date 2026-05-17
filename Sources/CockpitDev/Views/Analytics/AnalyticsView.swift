import SwiftUI
import SwiftData

/// Main analytics dashboard view displaying team performance metrics.
/// Provides filter controls and multiple chart sections for velocity,
/// workload, cycle time, throughput, and individual contributions.
struct AnalyticsView: View {

    let workspace: Workspace

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
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            Text("Analytics")
                .font(DesignSystem.Typography.headingLarge)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

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

            // Member filter
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

            // Label filter
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
