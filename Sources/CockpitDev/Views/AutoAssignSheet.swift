import SwiftUI
import SwiftData

/// Sheet view for the auto-assign workflow.
/// Displays computed assignment suggestions with accept/modify/reject controls
/// and a confirmation flow to apply assignments and sync to GitLab.
struct AutoAssignSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AutoAssignViewModel()

    let tickets: [Ticket]
    let sprint: Sprint
    let workspace: Workspace
    let modelContext: ModelContext
    let syncEngine: SyncEngine?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            if viewModel.isProcessing {
                processingView
            } else if viewModel.confirmationSuccess {
                successView
            } else if viewModel.showSuggestions {
                suggestionListView
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: 800, minHeight: 500, idealHeight: 600)
        .onAppear {
            viewModel.configure(
                modelContext: modelContext,
                syncEngine: syncEngine,
                workspace: workspace
            )
            viewModel.computeAssignments(tickets: tickets, sprint: sprint)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $viewModel.showMemberPicker) {
            memberPickerView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Assign Tickets")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                if viewModel.showSuggestions {
                    Text("\(viewModel.assignableSuggestions.count) assignable, \(viewModel.unassignableSuggestions.count) unassignable")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if viewModel.showSuggestions && !viewModel.confirmationSuccess {
                HStack(spacing: 8) {
                    Button("Accept All") {
                        viewModel.acceptAll()
                    }
                    .buttonStyle(.bordered)

                    Button("Reject All") {
                        viewModel.rejectAll()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(viewModel.progressMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(viewModel.progressMessage)
                .font(.system(size: 14, weight: .medium))
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No suggestions available")
                .font(.system(size: 14, weight: .medium))
            Text("Select tickets with story points to auto-assign.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Suggestion List

    private var suggestionListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Assignable suggestions
                    if !viewModel.assignableSuggestions.isEmpty {
                        Section {
                            ForEach(viewModel.assignableSuggestions) { suggestion in
                                suggestionRow(suggestion)
                            }
                        } header: {
                            sectionHeader("Suggested Assignments", count: viewModel.assignableSuggestions.count)
                        }
                    }

                    // Unassignable suggestions
                    if !viewModel.unassignableSuggestions.isEmpty {
                        Section {
                            ForEach(viewModel.unassignableSuggestions) { suggestion in
                                unassignableRow(suggestion)
                            }
                        } header: {
                            sectionHeader("Unassignable / Skipped", count: viewModel.unassignableSuggestions.count)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Divider()

            // Footer with confirm button
            footerView
        }
    }

    // MARK: - Suggestion Row

    private func suggestionRow(_ suggestion: AssignmentSuggestion) -> some View {
        let decision = viewModel.decisions[suggestion.id]
        let isRejected = decision == .rejected

        return HStack(spacing: 12) {
            // Ticket info
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.ticket.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(isRejected)
                    .foregroundStyle(isRejected ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let sp = suggestion.ticket.storyPoints {
                        Text("\(sp) SP")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if !suggestion.ticket.labels.isEmpty {
                        Text(suggestion.ticket.labels.prefix(2).joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Assigned member
            VStack(alignment: .trailing, spacing: 2) {
                if case .modified(let member) = decision {
                    Text(member.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                } else if let member = suggestion.suggestedMember {
                    Text(member.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isRejected ? .secondary : .primary)
                }

                Text("\(suggestion.resultingWorkload) SP workload")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 4) {
                Button {
                    viewModel.accept(suggestionId: suggestion.id)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(decision == .accepted ? .green : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Accept")

                Button {
                    viewModel.startModifying(suggestionId: suggestion.id)
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(isModifiedDecision(decision) ? .orange : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Modify")

                Button {
                    viewModel.reject(suggestionId: suggestion.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(isRejected ? .red : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Reject")
            }
            .font(.system(size: 18))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isRejected ? Color.secondary.opacity(0.05) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Unassignable Row

    private func unassignableRow(_ suggestion: AssignmentSuggestion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.ticket.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                if let sp = suggestion.ticket.storyPoints {
                    Text("\(sp) SP")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let reason = suggestion.reason {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
            }

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.secondary))

            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("\(viewModel.acceptedCount) to assign, \(viewModel.rejectedCount) rejected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button("Confirm Assignments") {
                Task {
                    await viewModel.confirmAssignments()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.acceptedCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Member Picker

    private var memberPickerView: some View {
        VStack(spacing: 16) {
            Text("Select Member")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.top, 16)

            List(workspace.members, id: \.id) { member in
                Button {
                    if let suggestionId = viewModel.modifyingSuggestionId {
                        viewModel.modifyAssignment(suggestionId: suggestionId, newMember: member)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(member.skillProfile?.rawValue ?? "No skill profile")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 200)

            Button("Cancel") {
                viewModel.showMemberPicker = false
                viewModel.modifyingSuggestionId = nil
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 16)
        }
        .frame(width: 300, height: 350)
    }

    // MARK: - Helpers

    private func isModifiedDecision(_ decision: SuggestionDecision?) -> Bool {
        guard let decision = decision else { return false }
        if case .modified = decision { return true }
        return false
    }
}
