import SwiftUI
import SwiftData

/// Displays detailed information about a sprint including assigned tickets,
/// progress, and burndown chart.
struct SprintDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let sprint: Sprint
    @Bindable var viewModel: SprintViewModel
    let syncEngine: SyncEngine?
    @State private var selectedDetailTicket: Ticket?
    @State private var showDeleteConfirmation = false
    @State private var ticketDetailViewModel = TicketManagementViewModel()
    @State private var createTicketViewModel = TicketManagementViewModel()
    @State private var dependencyViewModel = DependencyViewModel()
    @State private var showCreateTicket = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sprintContent
                    .frame(width: selectedDetailTicket == nil ? nil : max(300, geometry.size.width - inspectorWidth(in: geometry.size.width)))

                if let selectedDetailTicket {
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
                    .frame(width: inspectorWidth(in: geometry.size.width))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onAppear(perform: configureTicketDetailDependencies)
        .onChange(of: viewModel.workspace?.id) { _, _ in
            configureTicketDetailDependencies()
        }
        .animation(.snappy(duration: 0.18), value: selectedDetailTicket?.id)
        .alert("Move Incomplete Tickets", isPresented: $viewModel.showMoveToNextSprint) {
            Button("Move to Next Sprint") {
                viewModel.moveIncompleteToNextSprint(from: sprint)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(viewModel.incompleteTicketCount(for: sprint)) tickets are not done. Move them to the next sprint?")
        }
        .alert("No Next Sprint", isPresented: $viewModel.showCreateNewSprintForIncomplete) {
            Button("Create New Sprint") {
                Task {
                    await viewModel.createNewSprintAndMoveIncomplete(from: sprint)
                }
            }
            Button("Leave Unassigned") {
                // Unassign incomplete tickets from this sprint
                let incomplete = viewModel.incompleteTickets(for: sprint)
                for ticket in incomplete {
                    viewModel.unassignTicket(ticket)
                }
                viewModel.showCreateNewSprintForIncomplete = false
            }
            Button("Cancel", role: .cancel) {
                viewModel.showCreateNewSprintForIncomplete = false
            }
        } message: {
            Text("No next sprint exists. Would you like to create a new sprint for the incomplete tickets, or leave them unassigned?")
        }
        .sheet(isPresented: $viewModel.showTicketAssignment) {
            TicketAssignmentSheet(sprint: sprint, viewModel: viewModel)
        }
        .sheet(isPresented: $showCreateTicket) {
            CreateTicketSheet(
                viewModel: createTicketViewModel,
                members: viewModel.workspace?.members ?? [],
                sprints: viewModel.workspace?.sprints.sorted { $0.startDate < $1.startDate } ?? [],
                defaultSprint: sprint
            )
        }
        .confirmationDialog("Delete Sprint", isPresented: $showDeleteConfirmation) {
            Button("Delete Sprint", role: .destructive) {
                Task {
                    await viewModel.deleteSprint(sprint)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the sprint locally and deletes the linked GitLab milestone when connected. Assigned tickets are kept and unassigned.")
        }
    }

    private func inspectorWidth(in containerWidth: CGFloat) -> CGFloat {
        min(max(540, containerWidth * 0.58), max(420, containerWidth - 300))
    }

    private var sprintContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing20) {
                // Sprint header with progress
                sprintHeader

                Divider()

                // Burndown chart
                burndownSection

                Divider()

                // Assigned tickets
                ticketsSection

                // Sprint completion actions
                if viewModel.isSprintCompleted(sprint) && viewModel.incompleteTicketCount(for: sprint) > 0 {
                    Divider()
                    completionActionsSection
                }
            }
            .padding(DesignSystem.Spacing.spacing20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func configureTicketDetailDependencies() {
        ticketDetailViewModel.configure(
            modelContext: modelContext,
            syncEngine: syncEngine,
            workspace: viewModel.workspace
        )
        createTicketViewModel.configure(
            modelContext: modelContext,
            syncEngine: syncEngine,
            workspace: viewModel.workspace
        )
        dependencyViewModel.configure(
            modelContext: modelContext,
            workspace: viewModel.workspace
        )
    }

    // MARK: - Sprint Header

    private var sprintHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                    Text(sprint.name)
                        .font(DesignSystem.Typography.headingLarge)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    HStack(spacing: DesignSystem.Spacing.spacing8) {
                        Label(viewModel.formatDate(sprint.startDate), systemImage: "calendar")
                        Text("→")
                        Text(viewModel.formatDate(sprint.endDate))
                    }
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.danger)
                        .padding(8)
                        .background(DesignSystem.Colors.dangerSoft)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)

                // Status badge
                Text(viewModel.statusLabel(for: sprint))
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(viewModel.statusColor(for: sprint))
                    .padding(.horizontal, DesignSystem.Spacing.spacing12)
                    .padding(.vertical, DesignSystem.Spacing.spacing6)
                    .background(viewModel.statusColor(for: sprint).opacity(0.1))
                    .cornerRadius(DesignSystem.Radius.small)
            }

            // Progress overview
            HStack(spacing: DesignSystem.Spacing.spacing24) {
                progressStat(
                    title: "Progress",
                    value: viewModel.formattedProgress(for: sprint),
                    icon: "chart.bar.fill"
                )
                progressStat(
                    title: "Done",
                    value: "\(viewModel.doneStoryPoints(for: sprint)) SP",
                    icon: "checkmark.circle.fill"
                )
                progressStat(
                    title: "Total",
                    value: "\(viewModel.totalStoryPoints(for: sprint)) SP",
                    icon: "star.fill"
                )
                progressStat(
                    title: "Tickets",
                    value: "\(viewModel.ticketCount(for: sprint))",
                    icon: "ticket.fill"
                )
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.border)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(
                            width: geometry.size.width * CGFloat(viewModel.progressPercentage(for: sprint) / 100.0),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
        }
    }

    private func progressStat(title: String, value: String, icon: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing4) {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            Text(value)
                .font(DesignSystem.Typography.headingSmall)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }

    // MARK: - Burndown Section

    private var burndownSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            Text("Burndown Chart")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            BurndownChartView(
                dataPoints: viewModel.burndownData(for: sprint),
                totalStoryPoints: viewModel.totalStoryPoints(for: sprint)
            )
            .frame(height: 220)
        }
    }

    // MARK: - Tickets Section

    private var ticketsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            HStack {
                Text("Assigned Tickets")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("(\(viewModel.ticketCount(for: sprint)))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                Spacer()

                Button {
                    showCreateTicket = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("New Ticket")
                            .font(DesignSystem.Typography.bodyMedium)
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
                .help("Create a GitLab issue in this sprint")

                Button {
                    viewModel.refreshUnassignedTickets()
                    viewModel.showTicketAssignment = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("Assign Tickets")
                            .font(DesignSystem.Typography.bodyMedium)
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if sprint.tickets.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: DesignSystem.Spacing.spacing8) {
                        Image(systemName: "tray")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                        Text("No tickets assigned to this sprint")
                            .font(DesignSystem.Typography.bodyRegular)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.vertical, DesignSystem.Spacing.spacing24)
                    Spacer()
                }
            } else {
                LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(viewModel.orderedTickets(for: sprint), id: \.id) { ticket in
                        SprintTicketRow(ticket: ticket, viewModel: viewModel, sprint: sprint) {
                            selectedDetailTicket = ticket
                        }
                    }
                }
            }
        }
    }

    // MARK: - Completion Actions

    private var completionActionsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DesignSystem.Colors.warning)
                Text("Sprint ended with \(viewModel.incompleteTicketCount(for: sprint)) incomplete tickets")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }

            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Button {
                    if viewModel.nextSprint(after: sprint) != nil {
                        viewModel.showMoveToNextSprint = true
                    } else {
                        viewModel.showCreateNewSprintForIncomplete = true
                    }
                } label: {
                    Text("Move to Next Sprint")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.spacing12)
                        .padding(.vertical, DesignSystem.Spacing.spacing6)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.Radius.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.dangerSoft)
        .cornerRadius(DesignSystem.Radius.medium)
    }

    // MARK: - Helpers

    private var progressColor: Color {
        let progress = viewModel.progressPercentage(for: sprint)
        if progress >= 100 {
            return DesignSystem.Colors.success
        } else if progress >= 50 {
            return DesignSystem.Colors.accent
        } else {
            return DesignSystem.Colors.warning
        }
    }
}

// MARK: - Sprint Ticket Row

/// A row displaying a ticket within the sprint detail view.
struct SprintTicketRow: View {
    let ticket: Ticket
    @Bindable var viewModel: SprintViewModel
    let sprint: Sprint
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Ticket info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text(ticket.title)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Text(ticket.status.rawValue)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textTertiary)

                    if let assignee = ticket.assignee {
                        Text(assignee.displayName)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            // Story points
            if let sp = ticket.storyPoints {
                Text("\(sp) SP")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.spacing6)
                    .padding(.vertical, DesignSystem.Spacing.spacing2)
                    .background(DesignSystem.Colors.accentSoft)
                    .cornerRadius(DesignSystem.Radius.small)
            }

            // Remove from sprint
            Button {
                viewModel.unassignTicket(ticket)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.Radius.small)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }

    private var statusColor: Color {
        switch ticket.status {
        case .done: return DesignSystem.Colors.success
        case .inProgress, .inReview: return DesignSystem.Colors.accent
        case .todo: return DesignSystem.Colors.warning
        case .backlog: return DesignSystem.Colors.textTertiary
        }
    }
}

// MARK: - Ticket Assignment Sheet

/// Sheet for assigning tickets to a sprint.
struct TicketAssignmentSheet: View {
    let sprint: Sprint
    @Bindable var viewModel: SprintViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTickets: Set<UUID> = []

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            // Header
            HStack {
                Text("Assign Tickets to \(sprint.name)")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)
            }

            Divider()

            if viewModel.unassignedTickets.isEmpty {
                VStack(spacing: DesignSystem.Spacing.spacing8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(DesignSystem.Colors.success)
                    Text("All tickets are assigned to sprints")
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Ticket list
                List {
                    ForEach(viewModel.unassignedTickets, id: \.id) { ticket in
                        HStack(spacing: DesignSystem.Spacing.spacing12) {
                            // Selection checkbox
                            Image(systemName: selectedTickets.contains(ticket.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(
                                    selectedTickets.contains(ticket.id)
                                        ? DesignSystem.Colors.accent
                                        : DesignSystem.Colors.textTertiary
                                )
                                .font(.system(size: 16))

                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                                Text(ticket.title)
                                    .font(DesignSystem.Typography.bodyRegular)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)

                                HStack(spacing: DesignSystem.Spacing.spacing8) {
                                    Text(ticket.status.rawValue)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.textTertiary)

                                    if let sp = ticket.storyPoints {
                                        Text("\(sp) SP")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.textTertiary)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedTickets.contains(ticket.id) {
                                selectedTickets.remove(ticket.id)
                            } else {
                                selectedTickets.insert(ticket.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }

            // Assign button
            if !selectedTickets.isEmpty {
                HStack {
                    Text("\(selectedTickets.count) tickets selected")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Spacer()

                    Button {
                        assignSelectedTickets()
                    } label: {
                        Text("Assign to Sprint")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(.white)
                            .padding(.horizontal, DesignSystem.Spacing.spacing16)
                            .padding(.vertical, DesignSystem.Spacing.spacing8)
                            .background(DesignSystem.Colors.accent)
                            .cornerRadius(DesignSystem.Radius.small)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 500, height: 450)
    }

    private func assignSelectedTickets() {
        for ticketId in selectedTickets {
            if let ticket = viewModel.unassignedTickets.first(where: { $0.id == ticketId }) {
                viewModel.assignTicket(ticket, to: sprint)
            }
        }
        selectedTickets = []
        viewModel.refreshUnassignedTickets()
    }
}
