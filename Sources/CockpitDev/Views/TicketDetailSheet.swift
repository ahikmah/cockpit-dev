import SwiftUI
import SwiftData

/// Sheet for viewing and editing all fields of an existing ticket.
/// Supports inline editing with save, and displays non-standard SP indicator.
struct TicketDetailSheet: View {

    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: TicketManagementViewModel
    @Bindable var dependencyViewModel: DependencyViewModel

    /// The ticket being viewed/edited.
    let ticket: Ticket

    /// Members available for assignment.
    let members: [Member]

    // MARK: - Edit State

    @State private var isEditing: Bool = false
    @State private var editTitle: String = ""
    @State private var editDescription: String = ""
    @State private var editPriority: TicketPriority? = nil
    @State private var editStoryPointsText: String = ""
    @State private var editLabelsText: String = ""
    @State private var editAssignee: Member? = nil
    @State private var editStartDate: Date? = nil
    @State private var editEndDate: Date? = nil
    @State private var editStatus: TicketStatus = .backlog

    // MARK: - Validation

    @State private var storyPointsError: String?
    @State private var titleError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            detailContent
            Divider()
            footer
        }
        .frame(width: 560, height: 650)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl))
        .onAppear {
            loadTicketData()
            dependencyViewModel.evaluateConflictsForTicket(ticket)
        }
        .alert("Circular Dependency Detected", isPresented: $dependencyViewModel.showCycleError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cannot add this dependency because it would create a cycle:\n\(dependencyViewModel.cyclePathDescription)")
        }
        .sheet(isPresented: $dependencyViewModel.showStatusConflictWarning) {
            if let pending = dependencyViewModel.pendingStatusChange {
                StatusConflictWarningDialog(
                    conflictDescription: pending.conflictDescription,
                    onProceed: { dependencyViewModel.proceedWithStatusChange() },
                    onCancel: { dependencyViewModel.cancelStatusChange() }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                if let iid = ticket.gitlabIssueIid {
                    Text("#\(iid)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                Text(isEditing ? "Edit Ticket" : "Ticket Details")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            Spacer()

            if viewModel.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, DesignSystem.Spacing.spacing8)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.spacing24)
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                if isEditing {
                    editableFields
                } else {
                    readOnlyFields
                }
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
    }

    // MARK: - Read-Only Fields

    private var readOnlyFields: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
            // Title
            fieldRow(label: "Title") {
                Text(ticket.title)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            // Status
            fieldRow(label: "Status") {
                statusBadge(ticket.status)
            }

            // Priority
            if let priority = ticket.priority {
                fieldRow(label: "Priority") {
                    priorityBadge(priority)
                }
            }

            // Story Points
            if let sp = ticket.storyPoints {
                fieldRow(label: "Story Points") {
                    storyPointsDisplay(sp)
                }
            }

            // Description
            if let desc = ticket.descriptionText, !desc.isEmpty {
                fieldRow(label: "Description") {
                    Text(desc)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Labels
            if !ticket.labels.isEmpty {
                fieldRow(label: "Labels") {
                    FlowLayout(spacing: DesignSystem.Spacing.spacing4) {
                        ForEach(ticket.labels, id: \.self) { label in
                            labelBadge(label)
                        }
                    }
                }
            }

            // Assignee
            if let assignee = ticket.assignee {
                fieldRow(label: "Assignee") {
                    HStack(spacing: DesignSystem.Spacing.spacing6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.accent)
                        Text(assignee.displayName)
                            .font(DesignSystem.Typography.bodyRegular)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
            }

            // Dates
            if ticket.startDate != nil || ticket.endDate != nil {
                HStack(spacing: DesignSystem.Spacing.spacing24) {
                    if let start = ticket.startDate {
                        fieldRow(label: "Start Date") {
                            Text(start, style: .date)
                                .font(DesignSystem.Typography.bodyRegular)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                    }
                    if let end = ticket.endDate {
                        fieldRow(label: "End Date") {
                            Text(end, style: .date)
                                .font(DesignSystem.Typography.bodyRegular)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                    }
                }
            }

            // Dependencies
            Divider()
                .padding(.vertical, DesignSystem.Spacing.spacing8)

            DependencySection(
                ticket: ticket,
                viewModel: dependencyViewModel,
                isEditing: false
            )

            // Metadata
            Divider()
                .padding(.vertical, DesignSystem.Spacing.spacing8)

            metadataSection
        }
    }

    // MARK: - Editable Fields

    private var editableFields: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
            // Title
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Text("Title")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text("*")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.danger)
                }

                TextField("Ticket title", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.bodyRegular)
                    .padding(.horizontal, DesignSystem.Spacing.spacing12)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(
                                titleError != nil ? DesignSystem.Colors.danger : DesignSystem.Colors.border,
                                lineWidth: 1
                            )
                    )

                if let error = titleError {
                    errorLabel(error)
                }
            }

            // Status
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Status")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Picker("Status", selection: $editStatus) {
                    ForEach(TicketStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Priority
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Priority")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Picker("Priority", selection: $editPriority) {
                    Text("None").tag(nil as TicketPriority?)
                    ForEach(TicketPriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority as TicketPriority?)
                    }
                }
                .pickerStyle(.menu)
            }

            // Story Points
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Story Points")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(AppConstants.fibonacciSequence, id: \.self) { value in
                        Button {
                            editStoryPointsText = String(value)
                            storyPointsError = nil
                        } label: {
                            Text("\(value)")
                                .font(DesignSystem.Typography.bodyMedium)
                                .foregroundStyle(
                                    editStoryPointsText == String(value)
                                        ? .white
                                        : DesignSystem.Colors.textPrimary
                                )
                                .frame(width: 36, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                        .fill(
                                            editStoryPointsText == String(value)
                                                ? DesignSystem.Colors.accent
                                                : DesignSystem.Colors.accentSoft
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if !editStoryPointsText.isEmpty {
                        Button {
                            editStoryPointsText = ""
                            storyPointsError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = storyPointsError {
                    errorLabel(error)
                }
            }

            // Description
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Description")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextEditor(text: $editDescription)
                    .font(DesignSystem.Typography.bodyRegular)
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(DesignSystem.Spacing.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .scrollContentBackground(.hidden)
            }

            // Labels
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Labels")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextField("Comma-separated labels", text: $editLabelsText)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.bodyRegular)
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
            }

            // Assignee
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Assignee")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Picker("Assignee", selection: $editAssignee) {
                    Text("Unassigned").tag(nil as Member?)
                    ForEach(members, id: \.id) { member in
                        Text(member.displayName).tag(member as Member?)
                    }
                }
                .pickerStyle(.menu)
            }

            // Dates
            HStack(spacing: DesignSystem.Spacing.spacing16) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                    Text("Start Date")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    HStack {
                        if let date = editStartDate {
                            DatePicker("", selection: Binding(
                                get: { date },
                                set: { editStartDate = $0 }
                            ), displayedComponents: .date)
                            .labelsHidden()

                            Button {
                                editStartDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                editStartDate = Date()
                            } label: {
                                HStack(spacing: DesignSystem.Spacing.spacing4) {
                                    Image(systemName: "calendar")
                                    Text("Set date")
                                }
                                .font(DesignSystem.Typography.bodyRegular)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .padding(.horizontal, DesignSystem.Spacing.spacing12)
                                .padding(.vertical, DesignSystem.Spacing.spacing6)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                    Text("End Date")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    HStack {
                        if let date = editEndDate {
                            DatePicker("", selection: Binding(
                                get: { date },
                                set: { editEndDate = $0 }
                            ), displayedComponents: .date)
                            .labelsHidden()

                            Button {
                                editEndDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                editEndDate = Date()
                            } label: {
                                HStack(spacing: DesignSystem.Spacing.spacing4) {
                                    Image(systemName: "calendar")
                                    Text("Set date")
                                }
                                .font(DesignSystem.Typography.bodyRegular)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .padding(.horizontal, DesignSystem.Spacing.spacing12)
                                .padding(.vertical, DesignSystem.Spacing.spacing6)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Dependencies (editable)
            Divider()
                .padding(.vertical, DesignSystem.Spacing.spacing8)

            DependencySection(
                ticket: ticket,
                viewModel: dependencyViewModel,
                isEditing: true
            )
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            Text("Metadata")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            HStack(spacing: DesignSystem.Spacing.spacing24) {
                metadataItem(label: "Created", value: ticket.createdAt.formatted(date: .abbreviated, time: .shortened))
                metadataItem(label: "Updated", value: ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))
                if let synced = ticket.lastSyncedAt {
                    metadataItem(label: "Last Synced", value: synced.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isEditing {
                Button("Cancel") {
                    isEditing = false
                    loadTicketData()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .font(DesignSystem.Typography.bodyMedium)
            } else {
                Button {
                    viewModel.confirmDeletion(of: ticket)
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.danger)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if viewModel.canRetry {
                Button {
                    viewModel.retryLastOperation()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Sync")
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.warning)
                }
                .buttonStyle(.plain)
                .padding(.trailing, DesignSystem.Spacing.spacing12)
            }

            if isEditing {
                Button {
                    saveChanges()
                } label: {
                    Text("Save Changes")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignSystem.Spacing.spacing16)
                        .padding(.vertical, DesignSystem.Spacing.spacing8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .fill(isEditValid ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isEditValid)
            } else {
                Button {
                    isEditing = true
                } label: {
                    Text("Edit")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignSystem.Spacing.spacing16)
                        .padding(.vertical, DesignSystem.Spacing.spacing8)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .fill(DesignSystem.Colors.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
    }

    // MARK: - Component Helpers

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
            Text(label)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            content()
        }
    }

    private func statusBadge(_ status: TicketStatus) -> some View {
        Text(status.displayName)
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, DesignSystem.Spacing.spacing4)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                    .fill(status.color)
            )
    }

    private func priorityBadge(_ priority: TicketPriority) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Image(systemName: priority.iconName)
                .font(.system(size: 11))
            Text(priority.displayName)
                .font(DesignSystem.Typography.captionMedium)
        }
        .foregroundStyle(priority.color)
    }

    /// Displays story points with a non-standard indicator (⚠️) for external values
    /// not in the Fibonacci set.
    private func storyPointsDisplay(_ value: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Text("\(value)")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if viewModel.isNonStandardStoryPoints(value) {
                Text("⚠️")
                    .font(.system(size: 12))
                Text("Non-standard")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }
        }
    }

    private func labelBadge(_ label: String) -> some View {
        Text(label)
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.accent)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                    .fill(DesignSystem.Colors.accentSoft)
            )
    }

    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(value)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private func errorLabel(_ text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(text)
                .font(DesignSystem.Typography.caption)
        }
        .foregroundStyle(DesignSystem.Colors.danger)
    }

    // MARK: - Validation

    private var isEditValid: Bool {
        let trimmed = editTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if !editStoryPointsText.isEmpty {
            guard let sp = Int(editStoryPointsText),
                  AppConstants.fibonacciSequence.contains(sp) else { return false }
        }
        return true
    }

    // MARK: - Data Loading

    private func loadTicketData() {
        editTitle = ticket.title
        editDescription = ticket.descriptionText ?? ""
        editPriority = ticket.priority
        editStoryPointsText = ticket.storyPoints.map(String.init) ?? ""
        editLabelsText = ticket.labels.joined(separator: ", ")
        editAssignee = ticket.assignee
        editStartDate = ticket.startDate
        editEndDate = ticket.endDate
        editStatus = ticket.status
        storyPointsError = nil
        titleError = nil
    }

    // MARK: - Save

    private func saveChanges() {
        guard isEditValid else { return }

        let trimmedTitle = editTitle.trimmingCharacters(in: .whitespaces)
        if trimmedTitle.isEmpty {
            titleError = "Title is required."
            return
        }

        let parsedSP: Int? = editStoryPointsText.isEmpty ? nil : Int(editStoryPointsText)
        if let sp = parsedSP, viewModel.validateStoryPoints(sp) != nil {
            storyPointsError = viewModel.validateStoryPoints(sp)
            return
        }

        let parsedLabels = editLabelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        viewModel.updateTicket(
            ticket,
            title: trimmedTitle,
            description: editDescription,
            priority: editPriority,
            storyPoints: parsedSP,
            clearStoryPoints: editStoryPointsText.isEmpty && ticket.storyPoints != nil,
            labels: parsedLabels,
            assignee: editAssignee,
            clearAssignee: editAssignee == nil && ticket.assignee != nil,
            startDate: editStartDate,
            clearStartDate: editStartDate == nil && ticket.startDate != nil,
            endDate: editEndDate,
            clearEndDate: editEndDate == nil && ticket.endDate != nil,
            status: editStatus
        )

        isEditing = false
    }
}

// MARK: - TicketStatus Display Extension

extension TicketStatus {
    var displayName: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Done"
        }
    }

    var color: Color {
        switch self {
        case .backlog: return DesignSystem.Colors.textSecondary
        case .todo: return Color.blue
        case .inProgress: return DesignSystem.Colors.warning
        case .inReview: return Color.purple
        case .done: return DesignSystem.Colors.success
        }
    }
}

// MARK: - FlowLayout

/// A simple flow layout that wraps items to the next line when they exceed available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return LayoutResult(size: CGSize(width: totalWidth, height: totalHeight), positions: positions)
    }
}
