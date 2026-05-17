import SwiftUI

/// Displays the version history for an OpenSpec specification entry.
///
/// Shows a reverse-chronological list of all stored DocSpecVersion snapshots,
/// displaying commit timestamp, author name, and content hash identifier.
/// Supports selecting two versions for side-by-side diff comparison.
///
/// Requirement 18.2: Display chronological list in reverse-chronological order (newest first)
/// Requirement 18.5: Remove unread badge when history is opened
struct VersionHistoryView: View {

    let spec: OpenSpecEntry
    let viewModel: SpecViewModel

    /// The two selected versions for comparison (first selected, second selected).
    @State private var selectedVersions: [DocSpecVersion] = []

    /// Whether the diff view is being shown.
    @State private var showingDiff: Bool = false

    @Environment(\.dismiss) private var dismiss

    /// Versions sorted in reverse-chronological order (newest first).
    private var sortedVersions: [DocSpecVersion] {
        spec.versions.sorted { $0.detectedAt > $1.detectedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            historyHeader

            Divider()

            // Content
            if sortedVersions.isEmpty {
                emptyStateView
            } else {
                versionListContent
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(DesignSystem.Colors.background)
        .onAppear {
            // Requirement 18.5: Remove badge when history is opened
            viewModel.markAsRead(spec)
        }
        .sheet(isPresented: $showingDiff) {
            if selectedVersions.count == 2 {
                VersionDiffView(
                    oldVersion: selectedVersions[1],
                    newVersion: selectedVersions[0],
                    specName: spec.specName
                )
            }
        }
    }

    // MARK: - Header

    private var historyHeader: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Version History")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("\(spec.specName) • \(sortedVersions.count) version\(sortedVersions.count == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Compare button (enabled when 2 versions selected)
            if selectedVersions.count == 2 {
                Button {
                    showingDiff = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Compare")
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .padding(.horizontal, DesignSystem.Spacing.spacing12)
                    .padding(.vertical, DesignSystem.Spacing.spacing6)
                    .background(DesignSystem.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)
            }

            // Clear selection
            if !selectedVersions.isEmpty {
                Button {
                    selectedVersions.removeAll()
                } label: {
                    Text("Clear")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
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

    // MARK: - Version List

    private var versionListContent: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                if selectedVersions.count < 2 {
                    Text("Select two versions to compare")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.top, DesignSystem.Spacing.spacing4)
                }

                ForEach(Array(sortedVersions.enumerated()), id: \.element.id) { index, version in
                    VersionRowView(
                        version: version,
                        versionNumber: sortedVersions.count - index,
                        isSelected: selectedVersions.contains(where: { $0.id == version.id }),
                        selectionOrder: selectionOrder(for: version)
                    )
                    .onTapGesture {
                        toggleVersionSelection(version)
                    }
                }
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No versions recorded")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Version history will appear here when spec content changes are detected.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection Logic

    private func toggleVersionSelection(_ version: DocSpecVersion) {
        if let existingIndex = selectedVersions.firstIndex(where: { $0.id == version.id }) {
            selectedVersions.remove(at: existingIndex)
        } else if selectedVersions.count < 2 {
            selectedVersions.append(version)
        } else {
            // Replace the second selection
            selectedVersions[1] = version
        }
    }

    private func selectionOrder(for version: DocSpecVersion) -> Int? {
        if let index = selectedVersions.firstIndex(where: { $0.id == version.id }) {
            return index + 1
        }
        return nil
    }
}

// MARK: - Version Row View

/// A single row in the version history list showing commit metadata.
struct VersionRowView: View {

    let version: DocSpecVersion
    let versionNumber: Int
    let isSelected: Bool
    let selectionOrder: Int?

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Selection indicator
            ZStack {
                Circle()
                    .stroke(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.border, lineWidth: 2)
                    .frame(width: 24, height: 24)

                if let order = selectionOrder {
                    Text("\(order)")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(Circle())
                }
            }

            // Version info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Text("Version \(versionNumber)")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    // Content hash badge
                    Text(String(version.contentHash.prefix(8)))
                        .font(DesignSystem.Typography.monospace)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.horizontal, DesignSystem.Spacing.spacing6)
                        .padding(.vertical, DesignSystem.Spacing.spacing2)
                        .background(DesignSystem.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }

                HStack(spacing: DesignSystem.Spacing.spacing12) {
                    // Author
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 11))
                        Text(version.authorName)
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                    // Timestamp
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(version.commitTimestamp.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(isSelected ? DesignSystem.Colors.accentSoft : DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

#Preview {
    let spec = OpenSpecEntry(
        specName: "user-authentication",
        branchName: "feature/auth",
        phase: .design,
        isAvailable: true,
        hasUnreadVersion: true
    )

    VersionHistoryView(
        spec: spec,
        viewModel: SpecViewModel(workspace: Workspace(name: "Preview"))
    )
}
