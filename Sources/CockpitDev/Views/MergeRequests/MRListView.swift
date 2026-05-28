import SwiftUI
import SwiftData

// MARK: - MR List View

/// Displays all open merge requests across workspace repositories.
/// Shows title, author, source/target branch, pipeline status, and time since creation.
struct MRListView: View {

    let workspace: Workspace
    let gitLabAPIClient: GitLabAPIClient
    @State private var viewModel = MergeRequestViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if viewModel.isLoadingList && viewModel.mergeRequests.isEmpty {
                loadingView
            } else if let error = viewModel.listError, viewModel.mergeRequests.isEmpty {
                errorView(error)
            } else if viewModel.mergeRequests.isEmpty {
                emptyStateView
            } else {
                mrListContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
        .task {
            configureViewModel()
            await viewModel.fetchMergeRequests()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Merge Requests")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("\(viewModel.mergeRequests.count) open")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.fetchMergeRequests()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .rotationEffect(.degrees(viewModel.isLoadingList ? 360 : 0))
                    .animation(
                        viewModel.isLoadingList
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isLoadingList
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoadingList)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing16)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - List Content

    private var mrListContent: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(viewModel.mergeRequests, id: \.id) { mr in
                        NavigationLink(value: mr.id) {
                            MRCardView(mr: mr)
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing24)
                .padding(.vertical, DesignSystem.Spacing.spacing16)
            }
            .navigationDestination(for: UUID.self) { mrId in
                if let mr = viewModel.mergeRequests.first(where: { $0.id == mrId }) {
                    MRDetailView(mr: mr, viewModel: viewModel)
                }
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading merge requests...")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.warning)

            Text("Failed to load merge requests")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(error)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Retry") {
                Task {
                    await viewModel.fetchMergeRequests()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Open Merge Requests")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Open merge requests across your workspace repositories will appear here.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func configureViewModel() {
        viewModel.configure(apiClient: gitLabAPIClient, modelContext: modelContext, workspace: workspace)
    }
}

// MARK: - MR Card View

/// A card displaying a single merge request in the list.
struct MRCardView: View {

    let mr: MergeRequestEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Title row
            HStack(alignment: .top) {
                Text(mr.title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)

                Spacer()

                pipelineStatusBadge
            }

            // Branch info
            HStack(spacing: DesignSystem.Spacing.spacing6) {
                branchLabel(mr.sourceBranch)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                branchLabel(mr.targetBranch)
            }

            // Meta row
            HStack(spacing: DesignSystem.Spacing.spacing12) {
                // Author
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(mr.authorUsername)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                // Repository name
                if let repoName = mr.repository?.name {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        Text(repoName)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                Spacer()

                // Time since creation
                Text(MergeRequestViewModel.timeSinceCreation(mr.createdAt))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
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

    @ViewBuilder
    private var pipelineStatusBadge: some View {
        if let status = mr.pipelineStatus {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Circle()
                    .fill(pipelineColor(status))
                    .frame(width: 8, height: 8)
                Text(status.rawValue.capitalized)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(pipelineColor(status))
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(pipelineColor(status).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
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
