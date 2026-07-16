# Spec 11 — Bulk cleanup from Duplicates and Review Candidates

**Workstream:** Cleanup workflow. **Depends on:** existing snapshot/script engine. **Touches hot files:** `AppCoordinator`, `RootView`, `InstalloryApp`, `PackageListView`, `DuplicatesView`, `OrphansView`, app tests, and shared cleanup controls.

## Problem

The package list supports Cleanup Mode, but Duplicates and Review Candidates are where users most often decide what to inspect together. Those views currently require opening one detail at a time even though `generateAndShowCleanupScript(packages:captureSnapshot:)` already accepts an array.

## Target state

Duplicates and Review Candidates participate in the same Cleanup Mode as the main package list: explicit per-row check controls, an exact selected count, and one generated script that is shown for review and never executed. Bulk generation always attempts a pre-cleanup snapshot, matching the existing package-list behavior.

## Eligibility contract

1. A row is selectable only when a shell removal command exists: it is not read-only and is not a Mac App Store receipt.
2. Put this predicate in Core and make `ScriptGenerator.removalCommand(for:)` use the same rule so UI eligibility cannot drift from script behavior.
3. The current sidebar determines the cleanup scope:
   - All packages: every eligible live package.
   - Manager: eligible packages for that manager.
   - Duplicates: eligible members of cross-manager and multi-location groups, deduplicated by package ID.
   - Review Candidates: eligible orphan-analysis results.
   - Read-only, AI Installed, and snapshots: no bulk cleanup controls.
4. Changing sidebar sections intersects the selection with the new section. Hidden selections from another analysis must never be included in a script.
5. Search may temporarily hide a selected row within the same section; it does not silently discard that explicit selection. The footer's count remains the source of truth.

## App behavior

1. Extract the existing selection toggle and bottom action bar into a small shared SwiftUI control used by Package List, Duplicates, and Review Candidates.
2. Outside Cleanup Mode, eligible sections show “Select for Cleanup.” Inside it, eligible rows show a check control and the footer offers “Generate Cleanup Script (N)” plus “Done.”
3. Generate from the coordinator's section-scoped selected packages and capture a snapshot first. The existing script sheet, warnings, and save/copy flow remain unchanged.
4. Read-only and Mac App Store rows show a non-interactive lock in Cleanup Mode with an accurate accessibility label and help text.
5. The toolbar button and Shift-Command-K menu command are enabled only when the current section contains at least one eligible package.

## Accessibility and keyboard behavior

- Reuse labeled native buttons; the toolbar and Inventory menu retain Shift-Command-K.
- Toggle labels announce the package name and selected state.
- The footer count is visible text in the button label and available to VoiceOver.
- Rows remain arrow-key navigable and their cleanup control remains reachable through Full Keyboard Access.

## Regression tests

- APP-F2: eligibility rejects read-only and Mac App Store packages and agrees with `removalCommand(for:)`.
- APP-F2: Duplicates and Review Candidates advertise cleanup support; read-only, AI, and snapshots do not.
- APP-F2: section reconciliation removes selections outside the new manager/analysis.
- APP-F2: duplicate membership is deduplicated when a package appears in more than one analysis group.
- Existing empty-selection, script-generation, snapshot, denylist, and shell-quoting tests remain green.

## Invariants

Installory only generates and displays text. It never executes the selected commands, mutates package-manager directories, spawns a subprocess, or uses the network.
