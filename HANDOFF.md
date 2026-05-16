> **👉 Resuming work? Read `NEXT-SESSION.md` first.** It contains the one-screen "do this now" checklist. This file (HANDOFF.md) is the long-form historical record.
>
> **State correction (2026-05-15 evening pause):** the "implementation-complete and verified working on hardware" line below is slightly ahead of reality. Accurate state is: Phase 5b inventory UI is built; sidebar filtering **was verified working on hardware** by William (he clicked Homebrew → list filtered, screenshot captured); brew dedup fix is in code with tests; pip dedup fix is in code with tests but **the post-fix console-warning verification by William is still pending**; the debug overlay is still in `PackageListView.swift`; final commit + tag are pending. See `NEXT-SESSION.md` for the four-step checklist to close 5b cleanly.

---

> **Renamed Cruft → Backshelf on 2026-05-15.** The SPM package directory, library target, and all source/doc references have been updated. The git root directory rename is handled separately by William.

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

Five design questions were discussed; William approved all five proposals:

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

- `phase-5a-verified` — sandboxed app shell + working scan UI verified on hardware (110 brew + 78 pip + 5 npm packages on William's M-class MacBook Pro).
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

## William's Manual Checklist (run after this phase)

1. `./scripts/regenerate-xcode.sh` from repo root
2. `open Backshelf.xcodeproj`
3. Set Development Team under Signing & Capabilities if prompted
4. ⌘R — app launches
5. If directories were already granted in 5a's UserDefaults: auto-scan fires and the package list populates within ~2 s
6. If no directories granted: "No Access Granted" empty state appears; grant `/opt/homebrew` (or `/usr/local` on Intel) → Cmd+R to scan
7. Sidebar → click "Homebrew (N)" → list filters to brew + cask packages only
8. Click "All packages (N)" → list returns to full set
9. Type in the search field → list filters live
10. Open the Sort menu → switch to "Name (A–Z)" → list re-sorts
11. Click any package row → detail pane shows name, version, badge, install path, dependencies
12. Click "Reveal in Finder" → Finder opens to the install path
13. Click "Show raw record" disclosure → pretty-printed JSON appears, is text-selectable
14. ⌘R → scan re-runs; Refresh button shows spinner while running
15. "Grant Recommended ▾" menu in sidebar bottom bar → lists ungranted canonical dirs
16. "Custom…" button → NSOpenPanel opens to pick any directory

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
8. **No code signing identity in project.yml** — William sets team in Xcode UI.
9. **AppIcon: solid indigo placeholder (10 PNGs).** Real design in Phase 5d.

## Phase 5a Known Limitations

1. No folder-access suggestions for Intel Macs (resolved in 5b via CanonicalDirectory).
2. Single bookmark per manager simplification (resolved in 5b via per-directory model).
3. Stale bookmarks silently dropped on launch (still pending 5c).
4. No error surfacing in ContentView (resolved in 5b with empty states).
5. `NSOpenPanel.runModal()` blocks main thread (acceptable; could migrate to `begin(completionHandler:)`).
6. Database opened but not used (still pending 5c).

## Verification result

App launched successfully on William's Apple Silicon MacBook Pro. Granted `/opt/homebrew`, scan reported:
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
