# Workspace Local Root and Zed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clone all repositories in a workspace beneath one local root and open that root in Zed.

**Architecture:** `Workspace.localRootPath` owns directory placement. `IDEContextService` resolves/clones repositories and opens the root via an injectable Zed launcher, while `RepositoryManagementViewModel` orchestrates token-backed add and open actions.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, AppKit, XCTest

---

### Task 1: Persist Workspace Root

**Files:**
- Modify: `Sources/CockpitDev/Models/Workspace.swift`
- Test: `Tests/CockpitDevTests/RepositoryManagementViewModelTests.swift`

- [ ] Add a failing assertion that a workspace can retain a local root used by repository operations.
- [ ] Run `rtk swift test --filter RepositoryManagementViewModelTests` and confirm failure because `localRootPath` is absent.
- [ ] Add optional `localRootPath` to `Workspace` initialization and storage.
- [ ] Re-run the focused tests and confirm they pass.

### Task 2: Root-Based Clone And Zed Launch

**Files:**
- Modify: `Sources/CockpitDev/Services/IDEContextService.swift`
- Test: `Tests/CockpitDevTests/IDEContextServiceTests.swift`

- [ ] Add failing tests that cloning places a repo at `<root>/<repo-name>` and IDE launch targets the root via Zed.
- [ ] Run `rtk swift test --filter IDEContextServiceTests` and confirm the launch test fails under the existing `.code-workspace` behavior.
- [ ] Add workspace-root resolution and injectable Zed folder launching, then make `openInIDE` open the root.
- [ ] Re-run `rtk swift test --filter IDEContextServiceTests` and confirm pass.

### Task 3: Add Repository Auto Clone Flow

**Files:**
- Modify: `Sources/CockpitDev/ViewModels/RepositoryManagementViewModel.swift`
- Modify: `Sources/CockpitDev/Views/WorkspaceSettingsView.swift`
- Test: `Tests/CockpitDevTests/RepositoryManagementViewModelTests.swift`

- [ ] Add a failing view-model test for cloning before repository persistence into the resolved workspace root.
- [ ] Run the focused test and confirm failure under association-only add behavior.
- [ ] Inject token retrieval and use `IDEContextService` to clone before saving the new repository.
- [ ] Re-run focused tests and confirm pass.

### Task 4: Settings UX And Verification

**Files:**
- Modify: `Sources/CockpitDev/Views/RepositoriesSettingsView.swift`

- [ ] Show the workspace local root and state clearly that adding a repo clones it locally.
- [ ] Run `rtk swift build`.
- [ ] Run `rtk swift test --filter RepositoryManagementViewModelTests` and `rtk swift test --filter IDEContextServiceTests`.
