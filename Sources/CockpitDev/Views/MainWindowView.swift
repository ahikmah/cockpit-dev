import SwiftUI
import SwiftData

// MARK: - Workspace Tab

/// Represents the available tabs in the workspace detail view.
enum WorkspaceTab: String, CaseIterable, Identifiable {
    case board = "Board"
    case tickets = "Tickets"
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
        case .tickets: return "ticket"
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
/// Contains the workspace sidebar and detail tab surface.
struct MainWindowView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.credentialServices) private var credentialServices
    @Environment(WindowStateService.self) private var windowStateService: WindowStateService?
    @Environment(KeyboardShortcutState.self) private var shortcutState: KeyboardShortcutState?
    @Query(sort: \MergeRequestEntry.updatedAt, order: .reverse) private var mergeRequests: [MergeRequestEntry]
    @AppStorage(AppearancePreference.storageKey) private var appearancePreference = AppearancePreference.system.rawValue
    @State private var viewModel = WorkspaceListViewModel()
    @State private var selectedTab: WorkspaceTab = .board
    @State private var syncedWorkspaceIds: Set<UUID> = []
    @State private var syncingWorkspaceIds: Set<UUID> = []
    @State private var workspaceSyncRevision: [UUID: Int] = [:]
    @State private var planningSyncError: String?
    @State private var isRefreshingPlanningMetadata = false

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceListView(viewModel: viewModel)

            VStack(spacing: 0) {
                if let workspace = viewModel.selectedWorkspace {
                    workspaceDetailView(for: workspace)
                } else {
                    emptyDetailView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(DesignSystem.Colors.background)
        .onAppear {
            viewModel.configure(with: modelContext)
            // Restore persisted tab selection
            if let windowState = windowStateService {
                selectedTab = windowState.restoredTab
            }
            Task {
                await syncSelectedWorkspaceIfNeeded()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            windowStateService?.selectTab(newTab)
            Task {
                await syncSelectedWorkspaceIfNeeded()
            }
        }
        .onChange(of: viewModel.selectedWorkspace?.id) { _, newId in
            windowStateService?.selectWorkspace(id: newId)
            Task {
                await syncSelectedWorkspaceIfNeeded()
            }
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
        .id(workspace.id)
        .onChange(of: workspace.repositories.count) { _, _ in
            syncedWorkspaceIds.remove(workspace.id)
            Task {
                await syncSelectedWorkspaceIfNeeded()
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            ViewThatFits(in: .horizontal) {
                tabButtonGroup(showLabels: true)
                tabButtonGroup(showLabels: false)
            }

            Spacer(minLength: DesignSystem.Spacing.spacing8)
            appearanceMenu
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing20)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.navigation)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 1)
        }
    }

    private func tabButtonGroup(showLabels: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            ForEach(WorkspaceTab.allCases) { tab in
                tabButton(for: tab, showLabel: showLabels)
            }
        }
    }

    private func tabButton(for tab: WorkspaceTab, showLabel: Bool) -> some View {
        Button {
            withAnimation(DesignSystem.Motion.fast) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                if showLabel {
                    Text(tab.rawValue)
                        .font(DesignSystem.Typography.bodyMedium)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(selectedTab == tab ? DesignSystem.Colors.navigationActiveText : DesignSystem.Colors.textSecondary)
            .frame(minWidth: showLabel ? nil : 30)
            .padding(.horizontal, showLabel ? DesignSystem.Spacing.spacing12 : DesignSystem.Spacing.spacing8)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(selectedTab == tab ? DesignSystem.Colors.navigationActive : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                    .stroke(selectedTab == tab ? DesignSystem.Colors.border.opacity(0.65) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .help(tab.rawValue)
    }

    private var appearanceMenu: some View {
        Menu {
            ForEach(AppearancePreference.allCases) { preference in
                Button {
                    appearancePreference = preference.rawValue
                } label: {
                    Label(preference.label, systemImage: preference.icon)
                }
            }
        } label: {
            Image(systemName: currentAppearance.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 28, height: 28)
                .background(DesignSystem.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .help("Appearance")
    }

    private var currentAppearance: AppearancePreference {
        AppearancePreference(rawValue: appearancePreference) ?? .system
    }

    @MainActor
    private func syncSelectedWorkspaceIfNeeded() async {
        guard let workspace = viewModel.selectedWorkspace,
              selectedTab == .board || selectedTab == .tickets || selectedTab == .timeline || selectedTab == .sprints || selectedTab == .analytics,
              !workspace.repositories.isEmpty,
              !syncedWorkspaceIds.contains(workspace.id),
              !syncingWorkspaceIds.contains(workspace.id) else {
            return
        }

        syncingWorkspaceIds.insert(workspace.id)
        defer {
            syncingWorkspaceIds.remove(workspace.id)
        }

        let client = GitLabAPIClient(
            baseURL: URL(string: workspace.gitlabInstanceURL) ?? URL(string: AppConstants.defaultGitLabInstanceURL)!,
            tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
        )
        let planningClient = OpenSpecPMAPIClient(
            baseURL: URL(string: AppConstants.openSpecPMInstanceURL)!,
            tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
        )
        let engine = SyncEngine(
            apiClient: client,
            planningMetadataProvider: planningClient,
            modelContext: modelContext
        )

        await refreshPlanningMetadata(for: workspace, using: engine)

        do {
            _ = try await engine.fullReconcile(workspace: workspace)
            syncedWorkspaceIds.insert(workspace.id)
            workspaceSyncRevision[workspace.id, default: 0] += 1
            planningSyncError = nil
        } catch {
            planningSyncError = "Workspace data could not be refreshed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func forceRefreshWorkspaceData(for workspace: Workspace) async {
        syncedWorkspaceIds.remove(workspace.id)
        await syncSelectedWorkspaceIfNeeded()
    }

    @MainActor
    private func refreshPlanningMetadata(for workspace: Workspace, using engine: SyncEngine? = nil) async {
        guard !isRefreshingPlanningMetadata else { return }

        isRefreshingPlanningMetadata = true
        defer { isRefreshingPlanningMetadata = false }

        let syncEngine: SyncEngine
        if let engine {
            syncEngine = engine
        } else {
            let client = GitLabAPIClient(
                baseURL: URL(string: workspace.gitlabInstanceURL) ?? URL(string: AppConstants.defaultGitLabInstanceURL)!,
                tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
            )
            let planningClient = OpenSpecPMAPIClient(
                baseURL: URL(string: AppConstants.openSpecPMInstanceURL)!,
                tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
            )
            syncEngine = SyncEngine(
                apiClient: client,
                planningMetadataProvider: planningClient,
                modelContext: modelContext
            )
        }

        do {
            try await syncEngine.refreshPlanningMetadata(workspace: workspace)
            planningSyncError = nil
            workspaceSyncRevision[workspace.id, default: 0] += 1
        } catch GitLabOAuthError.tokenExpired {
            planningSyncError = "GitLab session expired. Reconnect in Settings to load planning dates and story points from OpenSpec PM."
        } catch GitLabOAuthError.tokenRefreshFailed {
            planningSyncError = "GitLab session expired. Reconnect in Settings to load planning dates and story points from OpenSpec PM."
        } catch GitLabOAuthError.tokenNotFound {
            planningSyncError = "Connect GitLab in Settings to load planning dates and story points from OpenSpec PM."
        } catch {
            planningSyncError = "Planning data could not be refreshed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func tabContent(for workspace: Workspace) -> some View {
        Group {
            switch selectedTab {
            case .board:
                DevLeadConsoleView(
                    workspace: workspace,
                    mergeRequests: mergeRequests,
                    syncRevision: workspaceSyncRevision[workspace.id, default: 0],
                    planningSyncError: planningSyncError,
                    isRefreshingPlanningMetadata: isRefreshingPlanningMetadata || syncingWorkspaceIds.contains(workspace.id),
                    onRefreshPlanningMetadata: {
                        Task {
                            await forceRefreshWorkspaceData(for: workspace)
                        }
                    }
                )
            case .tickets:
                TicketsView(
                    workspace: workspace,
                    syncEngine: SyncEngine(
                        apiClient: GitLabAPIClient(
                            baseURL: URL(string: workspace.gitlabInstanceURL) ?? URL(string: AppConstants.defaultGitLabInstanceURL)!,
                            tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
                        ),
                        planningMetadataProvider: OpenSpecPMAPIClient(
                            baseURL: URL(string: AppConstants.openSpecPMInstanceURL)!,
                            tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
                        ),
                        modelContext: modelContext
                    )
                )
            case .timeline:
                TimelineTabView(
                    workspace: workspace,
                    syncRevision: workspaceSyncRevision[workspace.id, default: 0],
                    planningSyncError: planningSyncError,
                    isRefreshingPlanningMetadata: isRefreshingPlanningMetadata,
                    onRefreshPlanningMetadata: {
                        Task {
                            await refreshPlanningMetadata(for: workspace)
                        }
                    }
                )
            case .sprints:
                SprintView(
                    workspace: workspace,
                    gitLabClient: GitLabAPIClient(
                        baseURL: URL(string: workspace.gitlabInstanceURL) ?? URL(string: AppConstants.defaultGitLabInstanceURL)!,
                        tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
                    ),
                    modelContext: modelContext
                )
            case .mergeRequests:
                MRListView(
                    workspace: workspace,
                    gitLabAPIClient: GitLabAPIClient(
                        baseURL: URL(string: workspace.gitlabInstanceURL) ?? URL(string: AppConstants.defaultGitLabInstanceURL)!,
                        tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
                    )
                )
            case .specs:
                SpecListView(
                    workspace: workspace,
                    gitLabAPIClient: GitLabAPIClient(
                        baseURL: URL(string: workspace.gitlabInstanceURL) ?? URL(string: AppConstants.defaultGitLabInstanceURL)!,
                        tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
                    )
                )
            case .docs:
                DocumentsView(workspace: workspace)
            case .analytics:
                AnalyticsView(
                    workspace: workspace,
                    syncRevision: workspaceSyncRevision[workspace.id, default: 0],
                    isRefreshing: syncingWorkspaceIds.contains(workspace.id),
                    onRefresh: {
                        Task {
                            await forceRefreshWorkspaceData(for: workspace)
                        }
                    }
                )
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
