# Provenance

How Cruft figures out *when* a package was installed and *what the user was doing* at the time. This is the differentiating feature — and it's the most engineered part of the system.

## The three signals

We combine three sources of evidence, each with its own confidence characteristics:

1. **Filesystem timestamps** — when did the package's files appear on disk?
2. **Shell history** — what `install` commands did the user run, and when?
3. **Claude Code logs** — what was the user trying to accomplish in the session that ran the install?

These are composed into structured `ProvenanceEvidence`. A small set of Swift string templates then turns that structured evidence into a human-readable paragraph at render time. There is no LLM in the loop and no network call — the templates are code in the app, and they fill in only the facts the evidence actually contains.

## Signal A: filesystem timestamps

Per manager, our source of truth for install time:

| Manager | Source | Confidence |
| --- | --- | --- |
| brew | `INSTALL_RECEIPT.json` `time` field | high |
| brewCask | `INSTALL_RECEIPT.json` `time` field | high |
| pip | mtime of `<name>-<version>.dist-info/` | medium |
| pipx | mtime of `~/.local/share/pipx/venvs/<tool>/` | medium |
| npm | mtime of `<global>/node_modules/<pkg>/package.json` | medium |
| cargo | mtime of `~/.cargo/bin/<binname>` | medium |
| gem | mtime of `<gem_path>/specifications/<name>-<version>.gemspec` | medium |
| mas | bundle's `Last Modified` from receipt, fallback to app bundle mtime | low |

Brew receipts are authoritative because Homebrew writes them once and never touches them again. mtimes are noisier: a `chmod`, an antivirus scan, or even some package rebuilds can update them.

When we have a high-confidence source, we use it. When we don't, we fall back to mtime and label confidence accordingly.

## Signal B: shell history

We parse the user's shell history files for `install` commands. Supported shells:

- **zsh** at `~/.zsh_history` — extended format `: <timestamp>:<elapsed>;<command>`
- **bash** at `~/.bash_history` — plain text, timestamps only if `HISTTIMEFORMAT` was set
- **fish** at `~/.local/share/fish/fish_history` — YAML-ish list of `{cmd, when}`

### Parser

```swift
struct ShellHistoryParser {
    func parseZshHistory(at: URL) throws -> [ShellCommand]
    func parseBashHistory(at: URL) throws -> [ShellCommand]
    func parseFishHistory(at: URL) throws -> [ShellCommand]
}

struct ShellCommand {
    let timestamp: Date?       // nil for bash without HISTTIMEFORMAT
    let raw: String
    let shell: Shell
}
```

### Install command detection

A regex pass over the parsed commands identifies installs:

```
^(brew install|brew reinstall|brew install --cask)\s+(.+)$
^(pip install|pip3 install|python -m pip install|python3 -m pip install|uv pip install)\s+(.+)$
^(pipx install)\s+(.+)$
^(npm install -g|npm i -g|yarn global add)\s+(.+)$
^(cargo install)\s+(.+)$
^(gem install)\s+(.+)$
^(mas install)\s+(.+)$
```

Each match yields one or more `(package, manager, timestamp)` tuples. `pip install -r requirements.txt` is parsed by reading the referenced file (if still present) and yielding one tuple per line.

### Matching install commands to packages

For each package, find the closest matching install command in the same manager within ±1 hour of the filesystem mtime. If found, attach to the evidence.

Edge cases:

- **Reinstalls** — multiple install commands for the same package. Pick the one closest in time to the current mtime.
- **`brew bundle`** — installs many things from a Brewfile in one command. We parse the Brewfile if findable; otherwise attribute all packages installed within a 5-minute window of the command.
- **No history** — `~/.zsh_history` doesn't exist or is empty. Skip this signal, fall back to filesystem only.

### Privacy and consent

Shell history is sensitive. On first launch, Cruft asks for permission to read history files. The Settings pane shows which files are being read and offers a per-file toggle. We never transmit shell history off the device.

## Signal C: Claude Code logs

This is the differentiator. For users who code with Claude Code, we can reconstruct exactly when and why each package was installed.

### File layout

```
~/.claude/
├── history.jsonl                          # every prompt ever, with timestamp
├── projects/
│   └── -Users-will-projects-podcast-app/
│       ├── sessions-index.json            # session summaries, message counts, branches
│       ├── <session-uuid>.jsonl           # the full transcript, one JSON per line
│       └── ...
```

The directory name under `projects/` is the project path with `/` replaced by `-`.

### JSONL format

Each line is one event in a session:

```json
{
  "parentUuid": "...",
  "sessionId": "abc123",
  "version": "1.x.x",
  "gitBranch": "main",
  "cwd": "/Users/will/projects/podcast-app",
  "message": {
    "role": "user" | "assistant",
    "content": [
      {"type": "text", "text": "..."},
      {"type": "tool_use", "name": "Bash", "input": {"command": "brew install ffmpeg"}, ...},
      {"type": "tool_result", "tool_use_id": "...", "content": [{"type": "text", "text": "..."}]}
    ]
  },
  "uuid": "...",
  "timestamp": "2025-08-14T15:23:11.000Z"
}
```

### Parser

```swift
struct ClaudeCodeLogParser {
    /// Walk ~/.claude/projects and return every Bash tool_use we find,
    /// with session context.
    func extractBashInvocations() throws -> [BashInvocationRecord]
}

struct BashInvocationRecord {
    let sessionId: String
    let projectPath: String          // reconstructed from the dashed directory name
    let timestamp: Date
    let command: String              // the `input.command` from the tool_use
    let cwd: String
    let firstUserMessage: String?    // from the session's first user message
    let sessionSummary: String?      // from sessions-index.json if present
}
```

### Matching invocations to packages

The match is identical in structure to shell-history matching but with `BashInvocationRecord` instead of `ShellCommand`. **Confidence: high** when matched — we have direct evidence Claude Code ran the install.

When both shell-history and Claude-Code matches exist for the same package, prefer the Claude Code match (more context). Mark `installCommand` and `claudeCodeContext` both in the evidence.

### What we extract for context

- The first user message of the session (often: "help me build a script to transcribe podcasts")
- The session summary if present in `sessions-index.json`
- The cwd (= the project they were working in)
- The git branch at the time

### Privacy

`~/.claude` contains sensitive prompt history. Same consent flow as shell history — the user grants Cruft read access to `~/.claude` via NSOpenPanel and can revoke it any time in Settings → Permissions. The Settings pane shows the project directories we've read from and lets the user exclude any of them. We never transmit Claude Code logs off the device. In fact the app makes no network calls at all — narratives are rendered locally from structured evidence using Swift string templates, so even the derived evidence never leaves the device.

## Composition into `ProvenanceEvidence`

For each package, the `ProvenanceCollector`:

1. Reads filesystem signal — produces `fsInstallTime` and source label.
2. Reads matching shell-history install command — produces `installCommand`.
3. Reads matching Claude Code invocation — produces `claudeCodeContext`.
4. Scans nearby projects (configurable roots) for files modified within ±24 hours of the install time. Ranks by file count.
5. Computes `coInstalledWithin1h` — other packages whose install time is within an hour, regardless of manager.
6. Sets `overallConfidence` to the highest of the three signals' confidences.

The complete evidence is persisted in `provenance_evidence` keyed by `package_id`.

## Narrative rendering

We turn `ProvenanceEvidence` into a paragraph by interpolating Swift string templates. The templates live in code (`Provenance/NarrativeRenderer.swift`) and are exercised by unit tests — there's no LLM, no API call, no caching layer to keep in sync.

### How it works

`NarrativeRenderer` picks one of a small number of template variants based on which signals are present in the evidence, then fills in the placeholders.

Example templates (abbreviated):

```swift
// Full evidence: install command + project + co-installed packages
"Installed {date} while working in {project}. You also installed " +
"{co_installed} around the same time."

// Install command + project, no co-installs
"Installed {date} while working in {project}."

// Filesystem timestamp only, no command and no project
"Installed {date}. We don't have a record of the command that installed it."

// No timestamp signal at all
"We don't have a record of when this was installed."
```

The renderer chooses the most specific template the evidence supports — never one that requires placeholders we don't have. If a co-installed list is empty, we skip the "you also installed" clause entirely rather than emitting an awkward "you also installed nothing".

### Sample output

> Installed on August 14 while working in `podcast-app`. You also installed `ffmpeg` and `pydub` around the same time.

The phrasing is intentionally plainer than what an LLM would produce. That trade-off is deliberate: deterministic, auditable, offline, and never wrong about a fact it doesn't have.

### What we lose, and why we're fine with it

An LLM narrative would sometimes synthesize across signals in ways a template can't ("they're typically used together for audio processing"). We chose to give that up in exchange for the simplicity of zero network calls and full sandbox compatibility. If we ever ship the future non-sandboxed direct-download version (see `ROADMAP.md`), we may revisit. For App Store Cruft, templates are the entire pipeline.

## Confidence calibration

In the UI, we surface confidence honestly:

- **High** — direct, dated evidence (brew receipt, Claude Code log match, well-formed shell history match)
- **Medium** — single signal (mtime only, or shell history with date imprecision)
- **Low** — weak inference (mtime from a file that might have been touched, ambiguous match)
- **Unknown** — no signal; we say so

A high-confidence row gets a green dot. Low/unknown gets a grey "?" icon with a tooltip explaining what we don't know.

## What we deliberately don't do

- **Don't infer "purpose."** We can describe co-installed packages, but we don't claim a package is "for video editing" unless we have evidence.
- **Don't speculate beyond evidence.** If we don't know, we say we don't know.
- **Don't make any network call.** The renderer is fully local; nothing leaves the device.
- **Don't depend on Claude Code being present.** The Claude Code signal makes things better; its absence doesn't break the feature.
