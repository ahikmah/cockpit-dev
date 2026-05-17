import SwiftUI

// MARK: - Discussion View

/// Displays all discussion comments (inline and general) for a merge request.
/// Supports posting general comments and retrying draft comments.
struct DiscussionView: View {

    let discussions: [GitLabDiscussion]
    @Bindable var viewModel: MergeRequestViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Discussion list
            if discussions.isEmpty && viewModel.draftComments.isEmpty {
                emptyDiscussionView
            } else {
                discussionList
            }

            Divider()

            // Comment input
            commentInputSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Discussion List

    private var discussionList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.spacing12) {
                // Draft comments (pending retry)
                if !viewModel.draftComments.isEmpty {
                    draftCommentsSection
                }

                // Existing discussions
                ForEach(discussions) { discussion in
                    DiscussionThreadView(discussion: discussion)
                }
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
    }

    // MARK: - Draft Comments Section

    private var draftCommentsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            HStack(spacing: DesignSystem.Spacing.spacing6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text("Unsent Comments")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }

            ForEach(viewModel.draftComments) { draft in
                DraftCommentCard(
                    draft: draft,
                    onRetry: {
                        Task { await viewModel.retryDraftComment(draft) }
                    },
                    onDiscard: {
                        viewModel.discardDraftComment(draft)
                    }
                )
            }
        }
    }

    // MARK: - Comment Input

    private var commentInputSection: some View {
        VStack(spacing: DesignSystem.Spacing.spacing8) {
            // Error message
            if let error = viewModel.commentError {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.danger)
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.danger)
                        .lineLimit(2)
                }
            }

            HStack(alignment: .bottom, spacing: DesignSystem.Spacing.spacing8) {
                TextField("Write a comment...", text: $viewModel.commentText, axis: .vertical)
                    .font(DesignSystem.Typography.bodyRegular)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .padding(DesignSystem.Spacing.spacing8)
                    .background(DesignSystem.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )

                Button {
                    Task { await viewModel.submitGeneralComment() }
                } label: {
                    if viewModel.isSubmittingComment {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? DesignSystem.Colors.textTertiary
                                    : DesignSystem.Colors.accent
                            )
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                    }
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isSubmittingComment
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Empty State

    private var emptyDiscussionView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Discussion Yet")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Start the conversation by posting a comment below.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Discussion Thread View

/// Renders a single discussion thread with all its notes.
struct DiscussionThreadView: View {

    let discussion: GitLabDiscussion

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Inline position indicator
            if let firstNote = discussion.notes.first,
               let position = firstNote.position {
                inlinePositionBadge(position)
            }

            // Notes in the thread
            ForEach(discussion.notes) { note in
                if !note.system {
                    NoteView(note: note)
                }
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    private func inlinePositionBadge(_ position: GitLabNotePosition) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.accent)

            if let path = position.newPath {
                Text(path)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .lineLimit(1)
            }

            if let line = position.newLine {
                Text("line \(line)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing6)
        .padding(.vertical, DesignSystem.Spacing.spacing2)
        .background(DesignSystem.Colors.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }
}

// MARK: - Note View

/// Renders a single note (comment) in a discussion.
struct NoteView: View {

    let note: GitLabNote

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            // Author and timestamp
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                // Avatar placeholder
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(note.author.name.prefix(1)).uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.accent)
                    )

                Text(note.author.name)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(formatDate(note.createdAt))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                Spacer()

                // Resolved indicator
                if note.resolvable {
                    if note.resolved == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.Colors.success)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
            }

            // Comment body
            Text(note.body)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
        }
        .padding(.vertical, DesignSystem.Spacing.spacing4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Draft Comment Card

/// Displays a draft comment that failed to send, with retry and discard options.
struct DraftCommentCard: View {

    let draft: DraftComment
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            // Position indicator if inline
            if draft.position != nil {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.warning)
                    Text("Inline comment")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
            }

            // Comment body
            Text(draft.body)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(3)

            // Actions
            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Text("Failed to send")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.danger)

                if draft.retryCount > 0 {
                    Text("(\(draft.retryCount) retries)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }

                Spacer()

                Button("Discard", action: onDiscard)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .buttonStyle(.plain)

                Button("Retry", action: onRetry)
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.warning.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .stroke(DesignSystem.Colors.warning.opacity(0.3), lineWidth: 1)
        )
    }
}
