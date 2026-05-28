# Developer Milestone Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Timeline group scheduled GitLab issue work by developer, filter by milestone, and support continuous zoom instead of fixed day/week/month/quarter levels.

**Architecture:** Keep the behavior in `GanttViewModel` so it is testable without rendering SwiftUI. `GanttChartView` consumes grouped rows, selected milestone, and continuous `pointsPerDay` to render a dense review timeline.

**Tech Stack:** Swift 5.9, SwiftUI Canvas, SwiftData models, XCTest.

---

### Task 1: View Model Timeline Data

**Files:**
- Modify: `Sources/CockpitDev/ViewModels/GanttViewModel.swift`
- Test: `Tests/CockpitDevTests/GanttViewModelTests.swift`

- [x] **Step 1: Write failing tests**

Add tests for milestone filtering, developer row grouping, and continuous zoom.

- [x] **Step 2: Verify red**

Run: `rtk swift test --filter GanttViewModelTests/testRefreshDataFiltersScheduledTicketsBySelectedMilestone`

Expected: fail because selected milestone filtering does not exist yet.

- [x] **Step 3: Implement model behavior**

Replace fixed zoom enum usage with continuous `pointsPerDay`, add `selectedSprint`, `timelineRows`, and adaptive labels.

- [x] **Step 4: Verify green**

Run: `rtk swift test --filter GanttViewModelTests`

Expected: pass.

### Task 2: Timeline UI

**Files:**
- Modify: `Sources/CockpitDev/Views/GanttChartView.swift`

- [x] **Step 1: Update toolbar**

Add milestone picker and continuous zoom controls.

- [x] **Step 2: Update Canvas rendering**

Render developer rows on the left and stacked ticket bars per developer row.

- [x] **Step 3: Verify build**

Run: `rtk swift build`

Expected: pass.

### Task 3: Regression Verification

**Files:**
- Test: `Tests/CockpitDevTests/GanttViewModelTests.swift`

- [x] **Step 1: Run focused tests**

Run: `rtk swift test --filter GanttViewModelTests`

Expected: pass.

- [x] **Step 2: Run full tests**

Run: `rtk swift test`

Expected: pass without CoreData/XPC noise.
