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
    let isFocusMode: Bool
    let onToggleFocus: () -> Void

    @State private var showingVersionHistory: Bool = false
    @State private var selectedTab: SpecDocumentTab = .proposal

    init(
        spec: OpenSpecEntry,
        viewModel: SpecViewModel,
        isFocusMode: Bool = false,
        onToggleFocus: @escaping () -> Void = {}
    ) {
        self.spec = spec
        self.viewModel = viewModel
        self.isFocusMode = isFocusMode
        self.onToggleFocus = onToggleFocus
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            detailHeader

            Divider()

            // Content
            if let snapshot = viewModel.latestSnapshot(for: spec) {
                documentContent(snapshot: snapshot)
            } else {
                noContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
        .onAppear {
            viewModel.markAsRead(spec)
            selectInitialTab()
        }
        .sheet(isPresented: $showingVersionHistory) {
            VersionHistoryView(spec: spec, viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.spacing12) {
                detailIdentity
                Spacer(minLength: DesignSystem.Spacing.spacing12)
                detailActions
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
                detailIdentity
                detailActions
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
    }

    private var detailIdentity: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
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
                    .lineLimit(1)

                HStack(spacing: DesignSystem.Spacing.spacing12) {
                    // Branch
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                        Text(spec.branchName)
                            .lineLimit(1)
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
        }
    }

    private var detailActions: some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
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

            Button(action: onToggleFocus) {
                Label(
                    isFocusMode ? "Show Queue" : "Focus",
                    systemImage: isFocusMode ? "sidebar.left" : "arrow.up.left.and.arrow.down.right"
                )
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.spacing12)
                .padding(.vertical, DesignSystem.Spacing.spacing6)
                .background(DesignSystem.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .help(isFocusMode ? "Show review queue" : "Read without the queue")
        }
    }

    // MARK: - Markdown Content

    private func documentContent(snapshot: OpenSpecDocumentSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Document", selection: $selectedTab) {
                    ForEach(SpecDocumentTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .labelStyle(.titleOnly)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing24)
            .padding(.vertical, DesignSystem.Spacing.spacing12)
            .background(DesignSystem.Colors.surface)

            Divider()

            switch selectedTab {
            case .proposal:
                tabMarkdownContent(snapshot.proposal, emptyMessage: "No proposal document found.")
            case .design:
                tabMarkdownContent(snapshot.design, emptyMessage: "No design document found.")
            case .tasks:
                tabMarkdownContent(snapshot.tasks, emptyMessage: "No tasks document found.")
            case .specs:
                capabilitySpecsContent(snapshot.specs)
            }
        }
    }

    @ViewBuilder
    private func tabMarkdownContent(_ content: String?, emptyMessage: String) -> some View {
        if let content {
            markdownContentView(content: content)
        } else {
            emptyDocumentView(message: emptyMessage)
        }
    }

    private func capabilitySpecsContent(_ documents: [OpenSpecDocumentSnapshot.SpecDocument]) -> some View {
        ScrollView {
            if documents.isEmpty {
                emptyDocumentView(message: "No capability spec documents found.")
                    .frame(minHeight: 280)
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                    ForEach(documents) { document in
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
                            Label(document.path, systemImage: "doc.text")
                                .font(DesignSystem.Typography.monospace)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)

                            MarkdownRendererView(content: document.content)
                        }
                        .padding(DesignSystem.Spacing.spacing16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.spacing24)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

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
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - No Content

    private func emptyDocumentView(message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "doc.text")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text(message)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
            return DesignSystem.Colors.warningSoft
        case .tasks:
            return DesignSystem.Colors.successSoft
        }
    }

    private func selectInitialTab() {
        guard let snapshot = viewModel.latestSnapshot(for: spec) else {
            return
        }

        if snapshot.proposal != nil {
            selectedTab = .proposal
        } else if snapshot.design != nil {
            selectedTab = .design
        } else if snapshot.tasks != nil {
            selectedTab = .tasks
        } else {
            selectedTab = .specs
        }
    }
}

private enum SpecDocumentTab: String, CaseIterable, Identifiable {
    case proposal
    case design
    case tasks
    case specs

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .proposal:
            return "doc.text"
        case .design:
            return "pencil.and.ruler"
        case .tasks:
            return "checklist"
        case .specs:
            return "books.vertical"
        }
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

    SpecDetailView(
        spec: spec,
        viewModel: SpecViewModel(workspace: Workspace(name: "Preview"))
    )
}
