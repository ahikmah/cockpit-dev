import SwiftUI

enum MarkdownComposerMode: String, CaseIterable, Identifiable {
    case write = "Write"
    case preview = "Preview"

    var id: String { rawValue }
}

/// GitLab-style markdown composer with a write/preview surface.
struct MarkdownEditorView: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    @State private var mode: MarkdownComposerMode = .write

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            Group {
                switch mode {
                case .write:
                    TextEditor(text: $text)
                        .font(DesignSystem.Typography.monospace)
                        .padding(DesignSystem.Spacing.spacing12)
                        .frame(minHeight: minHeight)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .font(DesignSystem.Typography.monospace)
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    .padding(.top, DesignSystem.Spacing.spacing20)
                                    .padding(.leading, DesignSystem.Spacing.spacing16)
                                    .allowsHitTesting(false)
                            }
                        }
                case .preview:
                    ScrollView {
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Nothing to preview.")
                                .font(DesignSystem.Typography.bodyRegular)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
                        } else {
                            MarkdownRendererView(content: text)
                                .padding(DesignSystem.Spacing.spacing16)
                        }
                    }
                    .frame(minHeight: minHeight)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72))

            Divider()

            HStack {
                Text(mode == .write ? "Markdown supported" : "Rendered preview")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Spacer()
                Image(systemName: "m.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(DesignSystem.Colors.surface)
        }
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(mode == .write ? DesignSystem.Colors.accent : DesignSystem.Colors.border, lineWidth: mode == .write ? 1.5 : 1)
        }
    }

    private var toolbar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing6) {
            Picker("Markdown mode", selection: $mode) {
                ForEach(MarkdownComposerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)

            Divider()
                .frame(height: 18)

            toolbarIcon("bold", label: "Bold")
            toolbarIcon("italic", label: "Italic")
            toolbarIcon("strikethrough", label: "Strike")
            toolbarIcon("list.bullet", label: "Bullet list")
            toolbarIcon("list.number", label: "Numbered list")
            toolbarIcon("checklist", label: "Task list")
            toolbarIcon("link", label: "Link")
            toolbarIcon("tablecells", label: "Table")
            toolbarIcon("curlybraces", label: "Code")

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing10)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.surface)
    }

    private func toolbarIcon(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .frame(width: 22, height: 22)
            .help(label)
    }
}
