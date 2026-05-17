import SwiftUI
import SwiftData

// MARK: - Repositories Settings View

/// Displays the list of repositories in a workspace with management actions.
/// Supports adding, removing, setting local paths, and opening in IDE.
struct RepositoriesSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RepositoryManagementViewModel()

    let workspace: Workspace
    var gitLabAPIClient: GitLabAPIClient?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing24) {
            headerSection
            repositoryListSection
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onAppear {
            viewModel.configure(
                workspace: workspace,
                modelContext: modelContext,
                gitLabAPIClient: gitLabAPIClient
            )
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AddRepositorySheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(
            "Remove Repository",
            isPresented: $viewModel.showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                viewModel.executeRemoval()
            }
            Button("Cancel", role: .cancel) {
                viewModel.repositoryPendingRemoval = nil
            }
        } message: {
            if let repo = viewModel.repositoryPendingRemoval {
                Text("Remove \"\(repo.name)\" from this workspace? The remote repository on GitLab will not be affected.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Repositories")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Manage GitLab repositories associated with this workspace.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: DesignSystem.Spacing.spacing8) {
                openInIDEButton
                addRepositoryButton
            }
        }
    }

    private var addRepositoryButton: some View {
        Button {
            viewModel.resetAddForm()
            viewModel.showAddSheet = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                Text("Add Repository")
                    .font(DesignSystem.Typography.bodyMedium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
    }

    private var openInIDEButton: some View {
        Button {
            Task {
                await viewModel.openInIDE()
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 12, weight: .medium))
                Text("Open in IDE")
                    .font(DesignSystem.Typography.bodyMedium)
            }
            .foregroundStyle(DesignSystem.Colors.accent)
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(DesignSystem.Colors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.repositories.isEmpty || !hasLocalRepos)
        .opacity(viewModel.repositories.isEmpty || !hasLocalRepos ? 0.5 : 1.0)
    }

    private var hasLocalRepos: Bool {
        viewModel.repositories.contains { $0.localPath != nil }
    }

    // MARK: - Repository List

    private var repositoryListSection: some View {
        Group {
            if viewModel.repositories.isEmpty {
                emptyState
            } else {
                VStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(viewModel.repositories, id: \.id) { repository in
                        RepositoryRowView(
                            repository: repository,
                            onRemove: { viewModel.confirmRemoval(of: repository) },
                            onSetLocalPath: { viewModel.setLocalPath(for: repository) },
                            onClearLocalPath: { viewModel.clearLocalPath(for: repository) },
                            onSelectPath: { path in
                                viewModel.updateLocalPath(for: repository, path: path)
                            }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No repositories")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Add a GitLab repository to get started.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.spacing48)
    }
}

// MARK: - Repository Row View

/// Displays a single repository with its name, URL, local path status, and actions.
struct RepositoryRowView: View {

    let repository: Repository
    let onRemove: () -> Void
    let onSetLocalPath: () -> Void
    let onClearLocalPath: () -> Void
    let onSelectPath: (String) -> Void

    @State private var showPathPicker: Bool = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Repository icon
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 32, height: 32)
                .background(DesignSystem.Colors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

            // Repository info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text(repository.name)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(repository.url)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                localPathIndicator
            }

            Spacer()

            // Actions
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                setPathButton
                removeButton
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .fileImporter(
            isPresented: $showPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    onSelectPath(url.path)
                }
            case .failure:
                break
            }
        }
    }

    private var localPathIndicator: some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            if let localPath = repository.localPath {
                let exists = FileManager.default.fileExists(atPath: localPath)
                Image(systemName: exists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(exists ? DesignSystem.Colors.success : DesignSystem.Colors.warning)

                Text(exists ? localPath : "Path not found: \(localPath)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(exists ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.warning)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                Text("Not cloned locally")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
    }

    private var setPathButton: some View {
        Button {
            if repository.localPath != nil {
                onClearLocalPath()
            } else {
                showPathPicker = true
            }
        } label: {
            Image(systemName: repository.localPath != nil ? "folder.badge.minus" : "folder.badge.plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(DesignSystem.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .help(repository.localPath != nil ? "Clear local path" : "Set local path")
    }

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.danger)
                .frame(width: 28, height: 28)
                .background(DesignSystem.Colors.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .help("Remove repository from workspace")
    }
}

// MARK: - Add Repository Sheet

/// Sheet for adding a new repository via URL input and GitLab API validation.
struct AddRepositorySheet: View {

    @Bindable var viewModel: RepositoryManagementViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.spacing24) {
            // Header
            VStack(spacing: DesignSystem.Spacing.spacing4) {
                Text("Add Repository")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Enter a GitLab repository URL to validate and associate with this workspace.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // URL Input
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Repository URL")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextField("https://gitlab.com/namespace/project.git", text: $viewModel.newRepositoryURL)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.bodyRegular)
                    .padding(DesignSystem.Spacing.spacing8)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )

                Text("Supports HTTPS and SSH URLs (e.g., git@gitlab.com:namespace/project.git)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            // Error display
            if let errorMessage = viewModel.errorMessage, viewModel.showError {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.danger)

                    Text(errorMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.danger)
                }
                .padding(DesignSystem.Spacing.spacing8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }

            // Actions
            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing8)

                Spacer()

                Button {
                    Task {
                        let success = await viewModel.addRepository()
                        if success {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        if viewModel.isValidating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isValidating ? "Validating..." : "Add Repository")
                            .font(DesignSystem.Typography.bodyMedium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignSystem.Spacing.spacing16)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(
                        viewModel.isValidating || viewModel.newRepositoryURL.isEmpty
                            ? DesignSystem.Colors.accent.opacity(0.5)
                            : DesignSystem.Colors.accent
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isValidating || viewModel.newRepositoryURL.isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 480)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Workspace.self, Repository.self, configurations: config)
    let workspace = Workspace(name: "Test Workspace")
    container.mainContext.insert(workspace)

    return RepositoriesSettingsView(workspace: workspace)
        .modelContainer(container)
}
