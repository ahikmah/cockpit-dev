import SwiftUI

/// Displays the detail view for a single OpenSpec specification entry.
///
/// Shows:
/// - Spec metadata (name, branch, phase, availability)
/// - Rendered markdown content of the latest version
/// - Version count and last updated timestamp
struct SpecDetailView: View {

    let spec: OpenSpecEntry
    let viewModel: SpecViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingVersionHistory: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            detailHeader

            Divider()

            // Content
            if let content = viewModel.latestContent(for: spec) {
                markdownContentView(content: content)
            } else {
                noContentView
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(DesignSystem.Colors.background)
        .onAppear {
            viewModel.markAsRead(spec)
        }
        .sheet(isPresented: $showingVersionHistory) {
            VersionHistoryView(spec: spec, viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Phase icon
            Image(systemName: SpecViewModel.phaseIcon(for: spec.phase))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(phaseColor)
                .frame(width: 36, height: 36)
                .background(phaseBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text(spec.specName)
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                HStack(spacing: DesignSystem.Spacing.spacing12) {
                    // Branch
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                        Text(spec.branchName)
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                    // Phase
                    Text(SpecViewModel.phaseLabel(for: spec.phase))
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(phaseColor)
                        .padding(.horizontal, DesignSystem.Spacing.spacing6)
                        .padding(.vertical, DesignSystem.Spacing.spacing2)
                        .background(phaseBackgroundColor)
                        .clipShape(Capsule())

                    // Availability
                    if !spec.isAvailable {
                        HStack(spacing: DesignSystem.Spacing.spacing4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Branch unavailable")
                        }
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.warning)
                    }

                    // Version count
                    if !spec.versions.isEmpty {
                        HStack(spacing: DesignSystem.Spacing.spacing4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                            Text("\(spec.versions.count) version\(spec.versions.count == 1 ? "" : "s")")
                        }
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            // Version history button
            if !spec.versions.isEmpty {
                Button {
                    showingVersionHistory = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .medium))
                        Text("History")
                            .font(DesignSystem.Typography.bodyMedium)
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.spacing12)
                    .padding(.vertical, DesignSystem.Spacing.spacing6)
                    .background(DesignSystem.Colors.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Markdown Content

    private func markdownContentView(content: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                // Last updated info
                if let latestVersion = spec.versions.sorted(by: { $0.detectedAt > $1.detectedAt }).first {
                    HStack(spacing: DesignSystem.Spacing.spacing8) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 12))
                        Text(latestVersion.authorName)
                            .font(DesignSystem.Typography.caption)

                        Text("•")
                            .foregroundStyle(DesignSystem.Colors.textTertiary)

                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(latestVersion.detectedAt.formatted(.relative(presentation: .named)))
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Divider()

                // Rendered markdown
                MarkdownRendererView(content: content)
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
    }

    // MARK: - No Content

    private var noContentView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No content available")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("The spec file content has not been fetched yet.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phase Styling

    private var phaseColor: Color {
        switch spec.phase {
        case .proposal:
            return DesignSystem.Colors.accent
        case .design:
            return DesignSystem.Colors.warning
        case .tasks:
            return DesignSystem.Colors.success
        }
    }

    private var phaseBackgroundColor: Color {
        switch spec.phase {
        case .proposal:
            return DesignSystem.Colors.accentSoft
        case .design:
            return Color(red: 1.0, green: 0.96, blue: 0.89)
        case .tasks:
            return Color(red: 0.89, green: 0.98, blue: 0.93)
        }
    }
}

// MARK: - Markdown Renderer View

/// A simple markdown renderer that displays formatted markdown content.
///
/// Renders headings, code blocks, lists, bold, italic, and links
/// using native SwiftUI text styling.
struct MarkdownRendererView: View {

    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Line Parsing

    private func parseLines() -> [MarkdownLine] {
        let lines = content.components(separatedBy: "\n")
        var result: [MarkdownLine] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    result.append(.codeBlock(codeBlockContent.joined(separator: "\n")))
                    codeBlockContent = []
                    inCodeBlock = false
                } else {
                    // Start code block
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeBlockContent.append(line)
            } else if line.hasPrefix("# ") {
                result.append(.heading1(String(line.dropFirst(2))))
            } else if line.hasPrefix("## ") {
                result.append(.heading2(String(line.dropFirst(3))))
            } else if line.hasPrefix("### ") {
                result.append(.heading3(String(line.dropFirst(4))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.listItem(String(line.dropFirst(2))))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(.empty)
            } else {
                result.append(.paragraph(line))
            }
        }

        // Handle unclosed code block
        if inCodeBlock && !codeBlockContent.isEmpty {
            result.append(.codeBlock(codeBlockContent.joined(separator: "\n")))
        }

        return result
    }

    // MARK: - Line Rendering

    @ViewBuilder
    private func renderLine(_ line: MarkdownLine) -> some View {
        switch line {
        case .heading1(let text):
            Text(text)
                .font(DesignSystem.Typography.headingLarge)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.top, DesignSystem.Spacing.spacing8)

        case .heading2(let text):
            Text(text)
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.top, DesignSystem.Spacing.spacing6)

        case .heading3(let text):
            Text(text)
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.top, DesignSystem.Spacing.spacing4)

        case .paragraph(let text):
            Text(renderInlineMarkdown(text))
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

        case .listItem(let text):
            HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing8) {
                Text("•")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text(renderInlineMarkdown(text))
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, DesignSystem.Spacing.spacing12)

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.spacing12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )

        case .empty:
            Spacer()
                .frame(height: DesignSystem.Spacing.spacing4)
        }
    }

    /// Renders inline markdown (bold, italic, code) as an AttributedString.
    private func renderInlineMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Markdown Line Types

/// Represents a parsed line of markdown content.
enum MarkdownLine {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case paragraph(String)
    case listItem(String)
    case codeBlock(String)
    case empty
}

#Preview {
    let spec = OpenSpecEntry(
        specName: "user-authentication",
        branchName: "feature/auth",
        phase: .design,
        isAvailable: true,
        hasUnreadVersion: true
    )

    SpecDetailView(
        spec: spec,
        viewModel: SpecViewModel(workspace: Workspace(name: "Preview"))
    )
}
