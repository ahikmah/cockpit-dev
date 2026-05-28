import SwiftUI

/// Sheet for creating a new workspace with name validation.
/// Validates: 1-100 characters, alphanumeric + spaces + hyphens + underscores.
/// Detects duplicate names and displays appropriate errors.
struct CreateWorkspaceSheet: View {

    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: WorkspaceListViewModel

    @State private var workspaceName: String = ""
    @State private var validationError: String?
    @State private var isSubmitting: Bool = false
    @FocusState private var isNameFieldFocused: Bool

    /// Whether the name field currently has valid input.
    private var isNameValid: Bool {
        let trimmed = workspaceName.trimmingCharacters(in: .whitespaces)
        return viewModel.validateWorkspaceName(trimmed) == nil
            && !trimmed.isEmpty
            && !viewModel.isDuplicateName(trimmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                nameField
                validationMessage
            }
            .padding(DesignSystem.Spacing.spacing24)

            Divider()

            // Footer
            footer
        }
        .frame(width: 420)
        .background(DesignSystem.Colors.surfaceElevated)
        .activateContainingWindow()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isNameFieldFocused = true
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Create Workspace")
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

    private var nameField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
            Text("Workspace Name")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            TextField("e.g., My Project", text: $workspaceName)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Typography.bodyRegular)
                .focused($isNameFieldFocused)
                .onChange(of: workspaceName) { _, newValue in
                    validateInput(newValue)
                }
                .onSubmit {
                    createWorkspace()
                }

            // Character count
            HStack {
                Spacer()
                Text("\(workspaceName.count)/\(AppConstants.maxWorkspaceNameLength)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(
                        workspaceName.count > AppConstants.maxWorkspaceNameLength
                            ? DesignSystem.Colors.danger
                            : DesignSystem.Colors.textTertiary
                    )
            }
        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        if let error = validationError {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                Text(error)
                    .font(DesignSystem.Typography.caption)
            }
            .foregroundStyle(DesignSystem.Colors.danger)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

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
                createWorkspace()
            } label: {
                Text("Create")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignSystem.Spacing.spacing16)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.small)
                            .fill(isNameValid ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isNameValid || isSubmitting)
        }
        .padding(DesignSystem.Spacing.spacing24)
    }

    // MARK: - Actions

    private func validateInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Don't show errors for empty field (user hasn't typed yet)
        guard !trimmed.isEmpty else {
            validationError = nil
            return
        }

        // Check character validity and length
        if let error = viewModel.validateWorkspaceName(trimmed) {
            withAnimation(DesignSystem.Motion.fast) {
                validationError = error
            }
            return
        }

        // Check duplicate
        if viewModel.isDuplicateName(trimmed) {
            withAnimation(DesignSystem.Motion.fast) {
                validationError = "A workspace with this name already exists."
            }
            return
        }

        withAnimation(DesignSystem.Motion.fast) {
            validationError = nil
        }
    }

    private func createWorkspace() {
        guard isNameValid else { return }

        isSubmitting = true
        let success = viewModel.createWorkspace(name: workspaceName)
        isSubmitting = false

        if success {
            dismiss()
        } else {
            // ViewModel will have set its own error
            validationError = viewModel.errorMessage
        }
    }
}

#Preview {
    CreateWorkspaceSheet(viewModel: WorkspaceListViewModel())
}
