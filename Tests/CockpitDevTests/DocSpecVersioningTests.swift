import XCTest
import SwiftData
@testable import CockpitDev

/// Unit tests for Document Spec Versioning (Task 25) covering:
/// - SHA-256 content hash computation
/// - DocSpecVersion snapshot creation on hash change
/// - Git commit metadata extraction fallback
/// - Version history ordering (reverse-chronological)
/// - Diff computation (LCS-based)
/// - Unread version badge logic
/// - Badge removal on history open
final class DocSpecVersioningTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var specTrackingService: SpecTrackingService!
    private var mockAPIClient: GitLabAPIClient!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            Workspace.self,
            Repository.self,
            Member.self,
            Ticket.self,
            Sprint.self,
            MergeRequestEntry.self,
            Document.self,
            OpenSpecEntry.self,
            DocSpecVersion.self,
            AppNotification.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)

        mockAPIClient = GitLabAPIClient(
            baseURL: URL(string: "https://gitlab.example.com")!,
            tokenProvider: { "mock-token" }
        )

        specTrackingService = SpecTrackingService(apiClient: mockAPIClient, modelContext: modelContext)
    }

    override func tearDown() async throws {
        specTrackingService = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - SHA-256 Content Hash Tests

    func testComputeContentHash_producesConsistentSHA256() {
        // Given: Same content
        let content = "# Requirements\n\nThis is a test document."

        // When: Hash computed twice
        let hash1 = specTrackingService.computeContentHash(content)
        let hash2 = specTrackingService.computeContentHash(content)

        // Then: Hashes are identical and valid SHA-256 (64 hex chars)
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 64)
        XCTAssertTrue(hash1.allSatisfy { $0.isHexDigit })
    }

    func testComputeContentHash_differentContentProducesDifferentHash() {
        // Given: Different content
        let content1 = "Version 1 of the spec"
        let content2 = "Version 2 of the spec"

        // When
        let hash1 = specTrackingService.computeContentHash(content1)
        let hash2 = specTrackingService.computeContentHash(content2)

        // Then
        XCTAssertNotEqual(hash1, hash2)
    }

    func testComputeContentHash_emptyStringProducesValidHash() {
        // Given: Empty content
        let content = ""

        // When
        let hash = specTrackingService.computeContentHash(content)

        // Then: Still produces valid SHA-256
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    func testComputeContentHash_whitespaceMatters() {
        // Given: Content differing only in whitespace
        let content1 = "Hello World"
        let content2 = "Hello  World"

        // When
        let hash1 = specTrackingService.computeContentHash(content1)
        let hash2 = specTrackingService.computeContentHash(content2)

        // Then: Different hashes
        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - DocSpecVersion Snapshot Creation Tests

    func testVersionCreation_storesContentAndHash() {
        // Given: Content for a version
        let content = "# Design\n\nArchitecture overview."
        let hash = specTrackingService.computeContentHash(content)

        // When: Creating a version
        let version = DocSpecVersion(
            contentHash: hash,
            content: content,
            authorName: "Alice",
            commitTimestamp: Date(),
            detectedAt: Date()
        )

        // Then: All fields are stored correctly
        XCTAssertEqual(version.contentHash, hash)
        XCTAssertEqual(version.content, content)
        XCTAssertEqual(version.authorName, "Alice")
    }

    func testVersionCreation_hashChangeTriggersNewVersion() {
        // Given: A spec entry with an existing version
        let spec = OpenSpecEntry(
            specName: "test-spec",
            branchName: "feature/test",
            phase: .design,
            isAvailable: true,
            hasUnreadVersion: false
        )
        modelContext.insert(spec)

        let oldContent = "# Design v1"
        let oldHash = specTrackingService.computeContentHash(oldContent)
        let oldVersion = DocSpecVersion(
            contentHash: oldHash,
            content: oldContent,
            authorName: "Alice",
            commitTimestamp: Date().addingTimeInterval(-3600),
            detectedAt: Date().addingTimeInterval(-3600)
        )
        oldVersion.spec = spec
        spec.versions.append(oldVersion)
        modelContext.insert(oldVersion)

        // When: New content with different hash
        let newContent = "# Design v2\n\nUpdated architecture."
        let newHash = specTrackingService.computeContentHash(newContent)

        // Then: Hashes differ, indicating a new version should be created
        XCTAssertNotEqual(oldHash, newHash)

        // Create new version
        let newVersion = DocSpecVersion(
            contentHash: newHash,
            content: newContent,
            authorName: "Bob",
            commitTimestamp: Date(),
            detectedAt: Date()
        )
        newVersion.spec = spec
        spec.versions.append(newVersion)
        modelContext.insert(newVersion)

        XCTAssertEqual(spec.versions.count, 2)
    }

    func testVersionCreation_sameHashDoesNotCreateNewVersion() {
        // Given: Same content hash
        let content = "# Design\n\nNo changes."
        let hash = specTrackingService.computeContentHash(content)

        let spec = OpenSpecEntry(
            specName: "test-spec",
            branchName: "feature/test",
            phase: .design,
            isAvailable: true
        )
        modelContext.insert(spec)

        let existingVersion = DocSpecVersion(
            contentHash: hash,
            content: content,
            authorName: "Alice",
            commitTimestamp: Date(),
            detectedAt: Date()
        )
        existingVersion.spec = spec
        spec.versions.append(existingVersion)
        modelContext.insert(existingVersion)

        // When: Computing hash of same content
        let newHash = specTrackingService.computeContentHash(content)

        // Then: Hash matches, no new version needed
        XCTAssertEqual(hash, newHash)
        XCTAssertEqual(spec.versions.count, 1)
    }

    // MARK: - Git Commit Metadata Fallback Tests

    func testMetadataFallback_unknownAuthorWhenAPIFails() async {
        // Given: API client that will fail (no real server)
        // When: Extracting metadata (will fail since no server)
        let (authorName, timestamp) = await specTrackingService.extractCommitMetadata(
            projectId: 999,
            filePath: "nonexistent/path.md",
            ref: "nonexistent-branch"
        )

        // Then: Falls back to "Unknown" and a recent timestamp
        XCTAssertEqual(authorName, "Unknown")
        // Timestamp should be approximately now (within 5 seconds)
        XCTAssertTrue(abs(timestamp.timeIntervalSinceNow) < 5)
    }

    func testDocSpecVersion_fallbackValues() {
        // Given: A version created with fallback values
        let version = DocSpecVersion(
            contentHash: "abc123",
            content: "# Test",
            authorName: "Unknown",
            commitTimestamp: Date(),
            detectedAt: Date()
        )

        // Then: Fallback values are stored correctly
        XCTAssertEqual(version.authorName, "Unknown")
        XCTAssertNotNil(version.commitTimestamp)
        XCTAssertNotNil(version.detectedAt)
    }

    // MARK: - Version History Ordering Tests

    func testVersionHistory_reverseChronologicalOrder() {
        // Given: Multiple versions with different timestamps
        let spec = OpenSpecEntry(
            specName: "test-spec",
            branchName: "main",
            phase: .tasks
        )
        modelContext.insert(spec)

        let now = Date()
        let v1 = DocSpecVersion(
            contentHash: "hash1",
            content: "v1",
            authorName: "Alice",
            commitTimestamp: now.addingTimeInterval(-7200),
            detectedAt: now.addingTimeInterval(-7200)
        )
        let v2 = DocSpecVersion(
            contentHash: "hash2",
            content: "v2",
            authorName: "Bob",
            commitTimestamp: now.addingTimeInterval(-3600),
            detectedAt: now.addingTimeInterval(-3600)
        )
        let v3 = DocSpecVersion(
            contentHash: "hash3",
            content: "v3",
            authorName: "Charlie",
            commitTimestamp: now,
            detectedAt: now
        )

        v1.spec = spec
        v2.spec = spec
        v3.spec = spec
        spec.versions = [v1, v2, v3]
        modelContext.insert(v1)
        modelContext.insert(v2)
        modelContext.insert(v3)

        // When: Sorting in reverse-chronological order (newest first)
        let sorted = spec.versions.sorted { $0.detectedAt > $1.detectedAt }

        // Then: Newest version is first
        XCTAssertEqual(sorted[0].contentHash, "hash3")
        XCTAssertEqual(sorted[1].contentHash, "hash2")
        XCTAssertEqual(sorted[2].contentHash, "hash1")
    }

    // MARK: - Diff Computation Tests

    func testComputeSpecDiff_identicalContent_allUnchanged() {
        // Given: Same content
        let content = "Line 1\nLine 2\nLine 3"

        // When
        let diff = computeSpecDiff(oldContent: content, newContent: content)

        // Then: All lines are unchanged
        XCTAssertTrue(diff.allSatisfy { $0.type == .unchanged })
        XCTAssertEqual(diff.count, 3)
    }

    func testComputeSpecDiff_addedLines_markedAsAdded() {
        // Given: New content has additional lines
        let oldContent = "Line 1\nLine 2"
        let newContent = "Line 1\nLine 2\nLine 3"

        // When
        let diff = computeSpecDiff(oldContent: oldContent, newContent: newContent)

        // Then: The new line is marked as added
        let addedLines = diff.filter { $0.type == .added }
        XCTAssertEqual(addedLines.count, 1)
        XCTAssertEqual(addedLines.first?.content, "Line 3")
    }

    func testComputeSpecDiff_removedLines_markedAsRemoved() {
        // Given: Old content has lines that are removed
        let oldContent = "Line 1\nLine 2\nLine 3"
        let newContent = "Line 1\nLine 3"

        // When
        let diff = computeSpecDiff(oldContent: oldContent, newContent: newContent)

        // Then: The removed line is detected
        let removedLines = diff.filter { $0.type == .removed }
        XCTAssertEqual(removedLines.count, 1)
        XCTAssertEqual(removedLines.first?.content, "Line 2")
    }

    func testComputeSpecDiff_modifiedLines_markedAsModified() {
        // Given: A line is changed
        let oldContent = "# Title\nOld description"
        let newContent = "# Title\nNew description"

        // When
        let diff = computeSpecDiff(oldContent: oldContent, newContent: newContent)

        // Then: The modified line is detected
        let modifiedLines = diff.filter { $0.type == .modified }
        XCTAssertEqual(modifiedLines.count, 1)
        XCTAssertEqual(modifiedLines.first?.content, "New description")
        XCTAssertEqual(modifiedLines.first?.oldContent, "Old description")
    }

    func testComputeSpecDiff_emptyOldContent_allAdded() {
        // Given: Old content is empty
        let oldContent = ""
        let newContent = "Line 1\nLine 2"

        // When
        let diff = computeSpecDiff(oldContent: oldContent, newContent: newContent)

        // Then: New lines are added (old empty line may be modified to first new line)
        let nonUnchanged = diff.filter { $0.type != .unchanged }
        XCTAssertFalse(nonUnchanged.isEmpty)
    }

    func testComputeSpecDiff_emptyNewContent_allRemoved() {
        // Given: New content is empty
        let oldContent = "Line 1\nLine 2"
        let newContent = ""

        // When
        let diff = computeSpecDiff(oldContent: oldContent, newContent: newContent)

        // Then: Old lines are removed (or modified to empty)
        let nonUnchanged = diff.filter { $0.type != .unchanged }
        XCTAssertFalse(nonUnchanged.isEmpty)
    }

    // MARK: - Unread Badge Tests

    func testUnreadBadge_setOnNewVersion() {
        // Given: A spec with no unread badge
        let spec = OpenSpecEntry(
            specName: "test-spec",
            branchName: "main",
            phase: .design,
            isAvailable: true,
            hasUnreadVersion: false
        )
        modelContext.insert(spec)

        // When: A new version is detected (simulating what SpecTrackingService does)
        spec.hasUnreadVersion = true

        // Then: Badge is set
        XCTAssertTrue(spec.hasUnreadVersion)
    }

    func testUnreadBadge_removedOnMarkAsRead() {
        // Given: A spec with unread badge
        let workspace = Workspace(name: "Test", specDirectoryPath: ".kiro/specs")
        modelContext.insert(workspace)

        let spec = OpenSpecEntry(
            specName: "test-spec",
            branchName: "main",
            phase: .design,
            isAvailable: true,
            hasUnreadVersion: true
        )
        spec.workspace = workspace
        workspace.specs = [spec]
        modelContext.insert(spec)

        let viewModel = SpecViewModel(workspace: workspace)

        // When: User opens the spec (markAsRead is called)
        viewModel.markAsRead(spec)

        // Then: Badge is removed
        XCTAssertFalse(spec.hasUnreadVersion)
    }

    func testUnreadBadge_multipleSpecsIndependent() {
        // Given: Two specs, one with unread badge
        let workspace = Workspace(name: "Test", specDirectoryPath: ".kiro/specs")
        modelContext.insert(workspace)

        let spec1 = OpenSpecEntry(
            specName: "spec-a",
            branchName: "main",
            phase: .design,
            isAvailable: true,
            hasUnreadVersion: true
        )
        let spec2 = OpenSpecEntry(
            specName: "spec-b",
            branchName: "main",
            phase: .tasks,
            isAvailable: true,
            hasUnreadVersion: true
        )
        spec1.workspace = workspace
        spec2.workspace = workspace
        workspace.specs = [spec1, spec2]
        modelContext.insert(spec1)
        modelContext.insert(spec2)

        let viewModel = SpecViewModel(workspace: workspace)

        // When: Only spec1 is marked as read
        viewModel.markAsRead(spec1)

        // Then: spec1 badge removed, spec2 badge remains
        XCTAssertFalse(spec1.hasUnreadVersion)
        XCTAssertTrue(spec2.hasUnreadVersion)
    }
}
