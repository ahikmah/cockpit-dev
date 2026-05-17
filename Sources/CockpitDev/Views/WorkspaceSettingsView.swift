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
    @State private var selectedSection: SettingsSection = .repositories
    @State private var showGitLabConnect: Bool = false

    var body: some View {
        HSplitView {
            // Settings sidebar
            settingsSidebar
                .frame(minWidth: 180, maxWidth: 200)

            // Settings content
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showGitLabConnect) {
            let encryptionService = EncryptionService()
            let oauthService = GitLabOAuthService(encryptionService: encryptionService)
            GitLabConnectSheet(viewModel: GitLabOAuthViewModel(
                oauthService: oauthService,
                encryptionService: encryptionService
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
                gitLabAPIClient: {
                    let encryptionService = EncryptionService()
                    let oauthService = GitLabOAuthService(encryptionService: encryptionService)
                    // Read instance URL from stored token data in keychain
                    let tokenJSON: String? = try? encryptionService.retrieveFromKeychain(key: "gitlab.oauth.tokenData")
                    var baseURL = URL(string: "https://gitlab.com")!
                    if let json = tokenJSON,
                       let data = json.data(using: .utf8),
                       let tokenData = try? JSONDecoder().decode(StoredTokenData.self, from: data),
                       let storedURL = URL(string: tokenData.instanceURL) {
                        baseURL = storedURL
                    }
                    return GitLabAPIClient(
                        baseURL: baseURL,
                        tokenProvider: { try await oauthService.getValidToken() }
                    )
                }()
            )
        case .members:
            MembersSettingsView(workspace: workspace)
        case .notifications:
            NotificationSettingsView(workspace: workspace, notificationService: NotificationService())
        case .general:
            GeneralSettingsView(showGitLabConnect: $showGitLabConnect)
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

                HStack(spacing: DesignSystem.Spacing.spacing12) {
                    Image(systemName: "network")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                        Text("Connect to GitLab")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        Text("Authenticate with your GitLab instance to sync repositories, issues, and merge requests.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    Button("Connect") {
                        showGitLabConnect = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.388, green: 0.4, blue: 0.945))
                }
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
