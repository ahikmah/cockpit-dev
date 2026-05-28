import SwiftUI
import SwiftData

/// GitLab-style ticket composer for creating a local ticket and pushing it to GitLab.
struct CreateTicketSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TicketManagementViewModel

    let members: [Member]
    let sprints: [Sprint]
    let defaultSprint: Sprint?

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedPriority: TicketPriority?
    @State private var storyPointsText: String = ""
    @State private var labelsText: String = ""
    @State private var selectedAssignee: Member?
    @State private var selectedSprint: Sprint?
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var titleError: String?
    @State private var storyPointsError: String?
    @State private var isSubmitting: Bool = false
    @State private var isConfidential: Bool = false

    init(
        viewModel: TicketManagementViewModel,
        members: [Member],
        sprints: [Sprint] = [],
        defaultSprint: Sprint? = nil
    ) {
        self.viewModel = viewModel
        self.members = members
        self.sprints = sprints
        self.defaultSprint = defaultSprint
        self._selectedSprint = State(initialValue: defaultSprint)
    }

    private var isFormValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if !storyPointsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = Int(storyPointsText), value > 0 else { return false }
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.spacing24) {
                    primaryColumn
                    metadataColumn
                }
                .padding(DesignSystem.Spacing.spacing24)
            }

            Divider()
            footer
        }
        .frame(width: 980, height: 720)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl))
        .onAppear {
            if selectedSprint == nil {
                selectedSprint = defaultSprint
            }
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("New issue")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Create a GitLab issue and keep planning metadata in CockpitDev.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing16)
    }

    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
            formField("Type") {
                staticTypeField
            }

            formField("Title (required)") {
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.bodyRegular)
                    .padding(.horizontal, DesignSystem.Spacing.spacing12)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(fieldBackground(titleError != nil))
                    .onChange(of: title) { _, newValue in
                        titleError = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !newValue.isEmpty
                            ? "Title is required."
                            : nil
                    }
            }

            if let titleError {
                errorLabel(titleError)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
                Text("Description")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Use markdown for tables, code blocks, images, task lists, and mermaid diagrams.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                MarkdownEditorView(
                    text: $descriptionText,
                    placeholder: "Write a description or drag your notes here...",
                    minHeight: 330
                )
            }

            Toggle(isOn: $isConfidential) {
                Text("Turn on confidentiality: limit visibility to project members with at least the Planner role.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .toggleStyle(.checkbox)
        }
        .frame(minWidth: 560, maxWidth: .infinity, alignment: .topLeading)
    }

    private var staticTypeField: some View {
        HStack(spacing: DesignSystem.Spacing.spacing8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text("Issue")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing12)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .frame(width: 220, alignment: .leading)
        .background(fieldBackground(false))
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .help("Only GitLab issues are supported for now.")
    }

    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
            metadataPicker(
                title: "Assignee",
                value: selectedAssignee?.displayName ?? "None - assign later"
            ) {
                Picker("Assignee", selection: $selectedAssignee) {
                    Text("None").tag(nil as Member?)
                    ForEach(members, id: \.id) { member in
                        Text(member.displayName).tag(member as Member?)
                    }
                }
                .labelsHidden()
            }

            metadataTextField(
                title: "Labels",
                value: $labelsText,
                placeholder: "backend, scheduler"
            )

            metadataPicker(
                title: "Milestone",
                value: selectedSprint?.name ?? "None"
            ) {
                Picker("Milestone", selection: $selectedSprint) {
                    Text("None").tag(nil as Sprint?)
                    ForEach(sprints, id: \.id) { sprint in
                        Text(sprint.name).tag(sprint as Sprint?)
                    }
                }
                .labelsHidden()
            }

            metadataPicker(
                title: "Priority",
                value: selectedPriority?.displayName ?? "None"
            ) {
                Picker("Priority", selection: $selectedPriority) {
                    Text("None").tag(nil as TicketPriority?)
                    ForEach(TicketPriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority as TicketPriority?)
                    }
                }
                .labelsHidden()
            }

            metadataTextField(
                title: "Story Points",
                value: $storyPointsText,
                placeholder: "8"
            )
            .onChange(of: storyPointsText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                storyPointsError = trimmed.isEmpty || (Int(trimmed) ?? 0) > 0
                    ? nil
                    : "Story points must be positive."
            }

            if let storyPointsError {
                errorLabel(storyPointsError)
            }

            dateMetadata

            Text("Planning metadata such as start date, story points, and dependencies stays in the planning DB. GitLab receives issue fields it supports.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 300, alignment: .topLeading)
    }

    private var dateMetadata: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing10) {
            metadataHeader("Dates", value: dateSummary)

            HStack(spacing: DesignSystem.Spacing.spacing10) {
                dateControl("Start", date: $startDate)
                dateControl("Due", date: $endDate)
            }
        }
        .padding(.bottom, DesignSystem.Spacing.spacing12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()

            Button {
                createTicket()
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Create issue")
                        .font(DesignSystem.Typography.bodyMedium)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || isSubmitting)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing24)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
    }

    private func formField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            Text(title)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            content()
        }
    }

    private func metadataPicker<Content: View>(
        title: String,
        value: String,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            metadataHeader(title, value: value)
            picker()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, DesignSystem.Spacing.spacing12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func metadataTextField(title: String, value: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            metadataHeader(title, value: value.wrappedValue.isEmpty ? "None" : value.wrappedValue)
            TextField(placeholder, text: value)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.bodyRegular)
                .padding(.horizontal, DesignSystem.Spacing.spacing10)
                .padding(.vertical, DesignSystem.Spacing.spacing6)
                .background(fieldBackground(false))
        }
        .padding(.bottom, DesignSystem.Spacing.spacing12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func metadataHeader(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(value)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func dateControl(_ title: String, date: Binding<Date?>) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            if let currentDate = date.wrappedValue {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    DatePicker("", selection: Binding(
                        get: { currentDate },
                        set: { date.wrappedValue = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()

                    Button {
                        date.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    date.wrappedValue = Date()
                } label: {
                    Label("Set", systemImage: "calendar")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateSummary: String {
        let start = startDate.map(formatDate) ?? "None"
        let due = endDate.map(formatDate) ?? "None"
        return "Start: \(start)\nDue: \(due)"
    }

    private func fieldBackground(_ hasError: Bool) -> some View {
        RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                    .stroke(hasError ? DesignSystem.Colors.danger : DesignSystem.Colors.border, lineWidth: 1)
            }
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.danger)
    }

    private func createTicket() {
        guard isFormValid else { return }

        isSubmitting = true
        let parsedStoryPoints = Int(storyPointsText.trimmingCharacters(in: .whitespacesAndNewlines))
        let parsedLabels = labelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let success = viewModel.createTicket(
            title: title,
            description: descriptionText.isEmpty ? nil : descriptionText,
            priority: selectedPriority,
            storyPoints: parsedStoryPoints,
            labels: parsedLabels,
            assignee: selectedAssignee,
            sprint: selectedSprint,
            startDate: startDate,
            endDate: endDate
        )

        isSubmitting = false
        if success {
            dismiss()
        } else if let error = viewModel.errorMessage {
            titleError = error.localizedCaseInsensitiveContains("title") ? error : nil
            storyPointsError = error.localizedCaseInsensitiveContains("story") ? error : nil
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

extension TicketPriority {
    var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var iconName: String {
        switch self {
        case .critical: return "exclamationmark.3"
        case .high: return "exclamationmark.2"
        case .medium: return "exclamationmark"
        case .low: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .critical: return DesignSystem.Colors.danger
        case .high: return Color.orange
        case .medium: return DesignSystem.Colors.warning
        case .low: return DesignSystem.Colors.textSecondary
        }
    }
}
