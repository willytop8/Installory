# Phase 1 Handoff

## What Was Built

Phase 1 adds `PackageScanner`, `DirectoryAccessProvider`, and `BrewScanner` to the
`CruftCore` library, plus GRDB round-trip tests for `ProvenanceEvidence`, `Snapshot`,
and `ScanRun`. No external dependencies were added. No SwiftUI, no networking, no
`Process`/`NSTask`. `swift build` and `swift test` both succeed — 65 tests, zero
warnings, Swift 6 strict concurrency.

```
Cruft/
├── Package.swift                                 # resources: [.copy("Fixtures")] added to test target
├── Sources/
│   └── CruftCore/
│       ├── Models/                               # unchanged from Phase 0
│       ├── Foundation/
│       │   ├── PathDiscovery.swift               # unchanged
│       │   └── DirectoryAccessProvider.swift     # NEW: protocol + SystemDirectoryAccessProvider
│       ├── Persistence/                          # unchanged
│       └── Scanners/                             # NEW directory
│           ├── PackageScanner.swift              # NEW: protocol + ScannerError
│           └── BrewScanner.swift                 # NEW: reads Cellar/ + Caskroom/ receipts
└── Tests/
    └── CruftCoreTests/
        ├── Fixtures/
        │   └── brew/
        │       ├── Cellar/
        │       │   ├── git/2.44.0/INSTALL_RECEIPT.json          # explicit, 2 deps
        │       │   ├── openssl@3/3.3.0/INSTALL_RECEIPT.json     # dependency, 0 deps
        │       │   ├── python@3.12/3.12.4/INSTALL_RECEIPT.json  # explicit, 4 deps
        │       │   └── wget/1.24.5/INSTALL_RECEIPT.json         # explicit, 2 deps
        │       └── Caskroom/
        │           ├── visual-studio-code/1.90.2/INSTALL_RECEIPT.json
        │           └── warp/0.2024.06.18.08.02.stable.01/INSTALL_RECEIPT.json
        ├── Support/
        │   └── InMemoryDirectoryAccessProvider.swift  # NEW: test-only fake
        ├── BrewScannerTests.swift                     # NEW: 14 tests
        ├── DatabaseTests.swift                        # +6 GRDB round-trip tests
        ├── ModelTests.swift                           # unchanged
        └── PathDiscoveryTests.swift                   # unchanged

HANDOFF.md                                            # this file
files/scanners.md                                     # unchanged
```

---

## Phase 0 Handoff (preserved)

### What Was Built

A pure Swift Package (`CruftCore`) at `Cruft/` with no Xcode project.
`swift build` and `swift test` both succeeded — 44 tests, zero warnings, Swift 6
strict concurrency.

Models: `PackageManager`, `Package`, `Confidence`, `ProvenanceEvidence`,
`Description`, `Snapshot` (+ `SnapshotReason`, `SnapshotPayload`, `SnapshotPackage`),
`ScanRun` (+ `ScannerStatus`). Foundation: `PathDiscovery` + `ManagerDirectory`.
Persistence: `Database` (DatabasePool wrapper) + `Migrations` (v1_initial schema).

---

## Phase 1 Decisions Where Docs Were Ambiguous

### 1. `PackageScanner.manager` returns `.brew` for `BrewScanner`

`scanners.md` documents one scanner ("brew") that covers both Cellar and Caskroom.
`BrewScanner.scan()` returns packages with `.brew` and `.brewCask` manager values;
the `manager` property returns `.brew` to identify this scanner to `ScanCoordinator`.
This is the natural reading: BrewScanner IS the brew scanner, it just also handles casks.

### 2. `DirectoryAccessProvider` is a protocol, not a closure pair

Phase 0 HANDOFF question #1 asked whether `DirectoryAccessProvider` should live in
`CruftCore` as a protocol. Answer: yes. `SystemDirectoryAccessProvider` is the
production implementation. `InMemoryDirectoryAccessProvider` (test-only, in the test
target) is the fake. This mirrors the `PathDiscovery` `checkExists` injection pattern
but scales better since scanners need two distinct operations (enumerate + read).

### 3. Fixture fake prefix must be a known Homebrew path

`PathDiscovery.homebrewPrefixes` hardcodes the two candidate paths (`/opt/homebrew`,
`/usr/local`). The in-memory fake uses `/opt/homebrew` as the fake Homebrew prefix so
that `PathDiscovery(checkExists: { path in path == "/opt/homebrew" })` returns a
non-empty prefix list. No real filesystem at `/opt/homebrew` is accessed — all reads
go through the injected `InMemoryDirectoryAccessProvider`.

### 4. `ScannerError` is module-level, not nested

`scanners.md` shows `ScannerError` at module level. `CLAUDE.md` says errors should be
nested (e.g. `BrewScanner.Error`). The spec wins: `ScannerError` is shared across all
scanners and is part of the `PackageScanner` protocol's contract. Module-level
placement is correct.

### 5. Receipt parsing skips malformed files silently

If `INSTALL_RECEIPT.json` is missing or unparsable for a version directory, that
directory is silently skipped. `scanners.md` notes the Homebrew JSON cache under
`<prefix>/var/homebrew/` as a fallback, but implementing that fallback is deferred
(the receipts are present for all real installations). The scan does not throw on
parse failure.

### 6. `time` field decoded as `Double`, not via `dateDecodingStrategy`

The receipt `time` field is a Unix timestamp stored as a JSON integer. Decoding it as
`Double?` and constructing `Date(timeIntervalSince1970:)` manually is safer than
relying on `dateDecodingStrategy` (which parses `TimeInterval` from `Double` but
could be confused by integer values in some decoder configurations).

---

## Known Limitations

1. **`FolderAccessManager` is absent.** See Phase 0 limitation #1. `Database.init(directory:)`
   and `BrewScanner.init(pathDiscovery:directoryAccess:)` both accept injected
   dependencies. The app shell will resolve security-scoped bookmarks and pass in the
   right URLs.

2. **`Description` has no GRDB conformances.** Deferred from Phase 0. Phase 2 should
   add `FetchableRecord` when `DescriptionStore` is built.

3. **`BrewScanner.scan()` performs blocking I/O in an `async` context.** The
   `DirectoryAccessProvider` protocol is synchronous. Since Homebrew Cellar/Caskroom
   scans are fast (<5s per the timeout table), this is acceptable. If profiling shows
   actor starvation, the protocol can be made `async` in a future phase.

4. **`ScanCoordinator` is not implemented.** Phase 1 scope is the scanner only.
   `ScanCoordinator` (TaskGroup, timeouts, per-scanner status) is Phase 2+.

5. **Only `BrewScanner` is implemented.** `PipScanner`, `NpmScanner`, etc. are
   deferred per the phase constraints.

6. **`installPath` for casks points to the versioned Caskroom directory**, not the
   installed `.app` bundle path. This is the information available from the receipt;
   the actual `.app` path (from `artifacts[].app[]`) is not parsed. If the UI needs
   the `.app` path for size calculation or Finder reveal, parse `artifacts` in a
   future iteration.

---

## Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `PackageScanner` protocol | N/A | Interface only |
| `ScannerError` | N/A | Enum only |
| `DirectoryAccessProvider` | N/A | Interface; `System` implementation covered via `BrewScanner` tests |
| `BrewScanner.isAvailable` | Full | True (prefix present) + False (no prefix) |
| `BrewScanner.scan` — count | Full | 6 packages: 4 formulae + 2 casks |
| `BrewScanner.scan` — managers | Full | Both `.brew` and `.brewCask` returned |
| `BrewScanner.scan` — empty prefix | Full | Returns `[]` when no Cellar/Caskroom |
| `BrewScanner.scan` — formula fields | Full | id, version, installedAt, deps (git, python@3.12) |
| `BrewScanner.scan` — cask fields | Full | id, version, installedAt, isExplicit (vscode) |
| `BrewScanner.scan` — isExplicit flag | Full | True (wget) + False (openssl@3, dependency) |
| `BrewScanner.scan` — confidence | Full | All packages `.high` |
| `BrewScanner.scan` — installPath | Full | All non-nil |
| `BrewScanner.scan` — qualifier/readOnly | Full | nil / false for all brew packages |
| `ProvenanceEvidence` GRDB round-trip | Full | Full + nil-optionals |
| `Snapshot` GRDB round-trip | Full | Full + nil note + empty payload |
| `ScanRun` GRDB round-trip | Full | Full + nil completedAt |
| `InMemoryDirectoryAccessProvider` | Covered indirectly | Through all `BrewScanner` tests |

---

## Questions for Phase 2

1. **`ScanCoordinator` actor isolation.** Should it be an `actor` or `@Observable final class`?
   `scanners.md` uses `@Observable`, but `@Observable` on a class doesn't provide actor
   isolation — concurrent writes from a `TaskGroup` would race without additional
   synchronization. Recommend: `actor ScanCoordinator` with `@Published`-style
   observation via `AsyncStream` or a wrapping `@Observable` view model.

2. **`DirectoryAccessProvider` async upgrade.** If blocking filesystem reads in `async`
   functions becomes a problem under load, the protocol methods should become
   `async throws`. That would ripple through `BrewScanner` and all future scanners.
   Decide before implementing more scanners.

3. **Receipt `artifacts` parsing for casks.** The `installPath` for casks currently
   points to the Caskroom versioned directory. If size reporting or "reveal in Finder"
   needs the `.app` path, parse `artifacts[].app[]` in `BrewScanner.makePackage`.

4. **Multiple Homebrew versions in the same Cellar.** A formula directory can have
   multiple version subdirectories (e.g. when `brew pin` is used). Currently the
   scanner produces one `Package` per version directory. `ScanCoordinator` or a
   post-processing step should deduplicate by `(manager, name)` keeping the latest
   version if duplicates are unwanted.

5. **GRDB pool configuration.** See Phase 0 question #4. WAL mode and reader pool
   tuning should be set before `ScanCoordinator` runs parallel scans.
