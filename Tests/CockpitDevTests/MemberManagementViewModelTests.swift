import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class MemberManagementViewModelTests: XCTestCase {

    private var viewModel: MemberManagementViewModel!
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var workspace: Workspace!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            Workspace.self, Repository.self, Member.self, Ticket.self,
            Sprint.self, Document.self, OpenSpecEntry.self,
            DocSpecVersion.self, AppNotification.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext

        workspace = Workspace(name: "Test Workspace")
        modelContext.insert(workspace)
        try modelContext.save()

        viewModel = MemberManagementViewModel()
        viewModel.configure(
            workspace: workspace,
            modelContext: modelContext,
            currentUserRole: .owner
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        workspace = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_membersEmpty() {
        XCTAssertTrue(viewModel.members.isEmpty)
    }

    func testInitialState_noErrors() {
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testCanManageMembers_ownerRole() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .owner)
        XCTAssertTrue(viewModel.canManageMembers)
    }

    func testCanManageMembers_adminRole() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .admin)
        XCTAssertTrue(viewModel.canManageMembers)
    }

    func testCanManageMembers_memberRole() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .member)
        XCTAssertFalse(viewModel.canManageMembers)
    }

    func testCanManageMembers_viewerRole() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .viewer)
        XCTAssertFalse(viewModel.canManageMembers)
    }

    // MARK: - Invite Member Tests

    func testInviteMember_success() {
        let user = GitLabUser(
            id: 42,
            username: "testuser",
            name: "Test User",
            avatarUrl: nil,
            email: "test@example.com",
            state: "active",
            webUrl: nil
        )

        let success = viewModel.inviteMember(user)

        XCTAssertTrue(success)
        XCTAssertEqual(viewModel.members.count, 1)
        XCTAssertEqual(viewModel.members.first?.username, "testuser")
        XCTAssertEqual(viewModel.members.first?.displayName, "Test User")
        XCTAssertEqual(viewModel.members.first?.role, .member) // Default role
        XCTAssertEqual(viewModel.members.first?.gitlabUserId, 42)
    }

    func testInviteMember_duplicateDetection() {
        // Add a member first
        let member = Member(
            gitlabUserId: 42,
            username: "testuser",
            displayName: "Test User",
            role: .member
        )
        member.workspace = workspace
        workspace.members.append(member)
        modelContext.insert(member)
        try? modelContext.save()

        // Try to invite the same user
        let user = GitLabUser(
            id: 42,
            username: "testuser",
            name: "Test User",
            avatarUrl: nil,
            email: nil,
            state: "active",
            webUrl: nil
        )

        let success = viewModel.inviteMember(user)

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage!.contains("already a member"))
    }

    func testInviteMember_insufficientPermissions_viewer() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .viewer)

        let user = GitLabUser(
            id: 42,
            username: "testuser",
            name: "Test User",
            avatarUrl: nil,
            email: nil,
            state: "active",
            webUrl: nil
        )

        let success = viewModel.inviteMember(user)

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage!.contains("Insufficient permissions"))
    }

    func testInviteMember_insufficientPermissions_member() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .member)

        let user = GitLabUser(
            id: 42,
            username: "testuser",
            name: "Test User",
            avatarUrl: nil,
            email: nil,
            state: "active",
            webUrl: nil
        )

        let success = viewModel.inviteMember(user)

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
    }

    // MARK: - Role Change Tests

    func testChangeRole_success() {
        let member = addMember(username: "testuser", role: .member)

        let success = viewModel.changeRole(of: member, to: .admin)

        XCTAssertTrue(success)
        XCTAssertEqual(member.role, .admin)
    }

    func testChangeRole_lastOwnerProtection() {
        let owner = addMember(username: "onlyowner", role: .owner)

        let success = viewModel.changeRole(of: owner, to: .admin)

        XCTAssertFalse(success)
        XCTAssertEqual(owner.role, .owner) // Role unchanged
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage!.contains("last Owner"))
    }

    func testChangeRole_multipleOwners_allowed() {
        let owner1 = addMember(username: "owner1", role: .owner)
        _ = addMember(username: "owner2", role: .owner)

        let success = viewModel.changeRole(of: owner1, to: .admin)

        XCTAssertTrue(success)
        XCTAssertEqual(owner1.role, .admin)
    }

    func testChangeRole_insufficientPermissions() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .member)
        let member = addMember(username: "testuser", role: .member)

        let success = viewModel.changeRole(of: member, to: .admin)

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
    }

    // MARK: - Remove Member Tests

    func testRemoveMember_success() {
        let member = addMember(username: "testuser", role: .member)
        XCTAssertEqual(viewModel.members.count, 1)

        viewModel.confirmRemoval(of: member)
        XCTAssertTrue(viewModel.showRemoveConfirmation)

        viewModel.executeRemoval()
        XCTAssertEqual(viewModel.members.count, 0)
    }

    func testRemoveMember_ticketUnassignmentCascade() {
        let member = addMember(username: "testuser", role: .member)

        // Create tickets assigned to this member
        let ticket1 = Ticket(title: "Ticket 1")
        ticket1.assignee = member
        ticket1.workspace = workspace
        workspace.tickets.append(ticket1)
        modelContext.insert(ticket1)

        let ticket2 = Ticket(title: "Ticket 2")
        ticket2.assignee = member
        ticket2.workspace = workspace
        workspace.tickets.append(ticket2)
        modelContext.insert(ticket2)
        try? modelContext.save()

        // Remove the member
        viewModel.confirmRemoval(of: member)
        viewModel.executeRemoval()

        // Verify tickets are unassigned
        XCTAssertNil(ticket1.assignee)
        XCTAssertNil(ticket2.assignee)
    }

    func testRemoveMember_lastOwnerProtection() {
        let owner = addMember(username: "onlyowner", role: .owner)

        viewModel.confirmRemoval(of: owner)

        // Should show error, not confirmation
        XCTAssertFalse(viewModel.showRemoveConfirmation)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage!.contains("last Owner"))
    }

    func testRemoveMember_insufficientPermissions() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .member)
        let member = addMember(username: "testuser", role: .member)

        viewModel.confirmRemoval(of: member)

        XCTAssertFalse(viewModel.showRemoveConfirmation)
        XCTAssertTrue(viewModel.showError)
    }

    // MARK: - Skill Profile Tests

    func testUpdateSkillProfile_success() {
        let member = addMember(username: "testuser", role: .member)

        let success = viewModel.updateSkillProfile(of: member, to: .beHeavy)

        XCTAssertTrue(success)
        XCTAssertEqual(member.skillProfile, .beHeavy)
    }

    func testUpdateSkillProfile_clearProfile() {
        let member = addMember(username: "testuser", role: .member)
        member.skillProfile = .fullstack

        let success = viewModel.updateSkillProfile(of: member, to: nil)

        XCTAssertTrue(success)
        XCTAssertNil(member.skillProfile)
    }

    func testUpdateSkillProfile_insufficientPermissions() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .member)
        let member = addMember(username: "testuser", role: .member)

        let success = viewModel.updateSkillProfile(of: member, to: .feHeavy)

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.showError)
    }

    // MARK: - Viewer Enforcement Tests

    func testViewerEnforcement_checkModifyPermission() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .viewer)

        let canModify = viewModel.checkModifyPermission()

        XCTAssertFalse(canModify)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage!.contains("Insufficient permissions"))
    }

    func testViewerEnforcement_ownerCanModify() {
        viewModel.configure(workspace: workspace, modelContext: modelContext, currentUserRole: .owner)

        let canModify = viewModel.checkModifyPermission()

        XCTAssertTrue(canModify)
        XCTAssertFalse(viewModel.showError)
    }

    // MARK: - Duplicate Detection Tests

    func testIsDuplicateMember_true() {
        _ = addMember(username: "testuser", role: .member, gitlabUserId: 42)

        XCTAssertTrue(viewModel.isDuplicateMember(gitlabUserId: 42))
    }

    func testIsDuplicateMember_false() {
        _ = addMember(username: "testuser", role: .member, gitlabUserId: 42)

        XCTAssertFalse(viewModel.isDuplicateMember(gitlabUserId: 99))
    }

    // MARK: - Search Tests

    func testSearchUsers_queryTooShort() async {
        viewModel.searchQuery = "a"
        await viewModel.searchUsers()

        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testSearchUsers_noClient_showsError() async {
        viewModel.searchQuery = "test"
        await viewModel.searchUsers()

        XCTAssertTrue(viewModel.showError)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Reset Tests

    func testResetInviteForm() {
        viewModel.searchQuery = "test"
        viewModel.errorMessage = "Some error"
        viewModel.showError = true

        viewModel.resetInviteForm()

        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
    }

    // MARK: - Helpers

    @discardableResult
    private func addMember(username: String, role: MemberRole, gitlabUserId: Int = Int.random(in: 1...10000)) -> Member {
        let member = Member(
            gitlabUserId: gitlabUserId,
            username: username,
            displayName: username.capitalized,
            role: role
        )
        member.workspace = workspace
        workspace.members.append(member)
        modelContext.insert(member)
        try? modelContext.save()
        return member
    }
}
