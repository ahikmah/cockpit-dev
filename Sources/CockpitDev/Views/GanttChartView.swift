import SwiftUI
import SwiftData

/// High-performance Gantt chart view using Canvas for rendering.
/// Displays ticket timelines, dependency arrows, conflict highlighting,
/// and supports zoom, pan, and drag-to-reschedule interactions.
struct GanttChartView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: GanttViewModel
    @State private var viewSize: CGSize = .zero
    @State private var magnifyGestureActive: Bool = false
    @State private var hoveredTicket: Ticket?
    @State private var hoverLocation: CGPoint = .zero
    @State private var selectedDetailTicket: Ticket?
    @State private var ticketDetailViewModel = TicketManagementViewModel()
    @State private var dependencyViewModel = DependencyViewModel()

    var body: some View {
        ZStack(alignment: .trailing) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Toolbar
                    ganttToolbar

                    Divider()

                    // Main chart area
                    GeometryReader { chartGeometry in
                        ZStack(alignment: .topLeading) {
                            // Canvas-rendered chart
                            ganttCanvas(size: chartGeometry.size)

                            // Focused dependency overlay, shown only for the hovered/selected ticket.
                            DependencyArrowsOverlay(viewModel: viewModel, focusedTicket: dependencyFocusTicket)

                            // Sync indicator
                            if viewModel.isSyncing {
                                syncIndicator
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                    .padding(DesignSystem.Spacing.spacing12)
                            }

                            if let hoveredTicket, selectedDetailTicket == nil {
                                TimelineTicketHoverCard(ticket: hoveredTicket)
                                    .position(hoverCardPosition(in: chartGeometry.size))
                                    .transition(.opacity)
                                    .allowsHitTesting(false)
                            }
                        }
                        .clipped()
                        .gesture(panGesture)
                        .gesture(magnifyGesture)
                        .onScrollWheelGesture { event in
                            if event.modifierFlags.contains(.command) {
                                viewModel.handleZoomGesture(delta: -event.scrollingDeltaY)
                            } else {
                                viewModel.pan(
                                    by: viewModel.panTranslationForScrollWheel(
                                        scrollingDeltaX: event.scrollingDeltaX,
                                        scrollingDeltaY: event.scrollingDeltaY,
                                        isShiftPressed: event.modifierFlags.contains(.shift)
                                    ),
                                    viewportSize: chartGeometry.size
                                )
                            }
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverLocation = location
                                hoveredTicket = viewModel.ticket(at: location)
                            case .ended:
                                hoveredTicket = nil
                            }
                        }
                        .onAppear {
                            viewSize = chartGeometry.size
                        }
                        .onChange(of: chartGeometry.size) { _, newSize in
                            viewSize = newSize
                        }
                    }

                    // Unscheduled section
                    if !viewModel.unscheduledTickets.isEmpty {
                        unscheduledSection
                    }
                }
                .onAppear {
                    viewSize = geometry.size
                    configureTicketDetailDependencies()
                    if !viewModel.hasAutoScrolledToToday {
                        viewModel.scrollToToday(viewWidth: geometry.size.width)
                    }
                }
            }

            if let selectedDetailTicket {
                HStack(spacing: 0) {
                    Divider()
                    TicketDetailSheet(
                        viewModel: ticketDetailViewModel,
                        dependencyViewModel: dependencyViewModel,
                        ticket: selectedDetailTicket,
                        members: viewModel.workspace?.members ?? [],
                        presentation: .inspector,
                        onClose: { self.selectedDetailTicket = nil },
                        onOpenDependency: { linkedTicket in
                            self.selectedDetailTicket = linkedTicket
                            dependencyViewModel.evaluateConflictsForTicket(linkedTicket)
                        }
                    )
                    .shadow(color: .black.opacity(0.22), radius: 22, x: -8, y: 0)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.workspace?.id) { _, _ in
            configureTicketDetailDependencies()
        }
        .animation(.snappy(duration: 0.18), value: selectedDetailTicket?.id)
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

    private func configureTicketDetailDependencies() {
        ticketDetailViewModel.configure(
            modelContext: modelContext,
            syncEngine: nil,
            workspace: viewModel.workspace
        )
        dependencyViewModel.configure(
            modelContext: modelContext,
            workspace: viewModel.workspace
        )
    }

    private var dependencyFocusTicket: Ticket? {
        selectedDetailTicket ?? hoveredTicket
    }

    // MARK: - Toolbar

    private var ganttToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text("Feature delivery schedule by developer")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Picker("Milestone", selection: milestoneSelection) {
                Text("All milestones").tag(UUID?.none)
                ForEach(viewModel.availableSprints, id: \.id) { sprint in
                    Text(sprint.name).tag(Optional(sprint.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 220, maxWidth: 360)

            Spacer()

            // Zoom controls
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Button {
                    viewModel.zoomOut()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .disabled(viewModel.pointsPerDay <= viewModel.minimumPointsPerDay)

                VStack(spacing: 1) {
                    Text(viewModel.zoomLabel)
                        .font(DesignSystem.Typography.caption)
                    Text("\(Int(viewModel.pointsPerDay.rounded())) pt/day")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 72)

                Button {
                    viewModel.zoomIn()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .disabled(viewModel.pointsPerDay >= viewModel.maximumPointsPerDay)
            }

            Text("\(viewModel.timelineRows.count) devs")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.spacing8)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

            Text("\(viewModel.scheduledTickets.count) scheduled")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.spacing8)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

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

    private var milestoneSelection: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedSprint?.id },
            set: { selectedId in
                viewModel.selectedSprint = selectedId.flatMap { id in
                    viewModel.availableSprints.first { $0.id == id }
                }
                viewModel.refreshData()
            }
        )
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

            // Draw developer rows and ticket bars
            drawDeveloperRows(context: &context, size: canvasSize, offsetY: offsetY)
            drawTicketBars(
                context: &context,
                size: canvasSize,
                offsetX: offsetX,
                offsetY: offsetY,
                focusedTicket: dependencyFocusTicket
            )

            // Draw developer labels on the left
            drawTicketLabels(context: &context, size: canvasSize, offsetY: offsetY)

        } symbols: {
            // Empty symbols - we draw everything directly on canvas
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(ticketDragGesture)
        .simultaneousGesture(ticketTapGesture)
    }

    private func hoverCardPosition(in size: CGSize) -> CGPoint {
        let cardWidth: CGFloat = 320
        let cardHeight: CGFloat = 300
        let margin: CGFloat = 12
        let preferredX = hoverLocation.x + cardWidth / 2 + 18
        let preferredY = hoverLocation.y + cardHeight / 2 + 18
        let minX = cardWidth / 2 + margin
        let maxX = max(minX, size.width - cardWidth / 2 - margin)
        let minY = cardHeight / 2 + margin
        let maxY = max(minY, size.height - cardHeight / 2 - margin)
        let x = min(max(preferredX, minX), maxX)
        let y = min(max(preferredY, minY), maxY)
        return CGPoint(x: x, y: y)
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

    private func drawTicketBars(
        context: inout GraphicsContext,
        size: CGSize,
        offsetX: CGFloat,
        offsetY: CGFloat,
        focusedTicket: Ticket?
    ) {
        let focusedIds = viewModel.focusedDependencyIds(for: focusedTicket)

        for (rowIndex, row) in viewModel.timelineRows.enumerated() {
            for ticket in row.tickets {
                let barX = viewModel.barXPosition(for: ticket) + offsetX
                let barY = viewModel.barYPosition(for: ticket, in: row, rowIndex: rowIndex) + offsetY
                let barWidth = viewModel.barWidth(for: ticket)

                var adjustedBarX = barX
                if viewModel.draggingTicket?.id == ticket.id {
                    adjustedBarX += viewModel.dragOffset
                }

                guard adjustedBarX + barWidth >= viewModel.labelWidth && adjustedBarX <= size.width else { continue }
                guard barY + viewModel.rowHeight >= viewModel.headerHeight && barY <= size.height else { continue }

                let barRect = CGRect(
                    x: adjustedBarX,
                    y: barY,
                    width: max(barWidth, 12),
                    height: viewModel.rowHeight
                )
                let roundedPath = Path(roundedRect: barRect, cornerRadius: DesignSystem.Radius.small)
                let isFocused = focusedIds.isEmpty || focusedIds.contains(ticket.id)
                let isCenterFocus = focusedTicket?.id == ticket.id
                let fillColor = viewModel.barColor(for: ticket).opacity(isFocused ? 1 : 0.24)
                let borderColor = isCenterFocus
                    ? DesignSystem.Colors.accent
                    : viewModel.barBorderColor(for: ticket).opacity(isFocused ? 1 : 0.35)

                context.fill(roundedPath, with: .color(fillColor))
                context.stroke(
                    roundedPath,
                    with: .color(borderColor),
                    lineWidth: isCenterFocus ? 2 : (viewModel.hasConflict(ticket) ? 2 : 1)
                )

                if barWidth > 54 {
                    let titleLimit = max(8, min(48, Int(barWidth / 7)))
                    let titleText = Text(String(ticket.title.prefix(titleLimit)))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(barTextColor.opacity(isFocused ? 1 : 0.35))

                    context.draw(
                        context.resolve(titleText),
                        at: CGPoint(x: adjustedBarX + 8, y: barY + viewModel.rowHeight / 2),
                        anchor: .leading
                    )
                }

                if let storyPoints = ticket.storyPoints, barWidth > 30 {
                    let hasDependencyMarker = (ticket.blockedBy.count + ticket.blocks.count) > 0 && barWidth > 48
                    let trailingPadding: CGFloat = hasDependencyMarker ? 28 : 10
                    let pointsText = Text("\(storyPoints)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(barTextColor.opacity(isFocused ? 1 : 0.35))

                    context.draw(
                        context.resolve(pointsText),
                        at: CGPoint(x: adjustedBarX + barRect.width - trailingPadding, y: barY + viewModel.rowHeight / 2),
                        anchor: .trailing
                    )
                }

                drawDependencyMarker(
                    context: &context,
                    ticket: ticket,
                    barRect: barRect,
                    isFocused: isFocused
                )
            }
        }
    }

    private func drawDependencyMarker(
        context: inout GraphicsContext,
        ticket: Ticket,
        barRect: CGRect,
        isFocused: Bool
    ) {
        let dependencyCount = ticket.blockedBy.count + ticket.blocks.count
        guard dependencyCount > 0, barRect.width > 48 else { return }

        let markerDiameter: CGFloat = 16
        let markerRect = CGRect(
            x: barRect.maxX - markerDiameter - 4,
            y: barRect.minY + (barRect.height - markerDiameter) / 2,
            width: markerDiameter,
            height: markerDiameter
        )
        context.fill(
            Path(ellipseIn: markerRect),
            with: .color(DesignSystem.Colors.surfaceElevated.opacity(isFocused ? 0.82 : 0.35))
        )

        let text = Text("\(dependencyCount)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(barTextColor.opacity(isFocused ? 0.9 : 0.35))
        context.draw(
            context.resolve(text),
            at: CGPoint(x: markerRect.midX, y: markerRect.midY),
            anchor: .center
        )
    }

    private func drawDeveloperRows(context: inout GraphicsContext, size: CGSize, offsetY: CGFloat) {
        for (rowIndex, row) in viewModel.timelineRows.enumerated() {
            let y = viewModel.rowYPosition(forRow: rowIndex) + offsetY
            let height = viewModel.rowHeight(for: row)

            guard y + height >= viewModel.headerHeight && y <= size.height else { continue }

            let rowRect = CGRect(x: 0, y: y, width: size.width, height: height)
            context.fill(
                Path(rowRect),
                with: .color(rowIndex.isMultiple(of: 2) ? DesignSystem.Colors.background : DesignSystem.Colors.surface.opacity(0.35))
            )

            var separator = Path()
            separator.move(to: CGPoint(x: 0, y: y + height))
            separator.addLine(to: CGPoint(x: size.width, y: y + height))
            context.stroke(separator, with: .color(DesignSystem.Colors.border.opacity(0.7)), lineWidth: 0.5)
        }
    }

    private func drawTicketLabels(context: inout GraphicsContext, size: CGSize, offsetY: CGFloat) {
        // Label background
        let labelBgRect = CGRect(x: 0, y: viewModel.headerHeight, width: viewModel.labelWidth, height: size.height - viewModel.headerHeight)
        context.fill(Path(labelBgRect), with: .color(DesignSystem.Colors.surface))

        for (rowIndex, row) in viewModel.timelineRows.enumerated() {
            let y = viewModel.rowYPosition(forRow: rowIndex) + offsetY
            let rowHeight = viewModel.rowHeight(for: row)

            guard y + rowHeight >= viewModel.headerHeight && y <= size.height else { continue }

            let avatarRect = CGRect(x: 16, y: y + 14, width: 44, height: 44)
            let avatarColor = row.member.map { member in
                Color(hue: Double(abs(member.id.hashValue) % 360) / 360.0, saturation: 0.55, brightness: 0.75)
            } ?? DesignSystem.Colors.accentSoft
            context.fill(Path(ellipseIn: avatarRect), with: .color(avatarColor))

            let initialsText = Text(row.initials)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            context.draw(
                context.resolve(initialsText),
                at: CGPoint(x: avatarRect.midX, y: avatarRect.midY),
                anchor: .center
            )

            let textX: CGFloat = 74
            let maxCharacters = max(12, Int((viewModel.labelWidth - textX - 18) / 7))

            let titleText = Text(truncatedLabel(row.title, maxCharacters: maxCharacters))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            context.draw(
                context.resolve(titleText),
                at: CGPoint(x: textX, y: y + 24),
                anchor: .leading
            )

            let subtitleText = Text(truncatedLabel(row.subtitle, maxCharacters: maxCharacters))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            context.draw(
                context.resolve(subtitleText),
                at: CGPoint(x: textX, y: y + 43),
                anchor: .leading
            )

            let countText = Text("\(row.tickets.count) features")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            context.draw(
                context.resolve(countText),
                at: CGPoint(x: textX, y: y + 60),
                anchor: .leading
            )
        }

        // Draw the boundary last so the timeline lane always has a clean edge.
        var borderPath = Path()
        borderPath.move(to: CGPoint(x: viewModel.labelWidth, y: viewModel.headerHeight))
        borderPath.addLine(to: CGPoint(x: viewModel.labelWidth, y: size.height))
        context.stroke(borderPath, with: .color(DesignSystem.Colors.border), lineWidth: 1)
    }

    private var barTextColor: Color {
        DesignSystem.Colors.timelineBarText
    }

    private func truncatedLabel(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return String(value.prefix(max(1, maxCharacters - 3))) + "..."
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
                ), viewportSize: viewSize)
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
                    for (rowIndex, row) in viewModel.timelineRows.enumerated() {
                        for ticket in row.tickets {
                            let barX = viewModel.barXPosition(for: ticket) + offsetX
                            let barY = viewModel.barYPosition(for: ticket, in: row, rowIndex: rowIndex) + offsetY
                            let barWidth = viewModel.barWidth(for: ticket)

                            let barRect = CGRect(x: barX, y: barY, width: barWidth, height: viewModel.rowHeight)
                            if barRect.contains(location) {
                                viewModel.beginDrag(ticket: ticket)
                                break
                            }
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

    private var ticketTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if let ticket = viewModel.ticket(at: value.location) {
                    selectedDetailTicket = ticket
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

// MARK: - Timeline Ticket Hover Card

private struct TimelineTicketHoverCard: View {
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            Text(ticket.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
                infoRow("Status", value: statusLabel, valueColor: statusColor)
                infoRow("Start", value: formattedDate(ticket.startDate))
                infoRow("Due", value: formattedDate(ticket.endDate), valueColor: DesignSystem.Colors.warning)
                infoRow("Story Points", value: ticket.storyPoints.map { "\($0) SP" } ?? "Unestimated", valueColor: DesignSystem.Colors.accent)
                infoRow("Milestone", value: ticket.sprint?.name ?? "No milestone")
                infoRow("Priority", value: priorityLabel)
            }
        }
        .padding(DesignSystem.Spacing.spacing16)
        .frame(width: 320, alignment: .leading)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.large)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private var statusColor: Color {
        switch ticket.status {
        case .done:
            return DesignSystem.Colors.success
        case .inProgress:
            return DesignSystem.Colors.accent
        case .inReview:
            return DesignSystem.Colors.warning
        case .todo, .backlog:
            return DesignSystem.Colors.textSecondary
        }
    }

    private var statusLabel: String {
        switch ticket.status {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Completed"
        }
    }

    private var priorityLabel: String {
        switch ticket.priority {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case nil: return "None"
        }
    }

    private func infoRow(_ label: String, value: String, valueColor: Color = DesignSystem.Colors.textPrimary) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing12) {
            Text(label)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(width: 105, alignment: .leading)
            Text(value)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundColor(valueColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "No date" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
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

    static func dismantleNSView(_ nsView: ScrollWheelNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class ScrollWheelNSView: NSView {
    var handler: ((NSEvent) -> Void)?
    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopMonitoring()
        } else {
            startMonitoringIfNeeded()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        handler?(event)
    }

    private func startMonitoringIfNeeded() {
        guard scrollMonitor == nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.shouldHandle(event) else {
                return event
            }

            self.handler?(event)
            return nil
        }
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }

        let location = convert(event.locationInWindow, from: nil)
        return bounds.contains(location)
    }

    func stopMonitoring() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}

extension View {
    func onScrollWheelGesture(handler: @escaping (NSEvent) -> Void) -> some View {
        modifier(ScrollWheelGestureModifier(handler: handler))
    }
}
