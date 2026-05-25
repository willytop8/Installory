# Scanners

The scanner subsystem is the heart of Installory. Everything else depends on accurate, fast, honest inventory.

## Design goals

1. **Honest about coverage.** If a scanner times out or can't see its target directory, we say so. We never silently drop a manager.
2. **Parallel.** No reason to wait for one manager (slow) before showing another (fast). UI streams in as each scanner finishes.
3. **Uniform interface, idiosyncratic internals.** Each manager has its own quirks; we don't force a lowest-common-denominator parser.
4. **No subprocess, ever.** The app is sandboxed and never invokes external binaries. Every scanner works by reading files at known on-disk locations: `INSTALL_RECEIPT.json` for Homebrew, `*.dist-info/` for pip, `~/.cargo/.crates2.json` for cargo, etc. If we can't see a manager's data without invoking its CLI, we document that as a known gap.

## The protocol

```swift
protocol PackageScanner {
    var manager: PackageManager { get }

    /// Whether the manager is installed at all on this Mac.
    /// Cheap: checks for the binary or known directories.
    func isAvailable() async -> Bool

    /// Scan and return packages.
    /// Throws ScannerError on unrecoverable failure.
    func scan() async throws -> [Package]
}

enum ScannerError: Error {
    case binaryNotFound(String)
    case timeout
    case malformedOutput(String)
    case unsupportedVersion(detected: String, minimum: String)
}
```

Scanners are concrete `struct`s or `final class`es, injected with `PathDiscovery`. No subclassing of scanners — composition only.

## `ScanCoordinator`

Runs all available scanners in a `TaskGroup`, applies timeouts, surfaces per-scanner status. The coordinator is an `actor` so scanner work, database writes, and status bookkeeping stay off the main actor. SwiftUI observes a separate `@MainActor @Observable` view model that projects coordinator updates into UI state.

```swift
actor ScanCoordinator {
    private var status: [PackageManager: ScannerStatus] = [:]
    private var packages: [Package] = []

    private let scanners: [any PackageScanner]
    private let database: Database

    func scan(
        onUpdate: @Sendable @escaping (ScanProjection) async -> Void
    ) async {
        await withTaskGroup(of: (PackageManager, Result<[Package], Error>).self) { group in
            for scanner in scanners {
                group.addTask {
                    do {
                        let result = try await withTimeout(scanner.timeout) {
                            try await scanner.scan()
                        }
                        return (scanner.manager, .success(result))
                    } catch {
                        return (scanner.manager, .failure(error))
                    }
                }
            }
            for await (manager, result) in group {
                let projection = await self.recordResult(manager: manager, result: result)
                await onUpdate(projection)
            }
        }
    }
}

@MainActor
@Observable
final class ScanViewModel {
    private(set) var status: [PackageManager: ScannerStatus] = [:]
    private(set) var packages: [Package] = []
    private(set) var isScanning: Bool = false

    private let coordinator: ScanCoordinator

    func scan() {
        isScanning = true
        Task {
            await coordinator.scan { projection in
                await MainActor.run {
                    self.status = projection.status
                    self.packages = projection.packages
                }
            }
            await MainActor.run {
                self.isScanning = false
            }
        }
    }
}
```

Default timeouts per scanner:

| Scanner | Default | Why |
| --- | --- | --- |
| brew | 5s | walking `Cellar/` + `Caskroom/` and reading receipts is fast |
| pip (per interpreter) | 3s | direct `dist-info/` reads |
| pipx | 5s | walk `~/.local/share/pipx/venvs/` |
| npm | 15s | walk `node_modules/<pkg>/package.json` across multiple node installs |
| cargo | 2s | single `~/.cargo/.crates2.json` read |
| gem | 5s | walk `specifications/` directories |
| mas | 5s | walk granted Applications folders and read App Store receipts |

Timeouts are configurable in Settings (advanced section, defaulted hidden).

## `PathDiscovery`

Locates package manager *directories* by checking known prefixes. We read files at these locations; we never invoke binaries.

```swift
struct PathDiscovery {
    /// Resolve a directory containing a package manager's on-disk state.
    /// Returns nil if the directory doesn't exist or the user hasn't granted access.
    func locate(_ kind: ManagerDirectory) -> URL?

    /// All Homebrew prefixes detected on this system.
    var homebrewPrefixes: [URL] { get }
}
```

Known prefixes (checked in this order):

```
/opt/homebrew                  # Apple Silicon
/usr/local                     # Intel Macs (and some Apple Silicon legacy)
~/.cargo                       # Rust
~/.rbenv/versions              # Ruby version manager
~/.pyenv/versions              # Python version manager
~/.nvm/versions/node           # Node version manager (each version)
~/.volta/tools/image/node      # Volta-managed Node
~/.bun/install/global          # Bun
~/.local/share/pipx/venvs      # pipx venvs
```

This list is in code as a single source of truth. When a new prefix is added, it's a one-line change. Each directory must be a folder the user has granted Installory read access to via `NSOpenPanel`; otherwise the scanner reports a "permission denied" status to the UI rather than skipping silently.

## Per-manager scanners

### BrewScanner

**Strategy:** Walk `Cellar/` and `Caskroom/` under each Homebrew prefix and read the `INSTALL_RECEIPT.json` inside every versioned subdirectory. No `brew` invocation — the receipts are authoritative for everything we need.

**Source of truth:** `INSTALL_RECEIPT.json` inside each Cellar / Caskroom directory:

```
/opt/homebrew/Cellar/<formula>/<version>/INSTALL_RECEIPT.json
/opt/homebrew/Caskroom/<cask>/<version>/INSTALL_RECEIPT.json    # casks
```

Key fields in receipts:

```json
{
  "time": 1719106768,                  // unix seconds, the install time
  "installed_as_dependency": false,
  "installed_on_request": true,
  "runtime_dependencies": [{"full_name": "openssl", "version": "3.0.7"}, ...],
  "source": {"tap": "homebrew/core", "versions": {"stable": "1.10.4"}},
  "artifacts": [                       // casks only
    {"app": ["Warp.app"]},
    {"zap": [{"trash": [...]}]}
  ]
}
```

Homebrew also keeps a JSON cache under `<prefix>/var/homebrew/` that mirrors what `brew info --json=v2 --installed` would print. If a receipt is missing or unparsable for a directory we see, that cache is an acceptable fallback. (For richer formula metadata — descriptions, homepage — we rely on the bundled corpus generated from `formulae.brew.sh` at build time, not on anything we read from disk at runtime.)

**Implementation outline:**

1. Detect brew prefix via `PathDiscovery.homebrewPrefixes`. If none, return `[]`.
2. Enumerate `<prefix>/Cellar/*/*` and `<prefix>/Caskroom/*/*` directories.
3. For each, read `INSTALL_RECEIPT.json`. Decode `time`, `installed_on_request`, `runtime_dependencies`.
4. Map to `Package` records. Manager is `.brew` or `.brewCask` based on which directory it came from.
5. `installedAtConfidence: .high` — receipts are authoritative.

For casks, the scanner decodes the `artifacts` array and flattens user-relevant paths into `Package.artifactPaths`. This field is optional and stored on `Package` rather than a separate associated table because the app only needs to display and preserve app paths and zap trash paths with the inventory row; if later cleanup planning needs per-artifact state or querying, migrate it into a dedicated table then. Runtime dependency names are normalized to bare names by stripping any tap prefix before the final `/`.

**Test fixtures:** capture several `INSTALL_RECEIPT.json` files plus a fake `Cellar/` directory layout in `Tests/Fixtures/brew/`.

### PipScanner

See [`python-problem.md`](python-problem.md) for the full strategy. Summary:

1. Enumerate all Python interpreters on the system via `PythonInterpreterDiscovery`.
2. For each interpreter, locate its `site-packages` directories.
3. Read each `*.dist-info/METADATA` file directly. Parse name, version. Read `RECORD` for installed files.
4. mtime of the `dist-info` directory is the install-time fallback (medium confidence).
5. Tag each package with the interpreter path as `qualifier`.
6. Tag system Python interpreters' packages as `isReadOnly: true`.

**Test fixtures:** capture a few `METADATA` and `RECORD` files plus a fake `site-packages` directory layout in `Tests/Fixtures/pip/`.

### NpmScanner

**Strategy:** Walk each global `node_modules/` directory and read every immediate child's `package.json`. No `npm` invocation.

**Discovery:** Each of these is a separate global root we look under for `lib/node_modules/`:

- `/opt/homebrew/lib/node_modules` (brew Node)
- `~/.nvm/versions/node/*/lib/node_modules` (nvm)
- `~/.volta/tools/image/node/*/lib/node_modules` (volta)
- `/usr/local/lib/node_modules` (Intel default)

For each directory that exists and the user has granted access to, list its first-level entries. For each entry, parse `<pkg>/package.json` for `name` and `version`. Scoped packages (`@scope/pkg`) appear as a two-level structure — read `@scope/<pkg>/package.json` accordingly.

**Why this layout:** the on-disk node_modules layout *is* the inventory; that's what `npm ls -g` reads internally. Walking it directly is faster and doesn't require invoking node or npm.

**Confidence for install time:** `.low` — there's no install receipt; we use mtime of the package's `package.json` as a best guess.

**Out of scope for v0:** pnpm globals (isolated install groups, complex), bun, yarn classic globals. Document each as "skipped: post-v0 feature" in the UI.

### PipxScanner

**Strategy:** Walk `~/.local/share/pipx/venvs/` directly. Each subdirectory is one pipx-managed tool with its own venv; we read the venv's `site-packages` to discover the main package and its version.

For each `~/.local/share/pipx/venvs/<tool>/` directory, locate `lib/python<X>.<Y>/site-packages/` underneath and read the `<tool>-<version>.dist-info/METADATA` file to get the name and version. (The `<tool>` directory name usually matches the package name but isn't always reliable; the dist-info is authoritative.)

Each entry is tagged `manager: .pipx`. Mark `isReadOnly: false` — pipx is the safest manager to uninstall from, since each tool is in its own venv.

### CargoScanner

**Strategy:** Read `~/.cargo/.crates2.json` directly. No subprocess.

The file format (abbreviated):

```json
{
  "installs": {
    "ripgrep 14.1.0 (registry+https://github.com/rust-lang/crates.io-index)": {
      "version_req": null,
      "bins": ["rg"],
      "features": [],
      "all_features": false,
      "no_default_features": false,
      "profile": "release",
      "target": "aarch64-apple-darwin",
      "rustc": "rustc 1.75.0 (...)",
      ...
    }
  }
}
```

Parse the key to extract name and version. Confidence for install time: mtime of the binary in `~/.cargo/bin/<binname>` (medium).

### GemScanner

**Strategy:** Walk each Ruby's `specifications/` directory directly. Gems are stored as `<gem_path>/specifications/<name>-<version>.gemspec`; the filenames give us name and version.

For Ruby version managers (rbenv, chruby, asdf), enumerate each managed Ruby's gem path under `~/.rbenv/versions/<ruby>/lib/ruby/gems/<api>/specifications/` or equivalent. For v0, handle rbenv and the default system Ruby; document other version managers as gaps.

The `.gemspec` files are Ruby source files; we don't try to evaluate them. We extract only what the filename tells us. Install time: mtime of the gemspec file.

### MasScanner

**Strategy:** Walk granted Applications folders and report only `.app` bundles that contain an App Store receipt at `Contents/_MASReceipt/receipt`. No `mas` invocation.

For each receipt-bearing app bundle, read `Contents/Info.plist` for `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier`, `CFBundleShortVersionString`, and `CFBundleVersion`. The package id uses the bundle identifier when available. Confidence for install time is `.low` using the receipt mtime or app bundle mtime as a fallback.

This does not recover the numeric App Store product id that `mas list` would return, because invoking `mas` is outside the sandbox model. Reinstall scripts therefore emit a comment directing the user back to the App Store.

## Adding a new scanner

The workflow:

1. Find the manager's on-disk source of truth (a JSON cache, a directory layout, a per-package metadata file). If the only way to enumerate the manager is to invoke its CLI, this is a sandbox-incompatible manager — document it as a known gap rather than adding it.
2. Capture representative samples of those files into `Tests/Fixtures/<manager>/`.
3. Implement the scanner conforming to `PackageScanner` — read-only filesystem access only.
4. Write parser tests against the fixtures.
5. Register the scanner in `ScanCoordinator`'s default list.
6. Add the manager case to `PackageManager` enum.
7. Add a display name and color in `PackageManager+Display.swift`.
8. Update the public docs if the scanner changes user-facing scope.
9. Update the first-launch onboarding to ask for read access to the relevant directory.

## Honest about gaps

The first version of Installory will not cover every package manager, and that's fine. The UI shows per-manager status. Users see:

```
brew         247 packages    ✓
pip          89 packages across 3 Pythons    ✓
npm          12 packages    ✓ (may miss installs done via mismatched npm prefix)
pipx         5 tools    ✓
cargo        18 crates    ✓
gem          ~        ✓ (rbenv, user gems, Homebrew gems, system gems read-only)
mas          ~        ✓ (receipt-bearing apps in granted Applications folders)
pnpm         ~        Skipped (post-v0)
bun          ~        Skipped (post-v0)
conda        ~        Skipped (post-v0)
```

We never present a partial scan as complete. Gaps like "npm globals installed via a non-standard prefix" are documented in the UI's per-scanner status row so the user sees exactly what we missed and why.
