import SwiftUI
import QuickLookUI

/// A row view displaying a single document with metadata, file status, and actions.
struct DocumentRowView: View {

    let document: Document
    @Bindable var viewModel: DocumentViewModel

    @State private var isHovered = false
    @State private var isShowingQuickLook = false

    private var isMissing: Bool {
        !viewModel.fileExists(for: document)
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // File icon
            fileIcon

            // Document info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Text(document.name)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(
                            isMissing
                                ? DesignSystem.Colors.textTertiary
                                : DesignSystem.Colors.textPrimary
                        )
                        .lineLimit(1)

                    if isMissing {
                        fileMissingBadge
                    }
                }

                HStack(spacing: DesignSystem.Spacing.spacing12) {
                    // File size
                    Text(viewModel.formattedFileSize(document.fileSize))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    // Date added
                    Text(formattedDate(document.addedAt))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    // Added by
                    if let member = document.addedByMember {
                        HStack(spacing: DesignSystem.Spacing.spacing2) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9))
                            Text(member.displayName)
                                .lineLimit(1)
                        }
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            // Actions
            if isHovered {
                actionButtons
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .fill(isHovered ? DesignSystem.Colors.surface : Color.clear)
                .shadow(color: isHovered ? .black.opacity(0.04) : .clear, radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(
                    isHovered ? DesignSystem.Colors.border : Color.clear,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Motion.fast) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $isShowingQuickLook) {
            QuickLookPreviewView(url: URL(fileURLWithPath: document.filePath))
                .frame(minWidth: 600, minHeight: 400)
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - File Icon

    private var fileIcon: some View {
        let ext = (document.filePath as NSString).pathExtension.lowercased()
        let iconName = iconForExtension(ext)

        return Image(systemName: iconName)
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(isMissing ? DesignSystem.Colors.danger : iconColor(for: ext))
            .frame(width: 32, height: 32)
    }

    // MARK: - File Missing Badge

    private var fileMissingBadge: some View {
        HStack(spacing: DesignSystem.Spacing.spacing2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text("File missing")
                .font(DesignSystem.Typography.caption)
        }
        .foregroundStyle(DesignSystem.Colors.danger)
        .padding(.horizontal, DesignSystem.Spacing.spacing6)
        .padding(.vertical, DesignSystem.Spacing.spacing2)
        .background(DesignSystem.Colors.dangerSoft)
        .clipShape(Capsule())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            if !isMissing && viewModel.canPreview(document) {
                Button {
                    isShowingQuickLook = true
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)
                .help("Quick Look preview")
            }

            if !isMissing {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.filePath)])
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }

            Button {
                viewModel.confirmRemoveDocument(document)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.danger)
                    .frame(width: 28, height: 28)
                    .background(DesignSystem.Colors.dangerSoft)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
            .buttonStyle(.plain)
            .help("Remove document reference")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if !isMissing && viewModel.canPreview(document) {
            Button("Quick Look") {
                isShowingQuickLook = true
            }
        }

        if !isMissing {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.filePath)])
            }
        }

        Divider()

        Menu("Move to Folder") {
            Button("Root (No Folder)") {
                viewModel.moveDocument(document, toFolder: nil)
            }
            Divider()
            ForEach(viewModel.folders, id: \.self) { folder in
                Button(folder) {
                    viewModel.moveDocument(document, toFolder: folder)
                }
            }
        }

        Divider()

        Button("Remove", role: .destructive) {
            viewModel.confirmRemoveDocument(document)
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext {
        case "pdf":
            return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif":
            return "photo"
        case "txt", "rtf":
            return "doc.plaintext"
        case "md", "markdown":
            return "doc.text"
        case "swift", "py", "js", "ts", "json", "xml", "html", "css", "yaml", "yml":
            return "chevron.left.forwardslash.chevron.right"
        case "zip", "tar", "gz", "rar":
            return "doc.zipper"
        case "mp4", "mov", "avi":
            return "film"
        case "mp3", "wav", "aac":
            return "music.note"
        default:
            return "doc"
        }
    }

    private func iconColor(for ext: String) -> Color {
        switch ext {
        case "pdf":
            return .red
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif":
            return DesignSystem.Colors.accent
        case "md", "markdown":
            return DesignSystem.Colors.success
        case "swift", "py", "js", "ts", "json", "xml", "html", "css", "yaml", "yml":
            return .orange
        default:
            return DesignSystem.Colors.textSecondary
        }
    }
}
