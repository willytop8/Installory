# UI

SwiftUI design principles and screen-by-screen notes. Read before building views.

## Principles

These shape every layout, every interaction, every word in the UI.

1. **Trust through clarity.** When we know something, say it. When we don't know, say that.
2. **No magic.** The user can always see what we're about to do.
3. **One density, two modes.** Default presentation works for non-technical users. A toggle (Settings → "Show technical detail") reveals raw commands, dependency graphs, install paths.
4. **Native, not skeuomorphic.** Standard macOS controls. SF Symbols. System fonts. No custom theming until brand identity is settled.
5. **Latency hidden, not denied.** Skeletons and progressive disclosure for slow scans. Never lock the UI on I/O.
6. **Installory itself is non-destructive.** No screen has a button that changes the user's packages. Cleanup is "generate a script the user runs themselves" — the destructive action happens in Terminal, by the user, deliberately.

## SwiftUI architecture

- **`@Observable`** for view-state. No `ObservableObject`.
- **Top-level coordinators** for cross-screen state (`AppCoordinator`). Per-screen coordinators (`InventoryCoordinator`, `CleanupCoordinator`) for screen-specific state.
- **Views are thin.** Data manipulation happens in the coordinator or service layer.
- **No `@EnvironmentObject`** — pass things explicitly. Environment is for things that genuinely span the app (color scheme, locale, the `Database` reference).
- **No NavigationStack ceremony** unless drilling justifies it. For v0, most navigation is a `NavigationSplitView` (sidebar / list / detail).
- **Xcode Previews** are mandatory for every leaf view. The agent should always be able to see what they're building.

```swift
@main
struct InstalloryApp: App {
    @State private var appCoordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appCoordinator)
                .environment(\.database, appCoordinator.database)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appCoordinator.updater)
            }
        }
        Settings {
            SettingsView()
                .environment(appCoordinator)
        }
    }
}
```

## Screens

### 1. Main window (`ContentView`)

Three-pane `NavigationSplitView`:

```
┌────────────┬─────────────────────────────────┬────────────────────┐
│ Sidebar    │ Inventory list                  │ Detail pane        │
│            │                                 │                    │
│ All        │  ┌───────────────────────────┐  │  ffmpeg             │
│ Homebrew   │  │ name      manager  desc...│  │  ──────             │
│ Python     │  │ ffmpeg    brew     Conv...│  │  brew · 6.0_1       │
│ npm        │  │ libpng    brew     PNG ...│  │  Installed Aug 14   │
│ pipx       │  │ requests  pip      HTTP...│  │  ━━ Description ━━  │
│ cargo      │  │ ...                       │  │  ffmpeg is a tool   │
│            │  └───────────────────────────┘  │  for converting...  │
│ Snapshots  │  [filter ▾] [search           ]│  ━━ Backstory ━━     │
│ Settings   │                                 │  Installed while    │
│            │                                 │  building podcast...│
└────────────┴─────────────────────────────────┴────────────────────┘
```

### Sidebar

- "All" + one item per detected manager
- Item shows manager name + count: "Homebrew (247)"
- Sub-grouping for Python: under "Python" the user sees their interpreters listed
- "Snapshots" and "Settings" at the bottom

### Inventory list

Columns:

- Name
- Manager (colored badge)
- Version
- Installed (relative time + confidence dot)
- Description (truncated, full on hover)

Sort by any column. Default sort: most-recently-installed first. Search filters across name, description, and manager.

Multi-select with shift-click and cmd-click. Selected count surfaces a "Generate cleanup script…" button at the bottom. Read-only packages are unselectable (greyed out with an explanation tooltip).

### Detail pane

When a package is selected:

```
ffmpeg                                              [⋯]
brew formula · 6.0_1
Installed Aug 14, 2025 (high confidence)

Description
ffmpeg converts video and audio files between formats. AI tools that
work with video often need it.

Backstory
You installed ffmpeg on August 14 while building a podcast transcription
script in podcast-app. You also installed pydub around the same time —
they're typically used together for audio processing.

[ Show evidence ]

Details
  Installed: /opt/homebrew/Cellar/ffmpeg/6.0_1
  Size: 213 MB
  Dependencies: aom, dav1d, fdk-aac, ...
  Required by: (none)

Actions
  [ Add ffmpeg to cleanup… ]
```

"Show evidence" expands the structured provenance evidence below the narrative. Power-user disclosure.

### 2. Cleanup wizard

When the user clicks "Generate cleanup script…":

```
┌────────────────────────────────────────────────────────────┐
│  Generate cleanup script · 4 packages selected             │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Selected packages                                         │
│  ☑ ffmpeg (brew)         213 MB                            │
│  ☑ libpng (brew)         5 MB     ⚠ Required by 3 others   │
│  ☑ requests (pip 3.11)   <1 MB                             │
│  ☑ typescript (npm)      120 MB                            │
│                                                            │
│  Total reclaimed if you run the script: ~339 MB            │
│                                                            │
│  ⚠ Warning: libpng is required by ImageMagick, openssl, … │
│      The generated script will include a # WARNING: line.  │
│                                                            │
│  A snapshot will be captured before the script is built.   │
│  You can export the snapshot as a reinstall script later.  │
│                                                            │
│  [ Cancel ]                          [ Generate script ]   │
└────────────────────────────────────────────────────────────┘
```

After "Generate script":

```
┌────────────────────────────────────────────────────────────┐
│  Cleanup script ready                                      │
├────────────────────────────────────────────────────────────┤
│  Snapshot captured ✓                                       │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ #!/usr/bin/env bash                                  │  │
│  │ # Cleanup script generated by Installory on 2026-05-15.   │  │
│  │ # Snapshot: 7c4f… (export from Snapshots to undo).   │  │
│  │ set -euo pipefail                                    │  │
│  │                                                      │  │
│  │ echo "→ brew uninstall ffmpeg"                       │  │
│  │ brew uninstall ffmpeg                                │  │
│  │                                                      │  │
│  │ # ⚠ WARNING: libpng is required by ImageMagick,      │  │
│  │ #   openssl, and others. Uncomment only if certain.  │  │
│  │ # brew uninstall libpng                              │  │
│  │                                                      │  │
│  │ echo "→ pip uninstall -y requests"                   │  │
│  │ /Users/will/.pyenv/versions/3.11.7/bin/pip \         │  │
│  │     uninstall -y requests                            │  │
│  │                                                      │  │
│  │ echo "→ npm uninstall -g typescript"                 │  │
│  │ npm uninstall -g typescript                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  Open Terminal, paste this, and press Enter to review      │
│  what it will do before running.                           │
│                                                            │
│  [ Copy ]   [ Save as .sh ]                  [ Done ]      │
└────────────────────────────────────────────────────────────┘
```

The script pane is read-only and uses a monospaced font. The two actions are `Copy` (writes to clipboard) and `Save as .sh` (NSSavePanel — the user picks a location). Installory itself does not execute the script.

### 3. Snapshots

A list view with one row per snapshot:

```
┌────────────────────────────────────────────────────────────┐
│  Snapshots                                                 │
├────────────────────────────────────────────────────────────┤
│  Pre-cleanup                            12:34 PM today     │
│    Brew: 247 · Python: 89 · npm: 12 · ...                  │
│                              [ View ] [ Export as script ] │
│                                                            │
│  Manual                                  Yesterday         │
│    "Before reorganizing dev tools"                         │
│              [ View ] [ Export as script ] [ Delete ]      │
│                                                            │
│  First scan                              Mar 1, 2026       │
│              [ View ] [ Export as script ] [ Delete ]      │
└────────────────────────────────────────────────────────────┘
```

"Export as script" diffs the snapshot against the current inventory and produces a reinstall shell script (additive only — see `docs/safety.md`). Installory presents the script in the same Copy / Save-as-.sh pane as cleanup. The user runs it themselves in Terminal.

### 4. Settings

Standard macOS Settings pane (`Settings { ... }` scene), with tabs:

- **General** — appearance (light/dark/auto), launch at login, show technical detail toggle
- **Scanning** — per-manager enable/disable, project-venv search paths
- **Permissions** — the folders the user has granted Installory read access to (each package manager directory, plus `~/.zsh_history` and `~/.claude` if granted). Each row shows the path, when access was granted, and a button to revoke or re-grant. Add-folder action opens NSOpenPanel.
- **Snapshots** — auto-snapshot rules, snapshot location, retention
- **About** — version, build, links to docs, credits

## Color and typography

V0 ships with system defaults — no custom palette, no custom fonts. The exception:

- A small set of **manager badge colors** (one per `PackageManager`), defined in `PackageManager+Display.swift`. Use system semantic colors where possible.
- **Confidence indicators**: green / yellow / grey dots for high / medium / low/unknown.

Brand identity (custom palette, custom mark, marketing site) is post-v0 work and separate from in-app UI.

## Accessibility

- Every actionable control has an accessibility label.
- Color is never the only signal — confidence dots have icon variants too.
- Keyboard navigation works for the entire main flow: arrow keys move the list selection, Enter opens detail, Cmd-D plans deletion.
- VoiceOver tested before each release.

## Errors and empty states

- **Scan failures** are surfaced in the sidebar's per-manager row. Click for details.
- **No packages found** for a manager that's installed is suspicious — surface a message inviting the user to check their config.
- **No description for a package** says "No description available". Never just blank, never fabricated.
- **Permission-denied scanner errors** show inline in the sidebar's per-manager row: "Can't see your Homebrew folder. Grant access in Settings → Permissions." Clicking opens the Permissions tab directly.

## Performance budget

- App launch to first paint: <500ms
- First scan to first row visible: <2s
- Full scan complete on a populated Mac: <15s
- Memory at idle: <200MB
- Memory during scan: <500MB

These are budgets, not guarantees. If we miss, we surface honest progress.

## What's deferred

- **Custom UI theming** — defer until brand is settled
- **Drag-and-drop** of packages for cross-snapshot comparison — clever but post-v1
- **Menu bar mode** — post-v0
- **Multiple windows** — post-v0
