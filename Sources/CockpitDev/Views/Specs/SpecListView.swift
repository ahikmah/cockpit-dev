import SwiftUI
import SwiftData

/// Displays the list of tracked OpenSpec specifications for a workspace.
///
/// Shows each spec's name, associated branch, current phase, and availability status.
/// Supports navigation to SpecDetailView for viewing spec content.
struct SpecListView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SpecViewModel
    @State private var showingSettings: Bool = false
    @State private var isFocusMode: Bool = false
    @State private var searchText: String = ""
    private let gitLabAPIClient: GitLabAPIClient

    init(workspace: Workspace, gitLabAPIClient: GitLabAPIClient) {
        _viewModel = State(initialValue: SpecViewModel(workspace: workspace))
        self.gitLabAPIClient = gitLabAPIClient
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if viewModel.specs.isEmpty {
                emptyStateView
            } else {
                reviewWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
        .onAppear {
            viewModel.configure(modelContext: modelContext, apiClient: gitLabAPIClient)
            Task {
                await viewModel.loadBranchOptions()
            }
        }
        .sheet(isPresented: $showingSettings) {
            specSettingsSheet
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Specifications")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Track OpenSpec changes on one remote branch")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    specContextPill(
                        icon: "folder",
                        text: viewModel.editingSpecPath.isEmpty ? "Path not configured" : viewModel.editingSpecPath
                    )

                    specContextPill(icon: "arrow.branch", text: viewModel.branchSummary)
                    specContextPill(icon: "laptopcomputer", text: viewModel.localCheckoutSummary)
                }
            }

            Spacer()

            HStack(spacing: DesignSystem.Spacing.spacing8) {
                branchPicker

                // Scan button
                Button {
                    Task {
                        await viewModel.scanForSpecs()
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        if viewModel.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Scan")
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .padding(.horizontal, DesignSystem.Spacing.spacing12)
                    .padding(.vertical, DesignSystem.Spacing.spacing6)
                    .background(DesignSystem.Colors.accentSoft)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isScanning)

                // Settings button
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
    }

    private var branchPicker: some View {
        Picker("Scan branch", selection: branchSelection) {
            ForEach(selectableBranches, id: \.self) { branch in
                Text(branch).tag(branch)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 210)
        .disabled(viewModel.isLoadingBranches || viewModel.branchOptions.isEmpty || viewModel.isScanning)
        .help("Remote branch to scan")
    }

    private var selectableBranches: [String] {
        guard let selectedBranchName = viewModel.selectedBranchName,
              !viewModel.branchOptions.contains(selectedBranchName) else {
            return viewModel.branchOptions
        }

        return [selectedBranchName] + viewModel.branchOptions
    }

    private var branchSelection: Binding<String> {
        Binding(
            get: { viewModel.selectedBranchName ?? "" },
            set: { newValue in
                viewModel.selectBranch(newValue)
                isFocusMode = false
            }
        )
    }

    // MARK: - Review Workspace

    @ViewBuilder
    private var reviewWorkspace: some View {
        if isFocusMode {
            detailPanel
        } else {
            HSplitView {
                reviewQueue
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 320)

                detailPanel
                    .frame(minWidth: 480)
            }
        }
    }

    private var reviewQueue: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
                HStack {
                    Text("Review Queue")
                        .font(DesignSystem.Typography.headingSmall)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    Text("\(viewModel.availableSpecs.count)")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Spacing.spacing8)
                        .padding(.vertical, DesignSystem.Spacing.spacing4)
                        .background(DesignSystem.Colors.surfaceElevated)
                        .clipShape(Capsule())
                }

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    TextField("Filter changes", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.bodyRegular)
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing10)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                }
            }
            .padding(DesignSystem.Spacing.spacing16)
            .background(DesignSystem.Colors.surface)

            Divider()

            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                    if let error = viewModel.errorMessage {
                        errorBanner(message: error)
                    }

                    if let scanSummary = viewModel.scanSummary {
                        infoBanner(message: scanSummary)
                    }

                    if !filteredAvailableSpecs.isEmpty {
                        sectionHeader("Available")

                        ForEach(filteredAvailableSpecs, id: \.id) { spec in
                            SpecRowView(
                                spec: spec,
                                taskProgress: viewModel.taskProgress(for: spec),
                                isSelected: viewModel.selectedSpec?.id == spec.id
                            )
                            .onTapGesture {
                                viewModel.selectedSpec = spec
                                isFocusMode = false
                            }
                        }
                    }

                    if !filteredUnavailableSpecs.isEmpty {
                        sectionHeader("Unavailable")

                        ForEach(filteredUnavailableSpecs, id: \.id) { spec in
                            SpecRowView(
                                spec: spec,
                                taskProgress: viewModel.taskProgress(for: spec),
                                isSelected: viewModel.selectedSpec?.id == spec.id
                            )
                            .opacity(0.6)
                        }
                    }

                    if filteredAvailableSpecs.isEmpty && filteredUnavailableSpecs.isEmpty {
                        Text("No matching changes")
                            .font(DesignSystem.Typography.bodyRegular)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.spacing24)
                    }
                }
                .padding(DesignSystem.Spacing.spacing12)
            }
        }
        .background(DesignSystem.Colors.surface)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedSpec = viewModel.selectedSpec {
            SpecDetailView(
                spec: selectedSpec,
                viewModel: viewModel,
                isFocusMode: isFocusMode,
                onToggleFocus: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isFocusMode.toggle()
                    }
                }
            )
            .id(selectedSpec.id)
        } else {
            noSelectionReaderView
        }
    }

    private var noSelectionReaderView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("Select a change to review")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Proposal, design, tasks, and capability specs appear here.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }

    private var filteredAvailableSpecs: [OpenSpecEntry] {
        filtered(viewModel.availableSpecs)
    }

    private var filteredUnavailableSpecs: [OpenSpecEntry] {
        filtered(viewModel.unavailableSpecs)
    }

    private func filtered(_ specs: [OpenSpecEntry]) -> [OpenSpecEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return specs
        }

        return specs.filter {
            $0.specName.localizedCaseInsensitiveContains(query)
                || $0.branchName.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Specs Tracked")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Push branches with spec files in \"\(viewModel.editingSpecPath)\" to start tracking specifications.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            VStack(spacing: DesignSystem.Spacing.spacing6) {
                Text(viewModel.branchSummary)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text(viewModel.localCheckoutSummary)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button {
                Task {
                    await viewModel.scanForSpecs()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan Branch")
                }
                .font(DesignSystem.Typography.bodyMedium)
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isScanning)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Settings Sheet

    private var specSettingsSheet: some View {
        VStack(spacing: DesignSystem.Spacing.spacing20) {
            Text("Spec Directory Configuration")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
                Text("Spec Directory Path")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                TextField("e.g., .kiro/specs", text: $viewModel.editingSpecPath)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignSystem.Typography.monospace)

                Text("Remote path relative to the repository root. Do not include the repository name from the GitLab breadcrumb.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            HStack {
                Button("Cancel") {
                    viewModel.editingSpecPath = viewModel.workspace.specDirectoryPath
                    showingSettings = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                Button("Save") {
                    viewModel.updateSpecDirectoryPath(viewModel.editingSpecPath)
                    showingSettings = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 400)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.top, DesignSystem.Spacing.spacing8)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Colors.warning)

            Text(message)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private func infoBanner(message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(DesignSystem.Colors.accent)

            Text(message)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private func specContextPill(icon: String, text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))

            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(DesignSystem.Typography.caption)
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
        .padding(.vertical, DesignSystem.Spacing.spacing4)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        }
    }
}

// MARK: - Spec Row View

/// A single row in the spec list showing name, branch, phase, and availability.
struct SpecRowView: View {

    let spec: OpenSpecEntry
    let taskProgress: OpenSpecTaskProgress?
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Phase icon
            phaseIcon
                .frame(width: 32, height: 32)
                .background(phaseBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

            // Spec info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Text(spec.specName)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    if let taskProgress {
                        Text(taskProgress.displayText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(progressColor(for: taskProgress))
                            .padding(.horizontal, DesignSystem.Spacing.spacing6)
                            .padding(.vertical, DesignSystem.Spacing.spacing2)
                            .background(progressColor(for: taskProgress).opacity(0.14))
                            .clipShape(Capsule())
                    }

                    if spec.hasUnreadVersion {
                        Text("New")
                            .font(DesignSystem.Typography.captionMedium)
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .padding(.horizontal, DesignSystem.Spacing.spacing6)
                            .padding(.vertical, DesignSystem.Spacing.spacing2)
                            .background(DesignSystem.Colors.accentSoft)
                            .clipShape(Capsule())
                    }
                }

                if let taskProgress {
                    progressBar(taskProgress)
                }

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    // Branch name
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text(spec.branchName)
                            .lineLimit(1)
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                    // Phase badge
                    Text(SpecViewModel.phaseLabel(for: spec.phase))
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(phaseTextColor)
                        .padding(.horizontal, DesignSystem.Spacing.spacing6)
                        .padding(.vertical, DesignSystem.Spacing.spacing2)
                        .background(phaseBackgroundColor)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Availability indicator
            if !spec.isAvailable {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Unavailable")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundStyle(DesignSystem.Colors.warning)
            }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary)
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(isSelected ? DesignSystem.Colors.sidebarSelected : DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(
                    isSelected ? DesignSystem.Colors.accent.opacity(0.4) : DesignSystem.Colors.border,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
    }

    // MARK: - Phase Styling

    private var phaseIcon: some View {
        Image(systemName: SpecViewModel.phaseIcon(for: spec.phase))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(phaseTextColor)
    }

    private func progressBar(_ progress: OpenSpecTaskProgress) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignSystem.Colors.border.opacity(0.65))

                RoundedRectangle(cornerRadius: 2)
                    .fill(progressColor(for: progress))
                    .frame(width: geometry.size.width * progress.ratio)
            }
        }
        .frame(height: 4)
        .padding(.top, DesignSystem.Spacing.spacing2)
        .accessibilityLabel("Task progress \(progress.completed) of \(progress.total)")
    }

    private func progressColor(for progress: OpenSpecTaskProgress) -> Color {
        if progress.percentage >= 100 {
            return DesignSystem.Colors.success
        }

        if progress.percentage >= 50 {
            return DesignSystem.Colors.accent
        }

        return DesignSystem.Colors.warning
    }

    private var phaseTextColor: Color {
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
}

#Preview {
    SpecListView(
        workspace: Workspace(name: "Preview Workspace"),
        gitLabAPIClient: GitLabAPIClient(
            baseURL: URL(string: AppConstants.defaultGitLabInstanceURL)!,
            tokenProvider: { "" }
        )
    )
        .modelContainer(for: Workspace.self, inMemory: true)
}
