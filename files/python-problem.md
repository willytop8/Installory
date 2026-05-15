# The Python problem

Python deserves its own document because it's the messiest manager to scan and the riskiest to modify. Read before touching anything pip-related.

> **A note on sandboxing.** Backshelf is a sandboxed Mac App Store app. We never invoke any python binary — we only read files. But "only read files" still requires the user to grant Backshelf access to the directories where Python interpreters live: `~/.pyenv`, `~/.local/share/uv/python`, `~/.local/share/pipx`, `~/miniforge3`, `~/anaconda3`, and any project venv roots they want included. The first-launch onboarding asks for access to the ones we can detect. The Settings → Permissions tab lets the user add more later. When access to a directory is denied, the affected interpreters show up in the UI as "permission denied" rather than silently disappearing.

## The problem

A typical Mac that has been touched by an AI-coding workflow has:

- **System Python** at `/usr/bin/python3` — never modify. macOS itself depends on packages here.
- **CommandLineTools Python** at `/Library/Developer/CommandLineTools/usr/bin/python3` — also off-limits.
- **Homebrew Python** at `/opt/homebrew/opt/python@3.11`, `/opt/homebrew/opt/python@3.12`, `/opt/homebrew/opt/python@3.13` — each has its own site-packages.
- **pyenv-managed Pythons** at `~/.pyenv/versions/*/bin/python` — one per installed version.
- **uv-managed Pythons** at `~/.local/share/uv/python/*` — uv installs its own interpreters.
- **Conda / miniforge** at `~/miniforge3/bin/python` or `~/anaconda3/bin/python`.
- **pipx venvs** at `~/.local/share/pipx/venvs/<tool>/` — one per pipx-managed tool.
- **Project venvs** scattered as `venv/`, `.venv/`, `env/` inside project directories.

Each interpreter has its own `sys.path`. A package installed in pyenv's 3.11 is invisible from Homebrew's 3.12. `pip` on the user's `PATH` points to exactly one Python — and it's almost never the one with the interesting packages.

## The rules

These are inviolable:

1. **System Python is read-only.** Detect by path prefix and filter those packages out of generated cleanup scripts. The UI greys them out with an explanation.
2. **Never invoke `pip` or any python binary.** We're sandboxed and read-only. Reading `site-packages` directly is faster, more reliable, and doesn't depend on the interpreter being functional.
3. **Each interpreter's packages are tagged with the interpreter path as `qualifier`.** So `requests` in pyenv 3.11 and `requests` in pyenv 3.12 are distinct packages.
4. **pipx venvs are the safe zone.** A pipx tool in its own venv can be removed without affecting anything else. Surface this in the UI as `safe-to-remove: pipx`.

## Interpreter discovery

```swift
struct PythonInterpreter {
    let executable: URL
    let version: PythonVersion       // e.g., "3.11.7"
    let kind: Kind
    let sitePackages: [URL]
    let isSystem: Bool               // if true, packages are read-only
}

enum Kind: String {
    case system
    case commandLineTools
    case homebrew
    case pyenv
    case uv
    case conda
    case pipx          // a pipx-managed venv (its packages are pipx tools, not pip)
    case projectVenv   // a venv inside a user project
}

struct PythonVersion: Comparable, Codable {
    let major: Int
    let minor: Int
    let patch: Int
}
```

### Discovery strategy

`PythonInterpreterDiscovery` walks known locations and probes each candidate.

**Step 1: enumerate candidates.**

```
/usr/bin/python3
/Library/Developer/CommandLineTools/usr/bin/python3
/usr/local/bin/python3*                       # Intel macOS Homebrew
/opt/homebrew/opt/python@*/bin/python3*       # Apple Silicon Homebrew
/opt/homebrew/Cellar/python@*/*/bin/python3*  # Apple Silicon Homebrew alt
~/.pyenv/versions/*/bin/python
~/.local/share/uv/python/*/bin/python3        # uv's managed pythons
~/miniforge3/bin/python
~/anaconda3/bin/python
~/.local/share/pipx/venvs/*/bin/python        # pipx venvs (one per tool)
```

Project venvs are discovered separately and opt-in (see below).

**Step 2: probe each candidate.**

For each candidate path, verify it exists and is a regular file. Determine the version by reading `pyvenv.cfg` (for venvs) or by parsing the version out of the path (pyenv, uv, homebrew layouts all encode it). For interpreters where the path is ambiguous, fall back to reading the symlink chain or to inspecting the `lib/pythonX.Y/` directory name. We never execute the interpreter to ask for `--version`.

**Step 3: locate site-packages.**

For each interpreter, site-packages is `<install>/lib/python<X>.<Y>/site-packages` typically. For venvs, it's `<venv>/lib/python<X>.<Y>/site-packages`.

There can also be a `<install>/lib/python<X>.<Y>/dist-packages` directory on some systems — check both.

**Step 4: assign `kind`.**

```swift
func detectKind(path: URL) -> Kind {
    if path.path.hasPrefix("/usr/bin") { return .system }
    if path.path.contains("CommandLineTools") { return .commandLineTools }
    if path.path.hasPrefix("/opt/homebrew") || path.path.hasPrefix("/usr/local") { return .homebrew }
    if path.path.contains("/.pyenv/") { return .pyenv }
    if path.path.contains("/uv/python/") { return .uv }
    if path.path.contains("miniforge") || path.path.contains("anaconda") { return .conda }
    if path.path.contains("/pipx/venvs/") { return .pipx }
    return .projectVenv
}
```

`isSystem = (kind == .system || kind == .commandLineTools)`.

### Project venvs

Project venvs (`venv/`, `.venv/`, `env/` inside arbitrary directories) are discovered separately and **opt-in**. Reasons:

- The set of paths to walk is unbounded
- Users may have hundreds of project venvs they don't care to manage
- Scanning everything inside `~` is invasive

The user explicitly adds project venv search paths in Settings. Default: empty.

When enabled, walk the configured roots (e.g., `~/Developer`, `~/projects`) to depth 3, looking for directories containing `pyvenv.cfg`. Each match is treated as a `.projectVenv` interpreter.

## Reading site-packages directly

For each interpreter, scan its `site-packages` for installed distributions. Each is a `<name>-<version>.dist-info/` directory.

```
site-packages/
├── requests-2.31.0.dist-info/
│   ├── METADATA
│   ├── RECORD
│   ├── WHEEL
│   ├── INSTALLER
│   └── top_level.txt
├── requests/
│   └── ...
```

**`METADATA`** is PEP 566 / RFC 822 format. Parse for `Name`, `Version`, `Summary`, `Home-page`, `Author`, `License`.

**`RECORD`** is a CSV: `path,hash,size`. Lists every file installed by this distribution. We can use it later to compute installed size or to verify integrity.

**`INSTALLER`** contains the name of the tool that installed the package (`pip`, `uv`, etc.). Useful for diagnostics.

**`top_level.txt`** lists the top-level importable names. Not strictly needed but cheap to read.

### Install time

The `dist-info/` directory's mtime is our best signal for install time. It's set when pip writes the directory and is rarely touched after.

`installedAtConfidence: .medium` for dist-info mtimes (vs `.high` for brew receipts). Document this in the detail pane.

## Per-interpreter package identity

A package is identified as:

```
pip:<interpreter_path>:<package_name>
```

Examples:

```
pip:/Users/will/.pyenv/versions/3.11.7/bin/python:requests
pip:/opt/homebrew/opt/python@3.12/bin/python3.12:flask
pip:/Users/will/projects/whisper-app/.venv/bin/python:openai-whisper
```

This lets a user see "I have `requests` in three different Pythons" and decide what to do with each.

The UI groups packages by interpreter under the "Python" manager label, showing the interpreter version and kind:

```
▼ Python (3 interpreters, 89 packages)
   pyenv 3.11.7   →  47 packages
   pyenv 3.12.1   →  31 packages
   homebrew 3.12  →  11 packages
   (system 3.9    →  read-only)
```

## What cleanup-script generation means for pip

Backshelf never removes anything directly. The cleanup script we generate (see `docs/safety.md`) emits the right command for each kind of interpreter; the user runs it in Terminal.

- **System Python:** filtered out entirely. Cannot appear in a generated script. UI greys these out with the explanation: "These packages are part of macOS or Xcode Command Line Tools and removing them can break system functionality."
- **Homebrew Python:** emit `<interpreter> -m pip uninstall -y <pkg>` with a `# WARNING:` comment noting that some Homebrew formulae depend on Python packages.
- **pyenv / uv:** emit `<interpreter> -m pip uninstall -y <pkg>` — these are user-controlled, isolated Pythons and the safest non-pipx removals.
- **Conda:** v0 doesn't support conda. Document as a known gap.
- **pipx:** emit `pipx uninstall <tool>` for the *tool*, never `pip uninstall` within a pipx venv.
- **Project venvs:** emit the uninstall command, plus a `# WARNING:` comment noting that breaking a venv may break the project that depends on it.

## Implementation order

When implementing the Python subsystem, build in this order:

1. `PythonInterpreterDiscovery` with tests against fixture directories
2. `DistInfoParser` for METADATA and RECORD
3. `PipScanner` orchestrating discovery + parsing
4. UI grouping by interpreter
5. Cleanup-script generation for pip packages (gated until snapshots work — see `docs/safety.md`)

## What we deliberately don't do in v0

- **Don't infer pip dependencies.** The dependency tree for Python packages requires resolving `Requires-Dist` against installed versions, which is hard and error-prone. We show the raw `Requires-Dist` list but don't claim a dependency graph.
- **Don't touch conda environments.** Conda's model (channels, environments, base env, mamba) is enough complexity for its own phase.
- **Don't try to upgrade.** We're an inventory and cleanup tool, not a package manager.
