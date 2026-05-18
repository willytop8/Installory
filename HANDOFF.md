> **👉 Resuming work? Read `NEXT-SESSION.md` first.** This file is the long-form historical record.

---

# Phase 6: Cross-Manager Duplicate Detection (2026-05-17)

## Scope and deliberate exclusions

A "duplicate" is ONE tool installed by TWO OR MORE DIFFERENT package managers — e.g. `node` under both Homebrew and npm. This is almost always a genuine problem (wrong-version confusion on PATH) and almost never intentional.

Two cases are explicitly excluded and must stay excluded:

**Same-manager multi-environment** — `requests` appearing in nine pip interpreters is normal Python isolation. Flagging it would bury the real signal in noise. The qualifying rule is `distinctManagers.count >= 2` where `brew` and `brewCask` map to the same effective manager before the count.

**brew + brewCask same name** — a Homebrew formula and a Homebrew cask with the same name are not a cross-manager duplicate. Both are Homebrew. The `effectiveManager` mapping (`.brewCask → .brew`) inside `crossManagerDuplicates()` enforces this at the library level.

Matching is exact (case-insensitive) on `Package.name`. No fuzzy matching, no heuristic name normalization. A tool named `foo` in one manager and `foo-cli` in another is not matched in v1. Accept the misses; avoid false positives.

## Architecture decisions

**View reuse: dedicated `DuplicatesView`, `PackageDetailView` reused.** The duplicate content pane shows grouped data (tool name → installs), structurally unlike `PackageListView`'s flat list. Forcing groups into the flat list would require either a fake-Package wrapper type or leaking display logic into the coordinator. A small dedicated view is clean. `PackageDetailView` is reused for the detail pane — clicking any install row sets `coordinator.selectedPackage` and the existing detail pane opens with its full removal affordance. The removal flow is 100% unchanged.

**Sidebar placement: "Package Managers" section, after "Read-only."** Duplicates is a cross-cutting view of current inventory — conceptually adjacent to the manager rows. A standalone section would add visual noise for a feature that is usually absent (0 duplicate groups = row hidden entirely).

**`filtered(by: .duplicates)` returns `[]`.** `DuplicatesView` reads `coordinator.duplicateGroups` (backed by `crossManagerDuplicates()`) directly. When `.duplicates` is selected, `filteredPackages` is never consulted. Same pattern as `.snapshot`.

**`.duplicates` persists normally.** Unlike `.snapshot(UUID)`, a duplicates selection is always valid on next launch. `persistUIPreferences()` was left unchanged; the existing `.snapshot`-only guard correctly passes `.duplicates` through to persistence.

## Files changed

| File | Change |
|---|---|
| `Installory/Sources/InstalloryCore/Models/DuplicateGroup.swift` | NEW — struct + `crossManagerDuplicates()` extension |
| `Installory/Sources/InstalloryCore/Models/SidebarSelection.swift` | `.duplicates` case, userDefaultsKey, init?, filtered |
| `Installory/Tests/InstalloryCoreTests/DuplicateDetectionTests.swift` | NEW — 6 library tests |
| `App/Sources/AppCoordinator.swift` | `duplicateGroups` computed property |
| `App/Sources/Views/SidebarView.swift` | Duplicates row in Package Managers section |
| `App/Sources/Views/RootView.swift` | `.duplicates` branch in content pane |
| `App/Sources/Views/DuplicatesView.swift` | NEW — grouped duplicate list |

---

# Audit Cleanup (2026-05-17)

## What this session fixed

Post-audit cleanup pass. No product behavior changed. Changes:

| Task | What changed |
|---|---|
| Entitlements | `App/Installory.entitlements` was an empty dict — added `app-sandbox`, `files.user-selected.read-only`, `files.bookmarks.app-scope` |
| Snapshot failure UX | `CleanupResult` gains `snapshotFailed: Bool`; `CleanupScriptSheetView` now shows a prominent red warning when a requested snapshot fails, distinct from the neutral grey "no snapshot taken" message |
| First-scan snapshot | `AppCoordinator.scan()` now captures an `.autoFirstScan` snapshot on the first successful scan (UserDefaults flag: `backshelf.firstScanSnapshotTaken`); `SnapshotReason.autoFirstScan` was already defined but unused |
| SnapshotContentView duplicate-ID | `SnapshotPackage` gains `Identifiable` with `id = "\(name)\|\(qualifier ?? "")"` — fixes the same duplicate-SwiftUI-ID class that broke the sidebar in Phase 5b; `SnapshotContentView` ForEach updated |
| UI language | Context menu "Remove…" → "Create Removal Script…"; `SnapshotChoiceSheet` headline reworded to mention script generation, not removal; `PackageDetailView` section heading "Remove" → "Removal Script" |
| SnapshotPreference comment | Comment now states the actual UserDefaults key (`backshelf.settings.snapshotBeforeRemoval`) and explains the prefix is intentional |
| Shebang | `#!/bin/bash` → `#!/usr/bin/env bash` in both script generators; tests updated |
| `files/safety.md` | Rewritten — see below |
| `files/CLAUDE.md` | All `docs/` path references corrected to `files/`; stale "never snapshot" rule updated to reflect preference-based reality |
| `README.md` | Library test count updated from 248 → 315 |
| `HANDOFF.md` | Stale "Backshelf" refs fixed in 2026-05-17 sections (InstalloryApp, InstalloryCore path, menu name, reinstall filename) |
| `NEXT-SESSION.md` | Replaced stale Phase-5b content with current-state pointer |

## `files/safety.md` rewrite — why

The code was correct. The doc was stale. Rule 1 previously said "Snapshot before any cleanup script. No exceptions." but the product intentionally supports a `snapshotBeforeRemoval` preference (Always / Ask / Never) for per-package removal. Batch cleanup always snapshots. Per-package honors the preference. Pre-cleanup snapshots scope to the packages being removed, not the full inventory. The rewritten doc matches what the code actually does.

## Known limitations (documented, not fixed)

1. **Dependency warnings scope** (`ScriptGenerator`): dependency warnings consider only the selected packages, not the full inventory. A dependent package outside the current filter may be silently omitted from the warning. Noted in `files/safety.md`.
2. **App-layer test coverage**: `AppCoordinator`, settings, onboarding, and cleanup state have no unit tests (all SwiftUI / app-layer code). Tier 2 robustness item for a future phase.

---

# Renamed Backshelf → Installory (2026-05-17)

## What changed

- **SPM package dir**: `Backshelf/` → `Installory/` (via `git mv`; blame preserved)
- **Library target**: `BackshelfCore` → `InstalloryCore`; source dir `Sources/BackshelfCore/` → `Sources/InstalloryCore/`; test dir `Tests/BackshelfCoreTests/` → `Tests/InstalloryCoreTests/`
- **App entry point**: `BackshelfApp.swift` → `InstalloryApp.swift`; `struct BackshelfApp` → `struct InstalloryApp`
- **Bundle ID**: `app.backshelf.mac` → `app.installory.mac` in `project.yml`
- **Entitlements file**: `App/Backshelf.entitlements` → `App/Installory.entitlements`
- **Database filename**: `backshelf.db` → `installory.db` (Application Support; container resets anyway — see below)
- **Application Support subdir**: `~/…/Application Support/Backshelf/` → `…/Installory/`
- **All source identifiers, comments, doc-comments, and UI strings**: `Backshelf` → `Installory`, `backshelf` → `installory`
- **All docs** under `files/`, root `README.md`, `NEXT-SESSION.md`, scripts

## UserDefaults keys — intentionally kept as "backshelf.*"

The six UserDefaults keys (`backshelf.ui.*`, `backshelf.settings.*`, `backshelf.onboarding.completed`) were **not renamed**. Renaming them would silently drop every existing user's settings, sort preference, onboarding flag, and snapshot preference on first launch after the update — no migration, no fallback, just a silent reset. Pre-release the install base is small, but the precedent is wrong. An explanatory comment marks these keys in `AppCoordinator.swift`.

## Bundle ID change — container reset

Because the bundle ID changed from `app.backshelf.mac` to `app.installory.mac`, macOS moves the app's sandbox container from:

```
~/Library/Containers/app.backshelf.mac/
```
to a new, empty container at:
```
~/Library/Containers/app.installory.mac/
```

**Consequence**: the local SQLite database and any snapshots stored in the old container are not accessible to the new build. This is expected and acceptable pre-release — a clean local slate.

---

# Phase 5d-2: Provenance UI + Settings (2026-05-17)

## Status

Implementation-complete. `swift build` + `swift test` pass (315 tests, zero warnings — library
unchanged). Hardware verification status is tracked in `NEXT-SESSION.md`.

## Architecture decisions

### Provenance wiring (Task 1)

`ProvenanceCollector` and `ProvenanceDAO` were fully built in Phase 4 but had no call site.
Task 1 wires them into `AppCoordinator.scan()` after every successful scan:

1. `packageDAO.replaceAll(with:)` persists the fresh package list (FK prerequisite).
   The `ON DELETE CASCADE` on `provenance_evidence` wipes stale evidence automatically.
2. `ProvenanceCollector().collect(packages:)` runs inside `Task.detached(priority: .utility)`
   because it performs real filesystem I/O (shell history + `~/.claude/projects/*.jsonl` walks).
   `ProvenanceCollector` and `[Package]` are both `Sendable`; the detached task is safe.
3. Evidence rows are upserted one-at-a-time via `await provenanceDAO.upsert(e)`.
   Each call hops to the DAO actor (off main thread for the SQLite write), then returns.
   200 packages ≈ 200 hops ≈ negligible overhead; main thread is never blocked.
4. `AppCoordinator.provenanceByPackageId` is updated in one atomic assignment after all
   upserts complete. The detail pane never sees a partially-filled dict.
5. The entire step is skipped when `provenanceCollection == false` (Task 3 setting).

### Detail pane layout (Task 2)

Section order: **description (header) → fields → provenance → remove → raw record.**
Provenance is context, not action; it lives between fields (what is it?) and removal (what do I
do with it?) without competing for the user's attention. The section is omitted entirely when
`coordinator.provenanceCollection == false` — no empty section, no placeholder.

`PackageDetailView` reads `coordinator.provenanceByPackageId[package.id]` directly. No async
fetch, no `@State` for evidence — the coordinator dict is `@Observable` so changes (from a
background rescan's provenance re-collection) re-render the view automatically. During the brief
window between a scan clearing the DB and provenance being re-collected, the old dict entry stays
in memory, so the user sees the previous evidence without any flicker.

Three states the section can show:
- **Evidence found**: narrative sentence from `NarrativeRenderer` + optional confidence badge
  (medium/low/unknown). High confidence shows no badge — it doesn't need the disclaimer.
- **No evidence** (`nil` in dict after a scan): quiet "Install origin unknown." in tertiary color.
  This is the expected state for old packages without shell history or Claude Code logs.
  It is NOT presented as an error.
- **Disabled** (setting off): section is not rendered at all.

### Settings window (Task 3)

`InstalloryApp` now has a `Settings` scene alongside `WindowGroup`. The same `coordinator`
instance is injected into both scenes, so `SettingsView` binds directly to coordinator
properties — one source of truth, live reactivity.

Three preferences, all under the `backshelf.settings.` UserDefaults prefix:

| Preference | Key | Type | Default |
|---|---|---|---|
| Snapshot before per-package removal | `snapshotBeforeRemoval` | `SnapshotPreference` | `.ask` |
| Scan on launch | `scanOnLaunch` | `Bool` | `true` |
| Provenance collection | `provenanceCollection` | `Bool` | `true` |

The `SnapshotPreference` enum lives in the App module (not `BackshelfCore`). Nothing in the
library needs to know about snapshot preference — it's purely a UI/coordinator concern.

Bool defaults are `true`. `restoreSettings()` uses `UserDefaults.object(forKey:) != nil` to
distinguish "never written" (keep `true` default) from "explicitly written `false`".

### Removal flow (Task 4)

All per-package removal routes through `AppCoordinator.requestRemoval(_ packages: [Package])`:
- **Always** → `generateAndShowCleanupScript(packages:captureSnapshot: true)`
- **Never** → `generateAndShowCleanupScript(packages:captureSnapshot: false)`
- **Ask** → sets `coordinator.pendingRemovalPackages`, raising the snapshot-choice dialog

**One dialog, one code path.** Both the detail-pane button and the row context menu call
`coordinator.requestRemoval([package])`. `RootView` presents `SnapshotChoiceSheet` when
`pendingRemovalPackages != nil`. The sheet calls `coordinator.confirmRemoval(packages:takeSnapshot:remember:)`
or `coordinator.cancelRemoval()`. No per-view dialog duplication.

`generateAndShowCleanupScript` now takes an explicit `captureSnapshot: Bool` parameter.
Batch cleanup in `PackageListView` always passes `captureSnapshot: true` — the setting does not
affect batch mode.

The detail pane's "Remove this package…" button label is now setting-aware through
`guidedRemovalCaption`, which explains what will happen (snapshot / no snapshot / you'll be
asked) without the user needing to open Settings first.

## Files added / modified

| File | Change |
|---|---|
| `App/Sources/Models/SnapshotPreference.swift` | NEW — 3-state enum for snapshot preference |
| `App/Sources/AppCoordinator.swift` | Major additions — settings, provenance, removal flow |
| `App/Sources/InstalloryApp.swift` | Added `Settings` scene with coordinator injection |
| `App/Sources/Views/SettingsView.swift` | NEW — grouped Form bound to coordinator |
| `App/Sources/Views/SnapshotChoiceSheet.swift` | NEW — coordinator-driven "Ask" dialog |
| `App/Sources/Views/RootView.swift` | Added snapshot-choice sheet |
| `App/Sources/Views/PackageDetailView.swift` | Provenance section + updated removal button |
| `App/Sources/Views/PackageListView.swift` | Context menu + batch cleanup updated |

## Known limitations (documented, not solved)

- **Provenance coverage is uneven.** Old packages without shell history or Claude Code
  sessions will show "Install origin unknown." This is expected and by design — the app is
  honest about what it doesn't know.
- **pip `(manager, name)` qualifier collision** in provenance matching (Phase 4c known issue):
  multiple pip packages with the same name but different interpreter qualifiers share one bucket.
  First match wins. Not addressed in this phase.
- **`nearbyProjects` is always `[]`**: the git-walk signal was deferred in Phase 4 and remains
  unimplemented.

---

# Phase 5d-1: Package Descriptions Corpus (2026-05-17)

## Status

Implementation-complete. `swift test` passes (336 tests, zero warnings — 21 new
`DescriptionStoreTests` plus 315 prior). The corpus covers Homebrew (complete) and PyPI (top 4000).
See "Completing the corpus" below for npm seed expansion.

## Why Bundled, Not Fetched

Backshelf's App Store privacy story is "zero network calls, zero data collection."
Runtime description fetching would break that guarantee for marginally fresher
text about what tools do — and what a tool does barely changes. The corpus is
generated at BUILD TIME on the developer's machine and bundled into the app.
Coverage of brand-new packages improves by regenerating and shipping an update,
never by runtime networking. No network entitlement is added.

## Corpus Format Decision: JSON, Not SQLite

The corpus is a flat key→string map: `"{manager}:{normalizedName}" → "description"`.
A JSON file loaded into `[String: String]` at startup is 30 lines of code, zero
additional infrastructure, and loads instantly (~1 MB). SQLite would add a
read-only `DatabasePool`, GRDB conformances on `Description`, and query overhead
— none of which is needed for a single-key lookup. JSON is the right tool here.

## Description Model Decision

`Description.swift` (Phase 0) has been updated: the misleading SQLite/GRDB comment
is replaced with an accurate note, and a public `init(manager:name:text:)` is added
so the struct is usable as a domain model if needed. `DescriptionStore` uses a plain
`[String: String]` dictionary internally and does not depend on the `Description` struct.
The struct is retained as a domain concept (the shape of a description entry) but
has no GRDB conformances and is not used by the store.

## Corpus Coverage Generated

| Registry | Count | How |
|---|---|---|
| Homebrew formulae | 8,354 | Bulk API (`formulae.brew.sh/api/formula.json`) |
| Homebrew casks | 4,986 | Bulk API (`formulae.brew.sh/api/cask.json`) |
| PyPI | 1,092 (top 1100 by downloads) | `hugovk.github.io/top-pypi-packages/` seed + per-package PyPI JSON API |
| npm | 260 | Committed seed list in `seeds/npm-seed-list.json` |
| **Total** | **14,692** | |

The top-1100 PyPI slice covers the packages most users encounter (boto3, requests,
numpy, pandas, pytest, etc.). Run with `--limit 4000` or no limit to get fuller
coverage — the cache makes subsequent runs nearly instant.

## Seed Files

Both seed files are committed in `scripts/generate-descriptions/seeds/`:

- `pypi-seed-list.json` — 15,000 package names from hugovk/top-pypi-packages.
  The script fetched 4,000 of these (top by rank). Remove the file and re-run
  to refresh the list from upstream.
- `npm-seed-list.json` — 263 well-known packages (curated, committed as fallback).
  Expands automatically via the npm registry search API when < 1,000 entries.

## How to Regenerate the Full Corpus

```bash
# Full run (all registries, all packages — ~15 min on first run)
python3 scripts/generate-descriptions/generate.py

# Then commit the updated corpus:
git add App/Resources/descriptions.json scripts/generate-descriptions/seeds/
git commit -m "chore: refresh descriptions corpus"
```

The `.cache/` directory (gitignored) holds previously-fetched per-package JSON
responses. Re-runs are near-instant for cached packages. To force a full refresh:

```bash
rm -rf scripts/generate-descriptions/.cache/
python3 scripts/generate-descriptions/generate.py
```

## Completing the npm Coverage

The committed npm seed list covers ~260 packages. To expand to ~5,000 (top npm
packages by popularity), delete `seeds/npm-seed-list.json` and re-run — the
script will page through the npm registry search API and save the expanded list:

```bash
rm scripts/generate-descriptions/seeds/npm-seed-list.json
python3 scripts/generate-descriptions/generate.py
git add scripts/generate-descriptions/seeds/npm-seed-list.json App/Resources/descriptions.json
git commit -m "chore: expand npm descriptions corpus"
```

## New Library API

- `DescriptionStore` — `Sendable` struct in `InstalloryCore/Descriptions/DescriptionStore.swift`
  - `init(contentsOf: URL) throws` — loads the bundled JSON corpus
  - `init()` — empty store (every lookup returns nil; graceful fallback)
  - `init(raw: [String: String])` — internal, for tests
  - `description(for manager: PackageManager, name: String) -> String?` — the lookup

## New App API

- `AppCoordinator.descriptionStore: DescriptionStore` (private-set)
  - Loaded synchronously in `init()` via `Bundle.main.url(forResource: "descriptions", withExtension: "json")`
  - Falls back silently to empty store if the file is absent or malformed

## Key Normalization (non-negotiable; tested)

The corpus keys and the lookup normalize identically:
- **pip/pipx:** PEP 503 — lowercase, runs of `[-_.]` → single `-`. So `Requests`, `requests_oauthlib`, and `requests-oauthlib` all resolve to the same key.
- **npm:** `lowercased()` only. Scoped names (`@types/node`) are preserved exactly, just lowercased.
- **brew/brewCask/cargo/gem/mas:** exact match, no normalization.

21 tests in `DescriptionStoreTests.swift` cover all normalization paths explicitly.

---

# Snapshot-Based Recovery: Diff + Reinstall (2026-05-17)

## Status

Implementation-complete. `swift build` + `swift test` must be verified on hardware.

## Design: Why Diff, Not Whole-Snapshot Reinstall

A snapshot taken before a cleanup operation can hold 200+ packages, the vast majority of which are still installed. A "reinstall everything in this snapshot" script would:
- Re-install packages the user deliberately removed since the snapshot for unrelated reasons
- Be hundreds of lines of noise for a typical "I removed ffmpeg by accident" recovery
- Confuse the user about what was actually affected

The feature is therefore a **diff**: `snapshotDiff(snapshot:livePackages:)` returns only the packages that were in the snapshot but are no longer in the live inventory. The checklist UI shows that diff with all items pre-checked. The user unchecks what they don't want, then generates a reinstall script for the remainder.

## Task 2 Return Type Decision

`GeneratedReinstallScript` is a new type with just `scriptText: String` and a `public init(scriptText:)`. It does **not** reuse `GeneratedScript` because `GeneratedScript.skippedReadOnly` and `GeneratedScript.warnedDenylisted` are uninstall-specific fields with no meaning in a reinstall context. The reinstall path has no denylist filtering (reinstalling a common essential is harmless) and no concept of skipped packages (the checklist lets the user exclude items before calling the generator).

## Shell-Escaping Helpers

`shellDoubleQuoteEscape` and `shellEchoLine` were private methods on `ScriptGenerator`. They are now `internal` free functions in `Cleanup/ShellScriptHelpers.swift`, called by both `ScriptGenerator` and `ReinstallScriptGenerator`. No behavior change to the uninstall path.

## Known Limitation: isExplicit for pip and npm

`isExplicit` is always `true` for pip and npm packages (neither manager has an `installed_on_request` equivalent). The diff therefore cannot distinguish user-installed pip/npm packages from transitive dependencies — the restore checklist may offer dependency packages alongside user-installed ones. This is acceptable: reinstalling a dependency explicitly is harmless, and the checklist lets the user skip it. Do NOT attempt to infer explicitness for pip/npm.

## safety.md Updated

The old "Exporting a snapshot as a reinstall script" section described whole-snapshot export — the approach we explicitly rejected. It has been replaced with an accurate description of the diff-based "Restore Missing Packages" flow. A safety doc that describes a superseded feature is a trap for future decisions.

## New Library API Surface

- `MissingPackage` — `Sendable, Identifiable`. Public memberwise `init(manager:package:)`. Computed `id: String` mirrors the `(manager, qualifier, name)` match key.
- `snapshotDiff(snapshot:livePackages:) -> [MissingPackage]` — free function, pure, testable. Matches on `(manager, qualifier, name)`, not version.
- `GeneratedReinstallScript` — `Sendable`. Public `init(scriptText:)`.
- `ReinstallScriptGenerator` — `Sendable`. `generate(missing:) -> GeneratedReinstallScript`.

## New App API Surface

- `ScriptSheetView<Warning: View>` — generic sheet used by both cleanup and reinstall flows. `CleanupScriptSheetView` is now a thin wrapper.
- `RestoreChecklistSheet` — private, embedded in `SnapshotContentView.swift`. Two-step: checklist → script. Dismissing from either step closes the sheet.

---

# Product-Correction: Per-Package Removal as Primary Flow (2026-05-16)

## Rationale

The founding vision for Backshelf was per-package removal with full context — see a package, understand it, remove it. After 5c, the only removal path was batch cleanup mode: "Select for Cleanup" hidden in a toolbar that collapses on narrow windows, requiring the user to select packages before they could do anything. Per-package removal was never surfaced.

This correction makes individual removal a first-class flow without removing the batch path.

## What Shipped

### `ScriptGenerator.removalCommand(for:) -> String?` (library, public)

New public API on `ScriptGenerator`. Returns the single shell command to remove a package, or `nil` for:
- `isReadOnly == true` — system packages
- `.mas` — Mac App Store apps (no CLI uninstall exists)

Kept intentionally separate from the private `renderCommand` (script-line renderer). This method owns the nil cases cleanly; `renderCommand` stays script-oriented and private.

12 new library tests in `ScriptGeneratorTests.swift` covering all managers, nil cases, pip qualifier fallback, special characters in paths.

### `AppCoordinator.generateAndShowCleanupScript(packages:)` (refactored)

Signature changed from `generateAndShowCleanupScript()` (read `selectedForCleanup` internally) to `generateAndShowCleanupScript(packages: [Package])` (explicit package list). Both callers pass their selection explicitly:
- Batch: `coordinator.packages.filter { coordinator.selectedForCleanup.contains($0.id) }`
- Single: `[package]`

Both paths go through the identical snapshot-then-generate-then-sheet flow. The `.preCleanup` snapshot is captured regardless of how many packages are being removed. One-package removals are exactly where someone nukes `openssl` and needs the undo.

### `PackageDetailView` — removal section

Added below `fieldsSection`, above `rawRecordSection`. Three branches:
- `isReadOnly`: lock icon + "This is a system package and cannot be removed."
- `.mas`: info icon + "Mac App Store apps are removed by dragging them from /Applications to the Trash — mas has no uninstall command."
- Everything else: monospaced selectable command, optional orange denylist warning, "Copy command" button, "Paste into Terminal to run" hint, red "Remove this package…" button (triggers the full sheet with snapshot capture).

View now has `@Environment(AppCoordinator.self)`. `#Preview` updated to inject `.environment(AppCoordinator())`.

### `PackageListView` — context menu + bottom bar (Task 3)

**Context menu:** `PackageRowView` gains an `onRemove: (() -> Void)?` parameter. When non-nil, right-clicking a row shows "Remove…". The closure captures `pkg` (the ForEach iteration value — a struct, captured by value), not `coordinator.selectedPackage`. Read-only and `.mas` packages pass `nil` for `onRemove`, so the menu item is suppressed — the shortcut cannot bypass the rule the primary path enforces.

**Bottom bar (toolbar discoverability fix):** "Select for Cleanup" was in `ToolbarItem(placement: .automatic)`, which collapses into the overflow chevron on narrow windows. Replaced with `.safeAreaInset(edge: .bottom, spacing: 0)`:
- Normal mode: "Select for Cleanup" right-aligned, `background(.bar)`, separator above.
- Cleanup mode: "Generate Cleanup Script (N)" left + "Done" right in the same bar.
- Bar is hidden when `coordinator.packages.isEmpty` (no packages = nothing to clean up).

Sort picker stays in the toolbar (compact, never collapses alone). Batch cleanup is the secondary flow; per-package removal from the detail pane is primary.

## Row Context Menu vs. Button Decision

**Primary:** "Remove this package…" button in `PackageDetailView` — always visible when the package is selected, prominent, red, shows the command before committing.

**Secondary shortcut:** `.contextMenu` on `PackageRowView` — right-click any row → "Remove…". Power-user shortcut that skips opening the detail pane first. Acts on the clicked row's package, not on `coordinator.selectedPackage`.

This pairing matches macOS convention (action in inspector + right-click shortcut) without crowding the row with buttons.

## Safety Invariants Upheld

- `ScriptGenerator.generate` still filters `isReadOnly` packages into `skippedReadOnly` — the generator is the guarantee; UI suppression is the convenience.
- `.preCleanup` snapshot is captured on every call to `generateAndShowCleanupScript(packages:)`, including single-package calls.
- No "execute" button was added anywhere. The sheet shows, copies, and saves. The user runs it.

---

# Phase 5c-2 Handoff (2026-05-16)

## Status

Phase 5c-2 is **implementation-complete**. `swift build` passes (zero errors, zero warnings). All 272 library tests pass.

Tasks C (Snapshots UI), D (Cleanup Wizard), and E (Onboarding) are complete.

## What Was Built

### Task C — Snapshots UI

**`Backshelf/Sources/BackshelfCore/Models/Snapshot.swift`** — Added `case preCleanup` to `SnapshotReason`. (The model previously had `.manual`, `.preUninstall`, `.autoFirstScan`; `.preCleanup` is used by the cleanup wizard's auto-capture, as required by `files/safety.md` Rule 1.)

**`Backshelf/Sources/BackshelfCore/Models/SidebarSelection.swift`** — Added `case snapshot(UUID)`. The `.snapshot` case:
- Returns `""` from `userDefaultsKey` and is guarded against in `persistUIPreferences()` (so it's never written to UserDefaults).
- `init?(userDefaultsKey:)` produces `nil` for any unknown key — restoring a deleted snapshot ID correctly falls through to the default `.all`.
- `[Package].filtered(by:query:)` returns `[]` for `.snapshot(_)` — snapshot content is rendered by `SnapshotContentView`, not this filter.

**`App/Sources/AppCoordinator.swift`** — Added:
- `snapshots: [Snapshot]` (private-set, loaded asynchronously) and `snapshotManager: SnapshotManager?`
- `refreshSnapshots()` — async, awaits `snapshotManager.list()`; called by `autoScanIfNeeded()` and `refresh()`
- `captureManualSnapshot()` — captures `.manual` snapshot, refreshes list
- `generateAndShowCleanupScript()` — (1) captures `.preCleanup` snapshot, (2) calls `ScriptGenerator`, (3) stores result in `cleanupSheetScript`
- `persistUIPreferences()` updated to guard against `.snapshot` case before calling `userDefaultsKey`

**`App/Sources/Views/SidebarView.swift`** — Added `snapshotsSection` as a third section below "Directory Access". Each row is a `NavigationLink(value: SidebarSelection.snapshot(id))` showing the reason label and relative timestamp. Empty state: "No snapshots yet".

**`App/Sources/Views/RootView.swift`** — Routing updated:
- `content:` pane: switches to `SnapshotContentView(snapshotID:)` when `sidebarSelection == .snapshot(id)`, otherwise `PackageListView`
- `detail:` pane: shows a `ContentUnavailableView` in snapshot mode (no package detail while browsing snapshots)
- Added "Snapshot Now" (`camera.viewfinder`) toolbar button next to Refresh — disabled when packages are empty or scan is running
- Two sheets added: cleanup script sheet (presented when `cleanupSheetScript != nil`) and onboarding sheet (presented when `!onboardingCompleted`)

**`App/Sources/Views/SnapshotContentView.swift`** (NEW) — Lightweight snapshot browser:
- Metadata header: reason label, formatted capture date, total package count
- "Exit Snapshot" button (top right) sets `coordinator.sidebarSelection = .all`
- Per-manager `Section` groups (sorted alphabetically by rawValue), each containing `SnapshotPackageRowView` items
- `.searchable` filters by name within the snapshot
- Uses `SnapshotPackage` directly — does NOT synthesize ghost `Package` objects
- `SnapshotPackageRowView`: name (bold), `ManagerBadge`, version (monospaced), "dependency" label when `isExplicit == false`, interpreter's `lastPathComponent` when qualifier is present

### Task D — Cleanup Wizard

**`App/Sources/AppCoordinator.swift`** — Added:
- `selectedForCleanup: Set<String>` — Package IDs selected for cleanup (independent of `selectedPackage` / detail pane)
- `isCleanupMode: Bool` — toggled; default false
- `cleanupSheetScript: GeneratedScript?` — non-nil triggers the cleanup sheet

**Cleanup mode visibility decision: Toggled (not always-on).** Rationale: always-on checkboxes add a persistent leading column to every row, cluttering the default browsing experience. A toggled mode (via "Select for Cleanup" toolbar button) activates checkboxes only when the user has cleanup intent, matching macOS Mail.app's Edit mode pattern. This is the deliberate choice; it is noted here as required by the task brief.

**`App/Sources/Views/PackageListView.swift`** — Cleanup mode controls:
- When `isCleanupMode == false`: Sort picker + "Select for Cleanup" (`checkmark.circle`) button in toolbar
- When `isCleanupMode == true`: "Generate Cleanup Script (N)" button (disabled when 0 selected) + "Done" button; sort picker is hidden
- `PackageRowView` updated: when `isCleanupMode == true`, shows a leading checkbox (for non-readOnly packages) or a lock icon (for readOnly packages, unselectable per `safety.md` Rule 4). Checkbox tap toggles `selectedForCleanup` independently of `selectedPackage`. Row click still drives `selectedPackage` / detail pane.

**`App/Sources/Views/CleanupScriptSheetView.swift`** (NEW):
- Header: "Cleanup Script Ready" + "Snapshot captured before generation ✓" (green)
- Denylist warning banner (orange): appears when `script.warnedDenylisted` is non-empty; lists affected package names
- Script view: scrollable (vertical + horizontal), monospaced, text-selectable
- Safety reminder: "Backshelf does not run it for you" — always visible
- "Copy to Clipboard": writes `scriptText` to `NSPasteboard`
- "Save as .sh…": `NSSavePanel` defaulting to `backshelf-cleanup.sh`; uses `UTType(filenameExtension: "sh")` (safer than `UTType.shellScript` for macOS 13 compat)
- "Done": dismisses sheet, sets `cleanupSheetScript = nil`

**Safety invariant upheld:** `generateAndShowCleanupScript()` always captures a snapshot BEFORE calling `ScriptGenerator`. No "execute" button exists anywhere. Script is generated, previewed, copied, or saved only.

### Task E — Onboarding

**`App/Sources/AppCoordinator.swift`** — Added:
- `onboardingCompleted: Bool` (stored var, initialized from `UserDefaults` at launch)
- `completeOnboarding()` — sets `onboardingCompleted = true` and writes `backshelf.onboarding.completed` to UserDefaults

**`App/Sources/Views/OnboardingView.swift`** (NEW) — Three-panel sheet:
- Panel 0 ("Meet Backshelf"): what the app does
- Panel 1 ("We never delete anything"): the safety / trust message
- Panel 2 ("Grant access to get started"): "Grant Access to /opt/homebrew" (or `/usr/local` on Intel via `#if arch(arm64)`) + "Skip for Now"
- Page dots (3 circles, accent-colored for current page)
- "Skip" button always visible (top-right corner) — sets flag and dismisses
- "Next" button (pages 0–1, `keyboardShortcut(.defaultAction)`) → "Get Started" controls on page 2
- Flag is set on completion OR skip (per spec)

**`App/Sources/Views/RootView.swift`** — Sheet presented when `!coordinator.onboardingCompleted`. The sheet's `set:` binding is a no-op (`{ _ in }`) because dismissal is always driven by the `complete()` / Skip actions that write UserDefaults, not by swipe-to-dismiss.

## Decisions

1. **Toggled cleanup mode.** See Task D above.

2. **Snapshots load asynchronously.** `SnapshotManager` is an `actor`; its methods cannot be called synchronously from `AppCoordinator.init()`. Snapshots are loaded in `autoScanIfNeeded()` (and after any capture or refresh), so the sidebar section starts empty and populates quickly. This matches how packages already behave on cold launch.

3. **`.snapshot` excluded from UserDefaults persistence.** `persistUIPreferences()` returns early when `sidebarSelection` is `.snapshot(_)`. On next launch, the selection falls through to the `.all` default. A snapshot UUID from a deleted snapshot must not be persisted and re-presented.

4. **`SnapshotReason.preCleanup` added to library.** The existing `.preUninstall` did not match `safety.md`'s requirement. Adding `.preCleanup` keeps the enum honest and is backward-compatible (new `rawValue = "preCleanup"`; old snapshots decode without issue).

5. **`UTType(filenameExtension: "sh")` instead of `UTType.shellScript`.** `UTType.shellScript` is not guaranteed on macOS 13. The dynamic initializer returns `nil` gracefully (panel shows without content type restriction) vs. a crash.

6. **`SnapshotContentView` uses `SnapshotPackage` directly.** Per the task spec: no ghost `Package` objects synthesized. The view has its own `SnapshotPackageRowView` that reuses `ManagerBadge` but renders from `SnapshotPackage` fields only.

## Limitations

- No "Export as reinstall script" from snapshot view (Phase 5d scope per `safety.md`).
- No snapshot deletion UI (Phase 5d scope).
- Snapshot `note` field is unused in the UI (no manual note entry).
- Cleanup mode exits automatically when "Done" is tapped; it does NOT exit automatically when the sidebar selection changes to a snapshot. The coordinator could add an observer for this, but it's harmless: cleanup mode toolbar items simply don't appear in `SnapshotContentView`.
- `safetyReminder` in `CleanupScriptSheetView` uses markdown bold syntax (`**...**`) in a `Text` view — requires iOS 15+ / macOS 12+, which is met by the macOS 14.0 deployment target.

---

# Phase 5c-1 Handoff (2026-05-16)

## Status

Phase 5c-1 is implementation-complete.

Tasks A, B, G, F are built and all 272 library tests pass with zero warnings. Tasks C, D, E (snapshots UI, cleanup wizard, onboarding) are in Phase 5c-2, pending hardware verification of this batch.

## What Was Built

### Task A — NpmScanner symlink dedup

**`Backshelf/Sources/BackshelfCore/Scanners/NpmScanner.swift`**

Three-layer fix matching the pip/BrewScanner dedup pattern:

1. **`nodeModulesDirs()` version directory sort** — nvm and Volta version dirs are now sorted by path (`$0.path < $1.path`) before being appended. This guarantees deterministic candidate ordering across runs, so the first candidate's pre-resolution URL is stable (important for snapshot diff stability).

2. **`deduplicatedNodeModulesDirs()`** — new private method wrapping `nodeModulesDirs()`. Resolves each candidate dir's symlinks via `DirectoryAccessProvider.resolvingSymlinks(at:)` and skips any whose resolved path has already been seen. First candidate's pre-resolution URL is preserved as the Package qualifier (stable IDs).

3. **`packagesIn()` entry dedup** — for each entry (and scoped-package child) inside a node_modules directory, resolves symlinks and tracks resolved paths in a `Set<String>`. Skips entries that resolve to the same physical directory as a previously-seen entry.

4. **`scan()` defensive dedup** — final `[Package]` is filtered through a `seen: Set<String>` on `Package.id` to catch any residual duplicates not caught by layers 1–3.

**Tests added to `NpmScannerTests.swift`:** `symlinkedNodeModulesDirDeduplicatesPackages`, `symlinkedEntryWithinNodeModulesIsDeduped`, `nvmVersionDirsAreSorted`.

**`InMemoryDirectoryAccessProvider.swift` updated:** `resolvingSymlinks(at:)` now does component-by-component symlink resolution, matching real `FileManager` behaviour. `contentsOfDirectory`, `data(contentsOf:)`, and `modificationDate(at:)` all call `resolvingSymlinks` first so intermediate directory symlinks are followed correctly. All 272 existing tests pass; no regressions.

### Task B — Database persistence via ScanRun + PackageDAO

**New: `Backshelf/Sources/BackshelfCore/Persistence/PackageDAO.swift`**

`public struct PackageDAO: Sendable` — thin wrapper over `Package`'s existing `FetchableRecord`/`PersistableRecord` conformances. Two methods:
- `loadAll() throws -> [Package]` — reads the full `packages` table
- `replaceAll(with:) throws` — deletes all rows then inserts the new set in one transaction. `ON DELETE CASCADE` also clears `provenance_evidence`; acceptable in 5c since provenance is not collected at scan time.

No new migration needed — the `packages` table (v1_initial) is complete and `Package` already had full GRDB conformances.

**New: `Backshelf/Sources/BackshelfCore/Persistence/ScanRunDAO.swift`**

`public struct ScanRunDAO: Sendable` — thin wrapper over `ScanRun`'s existing GRDB conformances. Two methods:
- `save(_ scanRun: ScanRun) throws` — inserts a new row (diagnostic log; rows are not pruned)
- `mostRecentCompletedAt() throws -> Date?` — raw SQL query, returns the `completed_at` of the most recent `scan_runs` row ordered by `started_at DESC`

**`AppCoordinator.swift` updated:**
- Holds `private var packageDAO: PackageDAO?` and `private var scanRunDAO: ScanRunDAO?`, both non-nil when `database != nil`
- `init()` loads cached packages synchronously from `packageDAO.loadAll()` and `lastScanCompletedAt` from `scanRunDAO.mostRecentCompletedAt()` — UI populates instantly before the background re-scan completes
- `scan()` records `scanStartedAt = Date()` at entry, then after the scan loop: calls `packageDAO.replaceAll(with: packages)` and saves a `ScanRun` record. Both calls use `try?` — errors are swallowed; the worst case is no persistence (next launch is an empty list, auto-scan recovers)
- New `lastScanSummary: String?` computed property uses `RelativeDateTimeFormatter` ("Last scanned 2 hours ago"); nil when no scan has completed

**Tests added to `PackageDAOTests.swift`:** `loadAllEmpty`, `replaceAllAndLoadAll`, `replaceAllClearsPreviousPackages`, `replaceAllWithEmptyListClearsTable`, `mostRecentCompletedAtEmpty`, `saveThenMostRecent`, `mostRecentAmongMultiple`.

### Task G — Stale-bookmark prompt UI

**`App/Sources/Views/SidebarView.swift`**

In `directoryAccessSection`, stale paths from `coordinator.folderAccess.staleBookmarkPaths` are now rendered above the active grants. Each stale row shows:
- The directory's `lastPathComponent`
- Orange caption "Access lost — directory moved or revoked"
- A "Re-grant" button that calls `coordinator.grantDirectory(suggestedPath: path)`

All stale rows are `.selectionDisabled()`. The empty-state text ("No directories granted") is now suppressed if there are stale entries to show.

### Task F — Inline scan status per manager in sidebar

**`App/Sources/Views/SidebarView.swift`**

**Visibility fix (critical):** A `.failed` or `.timedOut` scanner status no longer hides the manager row even when N=0. Previously, a failed npm scan would yield 0 packages AND a hidden row — the user would never see the failure. Now:
- Row shown when N > 0 (normal case)
- Row shown when status is `.failed` or `.timedOut` (error surfacing, regardless of N)
- Row hidden when `.succeeded(count: 0)` or `.skipped` or status is nil with 0 packages

**Status badge:** A `managerStatusBadge(manager:)` helper returns an orange `exclamationmark.triangle.fill` icon with a `.help()` tooltip showing the failure reason or "Scan timed out". The badge appears trailing inside the label's text slot (using `Label { HStack } icon: { Image }` pattern). Clean states show nothing.

**Limitation:** Per-manager in-progress spinners are not implemented. The global toolbar spinner covers "scan in progress." Adding per-manager spinners requires keeping rows visible during the rescan (which requires not clearing `packages` at scan start, a larger refactor). This is noted for 5c-2 or later.

**Bottom bar update:** `lastScanSummary` (from AppCoordinator) is shown as a tertiary caption below `statusSummary` when a scan has completed.

## Decisions

1. **ScanRun as the persistence medium for last-scan timestamp.** Not UserDefaults. `scan_runs` table was built for this (Phase 2d) and has been sitting unused. `ScanRunDAO.mostRecentCompletedAt()` uses direct SQL to avoid exposing GRDB types to the app layer.

2. **Struct DAOs, not actors.** `PackageDAO` and `ScanRunDAO` are `struct: Sendable` (not actors). `DatabasePool` is already thread-safe internally; the DAOs have no mutable state. `init()` can call them synchronously without an async hop.

3. **`InMemoryDirectoryAccessProvider` component-by-component symlink resolution.** Required to correctly simulate intermediate directory symlinks. Updated `contentsOfDirectory`, `data(contentsOf:)`, and `modificationDate(at:)` all call `resolvingSymlinks` first. Zero test regressions.

4. **Package ID uses pre-resolution path as qualifier.** `deduplicatedNodeModulesDirs()` keeps the first (pre-resolution) URL when it deduplicates. This means IDs are stable across runs even if underlying symlink targets change.

5. **`visibleManagers` visibility rule.** `.failed`/`.timedOut` → visible. `.succeeded(count: 0)` → hidden. `.skipped` → hidden. Nil status with 0 packages → hidden (never scanned, or not a known manager for the current scanners).

## Limitations

- Per-manager in-progress spinners not implemented (global toolbar spinner covers this).
- `packageDAO.replaceAll` cascades to `provenance_evidence` — all provenance is cleared on each scan. Acceptable in 5c; provenance collection is not wired in the app layer yet (Phase 5d).
- `scan_runs` rows accumulate and are not pruned. Disk impact negligible; worth pruning in 5d if desired.
- No optimistic UI during rescan: the package list goes empty then refills as managers complete. A future improvement would keep stale packages visible during rescan.

---

> **Next:** Phase 5c-2 (Tasks C, D, E — Snapshots UI, Cleanup Wizard, Onboarding). Start with a fresh `/goal` after hardware verification of this batch.

---

> **Renamed Cruft → Backshelf on 2026-05-15.** The SPM package directory, library target, and all source/doc references have been updated. The git root directory rename is handled separately by the maintainer.

---

# 🛑 RESUME HERE (paused 2026-05-15 evening)

## Where we are

Phase 5b is **implementation-complete and verified working on hardware**. The three-pane inventory UI works end-to-end: NavigationSplitView shell, sidebar filtering (manager/all/read-only), search, sort, detail pane with structured fields + Reveal in Finder + raw JSON disclosure, auto-scan on launch, manual refresh. 262 library tests pass.

Three bugs surfaced and were fixed during 5b verification:
1. Sidebar selection didn't filter — fixed via `NavigationLink(value:)` pattern + `.selectionDisabled()` on directory rows
2. Brew duplicate-version IDs — fixed via `pickLatest` deduplication in `BrewScanner.packagesIn`
3. Pip duplicate-interpreter IDs — fixed via symlink resolution in `PythonInterpreterDiscovery.discover()` + defensive dedup in `PipScanner.scan()`

## Pending immediate actions (do these first when resuming)

**1. Remove the debug overlay from `PackageListView.swift`.**

Lines 11–15 contain a temporary debug Text marked `// TODO: remove after Phase 5b verified`. Open the file and delete:

```swift
// TODO: remove after Phase 5b verified
Text("DEBUG: sidebarSelection = \(String(describing: coordinator.sidebarSelection))")
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
```

The surrounding `VStack(spacing: 0) {` wrapper that was added to host the debug overlay can also be flattened — without the debug Text, the `Group { ... }` no longer needs to be inside a VStack. Either flatten it (cleaner) or leave the empty VStack in place (harmless).

**2. Rebuild and verify the debug text is gone.**

```bash
cd /Users/willy/Desktop/Projects/Backshelf
./scripts/regenerate-xcode.sh
# In Xcode: Cmd+Shift+K (Clean Build Folder), then Cmd+R
```

Confirm the app launches, the sidebar still filters correctly (click Homebrew → list filters to ~110, click All packages → back to 193), and the debug line at the top of the middle pane is gone.

**3. Take a final screenshot of working sidebar filter** for the project record.

**4. Commit and tag.**

```bash
git add -A
git commit -m "Phase 5b verified: sidebar filtering, pip+brew dedup, NavigationLink pattern, debug overlay removed"
git tag phase-5b-verified
```

After this, Phase 5b is officially closed.

## Phase 5c plan (design approved this session)

Five design questions were discussed; the maintainer approved all five proposals:

1. **Snapshot UI placement.** Sidebar section called "Snapshots" below "Directory Access". Chronologically listed entries ("Yesterday at 3:42 PM — pre-cleanup", "Last week — manual capture"). Clicking one switches middle/detail panes into snapshot-viewer mode showing the inventory at that point in time. Same window, no modals. Mail.app pattern.

2. **Snapshot capture trigger.** Both automatic and manual. Auto-capture fires before any cleanup script generation (per `files/safety.md` Rule 1). Plus a "Snapshot now" button in the toolbar near Refresh, for users who want a savepoint before doing manual brew/pip activity.

3. **Cleanup wizard flow.** Single-pane with sheet (not multi-step). Add checkboxes to each package row in the existing list. Toolbar button "Generate cleanup script (N selected)" enables when ≥1 selected. Click it → sheet appears with the generated bash script preview, "Copy to Clipboard" and "Save as .sh" buttons. One modal layer; matches macOS Finder's "select files → action" idiom.

4. **Onboarding.** Light-touch. First-launch sheet with three short panels:
   - "Backshelf shows what's installed on your Mac and helps you clean it up."
   - "We never delete anything. We generate scripts. You run them in Terminal when you're ready."
   - "Grant access to /opt/homebrew to get started" with a single grant button that triggers the standard NSOpenPanel.
   Total time ~10 seconds. Not a multi-step tutorial.

5. **Descriptions corpus.** Defer to Phase 5d. 5c stays focused on action surfaces (snapshots, cleanup wizard) and the first-time surface (onboarding). The detail pane will continue to show "No description available" until 5d.

## Open issues to address in 5c

- **`NpmScanner` likely has the same dedup vulnerability as `PipScanner`.** The path `/opt/homebrew/lib/node_modules/` resolves via symlinks to `Cellar/node/<version>/lib/node_modules/`. Both could appear as candidates and emit duplicate `Package` records with identical IDs. Fix preemptively at the start of 5c using the same resolve-symlinks-then-dedup pattern from `PythonInterpreterDiscovery`. Flagged in the pip dedup HANDOFF section below.

- **Doc-layout drift: `files/` should be `docs/`.** `CLAUDE.md` references `docs/...` paths but docs actually live in `files/...`. Known limitation noted in the Phase 2a HANDOFF. Separate cleanup pass, not 5c scope, but worth doing soon before more documents are added.

- **Database persistence not wired.** Scanned packages are in-memory only. App restart clears the list. Phase 5c should add `scan → persist packages → read on startup` so the inventory survives restarts. `AppCoordinator.database` is already initialized in Application Support and waiting.

- **No inline per-manager scan status in sidebar.** `AppCoordinator.scanStatuses: [PackageManager: ScannerStatus]` is populated by every scan but never displayed. The `files/ui.md` spec calls for per-manager rows showing "Can't see your Homebrew folder…" or "Scanning…" inline. Surface in 5c.

- **No stale-bookmark prompt UI.** `FolderAccessManager.staleBookmarkPaths` is populated on launch but never displayed. If a granted directory was moved/renamed/deleted, the user sees nothing — they just see fewer packages than expected. Phase 5c should add a "Re-grant" prompt in the sidebar's Directory Access section.

- **`isExplicit` always true for pip and npm.** Neither has an `installed_on_request` equivalent. Documented limitation. A two-pass dep-tagging approach would help but is fragile (a package can be both a user install and a dep). Defer.

- **`pip` (manager, name) qualifier collision in provenance matching.** Two pip packages with the same name in different interpreters collapse to one `PackageKey` in `ProvenanceCollector`. First match wins. Documented as Phase 4-followup. Not 5c scope.

- **`DetachedSignatures` SQLite warning in Xcode console.** `os_unix.c:51044: (2) open(/private/var/db/DetachedSignatures) - No such file or directory`. Harmless — SQLite tries to read a macOS code-signing database that's not exposed in the sandbox. Happens to every sandboxed Mac app using SQLite. Ignore. Can be silenced via GRDB verbose-logging config in a later phase if desired.

## Phase 5c /goal prompt skeleton

When ready to start 5c, the prompt should cover:

```
You are Claude Code on the Backshelf repo. Phase 5b is verified and closed.
This is Phase 5c — snapshots UI, cleanup wizard, onboarding flow, plus a
preemptive NpmScanner dedup fix.

## Read first
  1. CLAUDE.md
  2. HANDOFF.md (start at "RESUME HERE" — that's the latest state)
  3. files/safety.md (snapshot rules + cleanup script contract)
  4. files/ui.md (UI design intent)
  5. files/ROADMAP.md (Phase 5c section)
  6. App/Sources/AppCoordinator.swift
  7. Sources/BackshelfCore/Snapshots/SnapshotManager.swift
  8. Sources/BackshelfCore/Cleanup/ScriptGenerator.swift
  9. Sources/BackshelfCore/Scanners/NpmScanner.swift

## Tasks
  A. NpmScanner dedup (preemptive). Apply resolve-symlinks + dedup pattern
     from PythonInterpreterDiscovery to NpmScanner's node_modules walking.
     Tests for symlinked /opt/homebrew/lib/node_modules.

  B. Database persistence. After each scan, write packages to GRDB via a
     new PackageDAO. On startup, load last scan from DB so the inventory
     populates instantly without re-scanning. Re-scan in background.

  C. Snapshots UI. New sidebar section "Snapshots" with chronological
     entries. Click → switches middle/detail panes into snapshot-viewer
     mode. Toolbar "Snapshot now" button. Auto-capture before cleanup.

  D. Cleanup wizard. Checkboxes on package rows; toolbar button
     "Generate cleanup script (N selected)"; sheet with script preview +
     Copy + Save as .sh buttons.

  E. Onboarding. First-launch three-panel sheet. Skippable, ~10 seconds.

  F. Inline scan-status per manager in sidebar (surface scanStatuses).

  G. Stale-bookmark prompt UI in Directory Access section.

## Constraints
  - No descriptions corpus (5d).
  - No provenance UI (5d).
  - No App Store Connect work (5d).
  - swift build + swift test pass; library changes minimal.

## Stop after 120 turns.
```

Scope is meaty (7 sub-tasks; cleanup wizard alone is real work). Probably 100-120 agent turns. Consider splitting 5c into 5c-1 (A+B+G — plumbing) and 5c-2 (C+D+E+F — UI surfaces) if a single /goal feels too long.

## Tag history

- `phase-5a-verified` — sandboxed app shell + working scan UI verified on hardware (110 brew + 78 pip + 5 npm packages on the maintainer's M-class MacBook Pro).
- `phase-5b-verified` — **pending step 4 above**.
- Future: `phase-5c-verified` after snapshots + cleanup + onboarding land.

## Test count history

| Phase | Tests | Delta |
|---|---|---|
| Phase 0 (foundation) | 44 | — |
| Phase 1 (BrewScanner) | 65 | +21 |
| Phase 2a (Python discovery) | 82 | +17 |
| Phase 2b (PipScanner) | 99 | +17 |
| Phase 2c (NpmScanner) | 107 | +8 |
| Phase 2d (Timeout + SnapshotManager + ScanCoordinator) | 122 | +15 |
| Phase 3a (Denylist + ScriptGenerator) | 157 | +35 |
| Phase 4a (Shell history) | 205 | +48 |
| Phase 4b (Claude Code logs) | 221 | +16 |
| Phase 4c (Provenance integration) | 248 | +27 |
| Phase 5a (App shell) | 248 | 0 (library unchanged) |
| Phase 5b (inventory UI) | 248 | 0 (library unchanged) |
| Phase 5b sidebar fix | 256 | +8 (PackageFilterTests) |
| Phase 5b brew dedup | 260 | +4 (BrewScanner version-pick tests) |
| Phase 5b pip dedup | 262 | +2 (symlinked-interpreter dedup tests) |

## Remaining roadmap after 5b verified

- **Phase 5c.** Snapshots UI + cleanup wizard + onboarding + NpmScanner dedup + DB persistence + inline scan status + stale-bookmark UI. (See /goal skeleton above.)
- **Phase 5d.** Descriptions corpus generator (`scripts/generate-descriptions/`) + provenance UI surfacing (the existing `NarrativeRenderer` finally gets a home in the detail pane) + App Store Connect setup + TestFlight + submission. **Last phase before public release.**

## Repo state at pause

Most recent commits (newest first) — **verify via `git log --oneline -10` on resume; some recent agent-run commits may or may not have actually landed**:
- `pip dedup fix: symlink resolution in PythonInterpreterDiscovery + defensive Package.id dedup in PipScanner`
- `brew dedup fix: pickLatest in BrewScanner.packagesIn, version-string comparison + mtime fallback`
- `Phase 5b sidebar fix: SidebarSelection moved to BackshelfCore, .selectionDisabled() on directory rows, NavigationLink pattern`
- `Phase 5b: three-pane inventory UI (NavigationSplitView shell, sidebar filtering, search, sort, detail pane)`
- `Phase 5a: XcodeGen + app shell + working scan UI`
- `Renamed Cruft → Backshelf (single commit, three-pass sed, git mv with blame preserved)`

`Backshelf.xcodeproj/` is gitignored as designed; regenerate via `./scripts/regenerate-xcode.sh`.

---

# Phase 5b Bug Fix: pip Duplicate-ID Warnings from Symlinked Interpreters (2026-05-15)

> Note: originally labeled "Phase 5c Bug Fix" in the agent debrief because it preceded 5c work; relabeled here as Phase 5b since it's part of the 5b verification sequence.

## What Was Wrong

`PythonInterpreterDiscovery` discovered the same physical Python interpreter via multiple filesystem paths. For example, `/opt/homebrew/opt/python@3.13/bin/python3.13` (an `opt/` symlink) and `/opt/homebrew/Cellar/python@3.13/3.13.2/bin/python3.13` (the canonical Cellar binary) both appeared as candidates from `homebrewOptCandidates` and `homebrewCellarCandidates`. The existing deduplication in `discover()` compared the literal path strings, so both passed through. Both shared the same site-packages directory, causing `PipScanner` to emit identical `Package` records twice and SwiftUI `ForEach` to log:

```
ForEach<...>: the ID pip:/opt/homebrew/bin/python3.13:pip occurs multiple times within the collection...
```

This is the second instance of the duplicate-ID bug class (first was BrewScanner / Phase 5b).

## What Was Fixed

**Two-layer fix:**

**Layer 1 (root fix) — `PythonInterpreterDiscovery.discover()`** (`Foundation/PythonInterpreterDiscovery.swift`):
- After confirming a candidate exists, calls `directoryAccess.resolvingSymlinks(at: candidate.executable)` to obtain the canonical path.
- The `seen` set now tracks resolved (symlink-resolved) paths instead of literal paths. The first candidate whose resolved path is unseen is kept; all subsequent candidates resolving to the same physical binary are dropped.
- The first candidate wins, preserving its `kind` and `versionHint` metadata (opt path before Cellar path in iteration order).

**Layer 2 (belt-and-suspenders) — `PipScanner.scan()`** (`Scanners/PipScanner.swift`):
- The flat-mapped `[Package]` result is filtered through a `seen: Set<String>` on `Package.id` before returning.
- Guards against future scenarios (e.g. two different interpreters sharing a site-packages via symlinks) where Layer 1 wouldn't catch the duplication.

**`DirectoryAccessProvider`** (`Foundation/DirectoryAccessProvider.swift`):
- Added `func resolvingSymlinks(at: URL) -> URL` as a protocol requirement with a default extension that calls `URL.resolvingSymlinksInPath()`.
- `SystemDirectoryAccessProvider` inherits the default (real filesystem resolution).

**`InMemoryDirectoryAccessProvider`** (`Tests/BackshelfCoreTests/Support/InMemoryDirectoryAccessProvider.swift`):
- Added `symlinks: [String: String]` dictionary.
- `Builder.addSymlink(at:target:)` registers a symlink in the fake filesystem (also registers the path in the parent directory's contents).
- `resolvingSymlinks(at:)` follows the symlinks dict (cycle-safe), never touching the real filesystem.
- `fileExists(at:)` now resolves symlinks before checking contents/fileData, so symlinked paths report existence correctly.

## Tests Added

**`PythonInterpreterDiscoveryTests.swift`** — `deduplicatesSymlinkedInterpreters`:
- Registers the Cellar binary as a file and the opt path as a symlink pointing to it.
- Asserts `discover()` returns exactly one interpreter (the opt candidate, which is processed first).
- Would have returned 2 before the Layer 1 fix.

**`PipScannerTests.swift`** — `symlinkedInterpreterEmitsUniqueIds`:
- Same symlink scenario with a pip dist-info in the opt site-packages.
- Asserts `scan()` returns exactly one `Package` with no duplicate IDs.
- Exercises the full Layer 1 → Layer 2 pipeline.

## Open Issue: NpmScanner

`NpmScanner` almost certainly has the same vulnerability. `/opt/homebrew/lib/node_modules/` contents are symlinks whose targets live in `Cellar/node/...`. Both paths could appear as candidates. **Fix in a separate goal before shipping npm scanning.**

## Result

262 tests pass, zero warnings, Swift 6 strict concurrency. The `ForEach` duplicate-ID warnings for pip are eliminated.

---

# Phase 5b Bug Fix: Duplicate IDs Corrupting Sidebar Selection (2026-05-15)

## What Was Wrong

`BrewScanner` emitted one `Package` record per version directory found in `Cellar/<formula>/` and `Caskroom/<cask>/`. When Homebrew retains multiple keg versions (e.g. `python@3.13/3.13.0/` and `python@3.13/3.13.1/`), both produced a `Package` with id `"brew::python@3.13"`. SwiftUI `ForEach` logged:

```
ForEach<...>: the ID brew::python@3.13 occurs multiple times within the collection...
```

Duplicate IDs corrupt SwiftUI's `List(selection:)` hit-test model: clicking "Homebrew" in the sidebar bound the selection but the `ForEach` could not resolve a unique row, so `filteredPackages` never updated. This was flagged as a known limitation in the original Phase 1 `HANDOFF.md` entry ("duplicate versions in Cellar not yet handled").

## What Was Fixed

**`BrewScanner.packagesIn`** (`Scanners/BrewScanner.swift`) — instead of emitting one `Package` per version directory, the scanner now collects all `(versionDir, receipt)` candidates for each formula name and calls `pickLatest` to select exactly one.

- **`pickLatest`** — folds over candidates, comparing version strings with `compareVersionStrings`. The winning candidate is the one with the highest version.
- **`compareVersionStrings`** — splits on `.` and compares components numerically. Returns `nil` when a differing component is non-numeric (e.g. `1.0.0-alpha` vs `1.0.0-beta`).
- **mtime fallback** — when `compareVersionStrings` returns `nil`, `pickLatest` compares `INSTALL_RECEIPT.json` modification dates via `DirectoryAccessProvider.modificationDate(at:)` and picks the newer file.

The same deduplication applies to `Caskroom` via the shared `packagesIn` path.

**`InMemoryDirectoryAccessProvider`** (`Tests/BackshelfCoreTests/Support/InMemoryDirectoryAccessProvider.swift`) — `modificationDate(at:)` now returns stored dates instead of always returning `nil`. `Builder.addFile(at:data:modificationDate:)` accepts an optional `Date` parameter so tests can set per-file mtimes.

## Tests Added / Updated

File: `Backshelf/Tests/BackshelfCoreTests/BrewScannerTests.swift`

- **Updated** `vscodeCask` — fixture now has two VS Code versions (`1.90.2`, `1.91.0`); test updated to expect `1.91.0` and `time: 1720000000`.
- **Added** `twoVersionsFormulaPicksLatest` — inline provider, formula with `1.0.0` and `1.0.1` → expects version `1.0.1`.
- **Added** `threeVersionsFormulaPicksHighest` — inline provider, formula with `2.0.0`, `2.1.0`, `2.0.9` → expects `2.1.0`.
- **Added** `ambiguousVersionFallsBackToMtime` — inline provider, formula with `1.0.0-alpha` (older mtime) and `1.0.0-beta` (newer mtime) → expects `1.0.0-beta`.
- **Added** `caskTwoVersionsPicksLatest` — inline provider, cask with `1.0.0` and `1.1.0` → expects `1.1.0`, manager `.brewCask`.

Fixtures added:
- `Cellar/python@3.12/3.12.5/INSTALL_RECEIPT.json` (same 4 deps as `3.12.4`; time `1710000000`)
- `Caskroom/visual-studio-code/1.91.0/INSTALL_RECEIPT.json` (same artifact paths; time `1720000000`)

All 260 tests pass, zero warnings, Swift 6 strict concurrency.

## Result

The `ForEach` duplicate-ID warnings are eliminated. Sidebar selection now correctly filters the package list when clicking "Homebrew", "pip", "npm", or "All packages".

---

# Phase 5b Bug Fix: Sidebar Selection Not Filtering (2026-05-15)

## What Was Wrong

Clicking "Homebrew", "pip", "npm", or "All packages" in the sidebar produced no visible change in the package list.

**Root cause — Hypothesis A (confirmed):** `SidebarView.directoryAccessSection` renders rows with no `.tag()` modifier and no `.selectionDisabled()` modifier. In macOS SwiftUI, a `List(selection:)` that mixes tagged (selectable) and untagged rows has undefined selection behavior — the untagged rows corrupt the hit-test model for the entire list, preventing tagged rows from updating the binding when clicked.

**Hypothesis B (false):** `AppCoordinator.filteredPackages` was already correctly filtering on `sidebarSelection` at lines 47–54. No logic was missing.

## What Was Fixed

1. **`SidebarView.directoryAccessSection`** — added `.selectionDisabled()` to the "No directories granted" text and to each `VStack` row in the `ForEach(granted)` loop.

2. **`SidebarSelection` moved to `BackshelfCore`** — the enum and its `userDefaultsKey`/`init?(userDefaultsKey:)` codec are now in `Backshelf/Sources/BackshelfCore/Models/SidebarSelection.swift` (public). This puts the type alongside `Package` and `PackageManager` where it belongs, and makes it testable via `swift test`.

3. **`[Package].filtered(by:query:)` added to `BackshelfCore`** — the selection filter + search query logic is now a public extension on `[Package]` in the same file as `SidebarSelection`. `AppCoordinator.filteredPackages` delegates to it: `packages.filtered(by: sidebarSelection, query: searchQuery).sorted(by: sortOrder)`.

4. **`App/Sources/Models/SidebarSelection.swift`** — cleared (stub comment only; the type now comes from `BackshelfCore`).

> **Follow-up applied in a later commit:** Tags on `Label(...).tag(...)` were converted to `NavigationLink(value:)` pattern after `.selectionDisabled()` alone proved insufficient to make selection visible/functional on macOS 14+. The canonical macOS sidebar selection pattern requires `NavigationLink(value:)` for `List(selection:)` to wire up properly.

## Tests Added

`Backshelf/Tests/BackshelfCoreTests/PackageFilterTests.swift` — 8 tests covering all four sidebar selection cases against a synthetic `[Package]` array: `.all`, `.manager(.brew)`, `.manager(.pip)`, `.readOnly`, nil, query narrowing within a manager filter, case-insensitive query, and empty query. All 256 tests pass, zero warnings.

---

# Phase 5b Handoff

## What Was Built

Phase 5b replaces the placeholder `ContentView` with a full three-pane inventory UI built on `NavigationSplitView`. `swift build` and `swift test` still pass (248 tests, zero warnings, library unchanged). The app shell is App-layer only — no changes to `Sources/BackshelfCore/`.

```
App/Sources/
├── AppCoordinator.swift        CHANGED: per-dir grant model, UI state, autoScan, refresh, filteredPackages
├── BackshelfApp.swift          CHANGED: removed .windowResizability(.contentSize)
├── ContentView.swift           CHANGED: thin typealias shim → RootView
├── FolderAccessManager.swift   CHANGED: added grantedPaths: [String]
├── Extensions/
│   └── PackageManager+Display.swift   NEW: displayName, badgeLabel, badgeColor, sidebarSymbol
├── Models/
│   ├── CanonicalDirectory.swift   NEW: recommended dirs with manager list + arch detection
│   ├── GrantedDirectory.swift     NEW: bookmarked dir with display helpers
│   ├── SidebarSelection.swift     NEW: enum .all / .manager(m) / .readOnly + UserDefaults codec
│   └── SortOrder.swift            NEW: PackageSortOrder enum + [Package].sorted(by:) extension
└── Views/
    ├── DirectoryGrantsView.swift  NEW: menu content for ugranted canonical dirs
    ├── ManagerBadge.swift         NEW: colored capsule badge for each PackageManager
    ├── PackageDetailView.swift    NEW: header + LabeledContent fields + raw JSON disclosure
    ├── PackageListView.swift      NEW: search + sort + lazy list + empty states
    ├── RootView.swift             NEW: NavigationSplitView shell + toolbar refresh button
    └── SidebarView.swift          NEW: manager filters + directory list + grant buttons
```

## Phase 5b Decisions

### 1. `project.yml` was not modified

`App/Sources` is a recursive source path in XcodeGen — adding explicit subdirectory paths would cause duplicate file errors. No YAML change is needed; XcodeGen already picks up all files under `App/Sources/**/*.swift`.

### 2. Per-directory grant model: `GrantedDirectory` + `CanonicalDirectory`

`FolderAccessManager` was already per-directory (bookmarks keyed by path). The Phase 5b refactor adds:
- `GrantedDirectory` — wraps a path+bookmark and computes `managersUnlocked` label from path pattern
- `CanonicalDirectory` — recommended dirs with manager lists; filtered to show only Apple Silicon or Intel brew root via compile-time `#if arch(arm64)` check
- `AppCoordinator.grantedDirectories: [GrantedDirectory]` and `ungrantedCanonicalDirectories: [CanonicalDirectory]` as computed properties

### 3. Sidebar selection via `SidebarSelection?` and `NavigationLink(value:)`

`AppCoordinator.sidebarSelection: SidebarSelection?` (optional). `nil` and `.all` both mean "no filter" in `filteredPackages`. Sidebar rows are now `NavigationLink(value: SidebarSelection.X) { Label(...) }` per the canonical macOS 14+ sidebar pattern (revised from initial `Label(...).tag(...)` during 5b verification — see bug-fix entries above). Default is `.some(.all)` so the "All packages" row starts selected.

### 4. `selectedPackage` binding in `PackageListView`

`List` selection is bound to `coordinator.selectedPackage?.id` (a `String?` mapping through `Package.id`). On set, the view looks up the package in `coordinator.packages` by ID.

### 5. `autoScanIfNeeded` fires from `.task` on `RootView`

On every fresh window appearance, `.task { await coordinator.autoScanIfNeeded() }` runs. The method no-ops if no directories are granted. Idiomatic SwiftUI; avoids init-side-effect issues with `@Observable`.

### 6. UI preferences persisted via explicit `persistUIPreferences()` calls

`sortOrder` and `sidebarSelection` are persisted when they change (via `.onChange` in `PackageListView`). Keys are prefixed `backshelf.ui.` to avoid collision with bookmark keys. Search query is intentionally not persisted.

### 7. Manager badge colors

- brew/brewCask: amber `(0.85, 0.55, 0.05)`
- pip/pipx: blue `(0.20, 0.45, 0.90)`
- npm: red `(0.85, 0.15, 0.15)`
- cargo/gem/mas: distinct earth, magenta, purple

### 8. `scanResults` renamed to `packages`

`AppCoordinator.scanResults` is now `packages`. The old `ContentView.swift` (which read `scanResults`) is replaced by the `typealias ContentView = RootView` shim.

### 9. `.windowResizability(.contentSize)` removed from `BackshelfApp`

The fixed constraint fought `NavigationSplitView`'s own column sizing. Removed; `RootView` enforces a `.frame(minWidth: 900, minHeight: 580)` minimum instead.

## Phase 5b Known Limitations

1. **No database persistence yet.** Scan results are in-memory only. App restart clears the list. Phase 5c adds `scan → persist packages → read on startup`.

2. **No inline scan-status per manager in sidebar.** The `scanStatuses` dictionary exists but isn't shown. The `ui.md` spec calls for per-manager error rows ("Can't see your Homebrew folder…"); deferred to Phase 5c.

3. **Auto-scan after grant not wired.** After granting a new directory, the user must manually press Cmd+R or click Refresh.

4. **Stale-bookmark UI still missing.** `FolderAccessManager.staleBookmarkPaths` is not surfaced anywhere. Phase 5c should add a "Re-grant" prompt in the sidebar.

5. **`installedAt` nil packages sort to bottom** in `recentlyInstalled` order (`.distantPast`). Intentional.

6. **`ManagerBadge` in `PackageDetailView`** imports both `AppKit` (for `NSWorkspace`) and `BackshelfCore`. Intentional for a macOS-only target.

## Questions for Phase 5c (now superseded by RESUME HERE design decisions above)

1. Database persistence.
2. Onboarding flow.
3. Snapshot UI.
4. Stale-bookmark inline UI.
5. Per-manager scan-status in sidebar.
6. Scan persistence for ScanRun records.

---

# Phase 5a Handoff

## What Was Built

Phase 5a wraps the complete `BackshelfCore` library in a sandboxed macOS app shell. `swift build` and `swift test` still pass (248 tests, zero warnings, library unchanged). The Xcode project is generated from `project.yml` via XcodeGen and is not committed.

```
project.yml                              NEW: XcodeGen source of truth
scripts/
└── regenerate-xcode.sh                  NEW: runs xcodegen generate
App/
├── Backshelf.entitlements               NEW: sandbox + read-only + bookmarks
├── Info.plist                           NEW: bundle ID, version, category
├── Sources/
│   ├── BackshelfApp.swift               NEW: @main App entry point
│   ├── AppCoordinator.swift             NEW: @Observable @MainActor owner of DB + scan
│   ├── FolderAccessManager.swift        NEW: NSOpenPanel + security-scoped bookmarks
│   └── ContentView.swift               NEW: three-manager grant UI + scan results
└── Resources/
    └── Assets.xcassets/
        └── AppIcon.appiconset/          NEW: solid-color placeholder (indigo, 10 sizes)
README.md                                NEW: repo entry point + building instructions
.gitignore                               UPDATED: added Backshelf.xcodeproj/, *.xcuserstate
files/build-and-release.md              UPDATED: XcodeGen-as-source-of-truth note prepended
```

## Phase 5a Decisions

1. **XcodeGen as source of truth.** `Backshelf.xcodeproj` is generated from `project.yml` and gitignored.
2. **Local SPM dependency path: `./Backshelf`.** Referenced via XCLocalSwiftPackageReference.
3. **Deployment target: macOS 14.0** for the app; library stays at 13.0.
4. **FolderAccessManager API** — simplified path-keyed bookmark dictionary form for 5a. Revisited in 5b with `GrantedDirectory`.
5. **Security-scoped resource lifetime around scans.** `AppCoordinator.scan()` starts all granted bookmarks before constructing scanners and stops them in a `defer` block.
6. **Scanner construction: zero-arg defaults** — `BrewScanner()`, `PipScanner()`, `NpmScanner()` all work with `SystemDirectoryAccessProvider()`.
7. **AppCoordinator builds a new ScanCoordinator per scan** — no residual state between scans.
8. **No code signing identity in project.yml** — the maintainer sets the team in Xcode UI.
9. **AppIcon: solid indigo placeholder (10 PNGs).** Real design in Phase 5d.

## Phase 5a Known Limitations

1. No folder-access suggestions for Intel Macs (resolved in 5b via CanonicalDirectory).
2. Single bookmark per manager simplification (resolved in 5b via per-directory model).
3. Stale bookmarks silently dropped on launch (still pending 5c).
4. No error surfacing in ContentView (resolved in 5b with empty states).
5. `NSOpenPanel.runModal()` blocks main thread (acceptable; could migrate to `begin(completionHandler:)`).
6. Database opened but not used (still pending 5c).

## Verification result

App launched successfully on the maintainer's Apple Silicon MacBook Pro. Granted `/opt/homebrew`, scan reported:
- Homebrew: 110 packages · 0.1s
- pip: 78 packages across 9 interpreters · 0.2s
- npm: 5 packages · 0.0s

Numbers within order-of-magnitude of ground truth (`brew list --formula | wc -l` = 107; `brew list --cask | wc -l` = 5; `ls /opt/homebrew/lib/node_modules | grep -v ^@ | wc -l` = 1, plus 4 scoped).

Tagged `phase-5a-verified` after manual hardware verification.

---

# Phase 4c Handoff

Phase 4c integrates all three provenance signals into a usable pipeline: `ProvenanceCollector` (matching + confidence scoring), `ProvenanceDAO` (SQLite persistence), and `NarrativeRenderer` (human-readable sentence generation). Also fixes `ClaudeCodeContext.timestamp` from `Date` to `Date?`. `swift build` and `swift test` both pass: 248 tests, zero warnings, Swift 6 strict concurrency.

**Key decisions:**
- `ClaudeCodeContext.timestamp` → `Date?` (epoch fallback was causing spurious 1970 matches)
- `PackageKey: Hashable` for O(1) bucket lookup in matching
- Confidence table: Claude Code → `.high`; shell within 5min → `.high`; shell beyond 5min → `.medium`; fs only → `.low`; no fs mtime → `.unknown`
- FK prerequisite documented, not enforced at runtime (GRDB DatabasePool enables FKs by default)
- `NarrativeRenderer` inspects optionals directly, no `NarrativeInput` enum
- `RelativeDateTimeFormatter` with `.named` style for recent dates, absolute for >14 days old
- `nearbyProjects` always `[]` in v0 (git-walk signal deferred)
- pip `(manager, name)` qualifier collision accepted for v0 (first match wins)

**Known limitations:**
1. pip/npm collision: same name across different interpreters/locations.
2. `nearbyProjects` not implemented.
3. `ProvenanceCollector.collect()` is synchronous.
4. Nil-timestamp records excluded from matching.
5. `installTimeSource` inferred from manager, hardcoded.

27 tests added across `ProvenanceCollectorTests`, `ProvenanceDAOTests`, `NarrativeRendererTests`.

---

# Phase 4b Handoff

Phase 4b adds the Claude Code log provenance signal: walking `~/.claude/projects/`, parsing session JSONL transcripts, and extracting every `Bash` tool_use that contains an install command.

**Key decisions:**
- `ClaudeCodeContext` gains `Equatable` (auto-synthesised).
- `JSONSerialization` instead of `Codable` for JSONL parsing (tolerates schema variations).
- Two-pass parsing: first user message by minimum timestamp, then Bash extraction.
- `projectPath` from `cwd` field (handles ambiguous path reconstruction from directory-name dashes).
- `sessionId` field preferred over filename.
- `ISO8601DateFormatter` created per session call (Sendable concerns).
- `sessions-index.json` decoded loosely.

**Known limitations:**
1. Directory-name fallback lossy (corrupts paths with literal hyphens).
2. `sessionId` vs filename divergence silently resolved.
3. Global `~/.claude/history.jsonl` not parsed.
4. `collect()` synchronous.
5. String-form `content` handled in first pass only.

16 tests added in `ClaudeCodeLogCollectorTests`.

---

# Phase 4a Handoff

Phase 4a adds the shell-history provenance signal: reading zsh, bash, and fish history files and extracting install commands as structured `InstallCommandRecord` values.

**Key decisions:**
- `InstallCommandRecord.timestamp` changed from `Date` to `Date?` (no fake epoch fallbacks).
- `ShellCommand` intermediate struct skipped (direct line → record).
- Token-based matching, not regex.
- `brew reinstall --cask` maps to `.brew` (per spec; technically wrong for casks).
- Fish history line-by-line, not real YAML.
- Bash comment lines don't clear pending timestamp.

**Known limitations:**
1. `pip install -r requirements.txt` produces no records.
2. `brew install --cask` requires `--cask` as third token.
3. Local-file installs (`.whl`, paths) silently skipped.
4. Multi-line zsh entries not handled.
5. `collect()` synchronous.

47 tests added (`InstallCommandDetectorTests` + `ShellHistoryCollectorTests`).

---

# Phase 3a Handoff

Phase 3a adds `Denylist` and `ScriptGenerator` — cleanup script generation.

**Key decisions:**
- `set -euo pipefail` not just `set -e`.
- `echo "→ <command>"` before each active command (escapes `\`, `"`, `` ` ``, `$`).
- Single denylist warning block at the bottom (not interleaved).
- `SnapshotContext` parameter, not `SnapshotManager` dependency.
- Pip sections grouped per interpreter.
- Denylist as hardcoded Swift struct, JSON bundle deferred.
- Kahn's topological sort with cycle detection.
- Canonical manager output order: brew → brewCask → pip → npm → pipx → cargo → gem → mas.

**Known limitations:**
1. No `SnapshotManager` integration at the call site (caller's responsibility).
2. Denylist is hardcoded (no UI for edits).
3. `mas` uninstall is comment-only.
4. Cross-manager dependency edges ignored.
5. Pip `qualifier == nil` falls back to `"python3"`.

35 tests added (14 Denylist + 21 ScriptGenerator).

---

# Phase 2d Handoff

Phase 2d adds `withTimeout`, `SnapshotManager`, and `ScanCoordinator`.

**Key decisions:**
- `withTimeout` drain loop pattern prevents `CancellationError` propagation from `withThrowingTaskGroup`.
- `Task.detached` inside `AsyncStream.init` closure in `ScanCoordinator.scan()` (avoids actor-executor serialization).
- `ScanEvent.scannerStarted` ordering guaranteed per-manager (same task).
- `withTaskGroup` (non-throwing) for `ScanCoordinator`.
- `SnapshotManager` uses GRDB's `Column` API.
- Phase 0 schema already covers snapshots — no new migration needed.
- `durationMs` via wall-clock `Date()`.

**Known limitations:**
1. No default scanner list in `ScanCoordinator`.
2. GRDB operations block actor executor.
3. No `ScanRun` persistence yet.
4. Default timeout map is static.
5. `isAvailable()` not called inside coordinator.

15 tests added (3 Timeout + 6 SnapshotManager + 6 ScanCoordinator).

---

# Phase 2c Handoff

Phase 2c adds `NpmScanner` — walks known global `node_modules` directories.

**Key decisions:**
- `dependencies` sorted for snapshot stability (JSON dict order isn't preserved).
- Missing `version` → skip package (no empty-version fallback).
- `description` not parsed (corpus is separate concern).
- `homeDirectory` injection for nvm/Volta discovery.
- Static dirs always in candidate list; missing dirs silently skipped.

**Known limitations:**
1. Packages without `version` in `package.json` silently dropped.
2. `installedAt` nil in all tests (in-memory provider).
3. `isExplicit` always true for npm.
4. pnpm/bun/yarn not scanned.
5. `nodeModulesDirs()` called twice if both `isAvailable` and `scan` invoked.

8 tests added.

---

# Phase 2b Handoff

Phase 2b adds `PipScanner` — orchestrates `PythonInterpreterDiscovery` and `DistInfoParser` into the `PackageScanner` protocol.

**Key decisions:**
- `DirectoryAccessProvider.modificationDate(at:)` added.
- `DistInfo.requiresDist: [String]` added.
- `Requires-Dist` stripping handles version specs and env markers.
- `isExplicit` always true for pip (no `installed_on_request` equivalent).
- System Python `isReadOnly` tested with custom provider.

**Known limitations:**
1. `isExplicit` always true.
2. `installedAt` nil in tests.
3. `DistInfoParser.parseHeaders` last-value-wins for duplicate keys.
4. Discovery runs twice if both `isAvailable` and `scan` invoked.

12 tests added.

---

# Phase 2a Handoff

Phase 2a adds Python scanner foundations: interpreter discovery and `.dist-info` parsing.

**Key decisions:**
- `DirectoryAccessProvider.fileExists(at:)` added.
- `PythonInterpreter.Kind` includes all documented cases; Phase 2a only fills system/Homebrew/pyenv.
- `PythonVersion` nested under `PythonInterpreter`.
- System Python fixture version fallback is coarse (`3.0.0` if no minor available).
- Parser errors are specific to `DistInfoParser`.

**Doc-layout note:** `CLAUDE.md` references `docs/` paths but docs live in `files/`. Documented as known drift to be fixed in a separate cleanup pass.

**Known limitations:**
1. No `PipScanner` yet.
2. No uv/conda/pipx/project-venv discovery.
3. Python version parsing is simple (no pre-releases or build metadata).
4. Homebrew version may be coarse.
5. RECORD parsing is path-focused.
6. No install-time extraction.
7. `DirectoryAccessProvider` synchronous.

14 tests added (6 PythonInterpreterDiscovery + 8 DistInfoParser).

---

# Phase 1 Handoff

Phase 1 adds `PackageScanner`, `DirectoryAccessProvider`, and `BrewScanner` to `BackshelfCore`, plus GRDB round-trip tests for `ProvenanceEvidence`, `Snapshot`, and `ScanRun`. 65 tests pass.

**Key decisions:**
- `PackageScanner.manager` returns `.brew` for `BrewScanner` (covers both Cellar and Caskroom; emits packages with `.brew` and `.brewCask` manager values).
- `DirectoryAccessProvider` is a protocol with `SystemDirectoryAccessProvider` (production) + `InMemoryDirectoryAccessProvider` (test-only).
- Fixture fake prefix uses `/opt/homebrew` so `PathDiscovery` recognizes it.
- `ScannerError` is module-level, not nested.
- Receipt parsing skips malformed files silently.
- `time` field decoded as `Double` (Unix timestamp), not via `dateDecodingStrategy`.

**Known limitations (some resolved later):**
1. ~~`FolderAccessManager` is absent~~ (added in Phase 5a).
2. `Description` has no GRDB conformances (still pending Phase 5d).
3. `BrewScanner.scan()` performs blocking I/O in async context.
4. ~~`ScanCoordinator` not implemented~~ (added in Phase 2d).
5. ~~Only `BrewScanner` implemented~~ (pip in 2b, npm in 2c).
6. Cask `installPath` points to Caskroom directory, not `.app` bundle.

---

# Phase 0 Handoff

Initial pure Swift Package (`BackshelfCore`) at `Backshelf/`, no Xcode project. 44 tests pass.

Models: `PackageManager`, `Package`, `Confidence`, `ProvenanceEvidence`, `Description`, `Snapshot` (+ `SnapshotReason`, `SnapshotPayload`, `SnapshotPackage`), `ScanRun` (+ `ScannerStatus`).

Foundation: `PathDiscovery` + `ManagerDirectory`.

Persistence: `Database` (DatabasePool wrapper) + `Migrations` (v1_initial schema).
