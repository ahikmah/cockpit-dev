import SwiftUI
import SwiftData

// MARK: - Workspace Tab

/// Represents the available tabs in the workspace detail view.
enum WorkspaceTab: String, CaseIterable, Identifiable {
    case board = "Board"
    case timeline = "Timeline"
    case sprints = "Sprints"
    case mergeRequests = "MRs"
    case specs = "Specs"
    case docs = "Docs"
    case analytics = "Analytics"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .board: return "rectangle.split.3x1"
        case .timeline: return "chart.bar.xaxis"
        case .sprints: return "flag"
        case .mergeRequests: return "arrow.triangle.merge"
        case .specs: return "doc.text"
        case .docs: return "folder"
        case .analytics: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Main Window View

/// Main application window displayed after successful authentication.
/// Contains a NavigationSplitView with workspace sidebar and detail TabView.
struct MainWindowView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(WindowStateService.self) private var windowStateService: WindowStateService?
    @Environment(KeyboardShortcutState.self) private var shortcutState: KeyboardShortcutState?
    @State private var viewModel = WorkspaceListViewModel()
    @State private var selectedTab: WorkspaceTab = .board

    var body: some View {
        NavigationSplitView {
            WorkspaceListView(viewModel: viewModel)
        } detail: {
            if let workspace = viewModel.selectedWorkspace {
                workspaceDetailView(for: workspace)
            } else {
                emptyDetailView
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            viewModel.configure(with: modelContext)
            // Restore persisted tab selection
            if let windowState = windowStateService {
                selectedTab = windowState.restoredTab
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            windowStateService?.selectTab(newTab)
        }
        .onChange(of: viewModel.selectedWorkspace?.id) { _, newId in
            windowStateService?.selectWorkspace(id: newId)
        }
    }

    // MARK: - Detail Views

    @ViewBuilder
    private func workspaceDetailView(for workspace: Workspace) -> some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            // Tab content
            tabContent(for: workspace)
        }
    }

    private var tabBar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing24) {
            ForEach(WorkspaceTab.allCases) { tab in
                tabButton(for: tab)
            }
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
    }

    private func tabButton(for tab: WorkspaceTab) -> some View {
        Button {
            withAnimation(DesignSystem.Motion.fast) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: DesignSystem.Spacing.spacing4) {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: selectedTab == tab ? .medium : .regular))
                    Text(tab.rawValue)
                        .font(DesignSystem.Typography.bodyMedium)
                }
                .foregroundStyle(
                    selectedTab == tab
                        ? DesignSystem.Colors.textPrimary
                        : DesignSystem.Colors.textSecondary
                )
                .padding(.bottom, DesignSystem.Spacing.spacing4)

                // Active indicator
                Rectangle()
                    .fill(selectedTab == tab ? DesignSystem.Colors.accent : Color.clear)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabContent(for workspace: Workspace) -> some View {
        Group {
            switch selectedTab {
            case .board:
                placeholderTab(title: "Board", icon: "rectangle.split.3x1", description: "Kanban board for \(workspace.name)")
            case .timeline:
                placeholderTab(title: "Timeline", icon: "chart.bar.xaxis", description: "Gantt chart for \(workspace.name)")
            case .sprints:
                SprintView(workspace: workspace)
            case .mergeRequests:
                MRListView(workspace: workspace)
            case .specs:
                SpecListView(workspace: workspace)
            case .docs:
                DocumentsView(workspace: workspace)
            case .analytics:
                AnalyticsView(workspace: workspace)
            case .settings:
                WorkspaceSettingsView(workspace: workspace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }

    private func placeholderTab(title: String, icon: String, description: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text(title)
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(description)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("Select a workspace to get started")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Create a workspace to organize your repositories, team, and tickets.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}

#Preview {
    MainWindowView()
        .modelContainer(for: Workspace.self, inMemory: true)
}
