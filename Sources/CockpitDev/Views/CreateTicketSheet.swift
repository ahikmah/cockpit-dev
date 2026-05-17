import SwiftUI
import SwiftData

/// Sheet for creating a new ticket with title (required), description, priority,
/// story points (Fibonacci validation), labels, assignee, and dates.
struct CreateTicketSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: TicketManagementViewModel

    /// Members available for assignment in the current workspace.
    let members: [Member]

    // MARK: - Form State

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedPriority: TicketPriority? = nil
    @State private var storyPointsText: String = ""
    @State private var labelsText: String = ""
    @State private var selectedAssignee: Member? = nil
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var showStartDatePicker: Bool = false
    @State private var showEndDatePicker: Bool = false

    // MARK: - Validation State

    @State private var titleError: String?
    @State private var storyPointsError: String?
    @State private var isSubmitting: Bool = false

    /// Whether the form is valid for submission.
    private var isFormValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return false }
        if !storyPointsText.isEmpty {
            guard let sp = Int(storyPointsText),
                  AppConstants.fibonacciSequence.contains(sp) else { return false }
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formContent
            Divider()
            footer
        }
        .frame(width: 520, height: 600)
        .background(DesignSystem.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.xl))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Create Ticket")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

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

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                titleField
                descriptionField
                priorityField
                storyPointsField
                labelsField
                assigneeField
                dateFields
            }
            .padding(DesignSystem.Spacing.spacing24)
        }
    }

    // MARK: - Title Field

    private var titleField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Text("Title")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("*")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.danger)
            }

            TextField("Enter ticket title", text: $title)
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
                .onChange(of: title) { _, newValue in
                    validateTitle(newValue)
                }

            if let error = titleError {
                errorLabel(error)
            }
        }
    }

    // MARK: - Description Field

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Description")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            TextEditor(text: $descriptionText)
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
    }

    // MARK: - Priority Field

    private var priorityField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Priority")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Picker("Priority", selection: $selectedPriority) {
                Text("None").tag(nil as TicketPriority?)
                ForEach(TicketPriority.allCases, id: \.self) { priority in
                    Text(priority.displayName).tag(priority as TicketPriority?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Story Points Field

    private var storyPointsField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Story Points")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(spacing: DesignSystem.Spacing.spacing8) {
                ForEach(AppConstants.fibonacciSequence, id: \.self) { value in
                    Button {
                        storyPointsText = String(value)
                        storyPointsError = nil
                    } label: {
                        Text("\(value)")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundStyle(
                                storyPointsText == String(value)
                                    ? .white
                                    : DesignSystem.Colors.textPrimary
                            )
                            .frame(width: 36, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                                    .fill(
                                        storyPointsText == String(value)
                                            ? DesignSystem.Colors.accent
                                            : DesignSystem.Colors.accentSoft
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !storyPointsText.isEmpty {
                    Button {
                        storyPointsText = ""
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
    }

    // MARK: - Labels Field

    private var labelsField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Labels")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            TextField("Comma-separated labels (e.g., bug, frontend)", text: $labelsText)
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
    }

    // MARK: - Assignee Field

    private var assigneeField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Assignee")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Picker("Assignee", selection: $selectedAssignee) {
                Text("Unassigned").tag(nil as Member?)
                ForEach(members, id: \.id) { member in
                    Text(member.displayName).tag(member as Member?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Date Fields

    private var dateFields: some View {
        HStack(spacing: DesignSystem.Spacing.spacing16) {
            // Start Date
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Start Date")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                HStack {
                    if let date = startDate {
                        DatePicker("", selection: Binding(
                            get: { date },
                            set: { startDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()

                        Button {
                            startDate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            startDate = Date()
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

            // End Date
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("End Date")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                HStack {
                    if let date = endDate {
                        DatePicker("", selection: Binding(
                            get: { date },
                            set: { endDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()

                        Button {
                            endDate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            endDate = Date()
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
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .font(DesignSystem.Typography.bodyMedium)

            Spacer()

            Button {
                createTicket()
            } label: {
                Text("Create Ticket")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignSystem.Spacing.spacing16)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                            .fill(isFormValid ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isFormValid || isSubmitting)
        }
        .padding(DesignSystem.Spacing.spacing24)
    }

    // MARK: - Helpers

    private func errorLabel(_ text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.spacing4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(text)
                .font(DesignSystem.Typography.caption)
        }
        .foregroundStyle(DesignSystem.Colors.danger)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Validation

    private func validateTitle(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty && !input.isEmpty {
            withAnimation(DesignSystem.Motion.fast) {
                titleError = "Title is required."
            }
        } else {
            withAnimation(DesignSystem.Motion.fast) {
                titleError = nil
            }
        }
    }

    // MARK: - Actions

    private func createTicket() {
        guard isFormValid else { return }

        isSubmitting = true

        let parsedStoryPoints: Int? = storyPointsText.isEmpty ? nil : Int(storyPointsText)
        let parsedLabels: [String] = labelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let success = viewModel.createTicket(
            title: title,
            description: descriptionText.isEmpty ? nil : descriptionText,
            priority: selectedPriority,
            storyPoints: parsedStoryPoints,
            labels: parsedLabels,
            assignee: selectedAssignee,
            startDate: startDate,
            endDate: endDate
        )

        isSubmitting = false

        if success {
            dismiss()
        } else {
            // ViewModel will have set its own error
            if let error = viewModel.errorMessage {
                storyPointsError = error.contains("Fibonacci") ? error : nil
                titleError = error.contains("title") ? error : nil
            }
        }
    }
}

// MARK: - TicketPriority Display Extension

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
