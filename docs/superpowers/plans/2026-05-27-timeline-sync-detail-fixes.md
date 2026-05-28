# Timeline Sync Detail Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix timeline scrolling/hover/detail interactions and make sprint/ticket GitLab sync include milestone, due date, start date, and story points.

**Architecture:** Keep testable behavior in `GanttViewModel`, `GitLabAPIClient`, `SyncEngine`, and `SprintViewModel`. SwiftUI views only render state and call view model actions. GitLab issue scheduling follows OpenSpec PM evidence: `start_date`, `due_date`, and `weight` map to local `startDate`, `endDate`, and `storyPoints`.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, XCTest, GitLab REST API.

---

### Task 1: GitLab Issue Scheduling Fields

**Files:**
- Modify: `Sources/CockpitDev/Services/GitLabAPIClient.swift`
- Modify: `Sources/CockpitDev/Services/SyncEngine.swift`
- Test: `Tests/CockpitDevTests/GitLabAPIClientTests.swift`
- Test: `Tests/CockpitDevTests/SyncEngineTests.swift`

- [ ] Write failing tests for decoding `start_date`, creating issues with `due_date`, `weight`, `milestone_id`, and syncing local tickets to GitLab.
- [ ] Run focused tests to verify failure.
- [ ] Add `startDate` to `GitLabIssue`, `startDate`/`milestoneId`/`dueDate` to create issue payloads, and push these from `SyncEngine`.
- [ ] Run focused tests to verify pass.

### Task 2: Sprint Delete and GitLab Milestone Sync

**Files:**
- Modify: `Sources/CockpitDev/Services/GitLabAPIClient.swift`
- Modify: `Sources/CockpitDev/ViewModels/SprintViewModel.swift`
- Test: `Tests/CockpitDevTests/GitLabAPIClientTests.swift`
- Test: `Tests/CockpitDevTests/SprintViewModelTests.swift`

- [ ] Write failing tests for deleting a GitLab milestone and deleting a sprint locally while nullifying tickets.
- [ ] Run focused tests to verify failure.
- [ ] Add `deleteMilestone` API and `deleteSprint` view model flow.
- [ ] Run focused tests to verify pass.

### Task 3: Timeline Scroll, Hover Popup, and Detail Open

**Files:**
- Modify: `Sources/CockpitDev/ViewModels/GanttViewModel.swift`
- Modify: `Sources/CockpitDev/Views/GanttChartView.swift`
- Test: `Tests/CockpitDevTests/GanttViewModelTests.swift`

- [ ] Write failing tests for ticket hit testing and scroll clamping with viewport sizes.
- [ ] Run focused tests to verify failure.
- [ ] Add hit testing and viewport-aware pan/scroll methods to `GanttViewModel`.
- [ ] Add native scroll-wheel handling, hover popover, and ticket detail sheet to `GanttChartView`.
- [ ] Run focused tests to verify pass.

### Task 4: Sprint Ticket Detail

**Files:**
- Modify: `Sources/CockpitDev/Views/SprintDetailView.swift`

- [ ] Make sprint ticket rows open ticket details.
- [ ] Keep remove-from-sprint action explicit and non-ambiguous.

### Task 5: Verification

**Files:**
- Test: `Tests/CockpitDevTests`

- [ ] Run `rtk swift test --filter GitLabAPIClientTests`.
- [ ] Run `rtk swift test --filter SyncEngineTests`.
- [ ] Run `rtk swift test --filter SprintViewModelTests`.
- [ ] Run `rtk swift test --filter GanttViewModelTests`.
- [ ] Run `rtk swift test` and scan for CoreData/XPC noise.
- [ ] Run `rtk ./build-app.sh`.
