import XCTest
import SwiftData
@testable import CockpitDev

/// Unit tests for DocumentViewModel.
///
/// Tests cover:
/// - Document addition with file size validation
/// - Folder CRUD operations (create, rename, delete)
/// - Document removal (reference only)
/// - File existence checking ("file missing" indicator)
/// - File size formatting
/// - Document filtering by folder
/// - Quick Look preview support detection
@MainActor
final class DocumentViewModelTests: XCTestCase {

    private var viewModel: DocumentViewModel!
    private var modelContext: ModelContext!
    private var container: ModelContainer!
    private var workspace: Workspace!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            Workspace.self,
            Document.self,
            Member.self,
            Repository.self,
            Ticket.self,
            Sprint.self,
            OpenSpecEntry.self,
            DocSpecVersion.self,
            AppNotification.self,
            MergeRequestEntry.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        modelContext = container.mainContext

        workspace = Workspace(name: "Test Workspace")
        modelContext.insert(workspace)
        try modelContext.save()

        viewModel = DocumentViewModel()
        viewModel.configure(with: modelContext, workspace: workspace)

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        viewModel = nil
        modelContext = nil
        container = nil
        workspace = nil
        try await super.tearDown()
    }

    // MARK: - Document Addition Tests

    func testAddDocumentSuccess() throws {
        let fileURL = try createTempFile(name: "test.pdf", size: 1024)

        viewModel.addDocument(from: fileURL)

        XCTAssertEqual(viewModel.documents.count, 1)
        XCTAssertEqual(viewModel.documents[0].name, "test.pdf")
        XCTAssertEqual(viewModel.documents[0].filePath, fileURL.path)
        XCTAssertEqual(viewModel.documents[0].fileSize, 1024)
        XCTAssertNotNil(viewModel.documents[0].workspace)
    }

    func testAddDocumentWithMember() throws {
        let member = Member(gitlabUserId: 1, username: "dev1", displayName: "Developer One", role: .member)
        modelContext.insert(member)
        workspace.members.append(member)
        try modelContext.save()

        let fileURL = try createTempFile(name: "doc.txt", size: 512)

        viewModel.addDocument(from: fileURL, addedBy: member)

        XCTAssertEqual(viewModel.documents.count, 1)
        XCTAssertEqual(viewModel.documents[0].addedByMember?.displayName, "Developer One")
    }

    func testAddDocumentToSelectedFolder() throws {
        viewModel.newFolderName = "Design"
        viewModel.createFolder()
        viewModel.selectedFolder = "Design"

        let fileURL = try createTempFile(name: "mockup.png", size: 2048)
        viewModel.addDocument(from: fileURL)

        XCTAssertEqual(viewModel.documents.count, 1)
        XCTAssertEqual(viewModel.documents[0].folderPath, "Design")
    }

    func testAddDocumentExceedingMaxSize() throws {
        // Create a file that exceeds 100 MB (we'll fake the attributes)
        let fileURL = try createTempFile(name: "huge.zip", size: Int(AppConstants.maxFileSizeBytes) + 1)

        viewModel.addDocument(from: fileURL)

        XCTAssertEqual(viewModel.documents.count, 0)
        XCTAssertTrue(viewModel.isShowingError)
        XCTAssertEqual(viewModel.errorMessage, "File exceeds the maximum size of 100 MB.")
    }

    func testAddDocumentAtExactMaxSize() throws {
        let fileURL = try createTempFile(name: "exact.bin", size: Int(AppConstants.maxFileSizeBytes))

        viewModel.addDocument(from: fileURL)

        XCTAssertEqual(viewModel.documents.count, 1)
        XCTAssertEqual(viewModel.documents[0].name, "exact.bin")
    }

    func testAddMultipleDocuments() throws {
        let file1 = try createTempFile(name: "file1.txt", size: 100)
        let file2 = try createTempFile(name: "file2.pdf", size: 200)
        let file3 = try createTempFile(name: "file3.md", size: 300)

        viewModel.addDocuments(from: [file1, file2, file3])

        XCTAssertEqual(viewModel.documents.count, 3)
    }

    // MARK: - Folder CRUD Tests

    func testCreateFolder() {
        viewModel.newFolderName = "Designs"
        viewModel.createFolder()

        XCTAssertTrue(viewModel.folders.contains("Designs"))
        XCTAssertFalse(viewModel.isShowingCreateFolder)
        XCTAssertEqual(viewModel.newFolderName, "")
    }

    func testCreateFolderEmptyName() {
        viewModel.newFolderName = "   "
        viewModel.createFolder()

        XCTAssertTrue(viewModel.folders.isEmpty)
        XCTAssertTrue(viewModel.isShowingError)
        XCTAssertEqual(viewModel.errorMessage, "Folder name cannot be empty.")
    }

    func testCreateFolderDuplicateName() {
        viewModel.newFolderName = "Docs"
        viewModel.createFolder()

        viewModel.newFolderName = "Docs"
        viewModel.createFolder()

        XCTAssertEqual(viewModel.folders.filter { $0 == "Docs" }.count, 1)
        XCTAssertTrue(viewModel.isShowingError)
        XCTAssertEqual(viewModel.errorMessage, "A folder with this name already exists.")
    }

    func testRenameFolderSuccess() throws {
        viewModel.newFolderName = "OldName"
        viewModel.createFolder()

        let fileURL = try createTempFile(name: "test.txt", size: 100)
        viewModel.selectedFolder = "OldName"
        viewModel.addDocument(from: fileURL)

        viewModel.folderToRename = "OldName"
        viewModel.renameFolderName = "NewName"
        viewModel.renameFolder()

        XCTAssertFalse(viewModel.folders.contains("OldName"))
        XCTAssertTrue(viewModel.folders.contains("NewName"))
        XCTAssertEqual(viewModel.documents[0].folderPath, "NewName")
        XCTAssertEqual(viewModel.selectedFolder, "NewName")
    }

    func testRenameFolderEmptyName() {
        viewModel.newFolderName = "Folder1"
        viewModel.createFolder()

        viewModel.folderToRename = "Folder1"
        viewModel.renameFolderName = "  "
        viewModel.renameFolder()

        XCTAssertTrue(viewModel.folders.contains("Folder1"))
        XCTAssertTrue(viewModel.isShowingError)
    }

    func testRenameFolderDuplicateName() {
        viewModel.newFolderName = "FolderA"
        viewModel.createFolder()
        viewModel.newFolderName = "FolderB"
        viewModel.createFolder()

        viewModel.folderToRename = "FolderA"
        viewModel.renameFolderName = "FolderB"
        viewModel.renameFolder()

        // Both should still exist since rename was rejected
        XCTAssertTrue(viewModel.folders.contains("FolderA"))
        XCTAssertTrue(viewModel.folders.contains("FolderB"))
        XCTAssertTrue(viewModel.isShowingError)
    }

    func testDeleteFolder() throws {
        viewModel.newFolderName = "ToDelete"
        viewModel.createFolder()

        let fileURL = try createTempFile(name: "orphan.txt", size: 100)
        viewModel.selectedFolder = "ToDelete"
        viewModel.addDocument(from: fileURL)

        viewModel.folderToDelete = "ToDelete"
        viewModel.deleteFolder()

        XCTAssertFalse(viewModel.folders.contains("ToDelete"))
        // Document should be moved to root
        XCTAssertEqual(viewModel.documents[0].folderPath, nil)
        XCTAssertNil(viewModel.selectedFolder)
    }

    // MARK: - Document Removal Tests

    func testRemoveDocumentConfirmation() throws {
        let fileURL = try createTempFile(name: "remove-me.txt", size: 100)
        viewModel.addDocument(from: fileURL)

        let document = viewModel.documents[0]
        viewModel.confirmRemoveDocument(document)

        XCTAssertTrue(viewModel.isShowingRemoveDocumentConfirmation)
        XCTAssertEqual(viewModel.documentToRemove?.id, document.id)
    }

    func testRemoveDocument() throws {
        let fileURL = try createTempFile(name: "remove-me.txt", size: 100)
        viewModel.addDocument(from: fileURL)

        let document = viewModel.documents[0]
        viewModel.documentToRemove = document
        viewModel.removeDocument()

        XCTAssertEqual(viewModel.documents.count, 0)
        XCTAssertFalse(viewModel.isShowingRemoveDocumentConfirmation)
        // Original file should still exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - File Existence Tests

    func testFileExistsForValidPath() throws {
        let fileURL = try createTempFile(name: "exists.txt", size: 100)
        viewModel.addDocument(from: fileURL)

        let document = viewModel.documents[0]
        XCTAssertTrue(viewModel.fileExists(for: document))
    }

    func testFileExistsForInvalidPath() {
        let document = Document(
            name: "ghost.txt",
            filePath: "/nonexistent/path/ghost.txt",
            fileSize: 100
        )

        XCTAssertFalse(viewModel.fileExists(for: document))
    }

    // MARK: - File Size Formatting Tests

    func testFormattedFileSizeBytes() {
        let formatted = viewModel.formattedFileSize(500)
        XCTAssertTrue(formatted.contains("500") || formatted.contains("bytes") || formatted.contains("B"))
    }

    func testFormattedFileSizeKB() {
        let formatted = viewModel.formattedFileSize(2048)
        XCTAssertTrue(formatted.contains("KB") || formatted.contains("kB"))
    }

    func testFormattedFileSizeMB() {
        let formatted = viewModel.formattedFileSize(5 * 1024 * 1024)
        XCTAssertTrue(formatted.contains("MB"))
    }

    // MARK: - Filtering Tests

    func testFilteredDocumentsAllWhenNoFolderSelected() throws {
        let file1 = try createTempFile(name: "root.txt", size: 100)
        let file2 = try createTempFile(name: "folder.txt", size: 100)

        viewModel.addDocument(from: file1)
        viewModel.newFolderName = "Folder"
        viewModel.createFolder()
        viewModel.selectedFolder = "Folder"
        viewModel.addDocument(from: file2)

        viewModel.selectedFolder = nil
        XCTAssertEqual(viewModel.filteredDocuments.count, 2)
    }

    func testFilteredDocumentsByFolder() throws {
        let file1 = try createTempFile(name: "root.txt", size: 100)
        let file2 = try createTempFile(name: "in-folder.txt", size: 100)

        viewModel.selectedFolder = nil
        viewModel.addDocument(from: file1)

        viewModel.newFolderName = "MyFolder"
        viewModel.createFolder()
        viewModel.selectedFolder = "MyFolder"
        viewModel.addDocument(from: file2)

        XCTAssertEqual(viewModel.filteredDocuments.count, 1)
        XCTAssertEqual(viewModel.filteredDocuments[0].name, "in-folder.txt")
    }

    func testRootDocuments() throws {
        let file1 = try createTempFile(name: "root.txt", size: 100)
        let file2 = try createTempFile(name: "in-folder.txt", size: 100)

        viewModel.selectedFolder = nil
        viewModel.addDocument(from: file1)

        viewModel.newFolderName = "Folder"
        viewModel.createFolder()
        viewModel.selectedFolder = "Folder"
        viewModel.addDocument(from: file2)

        XCTAssertEqual(viewModel.rootDocuments.count, 1)
        XCTAssertEqual(viewModel.rootDocuments[0].name, "root.txt")
    }

    // MARK: - Quick Look Support Tests

    func testCanPreviewPDF() throws {
        let fileURL = try createTempFile(name: "document.pdf", size: 100)
        viewModel.addDocument(from: fileURL)

        XCTAssertTrue(viewModel.canPreview(viewModel.documents[0]))
    }

    func testCanPreviewImage() throws {
        let fileURL = try createTempFile(name: "photo.png", size: 100)
        viewModel.addDocument(from: fileURL)

        XCTAssertTrue(viewModel.canPreview(viewModel.documents[0]))
    }

    func testCanPreviewMarkdown() throws {
        let fileURL = try createTempFile(name: "readme.md", size: 100)
        viewModel.addDocument(from: fileURL)

        XCTAssertTrue(viewModel.canPreview(viewModel.documents[0]))
    }

    func testCanPreviewPlainText() throws {
        let fileURL = try createTempFile(name: "notes.txt", size: 100)
        viewModel.addDocument(from: fileURL)

        XCTAssertTrue(viewModel.canPreview(viewModel.documents[0]))
    }

    func testCannotPreviewUnsupportedType() throws {
        let fileURL = try createTempFile(name: "archive.zip", size: 100)
        viewModel.addDocument(from: fileURL)

        XCTAssertFalse(viewModel.canPreview(viewModel.documents[0]))
    }

    func testCannotPreviewMissingFile() {
        let document = Document(
            name: "missing.pdf",
            filePath: "/nonexistent/missing.pdf",
            fileSize: 100
        )

        XCTAssertFalse(viewModel.canPreview(document))
    }

    // MARK: - Move Document Tests

    func testMoveDocumentToFolder() throws {
        let fileURL = try createTempFile(name: "movable.txt", size: 100)
        viewModel.addDocument(from: fileURL)

        viewModel.newFolderName = "Target"
        viewModel.createFolder()

        viewModel.moveDocument(viewModel.documents[0], toFolder: "Target")

        XCTAssertEqual(viewModel.documents[0].folderPath, "Target")
    }

    func testMoveDocumentToRoot() throws {
        viewModel.newFolderName = "Source"
        viewModel.createFolder()
        viewModel.selectedFolder = "Source"

        let fileURL = try createTempFile(name: "movable.txt", size: 100)
        viewModel.addDocument(from: fileURL)

        viewModel.moveDocument(viewModel.documents[0], toFolder: nil)

        XCTAssertNil(viewModel.documents[0].folderPath)
    }

    // MARK: - Helper Methods

    private func createTempFile(name: String, size: Int) throws -> URL {
        let fileURL = tempDir.appendingPathComponent(name)
        let data = Data(repeating: 0, count: size)
        try data.write(to: fileURL)
        return fileURL
    }
}
