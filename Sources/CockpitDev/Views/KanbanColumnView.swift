import SwiftUI

/// A single column in the Kanban board displaying a vertical list of ticket cards.
/// Shows column header with name and ticket count, and supports drag-and-drop.
struct KanbanColumnView: View {
    let columnName: String
    let tickets: [Ticket]
    let isDropTarget: Bool
    let viewModel: KanbanViewModel

    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column Header
            columnHeader

            // Ticket Cards List
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(tickets, id: \.id) { ticket in
                        TicketCardView(
                            ticket: ticket,
                            isUnmapped: viewModel.isUnmappedStatus(ticket)
                        )
                        .onDrag {
                            viewModel.beginDrag(ticket: ticket, fromColumn: columnName)
                            return NSItemProvider(object: ticket.id.uuidString as NSString)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing8)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
            }
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
        .background(dropZoneBackground)
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(dropZoneOverlay)
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: isTargeted) { _, newValue in
            viewModel.updateDropTarget(newValue ? columnName : nil)
        }
    }

    // MARK: - Column Header

    private var columnHeader: some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Text(columnName)
                .font(DesignSystem.Typography.headingSmall)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // Ticket count badge
            Text("\(tickets.count)")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundColor(DesignSystem.Colors.textTertiary)
                .padding(.horizontal, DesignSystem.Spacing.spacing6)
                .padding(.vertical, DesignSystem.Spacing.spacing2)
                .background(DesignSystem.Colors.background)
                .cornerRadius(DesignSystem.Radius.small)

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
    }

    // MARK: - Drop Zone Styling

    @ViewBuilder
    private var dropZoneBackground: some View {
        if isDropTarget || isTargeted {
            DesignSystem.Colors.accentSoft
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var dropZoneOverlay: some View {
        if isDropTarget || isTargeted {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .strokeBorder(
                    DesignSystem.Colors.accent,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        } else {
            EmptyView()
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard item != nil else { return }
            Task { @MainActor in
                await viewModel.dropTicket(on: columnName)
            }
        }

        return true
    }
}
