import SwiftUI

/// A reusable section view for displaying and managing ticket dependencies.
/// Shows blockers and blocked tickets with search-and-link capability.
struct DependencySection: View {

    let ticket: Ticket
    @Bindable var viewModel: DependencyViewModel
    let isEditing: Bool

    @State private var showAddBlocker: Bool = false
    @State private var blockerSearchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            // Section header
            HStack {
                Text("Dependencies")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                if isEditing {
                    Button {
                        showAddBlocker.toggle()
                        if !showAddBlocker {
                            blockerSearchText = ""
                            viewModel.searchResults = []
                        }
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.spacing4) {
                            Image(systemName: "plus.circle")
                            Text("Add Blocker")
                        }
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Blocked By section
            if !ticket.blockedBy.isEmpty {
                blockedBySection
            }

            // Blocks section
            if !ticket.blocks.isEmpty {
                blocksSection
            }

            // Empty state
            if ticket.blockedBy.isEmpty && ticket.blocks.isEmpty && !showAddBlocker {
                Text("No dependencies defined.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            // Add blocker search UI
            if showAddBlocker {
                addBlockerSearchView
            }

            // Ticket conflicts
            if !viewModel.ticketConflicts.isEmpty {
                conflictsIndicator
            }
        }
    }

    // MARK: - Blocked By

    private var blockedBySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Blocked By")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            ForEach(ticket.blockedBy, id: \.id) { blocker in
                dependencyRow(ticket: blocker, isBlocker: true)
            }
        }
    }

    // MARK: - Blocks

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Blocks")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            ForEach(ticket.blocks, id: \.id) { blocked in
                dependencyRow(ticket: blocked, isBlocker: false)
            }
        }
    }

    // MARK: - Dependency Row

    private func dependencyRow(ticket linkedTicket: Ticket, isBlocker: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: isBlocker ? "hand.raised.fill" : "arrow.right.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(isBlocker ? DesignSystem.Colors.danger : DesignSystem.Colors.warning)

            Text(linkedTicket.title)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(linkedTicket.status.rawValue)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            if isEditing {
                Button {
                    if isBlocker {
                        viewModel.removeDependency(dependent: ticket, blocker: linkedTicket)
                    } else {
                        viewModel.removeDependency(dependent: linkedTicket, blocker: ticket)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
        .padding(.vertical, DesignSystem.Spacing.spacing6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .fill(DesignSystem.Colors.accentSoft.opacity(0.5))
        )
    }

    // MARK: - Add Blocker Search

    private var addBlockerSearchView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Search field
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                TextField("Search tickets to link as blocker...", text: $blockerSearchText)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.bodyRegular)
                    .onChange(of: blockerSearchText) { _, newValue in
                        viewModel.searchTickets(query: newValue, excluding: ticket)
                    }

                if !blockerSearchText.isEmpty {
                    Button {
                        blockerSearchText = ""
                        viewModel.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )

            // Search results
            if !viewModel.searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(viewModel.searchResults.prefix(10), id: \.id) { result in
                        Button {
                            let success = viewModel.addDependency(dependent: ticket, blocker: result)
                            if success {
                                blockerSearchText = ""
                                viewModel.searchResults = []
                            }
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.spacing8) {
                                Image(systemName: "ticket")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DesignSystem.Colors.accent)

                                Text(result.title)
                                    .font(DesignSystem.Typography.bodyRegular)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                Text(result.status.rawValue)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.spacing12)
                            .padding(.vertical, DesignSystem.Spacing.spacing8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if result.id != viewModel.searchResults.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                        .fill(DesignSystem.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Conflicts Indicator

    private var conflictsIndicator: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.danger)
                Text("Conflicts Detected")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.danger)
            }

            ForEach(viewModel.ticketConflicts) { conflict in
                Text(conflict.description)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.leading, DesignSystem.Spacing.spacing16)
            }
        }
        .padding(DesignSystem.Spacing.spacing8)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .fill(DesignSystem.Colors.dangerSoft)
        )
    }
}

// MARK: - Status Conflict Warning Dialog

/// A dialog shown when a status change would create a dependency conflict.
struct StatusConflictWarningDialog: View {

    let conflictDescription: String
    let onProceed: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.spacing20) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.Colors.warning)

            // Title
            Text("Dependency Conflict Warning")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            // Description
            Text(conflictDescription)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Actions
            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, DesignSystem.Spacing.spacing20)
                        .padding(.vertical, DesignSystem.Spacing.spacing8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onProceed()
                } label: {
                    Text("Proceed Anyway")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignSystem.Spacing.spacing20)
                        .padding(.vertical, DesignSystem.Spacing.spacing8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .fill(DesignSystem.Colors.warning)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.spacing32)
        .frame(width: 420)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl))
    }
}
