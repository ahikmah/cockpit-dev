import SwiftUI

/// A card view representing a single ticket on the Kanban board.
/// Displays title (truncated at 80 chars), assignee, story points badge, and up to 3 labels.
struct TicketCardView: View {
    let ticket: Ticket
    var isUnmapped: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Title
            Text(truncatedTitle)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Labels (up to 3)
            if !displayLabels.isEmpty {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    ForEach(displayLabels, id: \.self) { label in
                        LabelBadge(text: label)
                    }
                    if ticket.labels.count > 3 {
                        Text("+\(ticket.labels.count - 3)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
            }

            // Bottom row: assignee + story points
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                // Assignee
                if let assignee = ticket.assignee {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        AvatarView(name: assignee.displayName, size: 20)
                        Text(assignee.displayName)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Story Points badge
                if let sp = ticket.storyPoints {
                    StoryPointsBadge(points: sp)
                }

                // Unmapped status indicator
                if isUnmapped {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.warning)
                        .help("Status does not match any configured column")
                }
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // MARK: - Computed Properties

    /// Title truncated at 80 characters.
    private var truncatedTitle: String {
        if ticket.title.count > AppConstants.maxTicketTitleDisplayLength {
            return String(ticket.title.prefix(AppConstants.maxTicketTitleDisplayLength)) + "…"
        }
        return ticket.title
    }

    /// Up to 3 labels to display.
    private var displayLabels: [String] {
        Array(ticket.labels.prefix(3))
    }
}

// MARK: - Supporting Views

/// A small colored badge for a label.
struct LabelBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.accent)
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(DesignSystem.Colors.accentSoft)
            .cornerRadius(DesignSystem.Radius.small)
            .lineLimit(1)
    }
}

/// A circular avatar view with initials.
struct AvatarView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.accentSoft)
                .frame(width: size, height: size)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// A badge showing story points value.
struct StoryPointsBadge: View {
    let points: Int

    var body: some View {
        Text("\(points) SP")
            .font(DesignSystem.Typography.captionMedium)
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(DesignSystem.Colors.background)
            .cornerRadius(DesignSystem.Radius.small)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                    .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
            )
    }
}
