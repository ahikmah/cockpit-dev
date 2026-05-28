import SwiftUI
import SwiftData

struct TicketsView: View {
    @Environment(\.modelContext) private var modelContext

    let workspace: Workspace
    let syncEngine: SyncEngine?
    @State private var viewModel: TicketListViewModel
    @State private var ticketManagementViewModel = TicketManagementViewModel()
    @State private var createTicketViewModel = TicketManagementViewModel()
    @State private var dependencyViewModel = DependencyViewModel()
    @State private var selectedTicket: Ticket?
    @State private var showCreateTicket = false

    init(workspace: Workspace, syncEngine: SyncEngine? = nil) {
        self.workspace = workspace
        self.syncEngine = syncEngine
        self._viewModel = State(initialValue: TicketListViewModel(workspace: workspace))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ticketsContent
                    .frame(width: selectedTicket == nil ? nil : max(420, geometry.size.width - inspectorWidth(in: geometry.size.width)))

                if let selectedTicket {
                    Divider()
                    TicketDetailSheet(
                        viewModel: ticketManagementViewModel,
                        dependencyViewModel: dependencyViewModel,
                        ticket: selectedTicket,
                        members: workspace.members,
                        presentation: .inspector,
                        onClose: { self.selectedTicket = nil },
                        onOpenDependency: { linkedTicket in
                            self.selectedTicket = linkedTicket
                            dependencyViewModel.evaluateConflictsForTicket(linkedTicket)
                        }
                    )
                    .frame(width: inspectorWidth(in: geometry.size.width))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onAppear(perform: configure)
        .onChange(of: workspace.id) { _, _ in configure() }
        .onChange(of: workspace.tickets.count) { _, _ in viewModel.workspace = workspace }
        .animation(.snappy(duration: 0.18), value: selectedTicket?.id)
        .sheet(isPresented: $showCreateTicket) {
            CreateTicketSheet(
                viewModel: createTicketViewModel,
                members: workspace.members,
                sprints: workspace.sprints.sorted { $0.startDate < $1.startDate }
            )
        }
    }

    private var ticketsContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()

            if viewModel.filteredTickets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.spacing8) {
                        ForEach(viewModel.filteredTickets, id: \.id) { ticket in
                            TicketListRow(
                                ticket: ticket,
                                isSelected: selectedTicket?.id == ticket.id
                            ) {
                                selectedTicket = ticket
                                dependencyViewModel.evaluateConflictsForTicket(ticket)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.spacing16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tickets")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("\(viewModel.filteredTickets.count) shown · \(workspace.tickets.count) total")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                showCreateTicket = true
            } label: {
                Label("New Ticket", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.background)
    }

    private var filterBar: some View {
        VStack(spacing: DesignSystem.Spacing.spacing10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.spacing10) {
                    HStack(spacing: DesignSystem.Spacing.spacing8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        TextField("Search title, label, description, or #iid", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.spacing10)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(filterSurface)
                    .frame(minWidth: 260)

                    Picker("Sprint", selection: $viewModel.selectedSprint) {
                        Text("All sprints").tag(nil as Sprint?)
                        ForEach(workspace.sprints.sorted { $0.startDate < $1.startDate }, id: \.id) { sprint in
                            Text(sprint.name).tag(sprint as Sprint?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)

                    Picker("Status", selection: $viewModel.selectedStatus) {
                        Text("All status").tag(nil as TicketStatus?)
                        ForEach(TicketStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status as TicketStatus?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Picker("Priority", selection: $viewModel.selectedPriority) {
                        Text("All priority").tag(nil as TicketPriority?)
                        ForEach(TicketPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority as TicketPriority?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Picker("Assignee", selection: $viewModel.selectedAssignee) {
                        Text("All assignees").tag(nil as Member?)
                        ForEach(workspace.members, id: \.id) { member in
                            Text(member.displayName).tag(member as Member?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)

                    Picker("Sort", selection: $viewModel.sort) {
                        ForEach(TicketListSort.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    if viewModel.activeFilterCount > 0 {
                        Button("Clear") {
                            viewModel.clearFilters()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignSystem.Colors.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing10)
        .background(DesignSystem.Colors.navigation)
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "ticket")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("No tickets match these filters")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Button("Create Ticket") {
                showCreateTicket = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterSurface: some View {
        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
            .fill(DesignSystem.Colors.surface)
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            }
    }

    private func configure() {
        viewModel.workspace = workspace
        ticketManagementViewModel.configure(modelContext: modelContext, syncEngine: syncEngine, workspace: workspace)
        createTicketViewModel.configure(modelContext: modelContext, syncEngine: syncEngine, workspace: workspace)
        dependencyViewModel.configure(modelContext: modelContext, workspace: workspace)
    }

    private func inspectorWidth(in containerWidth: CGFloat) -> CGFloat {
        min(max(620, containerWidth * 0.46), max(500, containerWidth - 420))
    }
}

private struct TicketListRow: View {
    let ticket: Ticket
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing12) {
                Circle()
                    .fill(ticket.status.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                    HStack(spacing: DesignSystem.Spacing.spacing8) {
                        if let iid = ticket.gitlabIssueIid {
                            Text("#\(iid)")
                                .font(DesignSystem.Typography.captionMedium)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        Text(ticket.title)
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                    }

                    HStack(spacing: DesignSystem.Spacing.spacing8) {
                        compactChip(ticket.status.displayName, color: ticket.status.color)
                        if let priority = ticket.priority {
                            compactChip(priority.displayName, color: priority.color)
                        }
                        if let sprint = ticket.sprint {
                            compactChip(sprint.name, color: DesignSystem.Colors.accent)
                        }
                        if let assignee = ticket.assignee {
                            Label(assignee.displayName, systemImage: "person.crop.circle")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if let sp = ticket.storyPoints {
                    Text("\(sp) SP")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, DesignSystem.Spacing.spacing8)
                        .padding(.vertical, DesignSystem.Spacing.spacing4)
                        .background(DesignSystem.Colors.accentSoft)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DesignSystem.Colors.navigationActive : DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(isSelected ? DesignSystem.Colors.accent.opacity(0.6) : DesignSystem.Colors.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func compactChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}
