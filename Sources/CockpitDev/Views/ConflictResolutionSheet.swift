import SwiftUI

/// Sheet for resolving sync conflicts between local and remote ticket versions.
/// Displays both versions side-by-side and allows the user to choose which to keep.
struct ConflictResolutionSheet: View {

    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: TicketManagementViewModel

    /// The local version of the ticket.
    let localSnapshot: TicketSnapshot

    /// The remote version of the ticket (from GitLab).
    let remoteSnapshot: TicketSnapshot

    @State private var selectedSide: ConflictSide? = nil

    enum ConflictSide {
        case local
        case remote
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conflictContent
            Divider()
            footer
        }
        .frame(width: 720, height: 550)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .font(.system(size: 20))

                Text("Conflict Detected")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("This ticket was modified both locally and on GitLab. Choose which version to keep.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.spacing24)
    }

    // MARK: - Conflict Content

    private var conflictContent: some View {
        ScrollView {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing16) {
                // Local version
                versionCard(
                    title: "Local Version",
                    icon: "laptopcomputer",
                    snapshot: localSnapshot,
                    isSelected: selectedSide == .local,
                    side: .local
                )

                // Remote version
                versionCard(
                    title: "Remote Version (GitLab)",
                    icon: "cloud",
                    snapshot: remoteSnapshot,
                    isSelected: selectedSide == .remote,
                    side: .remote
                )
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
    }

    // MARK: - Version Card

    private func versionCard(
        title: String,
        icon: String,
        snapshot: TicketSnapshot,
        isSelected: Bool,
        side: ConflictSide
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            // Card header
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)

                Text(title)
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
                conflictField(label: "Title", value: snapshot.title, isDifferent: localSnapshot.title != remoteSnapshot.title)
                conflictField(label: "Status", value: snapshot.status.displayName, isDifferent: localSnapshot.status != remoteSnapshot.status)

                if let sp = snapshot.storyPoints {
                    conflictField(label: "Story Points", value: "\(sp)", isDifferent: localSnapshot.storyPoints != remoteSnapshot.storyPoints)
                }

                if let desc = snapshot.descriptionText, !desc.isEmpty {
                    conflictField(
                        label: "Description",
                        value: String(desc.prefix(100)) + (desc.count > 100 ? "..." : ""),
                        isDifferent: localSnapshot.descriptionText != remoteSnapshot.descriptionText
                    )
                }

                if !snapshot.labels.isEmpty {
                    conflictField(
                        label: "Labels",
                        value: snapshot.labels.joined(separator: ", "),
                        isDifferent: localSnapshot.labels != remoteSnapshot.labels
                    )
                }

                conflictField(
                    label: "Updated",
                    value: snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened),
                    isDifferent: true
                )
            }
        }
        .padding(DesignSystem.Spacing.spacing16)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(
                    isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.border,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .onTapGesture {
            withAnimation(DesignSystem.Motion.fast) {
                selectedSide = side
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Conflict Field

    private func conflictField(label: String, value: String, isDifferent: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text(value)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.spacing6)
                .padding(.vertical, DesignSystem.Spacing.spacing2)
                .background(
                    isDifferent
                        ? RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.warning.opacity(0.1))
                        : nil
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .font(DesignSystem.Typography.bodyMedium)

            Spacer()

            Button {
                guard let side = selectedSide else { return }
                viewModel.resolveConflict(keepLocal: side == .local)
                dismiss()
            } label: {
                Text(resolveButtonText)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignSystem.Spacing.spacing16)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                            .fill(selectedSide != nil ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedSide == nil)
        }
        .padding(DesignSystem.Spacing.spacing24)
    }

    private var resolveButtonText: String {
        switch selectedSide {
        case .local:
            return "Keep Local"
        case .remote:
            return "Keep Remote"
        case nil:
            return "Select a Version"
        }
    }
}
