# Cockpit Dev

> 🚧 **Work in Progress** — This project is under active development and not yet ready for testing or production use.

A native macOS desktop application that serves as a unified project management hub for development teams using GitLab. Cockpit Dev consolidates GitLab project management, multi-repo workspace management, and advanced PM features into a single native experience — eliminating context-switching between GitLab's web UI and external tools.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)
![Status](https://img.shields.io/badge/status-in%20development-yellow)

## Features

### Workspace Management
- Create workspaces that group multiple GitLab repositories, team members, documents, and project artifacts
- Multi-repo IDE context generation (`.code-workspace`) for cross-repo AI assistance
- Role-based access control (Owner, Admin, Member, Viewer)

### GitLab Integration
- OAuth2 authentication with GitLab (SaaS and self-hosted)
- Bidirectional ticket sync with GitLab issues
- Merge request management — review, approve, and merge from the app
- Story points (Fibonacci scale) synced to GitLab issue weights
- Webhook receiver for real-time updates from GitLab

### Project Planning
- **Kanban Board** — drag-and-drop ticket management by status
- **Sprint Planning** — time-boxed iterations with burndown charts
- **Gantt Chart** — timeline visualization with dependency tracking
- **Dependency Conflict Detection** — DAG-based validation to catch scheduling conflicts

### AI-Powered Features
- PRD breakdown — paste a product requirements document and get structured tickets
- Auto-assign — intelligent ticket assignment based on developer skill profiles and workload

### Developer Tools
- Git operations (clone, pull, push, commit) via libgit2
- OpenSpec specification tracking from developer branches
- Document/spec versioning with diff detection

### Analytics
- Team velocity and burndown charts (Swift Charts)
- Workload distribution and individual contribution metrics
- Sprint performance tracking

### Security
- Touch ID / password lock screen
- AES-256-GCM encryption for tokens and credentials (Apple CryptoKit)
- Secure credential storage via macOS Keychain Services

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (macOS 14+) |
| Data | SwiftData (local-first) |
| Networking | URLSession + async/await |
| Webhook Server | Swift NIO (HTTP, port 9876) |
| Encryption | Apple CryptoKit (AES-256-GCM) |
| Secure Storage | Keychain Services |
| Auth | LocalAuthentication (Touch ID) |
| Charts | Swift Charts |
| Git | libgit2 via SwiftGit2 |
| AI | OpenAI-compatible API (OpenRouter) |

## Architecture

Cockpit Dev follows a layered MVVM architecture:

```
┌─────────────────────────────────────────────────────┐
│          Presentation Layer (SwiftUI Views)          │
├─────────────────────────────────────────────────────┤
│        ViewModel Layer (@Observable classes)         │
├─────────────────────────────────────────────────────┤
│    Service Layer (GitLab, Sync, Conflict, AI...)    │
├─────────────────────────────────────────────────────┤
│   Data Layer (SwiftData, GitLab API, Webhooks)      │
├─────────────────────────────────────────────────────┤
│  Infrastructure (Keychain, CryptoKit, LocalAuth)    │
└─────────────────────────────────────────────────────┘
```

## Project Structure

```
Sources/CockpitDev/
├── CockpitDevApp.swift       # App entry point, SwiftData container setup
├── Models/                   # SwiftData @Model types + API response types
├── ViewModels/               # @Observable view models
├── Views/                    # SwiftUI views organized by feature
│   ├── Analytics/
│   ├── Documents/
│   ├── MergeRequests/
│   └── Specs/
├── Services/                 # Business logic, API clients, sync engine
├── Utilities/                # Constants, design system tokens
└── Resources/                # Assets and bundled resources

Tests/CockpitDevTests/        # Unit, integration, and performance tests
```

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+
- Xcode 15+ (for development)

## Getting Started

> ⚠️ The app is still in development. Build and run instructions are provided for contributors only.

### Build with Swift Package Manager

```bash
swift build
```

### Run

```bash
swift run CockpitDev
```

### Build macOS App Bundle

```bash
./build-app.sh
```

## Roadmap

- [ ] Complete GitLab OAuth2 flow and token refresh
- [ ] Finalize bidirectional ticket sync
- [ ] Git operations (clone, pull, push, commit)
- [ ] AI-powered PRD breakdown and auto-assign
- [ ] Webhook server integration testing
- [ ] UI polish and accessibility audit

## License

This project is proprietary. All rights reserved.
