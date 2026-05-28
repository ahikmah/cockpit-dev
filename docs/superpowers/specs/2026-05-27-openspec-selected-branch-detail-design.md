# OpenSpec Selected Branch and Detail Design

## Problem

The Specs screen currently exposes an all-branches scan mode and treats a change
folder as a single phase document. This produces duplicate rows across remote
branches and does not match the repository structure in
`~/Desktop/openspec-pm`, where each change may contain:

- `proposal.md`
- `design.md`
- `tasks.md`
- `specs/<capability>/spec.md` or `specs/<capability>.md`

Because the app looks for `requirements.md` for proposal content and stores
only one selected document, detail can be empty even when the remote change
contains valid OpenSpec files.

## Approved Behavior

The branch picker always has one selected branch. When the Specs surface first
loads, its selected branch is the repository's remote `defaultBranch`; there
is no `All branches` option. Pressing Scan reads only the selected branch, and
the visible list includes entries from that branch only.

Each list row represents one OpenSpec change folder on the selected branch.
Changing the branch swaps the visible result set rather than mixing rows from
multiple branches. Existing previously scanned entries may remain persisted for
history, but they do not appear outside their selected branch.

## Snapshot Format

No new SwiftData persisted properties are required. `DocSpecVersion.content`
continues to store the version payload, but new snapshots contain a Codable
document envelope with optional proposal, design, and tasks markdown plus an
array of named capability spec markdown files. A decoder falls back to treating
legacy plain-text versions as the document for the entry's saved phase.

The snapshot hash covers the encoded complete document. A content change in any
OpenSpec file therefore creates a version and sets the unread state, while old
version history remains readable.

## Discovery Data Flow

For a selected branch and configured `openspec/changes` path:

1. Fetch immediate child directories under `openspec/changes`.
2. For each change folder, inspect its immediate files to determine available
   `proposal.md`, `design.md`, and `tasks.md` documents.
3. Inspect `specs/`; accept both direct markdown files and nested
   `<capability>/spec.md` files.
4. Fetch present file content, form the complete document snapshot, and persist
   or version the corresponding `OpenSpecEntry`.
5. Derive row status from the most advanced available root document:
   tasks, then design, then proposal.

Absent optional files are not failures. A folder with no readable OpenSpec
document is skipped rather than displayed as an empty item.

## UI

The header communicates a single active remote branch and the repository path.
The picker lists remote branches only and defaults to the repository default.
The scan result reports the specific scanned branch.

Rows use a higher-contrast phase icon container and phase badge in both color
schemes. Unread state is shown as an explicit `New update` badge with an icon,
not only a small dot.

Detail presents tabs for `Proposal`, `Design`, `Tasks`, and `Specs`. Tabs with
missing data are disabled or clearly empty. The Specs tab renders each named
capability document, with the file path visible above its markdown content.

## Verification

- View-model tests verify default branch selection and single-branch filtering.
- Service tests verify OpenSpec multi-file discovery, nested capability
  documents, and complete snapshot versioning.
- Existing legacy content remains displayable through decoder fallback tests.
- Build and the full Swift test suite must pass after implementation.
