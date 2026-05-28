import SwiftUI
import SwiftData

/// Main sprint planning view combining the sprint list and detail views
/// in a split layout.
struct SprintView: View {
    let workspace: Workspace
    let gitLabClient: GitLabAPIClient?
    let modelContext: ModelContext?
    @State private var viewModel: SprintViewModel

    init(workspace: Workspace, gitLabClient: GitLabAPIClient? = nil, modelContext: ModelContext? = nil) {
        self.workspace = workspace
        self.gitLabClient = gitLabClient
        self.modelContext = modelContext
        self._viewModel = State(initialValue: SprintViewModel(
            workspace: workspace,
            gitLabClient: gitLabClient,
            modelContext: modelContext
        ))
    }

    var body: some View {
        HSplitView {
            // Left: Sprint list
            SprintListView(viewModel: viewModel)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)

            // Right: Sprint detail or empty state
            if let selectedSprint = viewModel.selectedSprint {
                SprintDetailView(
                    sprint: selectedSprint,
                    viewModel: viewModel,
                    syncEngine: syncEngine
                )
                    .frame(minWidth: 500)
            } else {
                noSelectionView
                    .frame(minWidth: 500)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .onAppear {
            viewModel.workspace = workspace
            viewModel.refreshSprints()
        }
        .onChange(of: workspace.sprints.count) { _, _ in
            viewModel.refreshSprints()
        }
        .onChange(of: workspace.tickets.count) { _, _ in
            viewModel.refreshSprints()
        }
    }

    private var syncEngine: SyncEngine? {
        guard let gitLabClient, let modelContext else { return nil }
        return SyncEngine(apiClient: gitLabClient, modelContext: modelContext)
    }

    // MARK: - No Selection View

    private var noSelectionView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "flag")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("Select a Sprint")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Choose a sprint from the list to view details, progress, and burndown chart.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}
