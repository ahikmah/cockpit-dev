# Cockpit Dev Agent Instructions

## Local Rules

- Always prefix shell commands with `rtk`.
- Prefer `rg` and `rg --files` for searching.
- Use `apply_patch` for manual file edits.
- Do not revert user changes unless explicitly asked.
- This repository is a SwiftPM-first macOS app. Prefer SwiftPM commands over Xcode project workflows.

## Project Context

Cockpit Dev is a native macOS project management app for GitLab-based development teams.

- Platform: macOS 14+
- Language: Swift 5.9+
- UI: SwiftUI
- Persistence: SwiftData
- Package entry point: `Package.swift`
- Product: executable `CockpitDev`
- Main app entry: `Sources/CockpitDev/CockpitDevApp.swift`
- Root authenticated shell: `Sources/CockpitDev/Views/MainWindowView.swift`

The app follows a layered MVVM structure:

- `Sources/CockpitDev/Models`: SwiftData models and API DTOs
- `Sources/CockpitDev/ViewModels`: observable feature state and user flows
- `Sources/CockpitDev/Views`: SwiftUI screens and components
- `Sources/CockpitDev/Services`: GitLab, sync, webhook, auth, encryption, git, AI, and domain services
- `Sources/CockpitDev/Utilities`: design tokens and constants
- `Tests/CockpitDevTests`: unit, integration, and performance tests

## Commands

Use these commands from the repository root:

```bash
rtk swift build
rtk swift test
rtk swift run CockpitDev
rtk ./build-app.sh
```

Swift build/test may need access to compiler caches outside the workspace. If sandboxed execution fails with cache or module cache permission errors, rerun with approval instead of changing project files.

## Current State

- `README.md` should describe the implementation as it exists, not the intended final product.
- Git operations currently use the system `/usr/bin/git` through `Process`; SwiftGit2/libgit2 is not configured in `Package.swift`.
- Board and Timeline views exist, but the main workspace shell still needs to wire them into `MainWindowView`.
- The project has broad test coverage. Keep tests passing after changes.
- Some runtime test output may include CoreData XPC noise even when tests pass.

## Engineering Priorities

Prioritize in this order:

1. UI/UX quality for a dense native macOS developer tool.
2. Performance on large workspaces, ticket lists, timelines, and analytics.
3. Clear data flow between SwiftData models, view models, and services.
4. Reliable GitLab sync and offline/conflict behavior.
5. Clean tests and warning-free builds.

For UI work:

- Prefer native macOS SwiftUI patterns.
- Keep operational screens dense, scannable, and efficient.
- Avoid marketing-style layouts.
- Use the existing `DesignSystem` before introducing new visual constants.
- Make controls keyboard-friendly where practical.

For performance work:

- Avoid recomputing expensive derived data in view bodies.
- Keep SwiftData fetches and relationship traversal bounded.
- Use Canvas or other efficient rendering paths for dense timeline/chart surfaces.
- Add focused tests around any caching, invalidation, or sorting behavior.

## Testing Expectations

Before claiming completion, run the smallest relevant test first, then the full suite when the change affects shared behavior:

```bash
rtk swift test --filter <TestClass>/<testName>
rtk swift test
```

If a test failure is unrelated to the current change, investigate enough to identify it clearly before deciding whether to fix it.
