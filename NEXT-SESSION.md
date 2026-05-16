# Next session — start here

**Paused: 2026-05-15 evening, mid-Phase-5b verification.**

When you come back, read this file first. Total time to resume: ~10 minutes.

---

## What's the state right now?

- **Phase 5b inventory UI** is built and the sidebar filtering bug is fixed in code.
- **Sidebar filter works** on hardware (you verified by clicking Homebrew → list filtered, screenshot captured).
- **Pip duplicate-ID fix** was applied by the agent (262 tests pass) but **you have not yet rebuilt and confirmed the console warnings are gone**.
- **A debug overlay is still in `App/Sources/Views/PackageListView.swift`** (lines 11–15) showing `DEBUG: sidebarSelection = ...` at the top of the middle pane. Needs removing.
- **Several recent fixes may not be committed.** Run `git log --oneline -10` first to see actual state.

---

## Do these four things in order

### 1. Check what's actually committed

```bash
cd /Users/willy/Desktop/Projects/Backshelf
git log --oneline -10
git status
```

Look for commits matching:
- "brew dedup" (BrewScanner `pickLatest` fix)
- "sidebar fix" (NavigationLink + `.selectionDisabled()`)
- "pip dedup" (symlink resolution in PythonInterpreterDiscovery)

If any are missing from `git log`, they're uncommitted. `git status` will show what's modified.

### 2. Final rebuild + verify

```bash
./scripts/regenerate-xcode.sh
open Backshelf.xcodeproj
```

In Xcode: **Cmd+Shift+K** (Clean Build Folder), then **Cmd+R**.

Open the debug console (View → Debug Area → Show Debug Area, or Cmd+Shift+Y).

You should see:
- ✅ No `ForEach<...> the ID brew::... occurs multiple times` warnings
- ✅ No `ForEach<...> the ID pip:... occurs multiple times` warnings
- ⚠️ `os_unix.c:51044 ... DetachedSignatures` is harmless, ignore

Click each sidebar tab: "All packages", "Homebrew", "pip", "npm". The middle list should filter accordingly.

### 3. Remove debug overlay

Open `App/Sources/Views/PackageListView.swift`. Lines 11–15 look like:

```swift
// TODO: remove after Phase 5b verified
Text("DEBUG: sidebarSelection = \(String(describing: coordinator.sidebarSelection))")
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
```

Delete those 5 lines. The surrounding `VStack(spacing: 0) {` can stay (harmless) or be flattened back to the bare `Group { ... }` if you want to clean it up further.

Rebuild (Cmd+R). Confirm the debug text is gone from the top of the middle pane.

### 4. Commit + tag

```bash
git add -A
git commit -m "Phase 5b verified: sidebar filtering, pip+brew dedup, NavigationLink pattern, debug overlay removed"
git tag phase-5b-verified
```

Phase 5b is officially closed.

---

## Then what?

Phase 5c is planned. Design choices already approved this session (see HANDOFF.md "Phase 5c plan" section for full detail):

1. Snapshots as a sidebar section below Directory Access
2. Auto-capture before cleanup + manual "Snapshot now" toolbar button
3. Cleanup wizard as single-pane-with-sheet (checkboxes on rows → Generate button → sheet with script preview + copy/save)
4. Light-touch three-panel first-launch onboarding
5. Descriptions corpus deferred to Phase 5d

Plus seven implementation tasks bundled into Phase 5c:

- A. NpmScanner dedup (preemptive — same bug class as pip)
- B. Database persistence (scans survive restarts)
- C. Snapshots UI
- D. Cleanup wizard
- E. Onboarding flow
- F. Inline scan-status per manager in sidebar
- G. Stale-bookmark prompt UI

The `/goal` prompt skeleton is in HANDOFF.md. Scope is meaty (~100-120 turns). Consider splitting into 5c-1 (A+B+G plumbing) and 5c-2 (C+D+E+F UI).

---

## Key context

- **Test count: 262** (44 → 65 → 82 → 99 → 107 → 122 → 157 → 205 → 221 → 248 → 256 → 260 → 262)
- **Bundle ID locked: `app.backshelf.mac`**
- **Domain: `backshelf.app` (registered or to-register on Cloudflare/Namecheap)**
- **Deployment target: macOS 14.0 (Sonoma) for app; library at 13.0**
- **XcodeGen as source of truth; `Backshelf.xcodeproj/` gitignored.** Always regenerate after pulling changes that touch project structure.
- **All scanners use `DirectoryAccessProvider` protocol — never `FileManager.default` directly.** This is what lets the library run in-memory tests and in the sandboxed app with security-scoped bookmarks.

---

## Open issues (not blockers, just notes)

- `NpmScanner` likely has the same symlink-dedup bug as pip. First task of Phase 5c.
- `files/` → `docs/` directory rename is overdue. CLAUDE.md references `docs/...` paths.
- Database persistence isn't wired yet — packages are in-memory only, scans don't survive restarts.
- `AppCoordinator.scanStatuses` is populated but never displayed.
- Stale-bookmark detection exists but no UI surfaces it.
- `DetachedSignatures` SQLite warning in console is harmless macOS sandbox quirk.

Full detail: HANDOFF.md "Open issues to address in 5c" section.
