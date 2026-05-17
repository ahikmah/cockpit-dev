import SwiftUI

// MARK: - Clone Missing Repos Sheet

/// Sheet displayed when "Open in IDE" is triggered and some repositories
/// are not available locally. Shows which repos need cloning and allows
/// the user to confirm or skip.
///
/// Implements Requirement 14.3: Prompt user to confirm cloning missing repos.
struct CloneMissingReposSheet: View {
    @Bindable var viewModel: IDEContextViewModel
    let credentials: GitCredentials
    var onDismiss: () -> Void = {}

    @State private var selectedDirectory: URL?
    @State private var showDirectoryPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection

            Divider()

            // Missing repos list
            missingReposSection

            // Stale repos section (if any)
            if !viewModel.staleRepositories.isEmpty {
                staleReposSection
            }

            Divider()

            // Directory picker
            directorySection

            // Action buttons
            actionButtons
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: 560)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Repositories Not Available Locally", systemImage: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("The following repositories need to be cloned before opening in your IDE.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var missingReposSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Missing Repositories (\(viewModel.missingRepositories.count))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(viewModel.missingRepositories, id: \.0.id) { repo, availability in
                HStack(spacing: 10) {
                    Image(systemName: availabilityIcon(for: availability))
                        .foregroundStyle(availabilityColor(for: availability))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.name)
                            .font(.system(size: 13, weight: .medium))

                        Text(availabilityDescription(for: availability))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var staleReposSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stale Paths Detected", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)

            Text("These repositories were previously cloned but their local paths no longer exist. They will be re-cloned.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ForEach(viewModel.staleRepositories, id: \.0.id) { repo, stalePath in
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundStyle(.orange)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.name)
                            .font(.system(size: 13, weight: .medium))
                        Text("Previous path: \(stalePath)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clone Directory")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack {
                if let dir = selectedDirectory {
                    Text(dir.path)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Select a directory for cloning repositories...")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button("Browse...") {
                    showDirectoryPicker = true
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedDirectory = url
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Skip & Open Available") {
                Task {
                    await viewModel.skipCloneAndOpen()
                    onDismiss()
                }
            }
            .controlSize(.regular)

            Spacer()

            Button("Cancel") {
                onDismiss()
            }
            .controlSize(.regular)

            Button("Clone & Open") {
                guard let directory = selectedDirectory else { return }
                Task {
                    await viewModel.confirmCloneAndOpen(
                        baseDirectory: directory,
                        credentials: credentials
                    )
                    onDismiss()
                }
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .disabled(selectedDirectory == nil)
        }
    }

    // MARK: - Helpers

    private func availabilityIcon(for availability: RepositoryAvailability) -> String {
        switch availability {
        case .available:
            return "checkmark.circle.fill"
        case .notCloned:
            return "arrow.down.circle"
        case .stalePath:
            return "folder.badge.questionmark"
        }
    }

    private func availabilityColor(for availability: RepositoryAvailability) -> Color {
        switch availability {
        case .available:
            return .green
        case .notCloned:
            return .blue
        case .stalePath:
            return .orange
        }
    }

    private func availabilityDescription(for availability: RepositoryAvailability) -> String {
        switch availability {
        case .available:
            return "Available locally"
        case .notCloned:
            return "Not cloned — will be cloned"
        case .stalePath(let path):
            return "Stale path: \(path) — will be re-cloned"
        }
    }
}

// MARK: - Clone Progress Sheet

/// Sheet displayed during batch clone operations showing per-repo progress.
struct CloneProgressSheet: View {
    @Bindable var viewModel: IDEContextViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Cloning Repositories...", systemImage: "arrow.down.circle")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            // Overall progress
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Overall Progress")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.completedCloneCount)/\(viewModel.totalReposToClone)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: viewModel.overallProgress, total: 100)
            }

            Divider()

            // Per-repo progress
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.missingRepositories, id: \.0.id) { repo, _ in
                        repoProgressRow(repo: repo)
                    }
                }
            }
            .frame(maxHeight: 200)

            // Results (if any)
            if !viewModel.cloneResults.isEmpty {
                Divider()
                resultsSection
            }
        }
        .padding(24)
        .frame(minWidth: 440, maxWidth: 520)
    }

    private func repoProgressRow(repo: Repository) -> some View {
        HStack(spacing: 10) {
            // Status icon
            if let result = viewModel.cloneResults.first(where: { $0.repositoryId == repo.id }) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.isSuccess ? .green : .red)
            } else if let progress = viewModel.cloneProgress[repo.id] {
                if progress.phase == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))

                if let progress = viewModel.cloneProgress[repo.id] {
                    Text(progress.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Percentage
            if let progress = viewModel.cloneProgress[repo.id],
               let percentage = progress.percentage {
                Text("\(percentage)%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasCloneFailures {
                Label(
                    "\(viewModel.failedClones.count) failed, \(viewModel.successfulClones.count) succeeded",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)

                ForEach(viewModel.failedClones, id: \.repositoryId) { result in
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 10))
                        Text("\(result.repositoryName): \(result.error?.localizedDescription ?? "Unknown error")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("All repositories cloned successfully", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
    }
}
