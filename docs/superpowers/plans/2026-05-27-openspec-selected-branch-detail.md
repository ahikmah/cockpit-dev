# OpenSpec Selected Branch and Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Specs scan exactly one selected remote branch and display complete OpenSpec change documents with legible status indicators.

**Architecture:** Add a Codable `OpenSpecDocumentSnapshot` value type that encodes multi-file OpenSpec content inside the existing `DocSpecVersion.content` field, avoiding a SwiftData schema migration. `SpecTrackingService` discovers root and nested documents into snapshots; `SpecViewModel` owns single-branch selection and filtering; SwiftUI details render document tabs from the decoded latest snapshot.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, XCTest, SwiftPM

---

### Task 1: Version Payload For Multi-File OpenSpec Content

**Files:**
- Create: `Sources/CockpitDev/Models/OpenSpecDocumentSnapshot.swift`
- Modify: `Sources/CockpitDev/ViewModels/SpecViewModel.swift`
- Test: `Tests/CockpitDevTests/DocSpecVersioningTests.swift`

- [ ] **Step 1: Write failing snapshot tests**

Add tests that require a complete snapshot to round-trip and legacy text to decode under its prior phase:

```swift
func testOpenSpecDocumentSnapshot_roundTripsAllDocuments() throws {
    let snapshot = OpenSpecDocumentSnapshot(
        proposal: "# Proposal",
        design: "# Design",
        tasks: "- [ ] Ship",
        specs: [.init(path: "specs/api/spec.md", content: "# API")]
    )
    let encoded = try snapshot.encodedContent()
    XCTAssertEqual(OpenSpecDocumentSnapshot.decode(encoded, legacyPhase: .proposal), snapshot)
}

func testOpenSpecDocumentSnapshot_legacyContentUsesSavedPhase() {
    let snapshot = OpenSpecDocumentSnapshot.decode("# Design", legacyPhase: .design)
    XCTAssertEqual(snapshot.design, "# Design")
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `rtk swift test --filter DocSpecVersioningTests/testOpenSpecDocumentSnapshot`

Expected: FAIL because `OpenSpecDocumentSnapshot` does not exist.

- [ ] **Step 3: Implement the snapshot value type and latest snapshot lookup**

Implement:

```swift
struct OpenSpecDocumentSnapshot: Codable, Equatable {
    struct SpecDocument: Codable, Equatable, Identifiable {
        var id: String { path }
        let path: String
        let content: String
    }

    let proposal: String?
    let design: String?
    let tasks: String?
    let specs: [SpecDocument]

    func encodedContent() throws -> String { /* stable JSON encoding */ }
    static func decode(_ content: String, legacyPhase: SpecPhase) -> Self { /* JSON then plain-text fallback */ }
}
```

Expose `latestSnapshot(for:)` from `SpecViewModel` by decoding the latest `DocSpecVersion`.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `rtk swift test --filter DocSpecVersioningTests`

Expected: PASS.

### Task 2: Single Selected Remote Branch

**Files:**
- Modify: `Sources/CockpitDev/ViewModels/SpecViewModel.swift`
- Modify: `Sources/CockpitDev/Views/Specs/SpecListView.swift`
- Test: `Tests/CockpitDevTests/DocSpecVersioningTests.swift`

- [ ] **Step 1: Write failing branch selection tests**

Add tests:

```swift
func testSelectedBranch_defaultsToRepositoryDefaultBranch() {
    let workspace = makeWorkspace(repositoryDefaultBranch: "orbit-dev-84")
    XCTAssertEqual(SpecViewModel(workspace: workspace).selectedBranchName, "orbit-dev-84")
}

func testSpecs_onlyContainsSelectedBranchEntries() {
    let viewModel = makeViewModelWithEntries(on: ["orbit-dev-84", "feature/other"])
    XCTAssertEqual(viewModel.specs.map(\.branchName), ["orbit-dev-84"])
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `rtk swift test --filter DocSpecVersioningTests/testSelectedBranch`

Expected: FAIL because selection starts nil and rows are not filtered.

- [ ] **Step 3: Implement selection and remove all-branches UI**

Set `selectedBranchName` to `primaryRepository?.defaultBranch` during initialization/configuration, retain it when present in fetched branches, and filter `specs` by the selected branch. Change `scanForSpecs()` to require and scan one selected branch only. Remove the `All branches` picker tag and change scan summary to include the selected branch name.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `rtk swift test --filter DocSpecVersioningTests`

Expected: PASS.

### Task 3: Discover Complete OpenSpec Folder Content

**Files:**
- Modify: `Sources/CockpitDev/Services/SpecTrackingService.swift`
- Test: `Tests/CockpitDevTests/SpecTrackingServiceTests.swift`

- [ ] **Step 1: Write failing service integration test**

Using `MockHTTPServer`, return a tree for `openspec/changes`, one change folder containing `proposal.md`, `design.md`, `tasks.md`, and `specs`, plus nested `specs/adjacent-articles-api/spec.md`. Assert `discoverSpecsOnBranch` creates one entry with decoded snapshot values and phase `.tasks`.

- [ ] **Step 2: Run test to verify RED**

Run: `rtk swift test --filter SpecTrackingServiceTests/testDiscoverSpecsOnBranch_readsOpenSpecDocumentFolder`

Expected: FAIL because the current service fetches `requirements.md` and does not fetch nested specs.

- [ ] **Step 3: Implement OpenSpec folder discovery**

Replace primary-file fetch behavior with:

```swift
private func fetchDocumentSnapshot(
    for specFile: SpecFileInfo,
    projectId: Int
) async -> OpenSpecDocumentSnapshot? { /* root markdown and nested specs */ }
```

Hash `try snapshot.encodedContent()` for initial and changed versions. Treat the most advanced present root document as `.tasks`, `.design`, or `.proposal`, and skip entries whose snapshot has no readable documents.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `rtk swift test --filter SpecTrackingServiceTests && rtk swift test --filter DocSpecVersioningTests`

Expected: PASS.

### Task 4: Detail Tabs And High-Contrast Row State

**Files:**
- Modify: `Sources/CockpitDev/Views/Specs/SpecDetailView.swift`
- Modify: `Sources/CockpitDev/Views/Specs/SpecListView.swift`
- Modify: `Sources/CockpitDev/Utilities/DesignSystem.swift` only if a missing semantic token is required

- [ ] **Step 1: Implement document tab state using decoded snapshot**

Render `Proposal`, `Design`, `Tasks`, and `Specs` segments from `viewModel.latestSnapshot(for:)`; render each capability file under its path in the Specs tab. Empty tabs show `No <type> document found` rather than a generic missing-content result.

- [ ] **Step 2: Implement readable row indicators**

Replace the unread dot with an icon-and-label badge:

```swift
Label("New update", systemImage: "sparkle")
    .font(DesignSystem.Typography.captionMedium)
    .foregroundStyle(DesignSystem.Colors.accent)
    .padding(.horizontal, DesignSystem.Spacing.spacing6)
    .padding(.vertical, DesignSystem.Spacing.spacing4)
    .background(DesignSystem.Colors.accentSoft)
```

Use existing adaptive `successSoft`, `warningSoft`, and `accentSoft` surfaces for phase icon and badge backgrounds.

- [ ] **Step 3: Compile UI changes**

Run: `rtk swift build`

Expected: PASS.

### Task 5: Regression Verification

**Files:**
- Verify: `Sources/CockpitDev/Models/OpenSpecDocumentSnapshot.swift`
- Verify: `Sources/CockpitDev/Services/SpecTrackingService.swift`
- Verify: `Sources/CockpitDev/ViewModels/SpecViewModel.swift`
- Verify: `Sources/CockpitDev/Views/Specs/SpecDetailView.swift`
- Verify: `Sources/CockpitDev/Views/Specs/SpecListView.swift`

- [ ] **Step 1: Run focused suites**

Run: `rtk swift test --filter DocSpecVersioningTests && rtk swift test --filter SpecTrackingServiceTests`

Expected: PASS with no test failures.

- [ ] **Step 2: Run full package verification**

Run: `rtk swift build && rtk swift test`

Expected: PASS; known CoreData XPC diagnostic noise may appear without test failure.
