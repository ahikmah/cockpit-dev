import SwiftUI

/// Displays a side-by-side diff comparison between two DocSpecVersion snapshots.
///
/// Requirement 18.3: Render a side-by-side diff with markdown formatting preserved,
/// highlighting additions in green, deletions in red, and inline modifications
/// with distinct styling.
struct VersionDiffView: View {

    let oldVersion: DocSpecVersion
    let newVersion: DocSpecVersion
    let specName: String

    @Environment(\.dismiss) private var dismiss

    /// Computed diff lines between old and new content.
    private var diffResult: [SpecDiffLine] {
        computeSpecDiff(oldContent: oldVersion.content, newContent: newVersion.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            diffHeader

            Divider()

            // Diff content
            diffContent
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var diffHeader: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Version Comparison")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(specName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Diff stats
            diffStats

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

    private var diffStats: some View {
        let additions = diffResult.filter { $0.type == .added }.count
        let deletions = diffResult.filter { $0.type == .removed }.count

        return HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Old version info
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Circle()
                    .fill(Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(oldVersion.commitTimestamp.formatted(.dateTime.month(.abbreviated).day()))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Text("→")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            // New version info
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Circle()
                    .fill(Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(newVersion.commitTimestamp.formatted(.dateTime.month(.abbreviated).day()))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Divider()
                .frame(height: 16)

            // Stats
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Text("+\(additions)")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.success)

                Text("-\(deletions)")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.danger)
            }
        }
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        HStack(spacing: 0) {
            // Old version (left side)
            VStack(spacing: 0) {
                versionColumnHeader(
                    title: "Previous",
                    author: oldVersion.authorName,
                    hash: String(oldVersion.contentHash.prefix(8)),
                    isOld: true
                )

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diffResult.enumerated()), id: \.offset) { _, line in
                            oldSideLine(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.spacing12)
                }
            }

            Divider()

            // New version (right side)
            VStack(spacing: 0) {
                versionColumnHeader(
                    title: "Current",
                    author: newVersion.authorName,
                    hash: String(newVersion.contentHash.prefix(8)),
                    isOld: false
                )

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diffResult.enumerated()), id: \.offset) { _, line in
                            newSideLine(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.spacing12)
                }
            }
        }
    }

    // MARK: - Column Header

    private func versionColumnHeader(title: String, author: String, hash: String, isOld: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Circle()
                .fill(isOld ? DesignSystem.Colors.danger.opacity(0.2) : DesignSystem.Colors.success.opacity(0.2))
                .frame(width: 8, height: 8)

            Text(title)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("by \(author)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()

            Text(hash)
                .font(DesignSystem.Typography.monospace)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Diff Line Rendering

    @ViewBuilder
    private func oldSideLine(_ line: SpecDiffLine) -> some View {
        switch line.type {
        case .unchanged:
            Text(line.content)
                .font(DesignSystem.Typography.monospace)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)

        case .removed:
            Text(line.content)
                .font(DesignSystem.Typography.monospace)
                .foregroundStyle(Color(red: 0.6, green: 0.1, blue: 0.1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .padding(.horizontal, DesignSystem.Spacing.spacing4)
                .background(Color(red: 1.0, green: 0.9, blue: 0.9))
                .clipShape(RoundedRectangle(cornerRadius: 2))

        case .added:
            // Show empty placeholder on old side for added lines
            Text(" ")
                .font(DesignSystem.Typography.monospace)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .opacity(0.3)

        case .modified:
            Text(line.oldContent ?? line.content)
                .font(DesignSystem.Typography.monospace)
                .foregroundStyle(Color(red: 0.6, green: 0.1, blue: 0.1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .padding(.horizontal, DesignSystem.Spacing.spacing4)
                .background(Color(red: 1.0, green: 0.93, blue: 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    @ViewBuilder
    private func newSideLine(_ line: SpecDiffLine) -> some View {
        switch line.type {
        case .unchanged:
            Text(line.content)
                .font(DesignSystem.Typography.monospace)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)

        case .added:
            Text(line.content)
                .font(DesignSystem.Typography.monospace)
                .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .padding(.horizontal, DesignSystem.Spacing.spacing4)
                .background(Color(red: 0.9, green: 1.0, blue: 0.93))
                .clipShape(RoundedRectangle(cornerRadius: 2))

        case .removed:
            // Show empty placeholder on new side for removed lines
            Text(" ")
                .font(DesignSystem.Typography.monospace)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .opacity(0.3)

        case .modified:
            Text(line.content)
                .font(DesignSystem.Typography.monospace)
                .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .padding(.horizontal, DesignSystem.Spacing.spacing4)
                .background(Color(red: 0.85, green: 0.95, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

// MARK: - Diff Computation

/// Represents a single line in the spec version diff output.
struct SpecDiffLine: Identifiable {
    let id = UUID()
    let type: SpecDiffLineType
    let content: String
    let oldContent: String?

    init(type: SpecDiffLineType, content: String, oldContent: String? = nil) {
        self.type = type
        self.content = content
        self.oldContent = oldContent
    }
}

/// The type of change for a spec diff line.
enum SpecDiffLineType {
    case unchanged
    case added
    case removed
    case modified
}

/// Computes a line-by-line diff between two content strings using the
/// Longest Common Subsequence (LCS) algorithm.
///
/// - Parameters:
///   - oldContent: The previous version content.
///   - newContent: The current version content.
/// - Returns: An array of SpecDiffLine representing the changes.
func computeSpecDiff(oldContent: String, newContent: String) -> [SpecDiffLine] {
    let oldLines = oldContent.components(separatedBy: "\n")
    let newLines = newContent.components(separatedBy: "\n")

    let lcs = longestCommonSubsequence(oldLines, newLines)

    var result: [SpecDiffLine] = []
    var oldIndex = 0
    var newIndex = 0
    var lcsIndex = 0

    while oldIndex < oldLines.count || newIndex < newLines.count {
        if lcsIndex < lcs.count {
            // Process lines before the next LCS match
            while oldIndex < oldLines.count && oldLines[oldIndex] != lcs[lcsIndex] {
                // Check if this is a modification (corresponding new line exists before next LCS)
                if newIndex < newLines.count && newLines[newIndex] != lcs[lcsIndex] {
                    result.append(SpecDiffLine(type: .modified, content: newLines[newIndex], oldContent: oldLines[oldIndex]))
                    oldIndex += 1
                    newIndex += 1
                } else {
                    result.append(SpecDiffLine(type: .removed, content: oldLines[oldIndex]))
                    oldIndex += 1
                }
            }

            while newIndex < newLines.count && newLines[newIndex] != lcs[lcsIndex] {
                result.append(SpecDiffLine(type: .added, content: newLines[newIndex]))
                newIndex += 1
            }

            // Add the matching LCS line
            if lcsIndex < lcs.count {
                result.append(SpecDiffLine(type: .unchanged, content: lcs[lcsIndex]))
                oldIndex += 1
                newIndex += 1
                lcsIndex += 1
            }
        } else {
            // Process remaining lines after LCS is exhausted
            while oldIndex < oldLines.count && newIndex < newLines.count {
                if oldLines[oldIndex] == newLines[newIndex] {
                    result.append(SpecDiffLine(type: .unchanged, content: oldLines[oldIndex]))
                } else {
                    result.append(SpecDiffLine(type: .modified, content: newLines[newIndex], oldContent: oldLines[oldIndex]))
                }
                oldIndex += 1
                newIndex += 1
            }

            while oldIndex < oldLines.count {
                result.append(SpecDiffLine(type: .removed, content: oldLines[oldIndex]))
                oldIndex += 1
            }

            while newIndex < newLines.count {
                result.append(SpecDiffLine(type: .added, content: newLines[newIndex]))
                newIndex += 1
            }
        }
    }

    return result
}

/// Computes the Longest Common Subsequence of two string arrays for spec diffing.
///
/// - Parameters:
///   - a: The first array of strings.
///   - b: The second array of strings.
/// - Returns: The longest common subsequence as an array of strings.
private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
    let m = a.count
    let n = b.count

    // Build LCS table
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 1...m {
        for j in 1...n {
            if a[i - 1] == b[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    // Backtrack to find the LCS
    var lcs: [String] = []
    var i = m
    var j = n

    while i > 0 && j > 0 {
        if a[i - 1] == b[j - 1] {
            lcs.append(a[i - 1])
            i -= 1
            j -= 1
        } else if dp[i - 1][j] > dp[i][j - 1] {
            i -= 1
        } else {
            j -= 1
        }
    }

    return lcs.reversed()
}

#Preview {
    let oldVersion = DocSpecVersion(
        contentHash: "abc12345def67890",
        content: "# Requirements\n\n## Feature A\n\nThis is the old content.\n\n- Item 1\n- Item 2",
        authorName: "Alice",
        commitTimestamp: Date().addingTimeInterval(-86400)
    )

    let newVersion = DocSpecVersion(
        contentHash: "xyz98765uvw43210",
        content: "# Requirements\n\n## Feature A\n\nThis is the new content with changes.\n\n- Item 1\n- Item 2\n- Item 3 (new)",
        authorName: "Bob",
        commitTimestamp: Date()
    )

    VersionDiffView(
        oldVersion: oldVersion,
        newVersion: newVersion,
        specName: "user-authentication"
    )
}
