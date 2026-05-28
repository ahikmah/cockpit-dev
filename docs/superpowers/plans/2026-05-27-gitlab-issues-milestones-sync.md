# GitLab Issues Milestones Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync GitLab repository milestones and issues into local sprints and tickets so developer tasks drive board and timeline views.

**Architecture:** Extend `GitLabAPIClient` with milestone pagination, then update `SyncEngine.fullReconcile(workspace:)` to process every repository in a workspace. Remote milestones are upserted into `Sprint`; remote issues are upserted into `Ticket` and linked to milestone-backed sprints, members, and timeline dates.

**Tech Stack:** SwiftPM, SwiftData, XCTest, GitLab REST API v4.

---

### Task 1: GitLab Milestone Fetch API

**Files:**
- Modify: `Sources/CockpitDev/Services/GitLabAPIClient.swift`
- Test: `Tests/CockpitDevTests/GitLabAPIClientTests.swift`

- [ ] **Step 1: Write failing API test**

Add a test that serves `/api/v4/projects/1/milestones` and asserts `fetchMilestones(projectId:)` decodes milestone id, title, start date, and due date.

- [ ] **Step 2: Run test to verify it fails**

Run: `rtk swift test --filter GitLabAPIClientTests/testFetchMilestones`
Expected: FAIL because `fetchMilestones(projectId:)` does not exist.

- [ ] **Step 3: Implement API method**

Add `func fetchMilestones(projectId: Int) async throws -> [GitLabMilestone]` using `fetchAllPages(path:queryItems:)` with `per_page=100`.

- [ ] **Step 4: Run focused API test**

Run: `rtk swift test --filter GitLabAPIClientTests/testFetchMilestones`
Expected: PASS.

### Task 2: Workspace Reconcile Imports Issues And Milestones

**Files:**
- Modify: `Sources/CockpitDev/Services/SyncEngine.swift`
- Test: `Tests/CockpitDevTests/SyncEngineTests.swift`

- [ ] **Step 1: Write failing sync test**

Add a test that creates a workspace with two repositories, serves one milestone and one issue per repository, runs `fullReconcile(workspace:)`, and asserts local `Sprint` and `Ticket` records exist for both repositories.

- [ ] **Step 2: Run test to verify it fails**

Run: `rtk swift test --filter SyncEngineTests/testFullReconcileImportsIssuesAndMilestonesFromAllRepositories`
Expected: FAIL because current reconcile only handles the first repository and does not persist remote-only issues.

- [ ] **Step 3: Implement milestone upsert**

Add private helpers in `SyncEngine` to parse GitLab dates, find or create local `Sprint` by `gitlabMilestoneId`, update title/date/workspace, and return milestone lookup maps.

- [ ] **Step 4: Implement issue upsert**

Add private helpers in `SyncEngine` to find or create local `Ticket` by `gitlabIssueId`, copy issue fields, assign workspace, member, milestone-backed sprint, and fallback timeline dates from due date or milestone.

- [ ] **Step 5: Run focused sync test**

Run: `rtk swift test --filter SyncEngineTests/testFullReconcileImportsIssuesAndMilestonesFromAllRepositories`
Expected: PASS.

### Task 3: Verification

**Files:**
- No production code beyond Task 1 and Task 2.

- [ ] **Step 1: Run focused suites**

Run: `rtk swift test --filter GitLabAPIClientTests` and `rtk swift test --filter SyncEngineTests`
Expected: PASS.

- [ ] **Step 2: Run full suite**

Run: `rtk swift test`
Expected: PASS with no CoreData XPC noise in test output.
