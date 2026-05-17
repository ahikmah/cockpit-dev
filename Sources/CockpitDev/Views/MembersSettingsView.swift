import SwiftUI
import SwiftData

// MARK: - Members Settings View

/// Displays the list of workspace members with role management, skill profiles,
/// invite flow, and member removal capabilities.
struct MembersSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = MemberManagementViewModel()

    let workspace: Workspace
    var gitLabAPIClient: GitLabAPIClient?
    var currentUserRole: MemberRole = .owner

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing24) {
            headerSection
            memberListSection
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onAppear {
            viewModel.configure(
                workspace: workspace,
                modelContext: modelContext,
                gitLabAPIClient: gitLabAPIClient,
                currentUserRole: currentUserRole
            )
        }
        .sheet(isPresented: $viewModel.showInviteSheet) {
            InviteMemberSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(
            "Remove Member",
            isPresented: $viewModel.showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                viewModel.executeRemoval()
            }
            Button("Cancel", role: .cancel) {
                viewModel.memberPendingRemoval = nil
            }
        } message: {
            if let member = viewModel.memberPendingRemoval {
                Text("Remove \"\(member.displayName)\" from this workspace? They will be unassigned from all tickets.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
                Text("Members")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Manage team members and their roles in this workspace.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            if viewModel.canManageMembers {
                inviteButton
            }
        }
    }

    private var inviteButton: some View {
        Button {
            viewModel.resetInviteForm()
            viewModel.showInviteSheet = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                Text("Invite Member")
                    .font(DesignSystem.Typography.bodyMedium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, DesignSystem.Spacing.spacing12)
            .padding(.vertical, DesignSystem.Spacing.spacing6)
            .background(DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Member List

    private var memberListSection: some View {
        Group {
            if viewModel.members.isEmpty {
                emptyState
            } else {
                VStack(spacing: DesignSystem.Spacing.spacing8) {
                    ForEach(viewModel.members, id: \.id) { member in
                        MemberRowView(
                            member: member,
                            canManage: viewModel.canManageMembers,
                            onRoleChange: { newRole in
                                viewModel.changeRole(of: member, to: newRole)
                            },
                            onSkillProfileChange: { profile in
                                viewModel.updateSkillProfile(of: member, to: profile)
                            },
                            onRemove: {
                                viewModel.confirmRemoval(of: member)
                            }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.spacing12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No members")
                .font(DesignSystem.Typography.headingSmall)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Invite team members from GitLab to collaborate.")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.spacing48)
    }
}

// MARK: - Member Row View

/// Displays a single member with avatar, name, role badge, skill profile, and actions.
struct MemberRowView: View {

    let member: Member
    let canManage: Bool
    let onRoleChange: (MemberRole) -> Void
    let onSkillProfileChange: (SkillProfile?) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Avatar
            memberAvatar

            // Member info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing2) {
                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Text(member.displayName)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    roleBadge
                }

                Text("@\(member.username)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Skill profile picker
            if canManage {
                skillProfilePicker
            } else {
                skillProfileBadge
            }

            // Role picker (only for managers)
            if canManage {
                rolePicker
            }

            // Remove button (only for managers)
            if canManage {
                removeButton
            }
        }
        .padding(DesignSystem.Spacing.spacing12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Avatar

    private var memberAvatar: some View {
        Group {
            if let avatarURL = member.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(DesignSystem.Colors.accentSoft)
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(member.displayName.prefix(1)).uppercased())
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.accent)
            )
    }

    // MARK: - Role Badge

    private var roleBadge: some View {
        Text(member.role.rawValue.capitalized)
            .font(DesignSystem.Typography.captionMedium)
            .foregroundStyle(roleColor)
            .padding(.horizontal, DesignSystem.Spacing.spacing6)
            .padding(.vertical, DesignSystem.Spacing.spacing2)
            .background(roleColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private var roleColor: Color {
        switch member.role {
        case .owner:
            return DesignSystem.Colors.warning
        case .admin:
            return DesignSystem.Colors.accent
        case .member:
            return DesignSystem.Colors.success
        case .viewer:
            return DesignSystem.Colors.textSecondary
        }
    }

    // MARK: - Skill Profile

    private var skillProfilePicker: some View {
        Menu {
            Button("None") {
                onSkillProfileChange(nil)
            }
            ForEach(SkillProfile.allCases, id: \.self) { profile in
                Button(profile.displayName) {
                    onSkillProfileChange(profile)
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.spacing4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10))
                Text(member.skillProfile?.displayName ?? "No Skill")
                    .font(DesignSystem.Typography.caption)
            }
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.spacing8)
            .padding(.vertical, DesignSystem.Spacing.spacing4)
            .background(DesignSystem.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var skillProfileBadge: some View {
        Group {
            if let profile = member.skillProfile {
                Text(profile.displayName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.spacing8)
                    .padding(.vertical, DesignSystem.Spacing.spacing4)
                    .background(DesignSystem.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
        }
    }

    // MARK: - Role Picker

    private var rolePicker: some View {
        Menu {
            ForEach(MemberRole.allCases, id: \.self) { role in
                Button(role.rawValue.capitalized) {
                    onRoleChange(role)
                }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(DesignSystem.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change role")
    }

    // MARK: - Remove Button

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.danger)
                .frame(width: 28, height: 28)
                .background(DesignSystem.Colors.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
        }
        .buttonStyle(.plain)
        .help("Remove member from workspace")
    }
}

// MARK: - Invite Member Sheet

/// Sheet for searching and inviting GitLab users to the workspace.
struct InviteMemberSheet: View {

    @Bindable var viewModel: MemberManagementViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.spacing24) {
            // Header
            VStack(spacing: DesignSystem.Spacing.spacing4) {
                Text("Invite Member")
                    .font(DesignSystem.Typography.headingMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Search for a GitLab user to invite to this workspace.")
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Search Input
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing6) {
                Text("Search GitLab Users")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                HStack(spacing: DesignSystem.Spacing.spacing8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    TextField("Username or display name (min 2 characters)", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.bodyRegular)
                        .onSubmit {
                            Task {
                                await viewModel.searchUsers()
                            }
                        }

                    if viewModel.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(DesignSystem.Spacing.spacing8)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.medium)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                )

                Text("Enter at least 2 characters and press Return to search.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            // Search button
            Button {
                Task {
                    await viewModel.searchUsers()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.spacing4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                    Text("Search")
                        .font(DesignSystem.Typography.bodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
                .frame(maxWidth: .infinity)
                .background(
                    viewModel.searchQuery.count < 2
                        ? DesignSystem.Colors.accent.opacity(0.5)
                        : DesignSystem.Colors.accent
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchQuery.count < 2)

            // Search Results
            if !viewModel.searchResults.isEmpty {
                searchResultsList
            }

            // Error display
            if let errorMessage = viewModel.errorMessage, viewModel.showError {
                HStack(spacing: DesignSystem.Spacing.spacing6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.danger)

                    Text(errorMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.danger)
                }
                .padding(DesignSystem.Spacing.spacing8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
            }

            // Close button
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, DesignSystem.Spacing.spacing16)
                .padding(.vertical, DesignSystem.Spacing.spacing8)
            }
        }
        .padding(DesignSystem.Spacing.spacing24)
        .frame(width: 480)
        .frame(minHeight: 300)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.spacing4) {
            Text("Results (\(viewModel.searchResults.count))")
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.spacing4) {
                    ForEach(viewModel.searchResults, id: \.id) { user in
                        GitLabUserRow(
                            user: user,
                            isAlreadyMember: viewModel.isDuplicateMember(gitlabUserId: user.id),
                            onInvite: {
                                let success = viewModel.inviteMember(user)
                                if success {
                                    dismiss()
                                }
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
}

// MARK: - GitLab User Row

/// Displays a GitLab user search result with invite action.
struct GitLabUserRow: View {

    let user: GitLabUser
    let isAlreadyMember: Bool
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.spacing12) {
            // Avatar
            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    userAvatarPlaceholder
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            } else {
                userAvatarPlaceholder
            }

            // User info
            VStack(alignment: .leading, spacing: 0) {
                Text(user.name)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("@\(user.username)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Invite button or already member indicator
            if isAlreadyMember {
                Text("Already a member")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            } else {
                Button {
                    onInvite()
                } label: {
                    Text("Invite")
                        .font(DesignSystem.Typography.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignSystem.Spacing.spacing12)
                        .padding(.vertical, DesignSystem.Spacing.spacing4)
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.spacing8)
        .padding(.vertical, DesignSystem.Spacing.spacing6)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.small))
    }

    private var userAvatarPlaceholder: some View {
        Circle()
            .fill(DesignSystem.Colors.accentSoft)
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(user.name.prefix(1)).uppercased())
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
            )
    }
}

// MARK: - SkillProfile Display Name Extension

extension SkillProfile {
    /// Human-readable display name for the skill profile.
    var displayName: String {
        switch self {
        case .beHeavy:
            return "BE Heavy"
        case .feHeavy:
            return "FE Heavy"
        case .fullstack:
            return "Fullstack"
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Workspace.self, Repository.self, Member.self, Ticket.self,
        Sprint.self, Document.self, OpenSpecEntry.self,
        DocSpecVersion.self, AppNotification.self,
        configurations: config
    )
    let workspace = Workspace(name: "Test Workspace")
    container.mainContext.insert(workspace)

    let member1 = Member(
        gitlabUserId: 1,
        username: "johndoe",
        displayName: "John Doe",
        role: .owner,
        skillProfile: .fullstack
    )
    member1.workspace = workspace
    workspace.members.append(member1)
    container.mainContext.insert(member1)

    let member2 = Member(
        gitlabUserId: 2,
        username: "janedoe",
        displayName: "Jane Doe",
        role: .admin,
        skillProfile: .feHeavy
    )
    member2.workspace = workspace
    workspace.members.append(member2)
    container.mainContext.insert(member2)

    return MembersSettingsView(workspace: workspace)
        .modelContainer(container)
        .frame(width: 700, height: 500)
}
