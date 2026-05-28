# Specs Review Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the OpenSpec reading sheet with a persistent two-pane review workspace and a focused reading mode.

**Architecture:** `SpecListView` owns the queue/reader layout and ephemeral focus state, while `SpecDetailView` becomes an embedded reader surface. `SpecViewModel` keeps selection consistent when the visible branch changes or a scan removes the currently visible item.

**Tech Stack:** SwiftUI, SwiftData, XCTest, Swift Package Manager

---

### Task 1: Keep Detail Selection Valid

**Files:**
- Modify: `Sources/CockpitDev/ViewModels/SpecViewModel.swift`
- Test: `Tests/CockpitDevTests/DocSpecVersioningTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testSelectBranch_clearsSelectionFromAHiddenBranch() {
    let viewModel = makeViewModelWithSpecsOnTwoBranches()
    viewModel.selectedSpec = viewModel.specs.first
    viewModel.selectBranch("feature/other")
    XCTAssertNil(viewModel.selectedSpec)
}

func testReconcileSelection_preservesAVisibleSelection() {
    let viewModel = makeViewModelWithSpecsOnTwoBranches()
    let selected = viewModel.specs.first!
    viewModel.selectedSpec = selected
    viewModel.reconcileSelection()
    XCTAssertEqual(viewModel.selectedSpec?.id, selected.id)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `rtk swift test --filter DocSpecVersioningTests/testSelectBranch_clearsSelectionFromAHiddenBranch`

Expected: FAIL because `selectBranch(_:)` does not exist yet.

- [ ] **Step 3: Add minimal selection reconciliation**

```swift
func selectBranch(_ branchName: String) {
    selectedBranchName = branchName
    reconcileSelection()
}

func reconcileSelection() {
    guard let selectedSpec else { return }
    guard specs.contains(where: { $0.id == selectedSpec.id }) else {
        self.selectedSpec = nil
        return
    }
}
```

- [ ] **Step 4: Run focused tests**

Run: `rtk swift test --filter DocSpecVersioningTests`

Expected: PASS.

### Task 2: Replace Sheet With Review Workspace

**Files:**
- Modify: `Sources/CockpitDev/Views/Specs/SpecListView.swift`
- Modify: `Sources/CockpitDev/Views/Specs/SpecDetailView.swift`

- [ ] **Step 1: Replace modal presentation with an embedded split view**

```swift
@State private var isFocusMode = false
@State private var searchText = ""

private var reviewWorkspace: some View {
    HSplitView {
        if !isFocusMode { reviewQueue }
        detailPanel
    }
}
```

- [ ] **Step 2: Make the queue compact and selectable**

```swift
SpecRowView(spec: spec, isSelected: viewModel.selectedSpec?.id == spec.id)
    .onTapGesture {
        viewModel.selectedSpec = spec
        isFocusMode = false
    }
```

- [ ] **Step 3: Convert detail view into a reader pane**

```swift
SpecDetailView(
    spec: spec,
    viewModel: viewModel,
    isFocusMode: isFocusMode,
    onToggleFocus: { isFocusMode.toggle() }
)
```

- [ ] **Step 4: Build the app**

Run: `rtk swift build`

Expected: Build succeeds with no compile error.

### Task 3: Verify Shared Behavior

**Files:**
- Verify: `Tests/CockpitDevTests`

- [ ] **Step 1: Run focused tests**

Run: `rtk swift test --filter DocSpecVersioningTests`

Expected: PASS.

- [ ] **Step 2: Run the complete suite**

Run: `rtk swift test`

Expected: PASS; existing CoreData XPC runtime noise is acceptable only if XCTest reports zero failures.
