import SwiftUI
import UniformTypeIdentifiers

/// Sheet view for AI-powered PRD breakdown workflow.
/// Supports document input (paste or file), preview with edit/remove/add,
/// confirmation flow, and re-evaluation comparison.
struct PRDBreakdownSheet: View {

    // MARK: - Properties

    @Bindable var viewModel: PRDBreakdownViewModel
    @Environment(\.dismiss) private var dismiss

    /// Whether this is a re-evaluation of an existing PRD.
    var isReEvaluation: Bool = false

    // MARK: - State

    @State private var showFileImporter: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if viewModel.confirmationSuccess {
                successView
            } else if viewModel.showReEvaluation, let result = viewModel.reEvaluationResult {
                reEvaluationView(result: result)
            } else if viewModel.showPreview {
                previewListView
            } else {
                inputView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .frame(maxWidth: 800, maxHeight: 700)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
            if !viewModel.showPreview {
                Button("Retry") {
                    Task { await viewModel.retryBreakdown() }
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $viewModel.showEditSheet) {
            if let ticket = viewModel.editingTicket {
                EditGeneratedTicketSheet(ticket: ticket) { edited in
                    viewModel.saveEditedTicket(edited)
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            EditGeneratedTicketSheet(ticket: nil) { newTicket in
                viewModel.addTicket(newTicket)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .text, UTType("public.markdown") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text(isReEvaluation ? "Re-evaluate PRD" : "AI PRD Breakdown")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(isReEvaluation
                     ? "Compare updated PRD against existing tickets"
                     : "Break down a PRD into actionable development tickets")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.spacing20)
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            // Input area
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
                HStack {
                    Text("PRD Content")
                        .font(DesignSystem.Typography.headingSmall)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Spacer()

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import File", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                TextEditor(text: $viewModel.prdContent)
                    .font(DesignSystem.Typography.bodyRegular)
                    .frame(minHeight: 250)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))

                if viewModel.prdContent.isEmpty {
                    Text("Paste your PRD content above or import a file.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                } else {
                    Text("\(viewModel.prdContent.count) characters")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }

            Spacer()

            // Action buttons
            HStack {
                if viewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.progressMessage)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                if isReEvaluation {
                    Button("Re-evaluate") {
                        Task { await viewModel.reEvaluatePRD() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.prdContent.isEmpty || viewModel.isProcessing)
                } else {
                    Button("Analyze PRD") {
                        Task { await viewModel.breakdownPRD() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.prdContent.isEmpty || viewModel.isProcessing)
                }
            }
        }
        .padding(DesignSystem.Spacing.spacing20)
    }

    // MARK: - Preview List View

    private var previewListView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            // Toolbar
            HStack {
                Text("\(viewModel.generatedTickets.count) tickets generated")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                Button {
                    viewModel.startAddingTicket()
                } label: {
                    Label("Add Ticket", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button("Back") {
                    viewModel.showPreview = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing20)
            .padding(.top, DesignSystem.Spacing.spacing12)

            // Ticket list
            List {
                ForEach(Array(viewModel.generatedTickets.enumerated()), id: \.element.id) { index, ticket in
                    GeneratedTicketRow(ticket: ticket) {
                        viewModel.startEditing(at: index)
                    } onRemove: {
                        viewModel.removeTicket(at: index)
                    }
                }
                .onDelete { offsets in
                    viewModel.removeTickets(at: offsets)
                }
            }
            .listStyle(.inset)

            // Confirm button
            HStack {
                if viewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.progressMessage)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Button("Confirm & Create Tickets") {
                    Task { await viewModel.confirmTickets() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.generatedTickets.isEmpty || viewModel.isProcessing)
            }
            .padding(DesignSystem.Spacing.spacing20)
        }
    }

    // MARK: - Re-Evaluation View

    private func reEvaluationView(result: ReEvaluationResult) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            // Summary
            HStack(spacing: DesignSystem.Spacing.spacing16) {
                summaryBadge(count: result.newTickets.count, label: "New", color: DesignSystem.Colors.success)
                summaryBadge(count: result.changedTickets.count, label: "Changed", color: DesignSystem.Colors.warning)
                summaryBadge(count: result.removedTicketTitles.count, label: "Removed", color: DesignSystem.Colors.danger)
                summaryBadge(count: result.unchangedTicketTitles.count, label: "Unchanged", color: DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing20)
            .padding(.top, DesignSystem.Spacing.spacing12)

            // Details list
            List {
                if !result.newTickets.isEmpty {
                    Section("New Tickets") {
                        ForEach(result.newTickets) { ticket in
                            ReEvaluationTicketRow(ticket: ticket, changeType: .new)
                        }
                    }
                }

                if !result.changedTickets.isEmpty {
                    Section("Changed Tickets") {
                        ForEach(result.changedTickets, id: \.suggested.id) { changed in
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                                Text("Was: \(changed.existingTitle)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    .strikethrough()
                                ReEvaluationTicketRow(ticket: changed.suggested, changeType: .changed)
                            }
                        }
                    }
                }

                if !result.removedTicketTitles.isEmpty {
                    Section("Removed Tickets") {
                        ForEach(result.removedTicketTitles, id: \.self) { title in
                            HStack {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(DesignSystem.Colors.danger)
                                Text(title)
                                    .font(DesignSystem.Typography.bodyRegular)
                                    .strikethrough()
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                }

                if !result.unchangedTicketTitles.isEmpty {
                    Section("Unchanged Tickets") {
                        ForEach(result.unchangedTicketTitles, id: \.self) { title in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DesignSystem.Colors.success)
                                Text(title)
                                    .font(DesignSystem.Typography.bodyRegular)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            // Action buttons
            HStack {
                if viewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.progressMessage)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Button("Back") {
                    viewModel.showReEvaluation = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

                Button("Apply Changes") {
                    Task { await viewModel.applyReEvaluation() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)
            }
            .padding(DesignSystem.Spacing.spacing20)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: DesignSystem.Spacing.spacing24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.success)

            Text(viewModel.progressMessage)
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Button("Done") {
                viewModel.reset()
                dismiss()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func summaryBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing2) {
            Text("\(count)")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(color)
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if let content = try? String(contentsOf: url, encoding: .utf8) {
                viewModel.prdContent = content
            }
        case .failure(let error):
            viewModel.errorMessage = "Failed to import file: \(error.localizedDescription)"
            viewModel.showError = true
        }
    }
}

// MARK: - Generated Ticket Row

/// A row displaying a generated ticket in the preview list.
struct GeneratedTicketRow: View {
    let ticket: GeneratedTicket
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text(ticket.title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)

                Text(ticket.description)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    priorityBadge(ticket.priority)
                    storyPointsBadge(ticket.estimatedStoryPoints)
                    skillBadge(ticket.skillClassification)
                }
                .padding(.top, DesignSystem.Spacing.spacing2)
            }

            Spacer()

            VStack(spacing: DesignSystem.Spacing.spacing4) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.accent)

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.danger)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.spacing4)
    }

    private func priorityBadge(_ priority: TicketPriority) -> some View {
        Text(priority.rawValue.capitalized)
            .font(DesignSystem.Typography.caption)
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(priorityColor(priority).opacity(0.15))
            .foregroundStyle(priorityColor(priority))
            .clipShape(Capsule())
    }

    private func storyPointsBadge(_ points: Int) -> some View {
        Text("\(points) SP")
            .font(DesignSystem.Typography.caption)
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(DesignSystem.Colors.accentSoft)
            .foregroundStyle(DesignSystem.Colors.accent)
            .clipShape(Capsule())
    }

    private func skillBadge(_ skill: SkillProfile) -> some View {
        Text(skillLabel(skill))
            .font(DesignSystem.Typography.caption)
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(DesignSystem.Colors.border.opacity(0.5))
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .clipShape(Capsule())
    }

    private func priorityColor(_ priority: TicketPriority) -> Color {
        switch priority {
        case .critical: return DesignSystem.Colors.danger
        case .high: return DesignSystem.Colors.warning
        case .medium: return DesignSystem.Colors.accent
        case .low: return DesignSystem.Colors.textSecondary
        }
    }

    private func skillLabel(_ skill: SkillProfile) -> String {
        switch skill {
        case .beHeavy: return "Backend"
        case .feHeavy: return "Frontend"
        case .fullstack: return "Fullstack"
        }
    }
}

// MARK: - Re-Evaluation Ticket Row

/// A row displaying a ticket in the re-evaluation comparison view.
struct ReEvaluationTicketRow: View {
    let ticket: GeneratedTicket
    let changeType: ChangeType

    enum ChangeType {
        case new, changed
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: changeType == .new ? "plus.circle.fill" : "arrow.triangle.2.circlepath")
                .foregroundStyle(changeType == .new ? DesignSystem.Colors.success : DesignSystem.Colors.warning)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text(ticket.title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(ticket.description)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Text(ticket.priority.rawValue.capitalized)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    Text("\(ticket.estimatedStoryPoints) SP")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Edit Generated Ticket Sheet

/// Sheet for editing or creating a generated ticket.
struct EditGeneratedTicketSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var priority: TicketPriority
    @State private var storyPoints: Int
    @State private var skillClassification: SkillProfile
    @State private var dependenciesText: String

    let isNew: Bool
    let onSave: (GeneratedTicket) -> Void

    init(ticket: GeneratedTicket?, onSave: @escaping (GeneratedTicket) -> Void) {
        self.isNew = ticket == nil
        self.onSave = onSave

        let t = ticket ?? GeneratedTicket(
            title: "",
            description: "",
            priority: .medium,
            estimatedStoryPoints: 3,
            skillClassification: .fullstack,
            suggestedDependencies: []
        )

        _title = State(initialValue: t.title)
        _description = State(initialValue: t.description)
        _priority = State(initialValue: t.priority)
        _storyPoints = State(initialValue: t.estimatedStoryPoints)
        _skillClassification = State(initialValue: t.skillClassification)
        _dependenciesText = State(initialValue: t.suggestedDependencies.joined(separator: "\n"))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "Add Ticket" : "Edit Ticket")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.spacing20)

            Divider()

            Form {
                Section("Title") {
                    TextField("Ticket title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TicketPriority.allCases, id: \.self) { p in
                            Text(p.rawValue.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Story Points") {
                    Picker("Story Points", selection: $storyPoints) {
                        ForEach(AppConstants.fibonacciSequence, id: \.self) { sp in
                            Text("\(sp)").tag(sp)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Skill Classification") {
                    Picker("Skill", selection: $skillClassification) {
                        Text("Backend").tag(SkillProfile.beHeavy)
                        Text("Frontend").tag(SkillProfile.feHeavy)
                        Text("Fullstack").tag(SkillProfile.fullstack)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Dependencies (one per line)") {
                    TextEditor(text: $dependenciesText)
                        .frame(minHeight: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(isNew ? "Add" : "Save") {
                    let dependencies = dependenciesText
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    let ticket = GeneratedTicket(
                        title: title,
                        description: description,
                        priority: priority,
                        estimatedStoryPoints: storyPoints,
                        skillClassification: skillClassification,
                        suggestedDependencies: dependencies
                    )
                    onSave(ticket)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
            .padding(DesignSystem.Spacing.spacing20)
        }
        .frame(minWidth: 500, minHeight: 500)
    }
}
