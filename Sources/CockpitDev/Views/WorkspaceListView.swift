import SwiftUI
import SwiftData

/// Sidebar view displaying the list of workspaces with create and delete actions.
struct WorkspaceListView: View {

    @Bindable var viewModel: WorkspaceListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            sectionHeader

            // Workspace list
            if viewModel.workspaces.isEmpty {
                emptyState
            } else {
                workspaceList
            }
        }
        .frame(
            minWidth: DesignSystem.Sidebar.minWidth,
            idealWidth: DesignSystem.Sidebar.width,
            maxWidth: DesignSystem.Sidebar.maxWidth
        )
        .background(DesignSystem.Colors.sidebar)
        .sheet(isPresented: $viewModel.showCreateSheet) {
            CreateWorkspaceSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Delete Workspace",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.executePendingDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.workspacePendingDeletion = nil
            }
        } message: {
            if let workspace = viewModel.workspacePendingDeletion {
                Text("Are you sure you want to delete \"\(workspace.name)\"? This will remove all local workspace data and cannot be undone.")
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        HStack {
            Text("Workspaces")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            Button {
                viewModel.showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Create Workspace")
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing20)
        .padding(.top, DesignSystem.Spacing.spacing20)
        .padding(.bottom, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.sidebar)
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            Spacer()

            Image(systemName: "rectangle.stack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No workspaces yet")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Button {
                viewModel.showCreateSheet = true
            } label: {
                Text("Create Workspace")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.spacing16)
    }

    private var workspaceList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.spacing4) {
                ForEach(viewModel.workspaces, id: \.id) { workspace in
                    Button {
                        viewModel.selectedWorkspace = workspace
                    } label: {
                        WorkspaceRowView(
                            workspace: workspace,
                            isSelected: viewModel.selectedWorkspace?.id == workspace.id
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete Workspace", role: .destructive) {
                            viewModel.confirmDeletion(of: workspace)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.top, DesignSystem.Spacing.spacing4)
        }
        .background(DesignSystem.Colors.sidebar)
    }
}

#Preview {
    WorkspaceListView(viewModel: WorkspaceListViewModel())
        .frame(width: 236, height: 400)
}
