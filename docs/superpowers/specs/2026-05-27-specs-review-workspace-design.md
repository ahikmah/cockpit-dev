# Specs Review Workspace Design

## Objective

Replace the narrow `SpecDetailView` modal with a persistent review workspace inside
the `Specs` tab. Long OpenSpec documents must be comfortable to read while keeping
the review queue available for quick movement between changes.

## Current Problem

The current list opens a selected OpenSpec entry in a centered sheet. For a document
containing proposal, design, tasks, and capability specifications, the sheet:

- constrains the reading width and vertical context,
- hides the surrounding review queue,
- forces repeated open/close interactions during review,
- makes a long document feel like a preview rather than primary work content.

## Chosen Layout

Use a persistent two-pane review workspace.

### Left Pane: Change Queue

- Display only the entries for the selected remote branch, preserving existing
  branch-scan behavior.
- Keep the pane compact, approximately 280 to 340 points wide, with a 220-point
  contraction at narrow window widths so the reader remains usable.
- Show a searchable/scannable list of change names with one secondary line for
  branch and phase.
- Show unread/update status without adding dense metadata.
- Apply an explicit selected row state.
- Selecting a row updates the reader in place and marks it as read when the content
  is displayed.

### Right Pane: Document Reader

- Consume the remainder of the Specs tab width.
- Present the selected change name, branch, phase, version information, and
  `History` action in a stable reader header.
- Present `Proposal`, `Design`, `Tasks`, and `Specs` as tabs immediately below the
  header.
- Render document content in a readable constrained column inside the wide pane,
  rather than constraining the entire reader surface.
- Render empty content or missing-document messages within the right pane.
- Render an unselected state in the right pane when no change is selected.

### Focus Mode

- Include a `Focus` control in the reader header.
- When enabled, hide the left change queue and allocate the full Specs tab to the
  reader.
- Provide an obvious control to restore the queue.
- Focus mode is ephemeral view state only; it does not affect persisted spec data or
  selected branch.

## Interaction Behavior

- Remove sheet presentation for selecting an OpenSpec entry.
- The selected entry remains visible while reviewing a document and switching
  document tabs.
- Scanning preserves selection when the selected entry still exists on the selected
  branch.
- If selection becomes invalid after branch change or scan, clear it and show the
  unselected reader state.
- Selecting another branch immediately limits visible entries to that branch; no
  all-branches review mode is introduced.

## Component Boundaries

- `SpecListView` owns the stable two-pane shell, toolbar, queue selection, focus
  state, and settings sheet.
- A dedicated queue/list subview renders selectable OpenSpec rows without owning
  scanning or persistence behavior.
- `SpecDetailView` becomes an embedded reader surface rather than a dismissible
  modal. It keeps document-tab selection, history presentation, markdown rendering,
  and read acknowledgement.
- `SpecViewModel` remains the owner of selected entry, branch filtering, scan state,
  and snapshot retrieval.

## Data Flow

1. The selected branch filters `SpecViewModel.specs`.
2. A queue click assigns `selectedSpec`.
3. The embedded reader requests the latest `OpenSpecDocumentSnapshot` for that
   entry.
4. Reader appearance marks unread content as read and displays the relevant
   document tab.
5. A scan updates versions; existing selection remains usable if the entry remains
   visible.

No persistence schema changes are required for this UI redesign.

## Visual Principles

- Use existing adaptive `DesignSystem` tokens for both light and dark mode.
- Treat the reader as the primary workspace, not as a card or modal.
- Keep borders and surfaces quiet; selected state and document hierarchy must be
  legible without introducing decorative UI.
- Keep row metadata minimal so long change names remain easy to scan.

## Error And Empty States

- Scan errors remain visible near the queue/toolbar because they affect the review
  set.
- An entry with no available snapshot displays its missing-content message in the
  right pane and does not interrupt navigation.
- No selected entry displays a reader prompt that invites selection from the queue.

## Verification

- Add or update view-model tests for branch-change selection validity where the
  behavior is testable without UI automation.
- Build with `rtk swift build`.
- Run focused Specs tests and `rtk swift test`.
- Launch the app and inspect the Specs tab at both normal and narrower window
  widths, checking queue usability, reader width, focus toggle, and dark/light
  contrast.
