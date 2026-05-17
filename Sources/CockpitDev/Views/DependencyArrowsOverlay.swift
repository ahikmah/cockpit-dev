import SwiftUI

/// Overlay view that draws curved bezier dependency arrows between related tickets
/// on the Gantt chart. Arrows flow from blocker ticket to dependent ticket.
struct DependencyArrowsOverlay: View {
    let viewModel: GanttViewModel

    var body: some View {
        Canvas { context, size in
            let offsetX = viewModel.scrollOffset.x + viewModel.labelWidth
            let offsetY = viewModel.scrollOffset.y

            for (index, ticket) in viewModel.scheduledTickets.enumerated() {
                // Draw arrows from this ticket's blockers to this ticket
                for blocker in ticket.blockedBy {
                    guard let blockerIndex = viewModel.scheduledTickets.firstIndex(where: { $0.id == blocker.id }) else {
                        continue
                    }

                    let arrow = computeArrow(
                        fromTicketIndex: blockerIndex,
                        toTicketIndex: index,
                        fromTicket: blocker,
                        toTicket: ticket,
                        offsetX: offsetX,
                        offsetY: offsetY,
                        size: size
                    )

                    guard let arrow = arrow else { continue }

                    // Draw the bezier curve
                    context.stroke(
                        arrow.path,
                        with: .color(DesignSystem.Colors.textTertiary),
                        lineWidth: 1.5
                    )

                    // Draw arrowhead
                    context.fill(
                        arrow.arrowhead,
                        with: .color(DesignSystem.Colors.textTertiary)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Arrow Computation

    private struct ArrowGeometry {
        let path: Path
        let arrowhead: Path
    }

    /// Computes the bezier path and arrowhead for a dependency arrow.
    private func computeArrow(
        fromTicketIndex: Int,
        toTicketIndex: Int,
        fromTicket: Ticket,
        toTicket: Ticket,
        offsetX: CGFloat,
        offsetY: CGFloat,
        size: CGSize
    ) -> ArrowGeometry? {
        // Source: end of blocker bar (right edge, vertical center)
        let fromBarX = viewModel.barXPosition(for: fromTicket) + offsetX
        let fromBarWidth = viewModel.barWidth(for: fromTicket)
        let fromBarY = viewModel.barYPosition(forRow: fromTicketIndex) + offsetY

        let startX = fromBarX + fromBarWidth
        let startY = fromBarY + viewModel.rowHeight / 2

        // Destination: start of dependent bar (left edge, vertical center)
        let toBarX = viewModel.barXPosition(for: toTicket) + offsetX
        let toBarY = viewModel.barYPosition(forRow: toTicketIndex) + offsetY

        let endX = toBarX
        let endY = toBarY + viewModel.rowHeight / 2

        // Skip if both points are off-screen
        let visibleRect = CGRect(
            x: viewModel.labelWidth - 50,
            y: viewModel.headerHeight - 50,
            width: size.width + 100,
            height: size.height + 100
        )

        let startPoint = CGPoint(x: startX, y: startY)
        let endPoint = CGPoint(x: endX, y: endY)

        guard visibleRect.contains(startPoint) || visibleRect.contains(endPoint) else {
            return nil
        }

        // Compute bezier control points for a smooth curve
        let horizontalDistance = endX - startX
        let controlOffset = max(abs(horizontalDistance) * 0.3, 30)

        let control1 = CGPoint(x: startX + controlOffset, y: startY)
        let control2 = CGPoint(x: endX - controlOffset, y: endY)

        // Build the path
        var path = Path()
        path.move(to: startPoint)
        path.addCurve(to: endPoint, control1: control1, control2: control2)

        // Build arrowhead
        let arrowSize: CGFloat = 6
        let angle = atan2(endY - control2.y, endX - control2.x)

        var arrowhead = Path()
        arrowhead.move(to: endPoint)
        arrowhead.addLine(to: CGPoint(
            x: endX - arrowSize * cos(angle - .pi / 6),
            y: endY - arrowSize * sin(angle - .pi / 6)
        ))
        arrowhead.addLine(to: CGPoint(
            x: endX - arrowSize * cos(angle + .pi / 6),
            y: endY - arrowSize * sin(angle + .pi / 6)
        ))
        arrowhead.closeSubpath()

        return ArrowGeometry(path: path, arrowhead: arrowhead)
    }
}
