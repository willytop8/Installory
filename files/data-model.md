# Data model

The core types and schema. Read before changing any persistent or in-memory representation.

## Design principles

- **Plain `struct`s for value types.** No inheritance, no Core Data-style reference graphs.
- **GRDB record types for persistence.** Each persistent type implements `Codable`, `FetchableRecord`, `PersistableRecord`.
- **Identity is `(manager, name)` for packages**, with the qualifier of the Python interpreter path when manager is `.pip`. Versions are a property of the package, not part of identity.
- **Confidence is explicit.** Anywhere we have a derived fact, we attach a `Confidence`.

## Core types

### `PackageManager`

```swift
enum PackageManager: String, Codable, CaseIterable {
    case brew            // Homebrew formulae
    case brewCask        // Homebrew casks
    case pip             // Python packages (per interpreter)
    case pipx            // pipx-managed CLI tools
    case npm             // npm globals
    case cargo           // Rust crates
    case gem             // Ruby gems
    case mas             // Mac App Store apps
    case conda           // Conda / mamba environments — post-v0
    case pnpm            // post-v0
    case bun             // post-v0
}
```

Display names and icons are derived in `PackageManager+Display.swift`, not in the model.

### `Package`

```swift
struct Package: Identifiable, Codable, Equatable, Hashable {
    let id: String                  // "{manager}:{qualifier}:{name}"
    let manager: PackageManager
    let qualifier: String?          // interpreter path for pip, nil otherwise
    let name: String
    let version: String
    let installPath: URL?
    let installedAt: Date?          // best-effort, see Provenance
    let installedAtConfidence: Confidence
    let sizeBytes: Int64?
    let isExplicit: Bool            // installed_on_request, not as a dependency
    let isReadOnly: Bool            // true for system Python packages, etc.
    let dependencies: [String]      // names within the same manager
    let lastSeen: Date              // when this row was last refreshed by a scan
}
```

The `id` format examples:

- Homebrew formula: `brew::ffmpeg`
- Homebrew cask: `brewCask::visual-studio-code`
- pip in pyenv 3.11.7: `pip:/Users/x/.pyenv/versions/3.11.7/bin/python:requests`
- pipx tool: `pipx::black`

### `Confidence`

```swift
enum Confidence: String, Codable, Comparable {
    case unknown   // we have no signal
    case low       // weak signal, e.g., mtime only
    case medium    // multiple signals, some friction
    case high      // direct evidence, e.g., INSTALL_RECEIPT.json or Claude Code log

    static func < (lhs: Confidence, rhs: Confidence) -> Bool { ... }
}
```

### `ProvenanceEvidence`

Stored alongside a package, gathered by the `ProvenanceCollector`. Structured so the `NarrativeRenderer` has reliable input — the template-based rendering pipeline reads these fields directly to interpolate human-readable text.

```swift
struct ProvenanceEvidence: Codable {
    let packageId: String

    // Filesystem signal
    let fsInstallTime: Date?
    let fsInstallTimeSource: String?   // "INSTALL_RECEIPT.json" | "dist-info mtime" | etc.

    // Shell history signal
    let installCommand: InstallCommandRecord?

    // Claude Code signal
    let claudeCodeContext: ClaudeCodeContext?

    // Nearby activity (derived)
    let nearbyProjects: [NearbyProject]
    let coInstalledWithin1h: [String]  // package ids

    let overallConfidence: Confidence
    let collectedAt: Date
}

struct InstallCommandRecord: Codable {
    let timestamp: Date?        // nil when shell does not record timestamps
    let command: String         // raw, e.g. "pip install openai-whisper"
    let shell: Shell            // .zsh | .bash | .fish
    let cwd: String?            // if recoverable
}

struct ClaudeCodeContext: Codable {
    let sessionId: String
    let projectPath: String
    let sessionSummary: String? // from sessions-index.json
    let firstUserMessage: String?
    let bashInvocation: String  // the exact tool_use Bash command
    let timestamp: Date
}

struct NearbyProject: Codable {
    let path: String
    let modifiedFileCount: Int
    let gitCommitsThatDay: Int
}
```

### `Description`

```swift
struct Description: Codable {
    let manager: PackageManager
    let name: String
    let text: String               // 1-2 sentences, plain English
}
```

Descriptions are loaded read-only from the bundled SQLite corpus. There is no writable description table — if a `(manager, name)` is not in the corpus, the UI shows "No description available". Personalization, manual overrides, and live generation are all post-v1.

### `Snapshot`

> A snapshot is an **export manifest** (Brewfile-style): a record of every package installed at a moment in time. Installory never restores a snapshot itself. Restoration is the user running the reinstall script Installory generates from the snapshot.

```swift
struct Snapshot: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let reason: SnapshotReason     // user-initiated, pre-uninstall, auto-periodic
    let note: String?
    let payload: SnapshotPayload
}

enum SnapshotReason: String, Codable {
    case manual
    case preUninstall
    case autoFirstScan
}

struct SnapshotPayload: Codable {
    let managers: [PackageManager: [SnapshotPackage]]
}

struct SnapshotPackage: Codable {
    let name: String
    let version: String
    let qualifier: String?         // interpreter path for pip
    let isExplicit: Bool
}
```

### `ScanRun`

For diagnostics only.

```swift
struct ScanRun: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let perManagerResults: [PackageManager: ScannerStatus]
}

enum ScannerStatus: Codable, Equatable {
    case succeeded(count: Int, durationMs: Int)
    case failed(reason: String, durationMs: Int)
    case timedOut(durationMs: Int)
    case skipped(reason: String)
}
```

## SQLite schema

Defined in GRDB migrations. All migrations go in `Persistence/Migrations.swift`, never modified after release.

```sql
CREATE TABLE packages (
    id            TEXT PRIMARY KEY,
    manager       TEXT NOT NULL,
    qualifier     TEXT,
    name          TEXT NOT NULL,
    version       TEXT NOT NULL,
    install_path  TEXT,
    installed_at  REAL,
    installed_at_confidence TEXT NOT NULL,
    size_bytes    INTEGER,
    is_explicit   INTEGER NOT NULL DEFAULT 0,
    is_read_only  INTEGER NOT NULL DEFAULT 0,
    dependencies  TEXT NOT NULL DEFAULT '[]',  -- JSON array of names
    last_seen     REAL NOT NULL
);
CREATE INDEX idx_packages_manager ON packages(manager);
CREATE INDEX idx_packages_name ON packages(name);

CREATE TABLE provenance_evidence (
    package_id    TEXT PRIMARY KEY,
    payload       TEXT NOT NULL,             -- JSON of ProvenanceEvidence
    collected_at  REAL NOT NULL,
    overall_confidence TEXT NOT NULL,
    FOREIGN KEY (package_id) REFERENCES packages(id) ON DELETE CASCADE
);

CREATE TABLE snapshots (
    id            TEXT PRIMARY KEY,
    created_at    REAL NOT NULL,
    reason        TEXT NOT NULL,
    note          TEXT,
    payload       TEXT NOT NULL              -- JSON of SnapshotPayload
);
CREATE INDEX idx_snapshots_created ON snapshots(created_at DESC);

CREATE TABLE scan_runs (
    id            TEXT PRIMARY KEY,
    started_at    REAL NOT NULL,
    completed_at  REAL,
    per_manager_results TEXT NOT NULL        -- JSON
);
```

The bundled `descriptions.json` file is shipped in the app bundle and loaded read-only at startup. It is a flat key-value map:

```json
{
  "brew:ffmpeg": "Play, record, convert, and stream audio and video",
  "pip:requests": "Python HTTP for Humans."
}
```

`DescriptionStore` reads from that bundled JSON only. There is no writable descriptions table — the corpus is the single source of truth, and it's regenerated between releases.

## Why these choices

**Why `(manager, name)` identity?**
Because a user can have `requests` in three Pythons and we need to treat them as three packages, but they're also the same "thing" conceptually. The qualifier (interpreter path) disambiguates without losing the conceptual identity.

**Why JSON blobs for some fields (dependencies, payload, per_manager_results)?**
We rarely query inside them; they're read whole. Normalizing them into separate tables would add complexity for no query-pattern benefit. If a future feature needs to query inside, that's the trigger to normalize.

**Why a bundled JSON corpus instead of seeding the user's DB?**
We don't want to pollute the user's writable database with read-only data, and we don't want a 20MB initial seed migration on first launch. A separate bundle file is cleaner and gets refreshed for free with every app update through the App Store.
