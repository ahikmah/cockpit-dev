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

    init(workspace: Workspace) {
        _viewModel = State(initialValue: SpecViewModel(workspace: workspace))
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
                specListContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
        .sheet(isPresented: $showingSettings) {
            specSettingsSheet
        }
        .sheet(item: $viewModel.selectedSpec) { spec in
            SpecDetailView(spec: spec, viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Specifications")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Track OpenSpec specs from developer branches")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: DesignSystem.Spacing.spacing8) {
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

    // MARK: - Spec List Content

    private var specListContent: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                // Error banner
                if let error = viewModel.errorMessage {
                    errorBanner(message: error)
                }

                // Available specs
                if !viewModel.availableSpecs.isEmpty {
                    sectionHeader("Available")

                    ForEach(viewModel.availableSpecs, id: \.id) { spec in
                        SpecRowView(spec: spec)
                            .onTapGesture {
                                viewModel.selectedSpec = spec
                            }
                    }
                }

                // Unavailable specs
                if !viewModel.unavailableSpecs.isEmpty {
                    sectionHeader("Unavailable")

                    ForEach(viewModel.unavailableSpecs, id: \.id) { spec in
                        SpecRowView(spec: spec)
                            .opacity(0.6)
                    }
                }
            }
            .padding(DesignSystem.Spacing.spacing24)
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

            Button {
                Task {
                    await viewModel.scanForSpecs()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan Branches")
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

                Text("Path relative to repository root where spec directories are located.")
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
}

// MARK: - Spec Row View

/// A single row in the spec list showing name, branch, phase, and availability.
struct SpecRowView: View {

    let spec: OpenSpecEntry

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

                    if spec.hasUnreadVersion {
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 8, height: 8)
                    }
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

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Phase Styling

    private var phaseIcon: some View {
        Image(systemName: SpecViewModel.phaseIcon(for: spec.phase))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(phaseTextColor)
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
            return Color(red: 1.0, green: 0.96, blue: 0.89)
        case .tasks:
            return Color(red: 0.89, green: 0.98, blue: 0.93)
        }
    }
}

#Preview {
    SpecListView(workspace: Workspace(name: "Preview Workspace"))
        .modelContainer(for: Workspace.self, inMemory: true)
}
