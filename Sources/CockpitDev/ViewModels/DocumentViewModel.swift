import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// ViewModel for managing documents and folders within a workspace.
@Observable
class DocumentViewModel {

    // MARK: - Published State

    var documents: [Document] = []
    var folders: [String] = []
    var selectedFolder: String? = nil
    var selectedDocument: Document? = nil
    var isShowingFilePicker = false
    var isShowingCreateFolder = false
    var isShowingRenameFolder = false
    var isShowingDeleteConfirmation = false
    var isShowingRemoveDocumentConfirmation = false
    var newFolderName = ""
    var renameFolderName = ""
    var folderToRename: String? = nil
    var folderToDelete: String? = nil
    var documentToRemove: Document? = nil
    var errorMessage: String? = nil
    var isShowingError = false

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private var workspace: Workspace?

    // MARK: - Configuration

    func configure(with modelContext: ModelContext, workspace: Workspace) {
        self.modelContext = modelContext
        self.workspace = workspace
        loadDocuments()
    }

    // MARK: - Data Loading

    func loadDocuments() {
        guard let workspace else { return }
        documents = workspace.documents.sorted { $0.addedAt > $1.addedAt }
        extractFolders()
    }

    private func extractFolders() {
        let folderPaths = Set(documents.compactMap { $0.folderPath })
        folders = folderPaths.sorted()
    }

    /// Returns documents filtered by the currently selected folder.
    var filteredDocuments: [Document] {
        if let selectedFolder {
            return documents.filter { $0.folderPath == selectedFolder }
        }
        return documents
    }

    /// Returns documents at the root level (no folder assigned).
    var rootDocuments: [Document] {
        documents.filter { $0.folderPath == nil }
    }

    /// Returns documents for a specific folder.
    func documents(inFolder folder: String) -> [Document] {
        documents.filter { $0.folderPath == folder }
    }

    // MARK: - Folder CRUD

    func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("Folder name cannot be empty.")
            return
        }
        guard !folders.contains(trimmed) else {
            showError("A folder with this name already exists.")
            return
        }
        folders.append(trimmed)
        folders.sort()
        newFolderName = ""
        isShowingCreateFolder = false
    }

    func renameFolder() {
        guard let folderToRename else { return }
        let trimmed = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("Folder name cannot be empty.")
            return
        }
        guard !folders.contains(trimmed) else {
            showError("A folder with this name already exists.")
            return
        }

        // Update all documents in the old folder
        for document in documents where document.folderPath == folderToRename {
            document.folderPath = trimmed
        }

        if let index = folders.firstIndex(of: folderToRename) {
            folders[index] = trimmed
        }
        folders.sort()

        if selectedFolder == folderToRename {
            selectedFolder = trimmed
        }

        self.folderToRename = nil
        renameFolderName = ""
        isShowingRenameFolder = false
        saveContext()
    }

    func deleteFolder() {
        guard let folderToDelete else { return }

        // Move documents in this folder to root
        for document in documents where document.folderPath == folderToDelete {
            document.folderPath = nil
        }

        folders.removeAll { $0 == folderToDelete }

        if selectedFolder == folderToDelete {
            selectedFolder = nil
        }

        self.folderToDelete = nil
        isShowingDeleteConfirmation = false
        saveContext()
        loadDocuments()
    }

    // MARK: - Document Addition

    func addDocument(from url: URL, addedBy member: Member? = nil) {
        guard let workspace, let modelContext else { return }

        // Validate file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            guard fileSize <= AppConstants.maxFileSizeBytes else {
                showError("File exceeds the maximum size of 100 MB.")
                return
            }

            let document = Document(
                name: url.lastPathComponent,
                filePath: url.path,
                fileSize: fileSize,
                folderPath: selectedFolder,
                addedAt: Date()
            )
            document.addedByMember = member
            document.workspace = workspace

            modelContext.insert(document)
            saveContext()
            loadDocuments()
        } catch {
            showError("Unable to read file attributes: \(error.localizedDescription)")
        }
    }

    func addDocuments(from urls: [URL], addedBy member: Member? = nil) {
        for url in urls {
            addDocument(from: url, addedBy: member)
        }
    }

    // MARK: - Document Removal

    func confirmRemoveDocument(_ document: Document) {
        documentToRemove = document
        isShowingRemoveDocumentConfirmation = true
    }

    func removeDocument() {
        guard let document = documentToRemove, let modelContext else { return }
        modelContext.delete(document)
        saveContext()
        documentToRemove = nil
        isShowingRemoveDocumentConfirmation = false

        if selectedDocument?.id == document.id {
            selectedDocument = nil
        }
        loadDocuments()
    }

    // MARK: - Move Document to Folder

    func moveDocument(_ document: Document, toFolder folder: String?) {
        document.folderPath = folder
        saveContext()
        loadDocuments()
    }

    // MARK: - File Existence Check

    func fileExists(for document: Document) -> Bool {
        FileManager.default.fileExists(atPath: document.filePath)
    }

    // MARK: - File Size Formatting

    func formattedFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Quick Look Support

    func canPreview(_ document: Document) -> Bool {
        guard fileExists(for: document) else { return false }
        let ext = (document.filePath as NSString).pathExtension.lowercased()
        let supportedExtensions = [
            "pdf", "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif",
            "txt", "md", "markdown", "rtf", "swift", "py", "js", "ts",
            "json", "xml", "html", "css", "yaml", "yml"
        ]
        return supportedExtensions.contains(ext)
    }

    // MARK: - Error Handling

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    // MARK: - Persistence

    private func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            showError("Failed to save: \(error.localizedDescription)")
        }
    }
}
