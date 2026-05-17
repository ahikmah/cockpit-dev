import SwiftUI
import SwiftData
import QuickLookUI

/// Main documents view with folder tree sidebar and document list.
/// Supports file addition, Quick Look preview, metadata display, and folder management.
struct DocumentsView: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DocumentViewModel()

    var body: some View {
        HSplitView {
            // Folder tree sidebar
            FolderTreeView(viewModel: viewModel)

            // Document list
            documentListPanel
        }
        .onAppear {
            viewModel.configure(with: modelContext, workspace: workspace)
        }
        .sheet(isPresented: $viewModel.isShowingCreateFolder) {
            createFolderSheet
        }
        .sheet(isPresented: $viewModel.isShowingRenameFolder) {
            renameFolderSheet
        }
        .alert("Delete Folder", isPresented: $viewModel.isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.folderToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteFolder()
            }
        } message: {
            Text("Documents in this folder will be moved to the root level. This action cannot be undone.")
        }
        .alert("Remove Document", isPresented: $viewModel.isShowingRemoveDocumentConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.documentToRemove = nil
            }
            Button("Remove", role: .destructive) {
                viewModel.removeDocument()
            }
        } message: {
            Text("This will remove the document reference from the workspace. The original file will not be deleted.")
        }
        .alert("Error", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .fileImporter(
            isPresented: $viewModel.isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Document List Panel

    private var documentListPanel: some View {
        VStack(spacing: 0) {
            // Toolbar
            documentToolbar

            Divider()

            // Document list or empty state
            if viewModel.filteredDocuments.isEmpty {
                emptyState
            } else {
                documentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Toolbar

    private var documentToolbar: some View {
        HStack {
            if let folder = viewModel.selectedFolder {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text(folder)
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            } else {
                Text("All Documents")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            Spacer()

            Button {
                viewModel.isShowingFilePicker = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add File")
                        .font(DesignSystem.Typography.bodyMedium)
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing12)
                .padding(.vertical, DesignSystem.Spacing.spacing6)
                .background(DesignSystem.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Document List

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                ForEach(viewModel.filteredDocuments, id: \.id) { document in
                    DocumentRowView(
                        document: document,
                        viewModel: viewModel
                    )
                }
            }
            .padding(DesignSystem.Spacing.spacing16)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No documents")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Add files to this workspace to keep project materials organized.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button {
                viewModel.isShowingFilePicker = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add File")
                        .font(DesignSystem.Typography.bodyMedium)
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Create Folder Sheet

    private var createFolderSheet: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            Text("Create Folder")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            TextField("Folder name", text: $viewModel.newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Button("Cancel") {
                    viewModel.isShowingCreateFolder = false
                    viewModel.newFolderName = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

                Button("Create") {
                    viewModel.createFolder()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 340)
    }

    // MARK: - Rename Folder Sheet

    private var renameFolderSheet: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            Text("Rename Folder")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            TextField("New folder name", text: $viewModel.renameFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Button("Cancel") {
                    viewModel.isShowingRenameFolder = false
                    viewModel.renameFolderName = ""
                    viewModel.folderToRename = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

                Button("Rename") {
                    viewModel.renameFolder()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 340)
    }

    // MARK: - File Import Handler

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Find the current user as the "added by" member (first owner/admin)
            let currentMember = workspace.members.first { $0.role == .owner }
                ?? workspace.members.first { $0.role == .admin }
                ?? workspace.members.first
            viewModel.addDocuments(from: urls, addedBy: currentMember)
        case .failure(let error):
            viewModel.errorMessage = "Failed to import file: \(error.localizedDescription)"
            viewModel.isShowingError = true
        }
    }
}
