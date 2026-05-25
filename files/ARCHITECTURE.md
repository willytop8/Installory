# ARCHITECTURE.md

How Installory is organized as code. Read this before making structural changes.

## Stack choices and reasoning

| Concern | Choice | Why |
| --- | --- | --- |
| Language | Swift 6.1+ | Native, fast, AppKit/SwiftUI access, strong concurrency |
| UI | SwiftUI | Modern, declarative, less ceremony than AppKit for what we need |
| Persistence | GRDB.swift 7.x | Direct SQL when we want it, query builder when we don't, mature, actively maintained |
| Concurrency | Swift Concurrency | `async/await`, `TaskGroup`, actors — fits scanner orchestration model |
| State | `@Observable` | Macro-based, no Combine ceremony, plays well with SwiftUI |
| Distribution | Mac App Store | Handles signing, app review, and automatic updates. Sandbox is the trust signal — Apple has reviewed the app and constrained what it can do. |

**Considered and rejected:**

- **SwiftData** — iOS-first, perf issues at our data sizes, abstracts away the SQL control we need.
- **Core Data** — heavier than necessary; the ergonomics are worse than GRDB for our queries.
- **Tauri / Electron** — kills the trust positioning. See `PRODUCT.md`.
- **Rust core + Swift UI** — overkill. The bottleneck is filesystem walks, not our orchestration code. Swift's `TaskGroup` is plenty fast for parallel scans.
- **Combine** — Apple has signaled `@Observable` is the way forward; Combine adds a parallel mental model with no upside for this app.
- **Non-sandboxed Developer ID build** — kept as a possible future distribution option, but for v1 the App Store sandbox is the right trade. We give up the ability to invoke binaries; we get Apple review, automatic updates, and a stronger trust signal.

## Layered model

```
┌──────────────────────────────────────────────────────────────────┐
│                          Views (SwiftUI)                          │
│      InventoryView · DetailView · CleanupWizard · Settings        │
└────────────────────────────────┬─────────────────────────────────┘
                                 │ reads @Observable, sends actions
┌────────────────────────────────┴─────────────────────────────────┐
│                       Coordinators (Observable)                   │
│      AppCoordinator · ScanCoordinator · CleanupCoordinator        │
└────────────────────────────────┬─────────────────────────────────┘
                                 │ orchestrates services
┌─────────────┬─────────────────┬┴─────────────┬───────────────────┐
│  Scanners   │   Descriptions  │  Provenance  │      Safety       │
│  ────────   │   ────────────  │  ──────────  │  ───────────────  │
│ Per-manager │ Bundled,        │ 3 signals    │ Snapshots,        │
│ scanners,   │ read-only       │ composed     │ cleanup-script    │
│ ScanCoord — │ SQLite corpus   │ into         │ generator,        │
│ files only  │ from upstream   │ structured   │ denylist,         │
│             │ registry data   │ evidence +   │ read-only         │
│             │                 │ template     │ filtering         │
│             │                 │ narratives   │                   │
└──────┬──────┴─────────┬───────┴──────┬───────┴───────┬───────────┘
       │                │              │               │
┌──────┴────────────────┴──────────────┴───────────────┴───────────┐
│                          Foundation layer                          │
│   GRDB (SQLite) · Sandboxed filesystem · PathDiscovery             │
└────────────────────────────────────────────────────────────────────┘
```

**Direction of dependencies is downward only.** Foundation knows nothing about UI. Services know nothing about views. Views can read coordinator state but never call into services directly.

## Module responsibilities

### Foundation

- **`PathDiscovery`** — locates package manager *directories* (`/opt/homebrew`, `~/.cargo`, `~/.pyenv/versions/*`, etc.) by checking known prefixes. Returns `URL?`s. We read files at these locations; we never invoke binaries.
- **`FolderAccessManager`** — wraps `NSOpenPanel` + security-scoped bookmarks. The user grants Installory access to specific directories on first launch (or when a scanner reports it can't see its target); we persist those bookmarks so access survives launches.
- **`Database`** — GRDB DatabasePool, schema migrations, low-level DAO helpers.

### Scanners

- **`PackageScanner` protocol** — uniform contract: discover availability, scan, return `[Package]`.
- **One concrete scanner per manager** — `BrewScanner`, `PipScanner`, `PipxScanner`, `NpmScanner`, `CargoScanner`, `GemScanner`, and `MasScanner`.
- **`ScanCoordinator`** — runs scanners in parallel with `TaskGroup`, applies per-scanner timeouts, surfaces per-manager status to the UI (succeeded / failed / timed out / skipped).

See [`scanners.md`](scanners.md) for the protocol shape and per-manager notes. See [`python-problem.md`](python-problem.md) for why Python gets its own dedicated subsystem inside the pip scanner.

### Descriptions

- **`DescriptionStore`** — looks up plain-English descriptions by `(manager, name)`.
- **Bundled corpus** — SQLite read-only DB shipped inside the app bundle. Generated at build time by the maintainer's `scripts/generate-descriptions/` tool, which pulls upstream registry metadata (formulae.brew.sh, PyPI JSON API, npm registry, crates.io, rubygems) and writes them straight to SQLite. No LLM in the loop, no live lookup, no API key.
- **Missing descriptions** — when a package isn't in the bundle, the UI shows "No description available" rather than fabricating one.

See [`descriptions.md`](descriptions.md).

### Provenance

- **`ProvenanceCollector`** — combines three signals: filesystem timestamps, shell history, Claude Code logs. Outputs structured `ProvenanceEvidence`.
- **`NarrativeRenderer`** — turns structured evidence into a human-readable paragraph by interpolating Swift string templates. The structured pipeline is unchanged; only the final rendering step is template-based instead of LLM-generated.

See [`provenance.md`](provenance.md).

### Safety

- **`SnapshotManager`** — creates and lists snapshots. A snapshot is an export manifest (Brewfile-style) of the user's current inventory. Installory never restores a snapshot itself; it exports the snapshot as a reinstall shell script the user runs in Terminal.
- **`ScriptGenerator`** — given a selection of packages to remove, builds a dependency-aware shell script (with `set -e`, verbose echoes, and commented-out denylist lines). The script is what the user copies or saves; Installory never executes it.

## Concurrency model

- Scanners run in a `TaskGroup` inside `ScanCoordinator.scan()`. Each scanner is a `Task` with its own timeout.
- Results stream into the @Observable scan state as each scanner completes — the UI shows brew results in 200ms while npm is still running.
- GRDB writes go through a single `DatabaseWriter` (DatabasePool's writer) to serialize correctly.
- Heavy work (filesystem walks for provenance, dist-info parsing) runs in `Task.detached` to keep the main actor free for UI.
- No network calls anywhere — descriptions are read-only SQLite lookups, narratives are synchronous template renders.

## Persistence

A single SQLite database at `~/Library/Application Support/Installory/installory.db`.

Conceptual schema (see [`data-model.md`](data-model.md) for the full DDL):

- `packages` — current inventory, last scan time, manager, paths
- `provenance_evidence` — structured signals, package-id-keyed
- `snapshots` — JSON blobs, one per snapshot, with metadata
- `scan_runs` — log of scan runs for diagnostics

The bundled descriptions corpus is a *separate* read-only SQLite at `Bundle.main.url(forResource: "descriptions", withExtension: "db")`. We read from it but never write. There is no writable descriptions table — the corpus is the only source.

## Testing approach

- **Unit tests against fixtures.** Every scanner has a fixtures directory with real on-disk artifacts copied from a populated Mac (`INSTALL_RECEIPT.json` samples, `*.dist-info/` directories, `.crates2.json` snippets, etc.). Parsers are tested against these fixtures.
- **Integration tests are opt-in.** A separate test target runs the scanners against the developer's real package manager directories. Off by default in CI.
- **No UI snapshot tests yet.** Premature. Manual visual QA via Xcode Previews is enough until the app stabilizes.

When adding a new scanner, the workflow is:
1. Find the on-disk source of truth (a JSON file the manager writes, a directory layout, etc.)
2. Copy a representative sample to `Tests/Fixtures/<manager>/`
3. Write parser tests against the fixture
4. Wire into `ScanCoordinator`

## Networking and trust boundaries

- **The app makes no network calls at runtime.** Not for descriptions, not for narratives, not for telemetry, not for crash reporting. The only "network" activity is the App Store's own update mechanism, which is out of our process.
- Descriptions are pulled from upstream registries (`formulae.brew.sh`, PyPI JSON API, npm registry, crates.io, rubygems) by the maintainer's `scripts/generate-descriptions/` tool at build time. The output is a SQLite file bundled into the app.
- Provenance narratives are rendered from structured evidence using Swift string templates — no LLM, no API call.
- Sandbox: the app is sandboxed (`com.apple.security.app-sandbox`) and declares `com.apple.security.files.user-selected.read-only`. It can read filesystem locations the user explicitly grants via `NSOpenPanel`, persisted across launches as security-scoped bookmarks. It cannot write anywhere outside its container, cannot invoke binaries, and cannot reach the network.

## Non-goals at the architecture level

These are deliberately not in scope. If you find yourself reaching for them, stop and check with the maintainer:

- Plugin system for third-party scanners
- IPC between Installory and a CLI tool
- Daemon / background process
- iCloud sync
- Custom shell, terminal emulator, or REPL
- A built-in web view

## Glossary

- **Manager** — a package manager: `brew`, `pip`, `npm`, etc. Enumerated as `PackageManager`.
- **Package** — a single installed thing identified by `(manager, name)`. Versions and other detail in the `Package` value type.
- **Scan** — the act of asking every available scanner what's installed, in parallel.
- **Provenance** — the structured evidence we have for when/why a package was installed.
- **Narrative** — the template-rendered paragraph describing provenance to the user.
- **Snapshot** — a point-in-time record of all installed packages, restorable.
- **Confidence** — `.high | .medium | .low | .unknown`. Attached to provenance facts and removal recommendations.
