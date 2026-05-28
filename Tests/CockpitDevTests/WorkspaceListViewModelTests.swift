import XCTest
import SwiftData
@testable import CockpitDev

@MainActor
final class WorkspaceListViewModelTests: CockpitDevTestCase {

    private var viewModel: WorkspaceListViewModel!
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([Workspace.self, Repository.self, Member.self, Ticket.self, Sprint.self, Document.self, OpenSpecEntry.self, DocSpecVersion.self, AppNotification.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext

        viewModel = WorkspaceListViewModel()
        viewModel.configure(with: modelContext)
    }

    override func tearDown() async throws {
        viewModel = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Name Validation Tests

    func testValidateWorkspaceName_emptyName_returnsError() {
        let result = viewModel.validateWorkspaceName("")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("empty"))
    }

    func testValidateWorkspaceName_validName_returnsNil() {
        let result = viewModel.validateWorkspaceName("My Project")
        XCTAssertNil(result)
    }

    func testValidateWorkspaceName_validWithHyphensAndUnderscores_returnsNil() {
        let result = viewModel.validateWorkspaceName("my-project_2024")
        XCTAssertNil(result)
    }

    func testValidateWorkspaceName_tooLong_returnsError() {
        let longName = String(repeating: "a", count: 101)
        let result = viewModel.validateWorkspaceName(longName)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("100"))
    }

    func testValidateWorkspaceName_exactlyMaxLength_returnsNil() {
        let name = String(repeating: "a", count: 100)
        let result = viewModel.validateWorkspaceName(name)
        XCTAssertNil(result)
    }

    func testValidateWorkspaceName_disallowedCharacters_returnsError() {
        let result = viewModel.validateWorkspaceName("My Project!")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("letters, numbers, spaces, hyphens, and underscores"))
    }

    func testValidateWorkspaceName_specialCharacters_returnsError() {
        let invalidNames = ["test@project", "hello#world", "foo/bar", "a.b", "test$"]
        for name in invalidNames {
            let result = viewModel.validateWorkspaceName(name)
            XCTAssertNotNil(result, "Expected validation error for: \(name)")
        }
    }

    func testValidateWorkspaceName_singleCharacter_returnsNil() {
        let result = viewModel.validateWorkspaceName("A")
        XCTAssertNil(result)
    }

    // MARK: - Duplicate Detection Tests

    func testIsDuplicateName_noDuplicate_returnsFalse() {
        let result = viewModel.isDuplicateName("New Workspace")
        XCTAssertFalse(result)
    }

    func testIsDuplicateName_withExistingWorkspace_returnsTrue() {
        // Create a workspace first
        viewModel.createWorkspace(name: "Existing Workspace")

        let result = viewModel.isDuplicateName("Existing Workspace")
        XCTAssertTrue(result)
    }

    func testIsDuplicateName_caseInsensitive_returnsTrue() {
        viewModel.createWorkspace(name: "My Project")

        let result = viewModel.isDuplicateName("my project")
        XCTAssertTrue(result)
    }

    // MARK: - CRUD Tests

    func testCreateWorkspace_validName_succeeds() {
        let success = viewModel.createWorkspace(name: "Test Workspace")

        XCTAssertTrue(success)
        XCTAssertEqual(viewModel.workspaces.count, 1)
        XCTAssertEqual(viewModel.workspaces.first?.name, "Test Workspace")
    }

    func testCreateWorkspace_invalidName_fails() {
        let success = viewModel.createWorkspace(name: "")

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.workspaces.count, 0)
        XCTAssertTrue(viewModel.showError)
    }

    func testCreateWorkspace_duplicateName_fails() {
        viewModel.createWorkspace(name: "My Project")
        let success = viewModel.createWorkspace(name: "My Project")

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.workspaces.count, 1)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage?.contains("already exists") ?? false)
    }

    func testCreateWorkspace_trimsWhitespace() {
        let success = viewModel.createWorkspace(name: "  Trimmed Name  ")

        XCTAssertTrue(success)
        XCTAssertEqual(viewModel.workspaces.first?.name, "Trimmed Name")
    }

    func testCreateWorkspace_setsSelectedWorkspace() {
        viewModel.createWorkspace(name: "Selected Workspace")

        XCTAssertNotNil(viewModel.selectedWorkspace)
        XCTAssertEqual(viewModel.selectedWorkspace?.name, "Selected Workspace")
    }

    func testDeleteWorkspace_removesFromList() {
        viewModel.createWorkspace(name: "To Delete")
        let workspace = viewModel.workspaces.first!

        viewModel.deleteWorkspace(workspace)

        XCTAssertEqual(viewModel.workspaces.count, 0)
    }

    func testDeleteWorkspace_clearsSelectionIfSelected() {
        viewModel.createWorkspace(name: "Selected")
        let workspace = viewModel.workspaces.first!
        viewModel.selectedWorkspace = workspace

        viewModel.deleteWorkspace(workspace)

        XCTAssertNil(viewModel.selectedWorkspace)
    }

    func testConfirmDeletion_setsWorkspacePendingDeletion() {
        viewModel.createWorkspace(name: "Pending")
        let workspace = viewModel.workspaces.first!

        viewModel.confirmDeletion(of: workspace)

        XCTAssertEqual(viewModel.workspacePendingDeletion?.id, workspace.id)
        XCTAssertTrue(viewModel.showDeleteConfirmation)
    }

    func testExecutePendingDeletion_deletesWorkspace() {
        viewModel.createWorkspace(name: "To Delete")
        let workspace = viewModel.workspaces.first!
        viewModel.confirmDeletion(of: workspace)

        viewModel.executePendingDeletion()

        XCTAssertEqual(viewModel.workspaces.count, 0)
        XCTAssertNil(viewModel.workspacePendingDeletion)
    }

    func testFetchWorkspaces_sortsByCreationDateDescending() {
        viewModel.createWorkspace(name: "First")
        // Small delay to ensure different timestamps
        viewModel.createWorkspace(name: "Second")

        viewModel.fetchWorkspaces()

        XCTAssertEqual(viewModel.workspaces.count, 2)
        // Most recent first
        XCTAssertEqual(viewModel.workspaces.first?.name, "Second")
    }
}
