import SwiftUI
import SwiftData

// MARK: - Settings Section

/// Represents the available sections in workspace settings.
enum SettingsSection: String, CaseIterable, Identifiable {
    case repositories = "Repositories"
    case members = "Members"
    case notifications = "Notifications"
    case general = "General"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .repositories: return "externaldrive.connected.to.line.below"
        case .members: return "person.2"
        case .notifications: return "bell"
        case .general: return "gearshape"
        }
    }
}

// MARK: - Workspace Settings View

/// Container view for workspace settings with a sidebar navigation.
struct WorkspaceSettingsView: View {

    let workspace: Workspace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.credentialServices) private var credentialServices
    @State private var selectedSection: SettingsSection = .repositories
    @State private var showGitLabConnect: Bool = false
    @State private var connectedGitLabInstanceURL: URL?

    var body: some View {
        HSplitView {
            // Settings sidebar
            settingsSidebar
                .frame(minWidth: 180, maxWidth: 200)

            // Settings content
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await refreshConnectedGitLabInstance()
        }
        .sheet(isPresented: $showGitLabConnect, onDismiss: {
            Task {
                await refreshConnectedGitLabInstance()
            }
        }) {
            GitLabConnectSheet(viewModel: GitLabOAuthViewModel(
                oauthService: credentialServices.gitLabOAuthService,
                encryptionService: credentialServices.encryptionService
            ))
        }
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
            Text("SETTINGS")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .padding(.horizontal, DesignSystem.Spacing.spacing12)
                .padding(.top, DesignSystem.Spacing.spacing16)
                .padding(.bottom, DesignSystem.Spacing.spacing8)

            ForEach(SettingsSection.allCases) { section in
                settingsSidebarItem(section)
            }

            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.spacing8)
        .background(DesignSystem.Colors.surface)
    }

    private func settingsSidebarItem(_ section: SettingsSection) -> some View {
        Button {
            withAnimation(DesignSystem.Motion.fast) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: selectedSection == section ? .medium : .regular))
                    .foregroundStyle(
                        selectedSection == section
                            ? DesignSystem.Colors.accent
                            : DesignSystem.Colors.textSecondary
                    )

                Text(section.rawValue)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(
                        selectedSection == section
                            ? DesignSystem.Colors.textPrimary
                            : DesignSystem.Colors.textSecondary
                    )

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(
                selectedSection == section
                    ? DesignSystem.Colors.accentSoft
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
    }

    // MARK: - Content

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .repositories:
            RepositoriesSettingsView(
                workspace: workspace,
                gitLabAPIClient: GitLabAPIClient(
                    baseURL: currentGitLabBaseURL,
                    tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
                ),
                cloneTokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
            )
        case .members:
            MembersSettingsView(
                workspace: workspace,
                gitLabAPIClient: GitLabAPIClient(
                    baseURL: currentGitLabBaseURL,
                    tokenProvider: { try await credentialServices.gitLabOAuthService.getValidToken() }
                )
            )
        case .notifications:
            NotificationSettingsView(workspace: workspace, notificationService: NotificationService())
        case .general:
            GeneralSettingsView(showGitLabConnect: $showGitLabConnect)
        }
    }

    private var currentGitLabBaseURL: URL {
        connectedGitLabInstanceURL
            ?? URL(string: workspace.gitlabInstanceURL)
            ?? URL(string: AppConstants.defaultGitLabInstanceURL)!
    }

    @MainActor
    private func refreshConnectedGitLabInstance() async {
        guard let storedURL = await credentialServices.gitLabOAuthService.getInstanceURL() else {
            connectedGitLabInstanceURL = nil
            return
        }

        connectedGitLabInstanceURL = storedURL

        if workspace.gitlabInstanceURL != storedURL.absoluteString {
            workspace.gitlabInstanceURL = storedURL.absoluteString
            workspace.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private func settingsPlaceholder(title: String, description: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Text(title)
                .font(DesignSystem.Typography.headingMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(description)
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - General Settings View

/// General workspace settings including GitLab account connection.
struct GeneralSettingsView: View {

    @Binding var showGitLabConnect: Bool
    @Environment(\.credentialServices) private var credentialServices
    @State private var connectionState: GitLabConnectionState = .disconnected
    @State private var connectedUser: GitLabUser?
    @State private var instanceURLString: String = AppConstants.defaultGitLabInstanceURL

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing24) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("General")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Manage your GitLab connection and workspace preferences.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            // GitLab Connection Section
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing12) {
                Text("GitLab Account")
                    .font(DesignSystem.Typography.headingSmall)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                gitLabAccountCard
                .padding(DesignSystem.Spacing.spacing16)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                )
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .task {
            await refreshGitLabConnection()
        }
        .onChange(of: showGitLabConnect) { _, isPresented in
            if !isPresented {
                Task {
                    await refreshGitLabConnection()
                }
            }
        }
    }

    private var gitLabAccountCard: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: gitLabAccountIcon)
                .font(.system(size: 20))
                .foregroundStyle(gitLabAccountIconColor)
                .frame(width: 36, height: 36)
                .background(gitLabAccountIconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                Text(gitLabAccountTitle)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(gitLabAccountSubtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(gitLabAccountButtonTitle) {
                showGitLabConnect = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.388, green: 0.4, blue: 0.945))
        }
    }

    private var gitLabAccountIcon: String {
        switch connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .needsReauthentication:
            return "exclamationmark.arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle.fill"
        default:
            return "network"
        }
    }

    private var gitLabAccountIconColor: Color {
        switch connectionState {
        case .connected:
            return DesignSystem.Colors.success
        case .needsReauthentication, .error:
            return DesignSystem.Colors.warning
        default:
            return DesignSystem.Colors.accent
        }
    }

    private var gitLabAccountTitle: String {
        switch connectionState {
        case .connected:
            return connectedUser.map { "\($0.name) (@\($0.username))" } ?? "GitLab Connected"
        case .needsReauthentication:
            return "Reconnect GitLab"
        case .error:
            return "GitLab Connection Needs Attention"
        default:
            return "Connect to GitLab"
        }
    }

    private var gitLabAccountSubtitle: String {
        switch connectionState {
        case .connected:
            return "Connected to \(instanceURLString)."
        case .needsReauthentication:
            return "Your GitLab session expired. Reconnect to continue syncing repositories, issues, and merge requests."
        case .error(let message):
            return message
        default:
            return "Authenticate with your GitLab instance to sync repositories, issues, and merge requests."
        }
    }

    private var gitLabAccountButtonTitle: String {
        switch connectionState {
        case .connected:
            return "Manage"
        case .needsReauthentication:
            return "Reconnect"
        default:
            return "Connect"
        }
    }

    @MainActor
    private func refreshGitLabConnection() async {
        let storedURL = await credentialServices.gitLabOAuthService.getInstanceURL()
        if let storedURL {
            instanceURLString = storedURL.absoluteString
        }

        let hasToken = await credentialServices.gitLabOAuthService.hasValidToken()
        guard hasToken else {
            connectedUser = nil
            connectionState = storedURL == nil ? .disconnected : .needsReauthentication
            return
        }

        do {
            let user = try await credentialServices.gitLabOAuthService.fetchCurrentUserProfile()
            connectedUser = user
            connectionState = .connected(
                username: user.username,
                displayName: user.name,
                avatarURL: user.avatarUrl
            )
        } catch {
            connectedUser = nil
            connectionState = await credentialServices.gitLabOAuthService.isTokenExpired()
                ? .needsReauthentication
                : .error(error.localizedDescription)
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Workspace.self, Repository.self, configurations: config)
    let workspace = Workspace(name: "Test Workspace")
    container.mainContext.insert(workspace)

    return WorkspaceSettingsView(workspace: workspace)
        .modelContainer(container)
        .frame(width: 800, height: 500)
}
