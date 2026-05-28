import SwiftUI

/// Overlay view that draws curved bezier dependency arrows between related tickets
/// on the Gantt chart. Arrows flow from blocker ticket to dependent ticket.
struct DependencyArrowsOverlay: View {
    let viewModel: GanttViewModel
    let focusedTicket: Ticket?

    var body: some View {
        Canvas { context, size in
            guard let focusedTicket else { return }

            let offsetX = viewModel.scrollOffset.x + viewModel.labelWidth
            let offsetY = viewModel.scrollOffset.y

            for blocker in focusedTicket.blockedBy {
                drawArrow(
                    context: &context,
                    fromTicket: blocker,
                    toTicket: focusedTicket,
                    offsetX: offsetX,
                    offsetY: offsetY,
                    size: size
                )
            }

            for blocked in focusedTicket.blocks {
                drawArrow(
                    context: &context,
                    fromTicket: focusedTicket,
                    toTicket: blocked,
                    offsetX: offsetX,
                    offsetY: offsetY,
                    size: size
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Arrow Computation

    private struct ArrowGeometry {
        let path: Path
        let arrowhead: Path
    }

    private func drawArrow(
        context: inout GraphicsContext,
        fromTicket: Ticket,
        toTicket: Ticket,
        offsetX: CGFloat,
        offsetY: CGFloat,
        size: CGSize
    ) {
        guard let arrow = computeArrow(
            fromTicket: fromTicket,
            toTicket: toTicket,
            offsetX: offsetX,
            offsetY: offsetY,
            size: size
        ) else {
            return
        }

        context.stroke(
            arrow.path,
            with: .color(DesignSystem.Colors.accent.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round, dash: [5, 5])
        )

        context.fill(
            arrow.arrowhead,
            with: .color(DesignSystem.Colors.accent.opacity(0.65))
        )
    }

    /// Computes the bezier path and arrowhead for a dependency arrow.
    private func computeArrow(
        fromTicket: Ticket,
        toTicket: Ticket,
        offsetX: CGFloat,
        offsetY: CGFloat,
        size: CGSize
    ) -> ArrowGeometry? {
        guard let fromFrame = ticketFrame(for: fromTicket, offsetX: offsetX, offsetY: offsetY),
              let toFrame = ticketFrame(for: toTicket, offsetX: offsetX, offsetY: offsetY) else {
            return nil
        }

        // Source: end of blocker bar (right edge, vertical center)
        let startX = fromFrame.maxX
        let startY = fromFrame.midY
        // Destination: start of dependent bar (left edge, vertical center)
        let endX = toFrame.minX
        let endY = toFrame.midY

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
        let controlOffset = min(max(abs(horizontalDistance) * 0.24, 44), 140)

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

    private func ticketFrame(for ticket: Ticket, offsetX: CGFloat, offsetY: CGFloat) -> CGRect? {
        for (rowIndex, row) in viewModel.timelineRows.enumerated() {
            guard row.tickets.contains(where: { $0.id == ticket.id }) else { continue }
            return CGRect(
                x: viewModel.barXPosition(for: ticket) + offsetX,
                y: viewModel.barYPosition(for: ticket, in: row, rowIndex: rowIndex) + offsetY,
                width: max(viewModel.barWidth(for: ticket), 12),
                height: viewModel.rowHeight
            )
        }
        return nil
    }
}
