import SwiftUI

/// Hierarchical folder navigation sidebar for the Documents view.
struct FolderTreeView: View {

    @Bindable var viewModel: DocumentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Folders")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    viewModel.newFolderName = ""
                    viewModel.isShowingCreateFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Create new folder")
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing8)

            Divider()

            // All Documents (root)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                    allDocumentsRow

                    ForEach(viewModel.folders, id: \.self) { folder in
                        folderRow(folder)
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.spacing6)
            }
        }
        .frame(minWidth: 180, maxWidth: 220)
        .background(DesignSystem.Colors.background.opacity(0.5))
    }

    // MARK: - All Documents Row

    private var allDocumentsRow: some View {
        Button {
            viewModel.selectedFolder = nil
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(
                        viewModel.selectedFolder == nil
                            ? DesignSystem.Colors.accent
                            : DesignSystem.Colors.textSecondary
                    )

                Text("All Documents")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(
                        viewModel.selectedFolder == nil
                            ? DesignSystem.Colors.textPrimary
                            : DesignSystem.Colors.textSecondary
                    )

                Spacer()

                Text("\(viewModel.documents.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(
                viewModel.selectedFolder == nil
                    ? DesignSystem.Colors.accentSoft
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignSystem.Spacing.spacing6)
    }

    // MARK: - Folder Row

    private func folderRow(_ folder: String) -> some View {
        Button {
            viewModel.selectedFolder = folder
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(
                        viewModel.selectedFolder == folder
                            ? DesignSystem.Colors.accent
                            : DesignSystem.Colors.warning
                    )

                Text(folder)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(
                        viewModel.selectedFolder == folder
                            ? DesignSystem.Colors.textPrimary
                            : DesignSystem.Colors.textSecondary
                    )
                    .lineLimit(1)

                Spacer()

                Text("\(viewModel.documents(inFolder: folder).count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(
                viewModel.selectedFolder == folder
                    ? DesignSystem.Colors.accentSoft
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignSystem.Spacing.spacing6)
        .contextMenu {
            Button("Rename") {
                viewModel.folderToRename = folder
                viewModel.renameFolderName = folder
                viewModel.isShowingRenameFolder = true
            }
            Button("Delete", role: .destructive) {
                viewModel.folderToDelete = folder
                viewModel.isShowingDeleteConfirmation = true
            }
        }
    }
}
