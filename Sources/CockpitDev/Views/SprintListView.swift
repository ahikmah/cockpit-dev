import SwiftUI
import SwiftData

/// Displays a list of sprints with progress indicators and creation controls.
struct SprintListView: View {
    @Bindable var viewModel: SprintViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with create button
            sprintHeader

            Divider()

            if viewModel.sprints.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.spacing12) {
                        ForEach(viewModel.sprints, id: \.id) { sprint in
                            SprintRowView(sprint: sprint, viewModel: viewModel)
                                .onTapGesture {
                                    viewModel.selectedSprint = sprint
                                }
                        }
                    }
                    .padding(DesignSystem.Spacing.spacing16)
                }
            }
        }
        .sheet(isPresented: $viewModel.showCreateSprint) {
            CreateSprintSheet(viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var sprintHeader: some View {
        HStack {
            Text("Sprints")
                .font(DesignSystem.Typography.headingMedium)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            Button {
                viewModel.showCreateSprint = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                    Text("New Sprint")
                        .font(DesignSystem.Typography.bodyMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.spacing12)
                .padding(.vertical, DesignSystem.Spacing.spacing6)
                .background(DesignSystem.Colors.accent)
                .cornerRadius(DesignSystem.Radius.small)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "flag")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No Sprints")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Create a sprint to organize work into time-boxed iterations.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                viewModel.showCreateSprint = true
            } label: {
                Text("Create Sprint")
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.spacing16)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(DesignSystem.Colors.accent)
                    .cornerRadius(DesignSystem.Radius.small)
            }
            .buttonStyle(.plain)
            .padding(.top, DesignSystem.Spacing.spacing8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sprint Row View

/// A single sprint row showing name, dates, status, and progress bar.
struct SprintRowView: View {
    let sprint: Sprint
    @Bindable var viewModel: SprintViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing8) {
            // Top row: name and status
            HStack {
                Text(sprint.name)
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                // Status badge
                Text(viewModel.statusLabel(for: sprint))
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundColor(viewModel.statusColor(for: sprint))
                    .padding(.horizontal, DesignSystem.Spacing.spacing8)
                    .padding(.vertical, DesignSystem.Spacing.spacing2)
                    .background(viewModel.statusColor(for: sprint).opacity(0.1))
                    .cornerRadius(DesignSystem.Radius.small)
            }

            // Date range
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                Text("\(viewModel.formatDate(sprint.startDate)) – \(viewModel.formatDate(sprint.endDate))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            // Progress section
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DesignSystem.Colors.border)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * progressFraction, height: 6)
                    }
                }
                .frame(height: 6)

                // Progress text
                Text(viewModel.formattedProgress(for: sprint))
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 36, alignment: .trailing)
            }

            // Bottom row: ticket count and SP
            HStack(spacing: DesignSystem.Spacing.spacing12) {
                Label("\(viewModel.ticketCount(for: sprint)) tickets", systemImage: "ticket")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                Label("\(viewModel.doneStoryPoints(for: sprint))/\(viewModel.totalStoryPoints(for: sprint)) SP", systemImage: "star")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textTertiary)

                Spacer()

                if viewModel.isSprintCompleted(sprint) && viewModel.incompleteTicketCount(for: sprint) > 0 {
                    Text("\(viewModel.incompleteTicketCount(for: sprint)) incomplete")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.warning)
                }
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.Radius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(
                    viewModel.selectedSprint?.id == sprint.id
                        ? DesignSystem.Colors.accent
                        : DesignSystem.Colors.border,
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    private var progressFraction: CGFloat {
        CGFloat(viewModel.progressPercentage(for: sprint) / 100.0)
    }

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

// MARK: - Create Sprint Sheet

/// Sheet for creating a new sprint with name and date validation.
struct CreateSprintSheet: View {
    @Bindable var viewModel: SprintViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.spacing20) {
            // Header
            HStack {
                Text("Create Sprint")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Divider()

            // Form fields
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing16) {
                // Name field
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                    Text("Sprint Name")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    TextField("e.g., Sprint 1", text: $viewModel.newSprintName)
                        .textFieldStyle(.roundedBorder)
                        .font(DesignSystem.Typography.bodyRegular)
                }

                // Start date
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                    Text("Start Date")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    DatePicker("", selection: $viewModel.newSprintStartDate, displayedComponents: .date)
                        .labelsHidden()
                }

                // End date
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                    Text("End Date")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    DatePicker("", selection: $viewModel.newSprintEndDate, displayedComponents: .date)
                        .labelsHidden()
                }

                // Validation error
                if let error = viewModel.formValidationError {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundColor(DesignSystem.Colors.danger)
                }
            }

            Spacer()

            // Create button
            HStack {
                Spacer()
                Button {
                    Task {
                        await viewModel.createSprint()
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing6) {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Create Sprint")
                            .font(DesignSystem.Typography.bodyMedium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, DesignSystem.Spacing.spacing16)
                    .padding(.vertical, DesignSystem.Spacing.spacing8)
                    .background(DesignSystem.Colors.accent)
                    .cornerRadius(DesignSystem.Radius.small)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 420, height: 380)
    }
}
