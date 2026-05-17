import SwiftUI
import SwiftData

/// High-performance Gantt chart view using Canvas for rendering.
/// Displays ticket timelines, dependency arrows, conflict highlighting,
/// and supports zoom, pan, and drag-to-reschedule interactions.
struct GanttChartView: View {
    @Bindable var viewModel: GanttViewModel
    @State private var viewSize: CGSize = .zero
    @State private var magnifyGestureActive: Bool = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Toolbar
                ganttToolbar

                Divider()

                // Main chart area
                ZStack(alignment: .topLeading) {
                    // Canvas-rendered chart
                    ganttCanvas(size: geometry.size)

                    // Dependency arrows overlay
                    DependencyArrowsOverlay(viewModel: viewModel)

                    // Sync indicator
                    if viewModel.isSyncing {
                        syncIndicator
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(DesignSystem.Spacing.spacing12)
                    }
                }
                .clipped()
                .gesture(panGesture)
                .gesture(magnifyGesture)
                .onScrollWheelGesture { event in
                    if event.modifierFlags.contains(.command) {
                        viewModel.handleZoomGesture(delta: -event.scrollingDeltaY)
                    }
                }

                // Unscheduled section
                if !viewModel.unscheduledTickets.isEmpty {
                    unscheduledSection
                }
            }
            .onAppear {
                viewSize = geometry.size
                if !viewModel.hasAutoScrolledToToday {
                    viewModel.scrollToToday(viewWidth: geometry.size.width)
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
            }
        }
        .alert("Sync Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }

    // MARK: - Toolbar

    private var ganttToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            Text("Timeline")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            // Zoom controls
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Button {
                    viewModel.zoomIn()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .disabled(viewModel.zoomLevel == .day)

                Text(viewModel.zoomLevel.label)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 50)

                Button {
                    viewModel.zoomOut()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .disabled(viewModel.zoomLevel == .quarter)
            }

            // Today button
            Button {
                viewModel.scrollToToday(viewWidth: viewSize.width)
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text("Today")
                        .font(DesignSystem.Typography.bodyRegular)
                }
                .foregroundColor(DesignSystem.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Canvas

    private func ganttCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let offsetX = viewModel.scrollOffset.x + viewModel.labelWidth
            let offsetY = viewModel.scrollOffset.y

            // Draw grid lines
            drawGridLines(context: &context, size: canvasSize, offsetX: offsetX, offsetY: offsetY)

            // Draw timeline header
            drawTimelineHeader(context: &context, size: canvasSize, offsetX: offsetX)

            // Draw today line
            drawTodayLine(context: &context, size: canvasSize, offsetX: offsetX, offsetY: offsetY)

            // Draw ticket bars
            drawTicketBars(context: &context, size: canvasSize, offsetX: offsetX, offsetY: offsetY)

            // Draw ticket labels on the left
            drawTicketLabels(context: &context, size: canvasSize, offsetY: offsetY)

        } symbols: {
            // Empty symbols - we draw everything directly on canvas
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(ticketDragGesture)
    }

    // MARK: - Canvas Drawing

    private func drawGridLines(context: inout GraphicsContext, size: CGSize, offsetX: CGFloat, offsetY: CGFloat) {
        let labels = viewModel.timelineLabels()

        for (date, _) in labels {
            let x = viewModel.xPosition(for: date) + offsetX
            guard x >= viewModel.labelWidth && x <= size.width else { continue }

            var path = Path()
            path.move(to: CGPoint(x: x, y: viewModel.headerHeight))
            path.addLine(to: CGPoint(x: x, y: size.height))

            context.stroke(
                path,
                with: .color(DesignSystem.Colors.border.opacity(0.5)),
                lineWidth: 0.5
            )
        }
    }

    private func drawTimelineHeader(context: inout GraphicsContext, size: CGSize, offsetX: CGFloat) {
        let labels = viewModel.timelineLabels()

        // Header background
        let headerRect = CGRect(x: 0, y: 0, width: size.width, height: viewModel.headerHeight)
        context.fill(Path(headerRect), with: .color(DesignSystem.Colors.background))

        // Header bottom border
        var borderPath = Path()
        borderPath.move(to: CGPoint(x: 0, y: viewModel.headerHeight))
        borderPath.addLine(to: CGPoint(x: size.width, y: viewModel.headerHeight))
        context.stroke(borderPath, with: .color(DesignSystem.Colors.border), lineWidth: 1)

        for (date, label) in labels {
            let x = viewModel.xPosition(for: date) + offsetX
            guard x >= viewModel.labelWidth - 20 && x <= size.width + 50 else { continue }

            let text = Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            context.draw(
                context.resolve(text),
                at: CGPoint(x: x + 4, y: viewModel.headerHeight / 2),
                anchor: .leading
            )
        }
    }

    private func drawTodayLine(context: inout GraphicsContext, size: CGSize, offsetX: CGFloat, offsetY: CGFloat) {
        let todayX = viewModel.todayXOffset + offsetX
        guard todayX >= viewModel.labelWidth && todayX <= size.width else { return }

        // Dashed line
        var path = Path()
        path.move(to: CGPoint(x: todayX, y: viewModel.headerHeight))
        path.addLine(to: CGPoint(x: todayX, y: size.height))

        context.stroke(
            path,
            with: .color(DesignSystem.Colors.accent),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )

        // "Today" label at top
        let todayLabel = Text("Today")
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.accent)

        context.draw(
            context.resolve(todayLabel),
            at: CGPoint(x: todayX, y: viewModel.headerHeight - 8),
            anchor: .bottom
        )
    }

    private func drawTicketBars(context: inout GraphicsContext, size: CGSize, offsetX: CGFloat, offsetY: CGFloat) {
        for (index, ticket) in viewModel.scheduledTickets.enumerated() {
            let barX = viewModel.barXPosition(for: ticket) + offsetX
            let barY = viewModel.barYPosition(forRow: index) + offsetY
            let barWidth = viewModel.barWidth(for: ticket)

            // Apply drag offset if this ticket is being dragged
            var adjustedBarX = barX
            if viewModel.draggingTicket?.id == ticket.id {
                adjustedBarX += viewModel.dragOffset
            }

            // Skip if not visible
            guard adjustedBarX + barWidth >= viewModel.labelWidth && adjustedBarX <= size.width else { continue }
            guard barY + viewModel.rowHeight >= viewModel.headerHeight && barY <= size.height else { continue }

            // Draw bar
            let barRect = CGRect(
                x: adjustedBarX,
                y: barY,
                width: barWidth,
                height: viewModel.rowHeight
            )

            let roundedPath = Path(roundedRect: barRect, cornerRadius: DesignSystem.Radius.small)

            // Fill
            let fillColor = viewModel.barColor(for: ticket)
            context.fill(roundedPath, with: .color(fillColor))

            // Border
            let borderColor = viewModel.barBorderColor(for: ticket)
            let borderWidth: CGFloat = viewModel.hasConflict(ticket) ? 2 : 1
            context.stroke(roundedPath, with: .color(borderColor), lineWidth: borderWidth)

            // Title text inside bar (if wide enough)
            if barWidth > 60 {
                let titleText = Text(String(ticket.title.prefix(30)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                context.draw(
                    context.resolve(titleText),
                    at: CGPoint(x: adjustedBarX + 8, y: barY + viewModel.rowHeight / 2),
                    anchor: .leading
                )
            }
        }
    }

    private func drawTicketLabels(context: inout GraphicsContext, size: CGSize, offsetY: CGFloat) {
        // Label background
        let labelBgRect = CGRect(x: 0, y: viewModel.headerHeight, width: viewModel.labelWidth, height: size.height - viewModel.headerHeight)
        context.fill(Path(labelBgRect), with: .color(DesignSystem.Colors.background))

        // Right border for label area
        var borderPath = Path()
        borderPath.move(to: CGPoint(x: viewModel.labelWidth, y: viewModel.headerHeight))
        borderPath.addLine(to: CGPoint(x: viewModel.labelWidth, y: size.height))
        context.stroke(borderPath, with: .color(DesignSystem.Colors.border), lineWidth: 1)

        for (index, ticket) in viewModel.scheduledTickets.enumerated() {
            let y = viewModel.barYPosition(forRow: index) + offsetY

            guard y + viewModel.rowHeight >= viewModel.headerHeight && y <= size.height else { continue }

            let truncatedTitle = String(ticket.title.prefix(25))
            let labelText = Text(truncatedTitle)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            context.draw(
                context.resolve(labelText),
                at: CGPoint(x: DesignSystem.Spacing.spacing8, y: y + viewModel.rowHeight / 2),
                anchor: .leading
            )
        }
    }

    // MARK: - Unscheduled Section

    private var unscheduledSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            Divider()

            HStack {
                Text("Unscheduled")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("(\(viewModel.unscheduledTickets.count))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing16)
            .padding(.top, DesignSystem.Spacing.spacing8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(viewModel.unscheduledTickets, id: \.id) { ticket in
                        UnscheduledTicketChip(ticket: ticket, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
            }
            .frame(height: 44)
            .padding(.bottom, DesignSystem.Spacing.spacing8)
        }
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                viewModel.pan(by: CGSize(
                    width: value.translation.width / 10,
                    height: value.translation.height / 10
                ))
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !magnifyGestureActive {
                    magnifyGestureActive = true
                }
            }
            .onEnded { value in
                let scale = value.magnification
                if scale > 1.2 {
                    viewModel.zoomIn()
                } else if scale < 0.8 {
                    viewModel.zoomOut()
                }
                magnifyGestureActive = false
            }
    }

    private var ticketDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let location = value.startLocation
                let offsetY = viewModel.scrollOffset.y
                let offsetX = viewModel.scrollOffset.x + viewModel.labelWidth

                // Determine which ticket is being dragged
                if viewModel.draggingTicket == nil {
                    for (index, ticket) in viewModel.scheduledTickets.enumerated() {
                        let barX = viewModel.barXPosition(for: ticket) + offsetX
                        let barY = viewModel.barYPosition(forRow: index) + offsetY
                        let barWidth = viewModel.barWidth(for: ticket)

                        let barRect = CGRect(x: barX, y: barY, width: barWidth, height: viewModel.rowHeight)
                        if barRect.contains(location) {
                            viewModel.beginDrag(ticket: ticket)
                            break
                        }
                    }
                }

                if viewModel.draggingTicket != nil {
                    viewModel.updateDrag(offset: value.translation.width)
                }
            }
            .onEnded { _ in
                if viewModel.draggingTicket != nil {
                    Task {
                        await viewModel.endDrag()
                    }
                }
            }
    }

    // MARK: - Sync Indicator

    private var syncIndicator: some View {
        HStack(spacing: DesignSystem.Spacing.spacing6) {
            ProgressView()
                .controlSize(.small)
            Text("Syncing…")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing6)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.Radius.small)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Unscheduled Ticket Chip

/// A compact chip view for tickets without dates in the unscheduled section.
struct UnscheduledTicketChip: View {
    let ticket: Ticket
    let viewModel: GanttViewModel

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing6) {
            Circle()
                .fill(viewModel.barColor(for: ticket))
                .frame(width: 8, height: 8)

            Text(String(ticket.title.prefix(30)))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(1)

            if let sp = ticket.storyPoints {
                Text("\(sp)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.border.opacity(0.5))
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
        .padding(.vertical, DesignSystem.Spacing.spacing6)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.Radius.small)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .stroke(
                    viewModel.hasConflict(ticket) ? DesignSystem.Colors.danger : DesignSystem.Colors.border,
                    lineWidth: viewModel.hasConflict(ticket) ? 2 : 1
                )
        )
    }
}

// MARK: - Scroll Wheel Gesture Modifier

/// A view modifier that captures scroll wheel events for zoom handling.
struct ScrollWheelGestureModifier: ViewModifier {
    let handler: (NSEvent) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelView(handler: handler)
        )
    }
}

/// NSView wrapper to capture scroll wheel events.
struct ScrollWheelView: NSViewRepresentable {
    let handler: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

class ScrollWheelNSView: NSView {
    var handler: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        handler?(event)
    }
}

extension View {
    func onScrollWheelGesture(handler: @escaping (NSEvent) -> Void) -> some View {
        modifier(ScrollWheelGestureModifier(handler: handler))
    }
}
