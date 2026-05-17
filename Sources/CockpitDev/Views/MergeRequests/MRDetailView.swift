import SwiftUI
import SwiftData

// MARK: - MR Detail View

/// Displays detailed information about a merge request with Diff, Discussion, and Pipeline tabs.
struct MRDetailView: View {

    let mr: MergeRequestEntry
    @Bindable var viewModel: MergeRequestViewModel

    var body: some View {
        VStack(spacing: 0) {
            // MR Header
            mrHeader

            Divider()

            // Tab selector
            detailTabBar

            Divider()

            // Tab content
            detailTabContent

            // Action bar (Approve + Merge)
            if mr.state == .opened {
                Divider()
                actionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
        .task {
            await viewModel.loadMRDetail(mr)
        }
        .alert("Pipeline Failures Detected", isPresented: $viewModel.showPipelineWarning) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelMerge()
            }
            Button("Merge Anyway", role: .destructive) {
                Task {
                    await viewModel.confirmMergeWithPipelineFailure()
                }
            }
        } message: {
            Text("This merge request has unresolved pipeline failures. Are you sure you want to proceed with the merge?")
        }
    }

    // MARK: - Header

    private var mrHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Title
            Text(mr.title)
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(3)

            // Branch info
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                branchLabel(mr.sourceBranch)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                branchLabel(mr.targetBranch)

                Spacer()

                // State badge
                stateBadge
            }

            // Meta info
            HStack(spacing: DesignSystem.Spacing.spacing16) {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(mr.authorUsername)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                if let repoName = mr.repository?.name {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        Text(repoName)
                            .font(DesignSystem.Typography.bodyRegular)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                Text("Created \(MergeRequestViewModel.timeSinceCreation(mr.createdAt))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            // Error display
            if let error = viewModel.mergeError {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.danger)
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.danger)
                }
                .padding(DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }

            // Merge success
            if viewModel.mergeSuccess {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("Merge request successfully merged!")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.success)
                }
                .padding(DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Tab Bar

    private var detailTabBar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing24) {
            ForEach(MRDetailTab.allCases) { tab in
                Button {
                    withAnimation(DesignSystem.Motion.fast) {
                        viewModel.selectedDetailTab = tab
                    }
                } label: {
                    VStack(spacing: DesignSystem.Spacing.spacing4) {
                        HStack(spacing: DesignSystem.Spacing.spacing4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: viewModel.selectedDetailTab == tab ? .medium : .regular))
                            Text(tab.rawValue)
                                .font(DesignSystem.Typography.bodyMedium)
                        }
                        .foregroundStyle(
                            viewModel.selectedDetailTab == tab
                                ? DesignSystem.Colors.textPrimary
                                : DesignSystem.Colors.textSecondary
                        )
                        .padding(.bottom, DesignSystem.Spacing.spacing4)

                        Rectangle()
                            .fill(viewModel.selectedDetailTab == tab ? DesignSystem.Colors.accent : Color.clear)
                            .frame(height: 2)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var detailTabContent: some View {
        if viewModel.isLoadingDetail {
            VStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading...")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.detailError {
            VStack(spacing: DesignSystem.Spacing.spacing12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text(error)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task { await viewModel.loadMRDetail(mr) }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewModel.selectedDetailTab {
            case .diff:
                DiffView(files: viewModel.diffFiles, viewModel: viewModel)
            case .discussion:
                DiscussionView(
                    discussions: viewModel.discussions,
                    viewModel: viewModel
                )
            case .pipeline:
                PipelineTabView(mr: mr)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Draft comments indicator
            if !viewModel.draftComments.isEmpty {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.warning)
                    Text("\(viewModel.draftComments.count) draft\(viewModel.draftComments.count == 1 ? "" : "s")")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
            }

            Spacer()

            // Approve + Merge button
            Button {
                Task {
                    await viewModel.approveAndMerge()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    if viewModel.isMerging {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, weight: .medium))
                    }
                    Text("Approve & Merge")
                        .font(DesignSystem.Typography.bodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.success)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isMerging || viewModel.mergeSuccess)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Components

    private func branchLabel(_ branch: String) -> some View {
        Text(branch)
            .font(DesignSystem.Typography.monospace)
            .foregroundStyle(DesignSystem.Colors.accent)
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(DesignSystem.Colors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private var stateBadge: some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(mr.state.rawValue.capitalized)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(stateColor)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
        .padding(.vertical, DesignSystem.Spacing.spacing4)
        .background(stateColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private var stateColor: Color {
        switch mr.state {
        case .opened: return DesignSystem.Colors.success
        case .merged: return DesignSystem.Colors.accent
        case .closed: return DesignSystem.Colors.danger
        }
    }
}

// MARK: - Pipeline Tab View

/// Displays pipeline status information for the merge request.
struct PipelineTabView: View {

    let mr: MergeRequestEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                if let status = mr.pipelineStatus {
                    pipelineStatusCard(status)
                } else {
                    noPipelineView
                }
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pipelineStatusCard(_ status: PipelineStatus) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                pipelineIcon(status)
                    .font(.system(size: 20))
                    .foregroundStyle(pipelineColor(status))

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                    Text("Pipeline Status")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text(status.rawValue.capitalized)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(pipelineColor(status))
                }

                Spacer()
            }

            if status == .failed {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.danger)
                    Text("Pipeline has failures. Merging will require explicit confirmation.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.danger)
                }
                .padding(DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
        }
        .padding(DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    private var noPipelineView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Pipeline")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("No CI/CD pipeline is associated with this merge request.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.spacing32)
    }

    private func pipelineIcon(_ status: PipelineStatus) -> Image {
        switch status {
        case .success: return Image(systemName: "checkmark.circle.fill")
        case .failed: return Image(systemName: "xmark.circle.fill")
        case .running: return Image(systemName: "play.circle.fill")
        case .pending: return Image(systemName: "clock.fill")
        case .canceled: return Image(systemName: "minus.circle.fill")
        }
    }

    private func pipelineColor(_ status: PipelineStatus) -> Color {
        switch status {
        case .success: return DesignSystem.Colors.success
        case .failed: return DesignSystem.Colors.danger
        case .running: return DesignSystem.Colors.accent
        case .pending: return DesignSystem.Colors.warning
        case .canceled: return DesignSystem.Colors.textTertiary
        }
    }
}
