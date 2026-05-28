# Cockpit Dev

Native macOS project cockpit for GitLab-based development teams. Cockpit Dev brings workspace setup, GitLab issue/MR sync, sprint planning, OpenSpec review, timeline planning, and developer analytics into one dense desktop app for dev leads.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)
![Status](https://img.shields.io/badge/status-active%20development-yellow)

## Current Scope

Cockpit Dev is still under active development, but the core native shell and sync flows are now implemented enough for local iteration:

- Workspace sidebar with dark/light appearance support.
- GitLab OAuth connection for self-hosted GitLab instances.
- Multi-repository workspaces with local clone management.
- Zed IDE opening from the workspace local root.
- GitLab issue, milestone, member, and merge request sync.
- OpenSpec PM database sync for planning metadata that GitLab does not own.
- Tickets, Sprints, Timeline, MRs, Specs, Docs, Analytics, and Settings tabs.
- Markdown ticket details and editor with preview-oriented rendering.
- Native SwiftData persistence with broad unit/integration coverage.

## Data Ownership

The app intentionally separates GitLab-owned data from planning data:

| Data | Source of Truth |
|------|-----------------|
| Issue title, description, labels, assignee, state | GitLab |
| Merge requests, MR commits, reviews, pipeline state | GitLab |
| Milestones / sprints | GitLab milestones, synced into SwiftData |
| Start date, due date, story points, priority, dependencies | OpenSpec PM database |
| Deadline appeal / lead-approved exception state | Cockpit Dev local SwiftData |
| Local repository path and IDE context | Cockpit Dev local SwiftData |

GitLab does not support the planning fields this app needs for lead analytics, so start dates, due dates, story points, priorities, and dependencies are not derived from GitLab issue weight.

## Main Features

### Workspace Management

- Create workspaces for one or more GitLab repositories.
- Keep all repositories in a workspace under one local root.
- Clone missing repositories and open the workspace root in Zed.
- Switch workspaces without leaking selected workspace state into the main content.
- Authenticate once at app launch instead of per workspace/menu flow.

### GitLab Integration

- OAuth-based GitLab account connection.
- Repository search and add flow.
- Issue import and bidirectional issue creation/update.
- Milestone sync into local sprints.
- Member sync and GitLab user search for invites.
- Merge request listing, detail, discussions, approvals, and merge actions.
- Realization date analysis from the latest commit in the MR that mentions an issue.

### Tickets

- Dedicated ticket list for issue-focused work outside the sprint screen.
- Filtering by sprint, owner, status, label, and repository context.
- GitLab-style issue creation modal.
- Markdown description editor with write/preview modes.
- Planning metadata fields for assignee, labels, milestone, priority, story points, and dates.
- Dependency chips and ticket detail navigation.

### Sprint Planning

- GitLab milestones are represented as sprints.
- Sprint cards show ticket count, story point progress, completion percent, and status.
- Sprint detail view includes burndown, assigned tickets, and ticket detail panel.
- Tickets created or updated in the app sync back to GitLab where GitLab owns the field.

### Timeline

- Developer-based timeline filtered by milestone.
- Dynamic zoom with point-per-day scaling rather than fixed day/week/month modes.
- Horizontal and vertical scrolling for large schedules.
- Ticket bars show readable labels, story points, and dependency count.
- Hover preview shows status, dates, story points, milestone, and priority.
- Dependency visualization is available without making the primary schedule unreadable.

### Specs

- OpenSpec scanning from the selected branch only.
- Default selected branch follows the remote default branch.
- Spec list shows change entries from the configured spec directory.
- Spec detail preview supports proposal, design, tasks, and specs sections.
- Progress percent is computed from completed tasks over total tasks.

### Analytics

- Lead dashboard for delivery health and developer performance.
- Velocity, throughput, workload distribution, cycle time, and individual contribution metrics.
- On-time calculation treats completion on the due date as on time.
- Realization date uses the latest commit in the MR that mentions the issue, then falls back to issue/MR mention or issue close when needed.
- Deadline risk queue highlights missed due dates.
- Lead-approved deadline appeal flow excludes justified delays from accountability metrics.

### Security and Local Storage

- Touch ID / password lock screen.
- Secure credential storage via macOS Keychain Services.
- Shared credential service for the app process to avoid repeated password prompts.
- SwiftData local persistence for workspace state, sync metadata, and local-only lead decisions.

## Tech Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI for macOS 14+ |
| Data | SwiftData |
| Networking | URLSession + async/await |
| Webhook Server | Swift NIO HTTP server |
| Auth | GitLab OAuth + LocalAuthentication |
| Secure Storage | Keychain Services |
| Encryption | Apple CryptoKit |
| Charts | Swift Charts and custom SwiftUI chart surfaces |
| Git | System `/usr/bin/git` through `Process` |
| Package | Swift Package Manager |

## Architecture

Cockpit Dev follows a layered MVVM structure:

```text
Sources/CockpitDev/
├── CockpitDevApp.swift       # App entry point and SwiftData container setup
├── Models/                   # SwiftData models and API DTOs
├── ViewModels/               # Observable feature state and user flows
├── Views/                    # SwiftUI screens and components
│   ├── Analytics/
│   ├── MergeRequests/
│   └── Specs/
├── Services/                 # GitLab, sync, auth, git, webhook, PM data, AI
├── Utilities/                # Design system, app activation, constants
└── Resources/                # Bundled resources

Tests/CockpitDevTests/        # Unit, integration, and performance tests
```

Important entry points:

- `Package.swift`
- `Sources/CockpitDev/CockpitDevApp.swift`
- `Sources/CockpitDev/Views/MainWindowView.swift`
- `Sources/CockpitDev/Services/SyncEngine.swift`
- `Sources/CockpitDev/Services/GitLabAPIClient.swift`
- `Sources/CockpitDev/Services/OpenSpecPMAPIClient.swift`

## Requirements

- macOS 14 Sonoma or later
- Swift 5.9+
- Xcode 15+ command line tools
- GitLab account with access to the target repositories
- Zed installed if using Open in IDE

## Development Commands

Run commands from the repository root:

```bash
swift build
swift test
swift run CockpitDev
./build-app.sh
```

The app bundle command writes `CockpitDev.app` in the repository root:

```bash
open CockpitDev.app
```

## Testing

Run the full suite before committing shared behavior changes:

```bash
swift test
```

For focused work, run the smallest relevant test first:

```bash
swift test --filter SyncEngineTests/testFullReconcileRefreshesRealizationForLegacyTicketWithOnlyIssueIidStoredAsId
swift test --filter AnalyticsViewModelTests/testOnTimeUsesMRCommitRealizationDateInsteadOfIssueClosedDate
```

## Implementation Notes

- This repository is SwiftPM-first; prefer SwiftPM commands over Xcode project workflows.
- Git operations use the system `/usr/bin/git`; SwiftGit2/libgit2 is not configured.
- GitLab issue weight is not used as story points.
- OpenSpec PM is the source for planning metadata used by timeline and analytics.
- Realization analytics prefer MR commit evidence over GitLab issue close timestamps.
- CoreData/SwiftData runtime noise may appear in test logs; treat non-zero exits or XCTest failures as the signal.

## License

This project is proprietary. All rights reserved.
