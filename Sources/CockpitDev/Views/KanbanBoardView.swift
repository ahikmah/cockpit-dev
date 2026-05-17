import SwiftUI
import SwiftData

/// The main Kanban board view displaying tickets organized in horizontal columns.
/// Supports drag-and-drop between columns, filtering, and column configuration.
struct KanbanBoardView: View {
    @Bindable var viewModel: KanbanViewModel
    @State private var currentUserRole: MemberRole = .owner

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with filters
            filterToolbar

            Divider()

            // Kanban columns in horizontal scroll
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(viewModel.columns.enumerated()), id: \.element) { index, column in
                        if index > 0 {
                            columnSeparator
                        }

                        KanbanColumnView(
                            columnName: column,
                            tickets: viewModel.columnTickets[column] ?? [],
                            isDropTarget: viewModel.dropTargetColumn == column,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing12)
            }
        }
        .alert("Sync Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .sheet(isPresented: $viewModel.showColumnConfig) {
            ColumnConfigurationSheet(viewModel: viewModel, currentUserRole: currentUserRole)
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isSyncing {
                syncIndicator
            }
        }
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Assignee filter
            Menu {
                Button("All Assignees") {
                    viewModel.filterAssignee = nil
                    viewModel.refreshBoard()
                }
                Divider()
                ForEach(viewModel.availableMembers, id: \.id) { member in
                    Button(member.displayName) {
                        viewModel.filterAssignee = member
                        viewModel.refreshBoard()
                    }
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "person")
                        .font(.system(size: 12))
                    Text(viewModel.filterAssignee?.displayName ?? "Assignee")
                        .font(DesignSystem.Typography.bodyRegular)
                }
                .foregroundColor(viewModel.filterAssignee != nil ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)

            // Label filter
            Menu {
                Button("All Labels") {
                    viewModel.filterLabel = nil
                    viewModel.refreshBoard()
                }
                Divider()
                ForEach(viewModel.availableLabels, id: \.self) { label in
                    Button(label) {
                        viewModel.filterLabel = label
                        viewModel.refreshBoard()
                    }
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "tag")
                        .font(.system(size: 12))
                    Text(viewModel.filterLabel ?? "Label")
                        .font(DesignSystem.Typography.bodyRegular)
                }
                .foregroundColor(viewModel.filterLabel != nil ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)

            // Sprint filter
            Menu {
                Button("All Sprints") {
                    viewModel.filterSprint = nil
                    viewModel.refreshBoard()
                }
                Divider()
                ForEach(viewModel.availableSprints, id: \.id) { sprint in
                    Button(sprint.name) {
                        viewModel.filterSprint = sprint
                        viewModel.refreshBoard()
                    }
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text(viewModel.filterSprint?.name ?? "Sprint")
                        .font(DesignSystem.Typography.bodyRegular)
                }
                .foregroundColor(viewModel.filterSprint != nil ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)

            // Clear filters button
            if viewModel.filterAssignee != nil || viewModel.filterLabel != nil || viewModel.filterSprint != nil {
                Button {
                    viewModel.clearFilters()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Clear")
                            .font(DesignSystem.Typography.bodyRegular)
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Column configuration button
            if viewModel.canConfigureColumns(currentUserRole: currentUserRole) {
                Button {
                    viewModel.showColumnConfig = true
                } label: {
                    HStack(spacing: DesignSystem.Spacing.spacing4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                        Text("Columns")
                            .font(DesignSystem.Typography.bodyRegular)
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing16)
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Column Separator

    private var columnSeparator: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border)
            .frame(width: 1)
            .padding(.vertical, DesignSystem.Spacing.spacing12)
            .opacity(0.6)
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
        .padding(DesignSystem.Spacing.spacing12)
    }
}

// MARK: - Column Configuration Sheet

/// Sheet for managing Kanban column configuration (add, remove, rename, reorder).
struct ColumnConfigurationSheet: View {
    @Bindable var viewModel: KanbanViewModel
    let currentUserRole: MemberRole
    @Environment(\.dismiss) private var dismiss
    @State private var newColumnName: String = ""
    @State private var editingColumn: String?
    @State private var editedName: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var columnToDelete: String?

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.spacing16) {
            // Header
            HStack {
                Text("Column Configuration")
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

            // Column list with reorder
            List {
                ForEach(viewModel.columns, id: \.self) { column in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .font(.system(size: 12))

                        if editingColumn == column {
                            TextField("Column name", text: $editedName)
                                .textFieldStyle(.plain)
                                .font(DesignSystem.Typography.bodyRegular)
                                .onSubmit {
                                    if viewModel.renameColumn(oldName: column, newName: editedName, currentUserRole: currentUserRole) {
                                        editingColumn = nil
                                    }
                                }
                        } else {
                            Text(column)
                                .font(DesignSystem.Typography.bodyRegular)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }

                        Spacer()

                        // Rename button
                        Button {
                            editingColumn = column
                            editedName = column
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)

                        // Delete button
                        Button {
                            columnToDelete = column
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.Colors.danger)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.columns.count <= 1)
                    }
                    .padding(.vertical, DesignSystem.Spacing.spacing4)
                }
                .onMove { source, destination in
                    _ = viewModel.reorderColumn(from: source, to: destination, currentUserRole: currentUserRole)
                }
            }
            .listStyle(.plain)

            Divider()

            // Add new column
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                TextField("New column name", text: $newColumnName)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignSystem.Typography.bodyRegular)

                Button("Add") {
                    if viewModel.addColumn(name: newColumnName, currentUserRole: currentUserRole) {
                        newColumnName = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .disabled(newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Column count indicator
            Text("\(viewModel.columns.count) of \(AppConstants.maxKanbanColumns) columns")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 480, height: 500)
        .alert("Delete Column", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                columnToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let column = columnToDelete {
                    _ = viewModel.removeColumn(name: column, currentUserRole: currentUserRole)
                }
                columnToDelete = nil
            }
        } message: {
            if let column = columnToDelete {
                Text("Are you sure you want to remove the \"\(column)\" column? Tickets in this column will be moved to the first column.")
            }
        }
    }
}
