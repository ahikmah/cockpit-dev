import SwiftUI

/// Owns timeline view-model state for a workspace tab.
struct TimelineTabView: View {
    let workspace: Workspace
    let syncRevision: Int
    let planningSyncError: String?
    let isRefreshingPlanningMetadata: Bool
    let onRefreshPlanningMetadata: () -> Void
    @State private var viewModel = GanttViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let planningSyncError {
                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .foregroundStyle(DesignSystem.Colors.warning)

                    Text(planningSyncError)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: DesignSystem.Spacing.spacing12)

                    Button {
                        onRefreshPlanningMetadata()
                    } label: {
                        if isRefreshingPlanningMetadata {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Retry")
                        }
                    }
                    .disabled(isRefreshingPlanningMetadata)
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.warning.opacity(0.12))

                Divider()
            }

            GanttChartView(viewModel: viewModel)
        }
            .onAppear {
                configure()
            }
            .onChange(of: workspace.id) { _, _ in
                configure()
            }
            .onChange(of: workspace.tickets.count) { _, _ in
                viewModel.refreshData()
            }
            .onChange(of: syncRevision) { _, _ in
                viewModel.refreshData()
            }
    }

    private func configure() {
        viewModel.workspace = workspace
        viewModel.refreshData()
    }
}

/// Owns Kanban view-model state for future board execution surfaces.
struct KanbanTabView: View {
    let workspace: Workspace
    @State private var viewModel = KanbanViewModel()

    var body: some View {
        KanbanBoardView(viewModel: viewModel)
            .onAppear {
                configure()
            }
            .onChange(of: workspace.id) { _, _ in
                configure()
            }
            .onChange(of: workspace.tickets.count) { _, _ in
                viewModel.refreshBoard()
            }
    }

    private func configure() {
        viewModel.workspace = workspace
        viewModel.refreshBoard()
    }
}
