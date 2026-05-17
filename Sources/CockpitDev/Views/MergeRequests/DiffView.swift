import SwiftUI

// MARK: - Diff View

/// Renders file-by-file diffs with syntax highlighting and inline comment support.
/// Users can click on a diff line to add an inline comment.
struct DiffView: View {

    let files: [GitLabDiffFile]
    @Bindable var viewModel: MergeRequestViewModel

    @State private var expandedFiles: Set<String> = []
    @State private var inlineCommentLine: DiffLineInfo?
    @State private var inlineCommentText: String = ""

    var body: some View {
        if files.isEmpty {
            emptyDiffView
        } else {
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.spacing12) {
                    ForEach(files, id: \.newPath) { file in
                        DiffFileView(
                            file: file,
                            isExpanded: expandedFiles.contains(file.newPath),
                            inlineCommentLine: $inlineCommentLine,
                            inlineCommentText: $inlineCommentText,
                            onToggle: { toggleFile(file.newPath) },
                            onSubmitInlineComment: { lineInfo in
                                Task {
                                    await submitInlineComment(for: lineInfo)
                                }
                            }
                        )
                    }
                }
                .padding(DesignSystem.Spacing.spacing24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Auto-expand first few files
                let initialFiles = files.prefix(3).map(\.newPath)
                expandedFiles = Set(initialFiles)
            }
        }
    }

    private var emptyDiffView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Changes")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("This merge request has no file changes.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleFile(_ path: String) {
        if expandedFiles.contains(path) {
            expandedFiles.remove(path)
        } else {
            expandedFiles.insert(path)
        }
    }

    private func submitInlineComment(for lineInfo: DiffLineInfo) async {
        guard !inlineCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let position = DiffPosition(
            baseSha: "",
            startSha: "",
            headSha: "",
            oldPath: lineInfo.oldPath,
            newPath: lineInfo.newPath,
            positionType: "text",
            oldLine: lineInfo.oldLineNumber,
            newLine: lineInfo.newLineNumber
        )

        await viewModel.submitInlineComment(
            body: inlineCommentText.trimmingCharacters(in: .whitespacesAndNewlines),
            position: position
        )

        inlineCommentText = ""
        inlineCommentLine = nil
    }
}

// MARK: - Diff Line Info

/// Information about a specific line in a diff, used for inline comments.
struct DiffLineInfo: Equatable, Identifiable {
    let id: String
    let oldPath: String
    let newPath: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let lineContent: String

    init(oldPath: String, newPath: String, oldLineNumber: Int?, newLineNumber: Int?, lineContent: String) {
        self.id = "\(newPath):\(oldLineNumber ?? 0):\(newLineNumber ?? 0)"
        self.oldPath = oldPath
        self.newPath = newPath
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.lineContent = lineContent
    }
}

// MARK: - Diff File View

/// Renders a single file's diff with collapsible header and line-by-line content.
struct DiffFileView: View {

    let file: GitLabDiffFile
    let isExpanded: Bool
    @Binding var inlineCommentLine: DiffLineInfo?
    @Binding var inlineCommentText: String
    let onToggle: () -> Void
    let onSubmitInlineComment: (DiffLineInfo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // File header
            fileHeader

            // Diff content
            if isExpanded {
                Divider()
                diffContent
            }
        }
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - File Header

    private var fileHeader: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 12)

                fileStatusIcon

                Text(file.newPath)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if file.renamedFile {
                    Text("← \(file.oldPath)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Line count summary
                let stats = diffStats
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    if stats.additions > 0 {
                        Text("+\(stats.additions)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.success)
                    }
                    if stats.deletions > 0 {
                        Text("-\(stats.deletions)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.danger)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var fileStatusIcon: some View {
        if file.newFile {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.success)
        } else if file.deletedFile {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.danger)
        } else if file.renamedFile {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.accent)
        } else {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.warning)
        }
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        let lines = parseDiffLines(file.diff)

        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    VStack(spacing: 0) {
                        DiffLineView(
                            line: line,
                            file: file,
                            isCommentTarget: inlineCommentLine?.id == lineInfo(for: line).id,
                            onClickLine: {
                                let info = lineInfo(for: line)
                                if inlineCommentLine?.id == info.id {
                                    inlineCommentLine = nil
                                } else {
                                    inlineCommentLine = info
                                }
                            }
                        )

                        // Inline comment input
                        if let commentLine = inlineCommentLine,
                           commentLine.id == lineInfo(for: line).id {
                            inlineCommentInput(for: commentLine)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func inlineCommentInput(for lineInfo: DiffLineInfo) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.accent)

            TextField("Add a comment...", text: $inlineCommentText, axis: .vertical)
                .font(DesignSystem.Typography.bodyRegular)
                .textFieldStyle(.plain)
                .lineLimit(1...5)

            Button {
                onSubmitInlineComment(lineInfo)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(DesignSystem.Spacing.spacing6)
                    .background(DesignSystem.Colors.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(inlineCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.accentSoft)
    }

    // MARK: - Helpers

    private func lineInfo(for line: DiffLine) -> DiffLineInfo {
        DiffLineInfo(
            oldPath: file.oldPath,
            newPath: file.newPath,
            oldLineNumber: line.oldLineNumber,
            newLineNumber: line.newLineNumber,
            lineContent: line.content
        )
    }

    private var diffStats: (additions: Int, deletions: Int) {
        let lines = file.diff.components(separatedBy: "\n")
        let additions = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let deletions = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        return (additions, deletions)
    }
}

// MARK: - Diff Line Model

/// Represents a single parsed line from a unified diff.
struct DiffLine {
    enum LineType {
        case addition
        case deletion
        case context
        case hunkHeader
    }

    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

// MARK: - Diff Line View

/// Renders a single line of a diff with appropriate coloring and line numbers.
struct DiffLineView: View {

    let line: DiffLine
    let file: GitLabDiffFile
    let isCommentTarget: Bool
    let onClickLine: () -> Void

    var body: some View {
        Button(action: onClickLine) {
            HStack(spacing: 0) {
                // Old line number
                Text(line.oldLineNumber.map { String($0) } ?? "")
                    .font(DesignSystem.Typography.monospace)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, DesignSystem.Spacing.spacing4)

                // New line number
                Text(line.newLineNumber.map { String($0) } ?? "")
                    .font(DesignSystem.Typography.monospace)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, DesignSystem.Spacing.spacing8)

                // Line prefix
                Text(linePrefix)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundStyle(linePrefixColor)
                    .frame(width: 14, alignment: .center)

                // Line content with syntax highlighting
                Text(syntaxHighlightedContent)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundStyle(lineContentColor)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
            .padding(.horizontal, DesignSystem.Spacing.spacing4)
            .background(lineBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if isCommentTarget {
                Rectangle()
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 3)
            }
        }
    }

    private var linePrefix: String {
        switch line.type {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        case .hunkHeader: return "@@"
        }
    }

    private var linePrefixColor: Color {
        switch line.type {
        case .addition: return DesignSystem.Colors.success
        case .deletion: return DesignSystem.Colors.danger
        case .context: return DesignSystem.Colors.textTertiary
        case .hunkHeader: return DesignSystem.Colors.accent
        }
    }

    private var lineContentColor: Color {
        switch line.type {
        case .addition: return DesignSystem.Colors.textPrimary
        case .deletion: return DesignSystem.Colors.textPrimary
        case .context: return DesignSystem.Colors.textSecondary
        case .hunkHeader: return DesignSystem.Colors.accent
        }
    }

    private var lineBackground: Color {
        if isCommentTarget {
            return DesignSystem.Colors.accentSoft
        }
        switch line.type {
        case .addition: return DesignSystem.Colors.success.opacity(0.08)
        case .deletion: return DesignSystem.Colors.danger.opacity(0.08)
        case .context: return Color.clear
        case .hunkHeader: return DesignSystem.Colors.accent.opacity(0.05)
        }
    }

    /// Basic syntax highlighting for the line content.
    private var syntaxHighlightedContent: AttributedString {
        var attributed = AttributedString(line.content)
        attributed.font = DesignSystem.Typography.monospace

        // Apply basic syntax highlighting based on file extension
        let ext = (file.newPath as NSString).pathExtension.lowercased()
        applySyntaxHighlighting(to: &attributed, fileExtension: ext)

        return attributed
    }

    /// Applies basic syntax highlighting based on file extension.
    private func applySyntaxHighlighting(to attributed: inout AttributedString, fileExtension: String) {
        let content = line.content

        // Highlight keywords for common languages
        let keywords: [String]
        switch fileExtension {
        case "swift":
            keywords = ["func", "var", "let", "class", "struct", "enum", "protocol", "import",
                       "return", "if", "else", "guard", "for", "while", "switch", "case",
                       "private", "public", "internal", "static", "override", "async", "await",
                       "throws", "try", "catch", "self", "Self", "nil", "true", "false"]
        case "ts", "tsx", "js", "jsx":
            keywords = ["function", "const", "let", "var", "class", "interface", "type",
                       "import", "export", "return", "if", "else", "for", "while", "switch",
                       "case", "async", "await", "try", "catch", "new", "this", "null",
                       "undefined", "true", "false"]
        case "py":
            keywords = ["def", "class", "import", "from", "return", "if", "elif", "else",
                       "for", "while", "try", "except", "with", "as", "pass", "None",
                       "True", "False", "self", "async", "await", "yield"]
        case "rb":
            keywords = ["def", "class", "module", "require", "include", "return", "if",
                       "elsif", "else", "unless", "while", "do", "end", "nil", "true",
                       "false", "self", "yield", "begin", "rescue"]
        default:
            keywords = []
        }

        // Simple keyword highlighting - highlight whole words
        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let range = content.range(of: keyword, options: .regularExpression) {
                _ = regex // suppress unused warning
                if let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = NSColor(DesignSystem.Colors.accent)
                }
            }
        }

        // Highlight strings (simple approach)
        if content.contains("\"") || content.contains("'") {
            // Basic string detection - just color the whole thing if it's a string-heavy line
            // Full syntax highlighting would require a proper lexer
        }

        // Highlight comments
        let commentPrefixes = ["//", "#", "--"]
        for prefix in commentPrefixes {
            if let commentRange = content.range(of: prefix) {
                let suffixRange = commentRange.lowerBound..<content.endIndex
                if let attrRange = Range(String.Index(utf16Offset: content.distance(from: content.startIndex, to: suffixRange.lowerBound), in: String(attributed.characters))..<String.Index(utf16Offset: content.distance(from: content.startIndex, to: suffixRange.upperBound), in: String(attributed.characters)), in: attributed) {
                    attributed[attrRange].foregroundColor = NSColor(DesignSystem.Colors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Diff Parser

/// Parses a unified diff string into structured DiffLine objects.
func parseDiffLines(_ diff: String) -> [DiffLine] {
    let rawLines = diff.components(separatedBy: "\n")
    var result: [DiffLine] = []
    var oldLine = 0
    var newLine = 0

    for rawLine in rawLines {
        if rawLine.hasPrefix("@@") {
            // Parse hunk header to get line numbers
            let numbers = parseHunkHeader(rawLine)
            oldLine = numbers.oldStart
            newLine = numbers.newStart
            result.append(DiffLine(type: .hunkHeader, content: rawLine, oldLineNumber: nil, newLineNumber: nil))
        } else if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
            let content = String(rawLine.dropFirst())
            result.append(DiffLine(type: .addition, content: content, oldLineNumber: nil, newLineNumber: newLine))
            newLine += 1
        } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
            let content = String(rawLine.dropFirst())
            result.append(DiffLine(type: .deletion, content: content, oldLineNumber: oldLine, newLineNumber: nil))
            oldLine += 1
        } else if rawLine.hasPrefix("\\") {
            // "\ No newline at end of file" - skip
            continue
        } else {
            // Context line (may have a leading space)
            let content = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
            if !rawLine.hasPrefix("---") && !rawLine.hasPrefix("+++") {
                result.append(DiffLine(type: .context, content: content, oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
            }
        }
    }

    return result
}

/// Parses a hunk header (e.g., "@@ -1,5 +1,7 @@") to extract line numbers.
private func parseHunkHeader(_ header: String) -> (oldStart: Int, newStart: Int) {
    // Pattern: @@ -oldStart,oldCount +newStart,newCount @@
    let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else {
        return (1, 1)
    }

    let oldStartRange = Range(match.range(at: 1), in: header)!
    let newStartRange = Range(match.range(at: 2), in: header)!

    let oldStart = Int(header[oldStartRange]) ?? 1
    let newStart = Int(header[newStartRange]) ?? 1

    return (oldStart, newStart)
}
