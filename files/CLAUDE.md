# CLAUDE.md

Project-specific guidance for Claude Code working in the Cruft repo.

## What this project is

Cruft is a native macOS app that helps non-technical "vibe coders" understand and clean up the packages they've installed across multiple package managers (Homebrew, pip, npm, and more). It scans, explains each package in plain language, traces provenance ("when did I install this and what was I doing?"), and offers safe cleanup with mandatory snapshots.

The target user is someone who started coding with Claude Code or Cursor in the last 18 months, followed AI-given install instructions, and now has a Mac full of packages they couldn't name on a quiz. Every design decision should be evaluated against: **does this make that user feel safer and more in control, or less?**

## Required reading order

When starting work in this repo, read in this order:

1. This file (`CLAUDE.md`)
2. `README.md` — quick orientation
3. `PRODUCT.md` — the "why" that anchors all decisions
4. `ARCHITECTURE.md` — high-level system design
5. `ROADMAP.md` — current milestone and what comes next

Then, when working on a specific subsystem, also read its doc in `docs/`:

| Working on | Read |
| --- | --- |
| Adding or modifying scanners | `docs/scanners.md` |
| Anything Python-related | `docs/python-problem.md` |
| The provenance pipeline | `docs/provenance.md` |
| Description generation (bundled corpus) | `docs/descriptions.md` |
| Cleanup script generation or snapshots | `docs/safety.md` (every time, no exceptions) |
| Data model changes | `docs/data-model.md` |
| SwiftUI views and screens | `docs/ui.md` |
| Build, signing, App Store release | `docs/build-and-release.md` |
| Sandbox model, entitlements, folder access | `docs/sandboxing.md` |

## Conventions

### Language and frameworks

- **Swift 6.1+, SwiftUI for all UI.**
- **GRDB.swift 7.x** for persistence. Direct SQL is fine and encouraged where it's clearer than the query builder.
- **Swift Concurrency** (`async/await`, `TaskGroup`, actors). No GCD. No Combine.
- **`@Observable`** for state. No `ObservableObject`, no `@Published`.
- **No UIKit, no AppKit** unless a specific NSWindow / NSWorkspace behavior genuinely requires it. Document why if you reach for AppKit.
- **No external dependencies** beyond GRDB and (eventually) SharingGRDB. Adding any other dependency requires updating `ARCHITECTURE.md` with the justification.

### File organization

```
Cruft/
├── App/                    # @main entry, scene setup, top-level coordinators
├── Models/                 # Plain value types (Package, Snapshot, etc.)
├── Persistence/            # GRDB setup, migrations, DAOs
├── Scanners/               # PackageScanner protocol + per-manager scanners
│   ├── ScanCoordinator.swift
│   ├── PathDiscovery.swift
│   ├── BrewScanner.swift
│   ├── PipScanner.swift
│   ├── NpmScanner.swift
│   └── ...
├── Provenance/             # Three-signal pipeline
├── Descriptions/           # Bundled description lookup (read-only)
├── Safety/                 # Snapshots, cleanup-script generation
├── Views/                  # SwiftUI views, organized by screen
└── Resources/              # Bundled descriptions corpus, icons, etc.
```

### Code style

- Type names: `UpperCamelCase`. Functions and properties: `lowerCamelCase`.
- One public type per file, file named after the type.
- Prefer `struct` over `class` unless reference semantics are required (actors are fine for shared mutable state).
- Errors are `enum`s conforming to `Error`, defined alongside the type that throws them: `BrewScanner.Error`, not `BrewScannerError`.
- Avoid force-unwrap (`!`) and force-try (`try!`) outside of tests. Use `guard let` or document why a crash is correct.
- Comments explain *why*, not *what*. The code shows *what*.

### Things to never do

- **Never** generate a cleanup script without first capturing a snapshot. See `docs/safety.md`.
- **Never** mark system Python (`/usr/bin/python3`, `/Library/Developer/CommandLineTools/...`) packages as removable. They're filtered out of cleanup scripts; enforced in the model layer too.
- **Never** invoke external binaries via `Process`. The app is sandboxed and read-only — we read filesystem only.
- **Never** make a network call at app runtime. All data is local or bundled. Description metadata is fetched only by the maintainer's `scripts/generate-descriptions/` build-time tool.
- **Never** add a third-party Swift package without updating `ARCHITECTURE.md`.

### When uncertain

- If a package manager's output format isn't documented, run the real command on a populated Mac and save the output as a test fixture under `Tests/Fixtures/`. Build the parser against the fixture.
- If a path varies by system (Homebrew prefix on Intel vs Apple Silicon, etc.), introduce or extend the `PathDiscovery` service rather than hard-coding.
- Never guess at a JSON field name — verify by running the tool and inspecting actual output.
- If you'd need to know what the user was doing on a date and we don't have a signal, return `Confidence.unknown` rather than invent.

## Commands

To be filled in as the project develops. Expected entries:

- `swift build` — build the package
- `swift test` — run tests
- `xcodebuild -scheme Cruft -configuration Debug build` — Xcode build
- `./scripts/generate-descriptions.sh` — regenerate the bundled descriptions corpus from upstream registries (maintainer-only, build-time)

## Notes for the agent

- This is a private repo. Treat it as a real product, not a sketch.
- The app **IS sandboxed** (Mac App Store target). We never invoke external binaries; the entire inventory comes from reading filesystem locations (INSTALL_RECEIPT.json, dist-info/, .crates2.json, etc.) via user-granted directory access. Distribution and updates are handled by the App Store; no Sparkle, no notarization.
- There is **no network integration in v1**. Descriptions are bundled (generated at build time by a maintainer script that pulls from upstream registries — formulae.brew.sh, PyPI, npm registry, crates.io); provenance narratives are template-rendered Swift strings. The app makes zero network calls at runtime.
- Cruft is **read-only**: we don't uninstall, install, or upgrade anything. The "cleanup" feature generates a shell script the user runs themselves in Terminal.
- When in doubt about UX, err on the side of *honest about what we can't determine*, not *confident-sounding guess*. The trust we're building with non-technical users is the product.
