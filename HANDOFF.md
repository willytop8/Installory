> **Renamed Cruft → Backshelf on 2026-05-15.** The SPM package directory, library target, and all source/doc references have been updated. The git root directory rename is handled separately by William.

# Phase 4c Handoff

## What Was Built

Phase 4c integrates all three provenance signals into a usable pipeline:
`ProvenanceCollector` (matching + confidence scoring), `ProvenanceDAO` (SQLite persistence),
and `NarrativeRenderer` (human-readable sentence generation). Also fixes `ClaudeCodeContext.timestamp`
from `Date` to `Date?`. `swift build` and `swift test` both pass: 248 tests, zero warnings,
Swift 6 strict concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       ├── Models/
│       │   └── ProvenanceEvidence.swift  # CHANGED: ClaudeCodeContext.timestamp → Date?
│       ├── Provenance/
│       │   ├── ClaudeCodeLogCollector.swift  # CHANGED: removed epoch fallback (nil on parse failure)
│       │   ├── ProvenanceCollector.swift     # NEW: matches signals, scores confidence
│       │   └── NarrativeRenderer.swift       # NEW: template-based sentence renderer
│       └── Persistence/
│           └── ProvenanceDAO.swift           # NEW: upsert / fetch / delete / deleteAll
└── Tests/
    └── BackshelfCoreTests/
        ├── ProvenanceCollectorTests.swift    # NEW: 9 tests
        ├── ProvenanceDAOTests.swift          # NEW: 5 tests
        └── NarrativeRendererTests.swift      # NEW: 13 tests

HANDOFF.md                                   # this file
```

---

## Phase 4c Decisions

### 1. `ClaudeCodeContext.timestamp: Date` → `Date?`

Nil is now emitted when the JSONL timestamp field is absent or malformed, instead of
falling back to `Date(timeIntervalSince1970: 0)` (the epoch). The epoch fake caused
nil-timestamp Claude Code records to spuriously match packages installed in January 1970.
`ProvenanceCollector` filters these records out: only records with a non-nil timestamp
participate in matching. `InstallCommandRecord.timestamp` was already `Date?` from Phase 4a;
`ClaudeCodeContext` is now consistent.

### 2. `PackageKey: Hashable` for O(1) bucket lookup

`ProvenanceCollector` builds `[PackageKey: [ShellRecord]]` and `[PackageKey: [ClaudeRecord]]`
dictionaries keyed on `(manager, name)` before iterating packages. This keeps the matching
algorithm O(packages × signals) rather than O(packages² × signals). `InstallCommandDetector`
is called once per shell record during the build phase (not per package), because
`InstallCommandRecord` stores only the raw command string — the parsed `(name, manager)` pairs
must be re-derived.

### 3. Confidence table (definitive)

| Signal present | Condition | Confidence |
|---|---|---|
| `fsInstallTime == nil` | — | `.unknown` |
| `claudeCodeContext != nil` | — | `.high` |
| shell match | Δ ≤ 5 min | `.high` |
| shell match | Δ > 5 min OR nil timestamp | `.medium` |
| fs only | — | `.low` |

Claude Code presence always wins over shell timing because it implies the install was
deliberately initiated by an AI assistant in a known project context.

### 4. FK prerequisite documented, not enforced at runtime

`ProvenanceDAO.upsert` carries a doc comment requiring the `packages` row to exist first.
GRDB enables foreign keys by default via `DatabasePool`. The test suite seeds a minimal
`packages` row before each upsert using raw SQL. Phase 5's app shell sequences
`scan → persist packages → collect provenance → persist evidence`, which satisfies the
constraint naturally.

### 5. `NarrativeRenderer` inspects optionals directly, no `NarrativeInput` enum

The four template cases are selected by checking `claudeCodeContext`, `installCommand`,
and `fsInstallTime` for nil — exactly the same optionality that callers already use.
A `NarrativeInput` enum would duplicate this logic without adding expressiveness.

### 6. `RelativeDateTimeFormatter` with `.named` style

`.named` produces "yesterday", "3 days ago", "last week" rather than "1 day ago",
"3 days ago", "7 days ago". The 14-day threshold preserves the named style's useful
range; dates older than 14 days use `DateFormatter("MMM d, yyyy")` for unambiguous
absolute output.

### 7. `nearbyProjects` always `[]` in v0

`ProvenanceEvidence.nearbyProjects` is populated by a future git-repo-walk signal.
`ProvenanceCollector` always emits `[]`. The field is modelled and persisted correctly;
the collection logic is deferred.

### 8. pip `(manager, name)` qualifier collision accepted for v0

Two pip packages with the same name but different interpreter paths produce the same
`PackageKey`. The first matching shell or Claude Code record wins. This is incorrect
in theory (different pythons are different packages) but acceptable for v0 because:
(a) it affects only the timestamp correlation step, not identity, and (b) the full fix
requires `(manager, name, qualifier)` keying, which complicates matching against
shell commands that don't record the interpreter. Documented as Phase 4-followup.

---

## Phase 4c Known Limitations

1. **pip `(manager, name)` collision.** See Decision #8. npm global packages installed
   into different `node_modules` directories have the same issue. gem version-pinned
   installs also produce the same name-collision scenario.

2. **`nearbyProjects` not implemented.** Always `[]`. Walking git repos near the
   package install path is post-v0.

3. **`ProvenanceCollector.collect()` is synchronous.** Calls `shellCollector.collect()`
   and `claudeCodeCollector.collect()` inline. Both are synchronous (they read files).
   Phase 5's app shell should dispatch to a background thread.

4. **Nil-timestamp records are excluded from matching.** A shell history entry with no
   timestamp cannot be time-correlated with `installedAt`. This means well-typed zsh
   bare-format entries (no `: <ts>:0;` prefix) never match, even if the command name
   matches. This is correct: a match without timestamp data would have `.unknown`
   confidence, which is worse than the `.low` from fs-only. If users request
   name-only matching as a separate feature, add it as a new confidence tier.

5. **`installTimeSource` is inferred from manager.** `brew`/`brewCask` → "INSTALL_RECEIPT.json",
   `pip` → "dist-info mtime", `npm` → "package.json mtime", others → "directory mtime".
   This matches the physical source of `Package.installedAt` for each scanner, but is
   hardcoded rather than carried on the `Package` model. If future scanners use
   different sources for the same manager, this will need updating.

---

## Phase 4c Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `ProvenanceCollector` — Claude Code ±1h → .high | Full | claudeCodeContext set, confidence .high |
| `ProvenanceCollector` — shell within 5 min → .high | Full | installCommand set, confidence .high |
| `ProvenanceCollector` — shell beyond 5 min → .medium | Full | |
| `ProvenanceCollector` — fs only → .low | Full | Both collectors empty |
| `ProvenanceCollector` — no fs mtime → .unknown | Full | installedAt nil; signals ignored |
| `ProvenanceCollector` — coInstalledWithin1h window | Full | ±1h window, sorted, no self-ref |
| `ProvenanceCollector` — manager+name key isolation | Full | brew shell cmd doesn't match pip pkg |
| `ProvenanceCollector` — nil-timestamp exclusion | Full | nil-ts shell + Claude records produce no match |
| `ProvenanceCollector` — Claude Code preferred over shell | Full | Both set; confidence still .high |
| `ProvenanceDAO` — upsert then fetch | Full | Round-trip field equality |
| `ProvenanceDAO` — upsert twice keeps latest | Full | Single row; updated fields verified |
| `ProvenanceDAO` — delete | Full | Fetch returns nil after delete |
| `ProvenanceDAO` — deleteAll | Full | COUNT(*) = 0 |
| `ProvenanceDAO` — fetch nonexistent | Full | Returns nil without error |
| `NarrativeRenderer` — Claude Code + summary | Full | Full context sentence |
| `NarrativeRenderer` — Claude Code + user message | Full | "You'd asked:" clause |
| `NarrativeRenderer` — Claude Code no summary | Full | Summary clause absent |
| `NarrativeRenderer` — shell only | Full | Backtick-quoted command |
| `NarrativeRenderer` — fs only | Full | File timestamp disclaimer |
| `NarrativeRenderer` — unknown | Full | Exact string match |
| `NarrativeRenderer` — co-installed 0 | Full | Clause absent |
| `NarrativeRenderer` — co-installed 1 | Full | Bare name |
| `NarrativeRenderer` — co-installed 2 | Full | "a and b" |
| `NarrativeRenderer` — co-installed 3+ | Full | Oxford comma |
| `NarrativeRenderer` — recent date relative | Full | No 4-digit year |
| `NarrativeRenderer` — old date absolute | Full | "Aug 14, 2024" format |
| `NarrativeRenderer` — co-installed name fallback | Full | Empty dict → last colon-segment |

---

## Questions for Phase 5 (App Shell)

1. **Sequencing: scan → persist packages → collect provenance → persist evidence.**
   `ProvenanceDAO.upsert` requires the `packages` row to exist first (FK constraint
   enforced by GRDB's default `DatabasePool` config). The app shell must call
   `ProvenanceDAO.upsert` only after `PackageDAO` (or equivalent) has written the
   package row.

2. **Consent gating for `~/.claude` access.** `ClaudeCodeLogCollector` is a passive
   reader with injected `DirectoryAccessProvider`. Phase 5 should wire the consent
   check: if the user hasn't granted permission, pass a no-op provider (or don't
   call `collect()`). See Phase 4b handoff for context.

3. **`ProvenanceCollector` background dispatch.** `collect()` is synchronous. The app
   shell should wrap it in `Task.detached` or `DispatchQueue.global().async` to avoid
   blocking the main actor.

4. **Re-run policy.** Decide whether `ProvenanceCollector` re-runs on every app launch
   (overwriting existing evidence via `upsert`) or only runs for packages with no
   existing evidence (`fetch` → skip if non-nil). The simplest policy is always-rerun;
   lazy-skip is an optimization.

5. **`nameByPackageId` dict at `NarrativeRenderer.render` call site.** Build it as:
   ```swift
   let nameByPackageId = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0.name) })
   ```
   This must be constructed from the full current package list, not just the package
   being rendered, so co-installed names resolve correctly.

6. **`nearbyProjects` signal.** Walk git repos within ~2 directory levels of the
   package install path and collect their remote URLs / project names. Populate
   `ProvenanceEvidence.nearbyProjects`. This is the last unimplemented signal from
   `provenance.md`.

---

# Phase 4b Handoff

## What Was Built

Phase 4b adds the Claude Code log provenance signal: walking `~/.claude/projects/`, parsing
session JSONL transcripts, and extracting every `Bash` tool_use that contains an install command.
`swift build` and `swift test` both pass: 221 tests, zero warnings, Swift 6 strict concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       ├── Models/
│       │   └── ProvenanceEvidence.swift  # CHANGED: ClaudeCodeContext gains Equatable
│       └── Provenance/
│           └── ClaudeCodeLogCollector.swift  # NEW: collector + InstalledByClaudeCode
└── Tests/
    └── BackshelfCoreTests/
        ├── Fixtures/
        │   └── claude-code/              # NEW directory
        │       └── projects/
        │           ├── -Users-will-projects-podcast-app/
        │           │   ├── sessions-index.json
        │           │   ├── abc-111-uuid.jsonl  # user msg + Read tool_use + ls + pip install; one malformed line
        │           │   └── def-222-uuid.jsonl  # user msg + brew install
        │           └── -Users-will-projects-my-app/
        │               └── ghi-333-uuid.jsonl  # user msg + npm install -g; cwd resolves -my-app ambiguity
        └── ClaudeCodeLogCollectorTests.swift  # NEW: 13 tests

HANDOFF.md                                # this file
```

---

## Phase 4b Decisions

### 1. `ClaudeCodeContext` gains `Equatable`

`InstalledByClaudeCode` is declared `Equatable` so tests can compare records directly. All
fields of `ClaudeCodeContext` are `Equatable` (`String`, `String?`, `Date`), so the conformance
is compiler-synthesised and zero-cost. No existing callsites break.

### 2. `JSONSerialization` instead of `Codable` for JSONL parsing

`Codable` handles well-defined schemas well but is fragile against the variations in
Claude Code's JSONL format across versions (user message `content` may be a plain string
or an array; the `sessionId` field may be absent in metadata-only events; future event
types add new keys). `JSONSerialization` with `as? [String: Any]` decoding is explicitly
tolerant: missing or wrong-typed fields are simply skipped via optional chaining. This is
the right trade-off for an unstable third-party format.

### 3. Two-pass parsing: first user message by minimum timestamp

The spec requires the "first" user message to be first-by-time, not first-by-position —
Claude Code sessions can contain out-of-order events in some edge cases. The first pass
walks each line string, parses minimally (only `timestamp`, `role`, and the first text
value), and tracks `(ts, text)` pairs. Only the minimum-timestamp pair is retained. This
pass uses O(1) auxiliary memory beyond the lines array itself. The second pass walks in
file order to extract Bash installs, using the result from the first pass.

### 4. `projectPath` from `cwd` field, not directory-name reconstruction

The `~/.claude/projects/` directory naming convention (`/` → `-`) is lossy: a project at
`/Users/will/projects/my-app` becomes `-Users-will-projects-my-app`, and naive
reconstruction turns it back into `/Users/will/projects/my/app` (wrong). Every JSONL event
carries a `cwd` field with the real project path. The second pass updates `projectPath`
in-place on each event that has a `cwd` value starting with `/`. The directory-name
reconstruction is the fallback only for sessions where no event has a `cwd` field.

### 5. `sessionId` field preferred over filename

Each JSONL event carries a top-level `sessionId` field. The collector uses that field and
falls back to the filename-derived ID only when the field is absent. If the field and
filename disagree (concatenated, corrupted, or manually edited file), the field wins —
document as a known limitation.

### 6. `ISO8601DateFormatter` created per session call

`ISO8601DateFormatter` is a class and `@unchecked Sendable`. Creating it inside
`parseSession()` (called once per JSONL file) avoids any cross-task shared-state concern
and costs negligible allocation. Options: `.withInternetDateTime | .withFractionalSeconds`
match the Claude Code timestamp format (`"2025-08-14T15:23:11.000Z"`).

### 7. `sessions-index.json` decoded loosely

`JSONSerialization` is used (not `Codable`) to extract only `id → summary` pairs. Missing
`summary`, wrong-typed fields, absent `sessions` key, or completely malformed JSON all
yield an empty summary map. The collector proceeds normally; affected sessions have
`sessionSummary: nil`.

---

## Phase 4b Known Limitations

1. **Directory-name fallback is lossy.** When a session has no `cwd` field (rare), the
   reconstructed path converts every `-` to `/`, corrupting paths that contain literal
   hyphens. The `cwd` override covers all real sessions observed; the fallback path is a
   defensive last-resort.

2. **`sessionId` field vs. filename divergence is silently resolved in favour of the field.**
   A JSONL where events have `sessionId` values that don't match the filename (concatenated
   or corrupted file) will produce records attributed to the wrong session ID. There is no
   warning mechanism; callers cannot detect this.

3. **`history.jsonl` at `~/.claude/history.jsonl` is not parsed.** This global history file
   contains commands from all sessions but lacks the rich session-context fields
   (`sessionSummary`, `firstUserMessage`). Deferred to post-v0.

4. **`collect()` is synchronous.** Reads each JSONL file inline. Files are typically small
   (<5 MB), but a user with years of dense Claude Code history could have large sessions.
   Same limitation as `ShellHistoryCollector`. Callers are responsible for dispatching to a
   background thread if needed.

5. **User messages with `content` as a plain string are handled in the first pass only.**
   The second pass (Bash extraction) uses `message["content"] as? [[String: Any]]`, which
   requires array content. Plain-string content cannot contain `tool_use` blocks anyway, so
   this is not a functional limitation.

---

## Phase 4b Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `ClaudeCodeLogCollector` — total count | Full | 3 records from 2 project dirs |
| `ClaudeCodeLogCollector` — cwd overrides path reconstruction | Full | `-Users-will-projects-my-app` → `/Users/will/projects/my-app` |
| `ClaudeCodeLogCollector` — podcast projectPath | Full | `/Users/will/projects/podcast-app` |
| `ClaudeCodeLogCollector` — sessionId from field | Full | `abc-111-uuid` |
| `ClaudeCodeLogCollector` — timestamp parsed | Full | ISO 8601 with ms |
| `ClaudeCodeLogCollector` — firstUserMessage by timestamp | Full | Earliest message, not file-position |
| `ClaudeCodeLogCollector` — firstUserMessage out-of-order | Full | Inline fixture with reversed event order |
| `ClaudeCodeLogCollector` — sessionSummary present | Full | From sessions-index.json |
| `ClaudeCodeLogCollector` — sessionSummary absent | Full | nil when no index |
| `ClaudeCodeLogCollector` — bashInvocation raw command | Full | Exact string match |
| `ClaudeCodeLogCollector` — non-install Bash filtered | Full | `ls -la` produces no record |
| `ClaudeCodeLogCollector` — non-Bash tool_use filtered | Full | `Read` tool_use excluded |
| `ClaudeCodeLogCollector` — malformed JSONL line skipped | Full | Other lines still parsed |
| `ClaudeCodeLogCollector` — missing projects directory | Full | Returns [] without crash |
| `ClaudeCodeLogCollector` — empty project directory | Full | No JSONL files → [] |
| `ClaudeCodeLogCollector` — malformed sessions-index.json | Full | summarySession nil; install still detected |

---

## Questions for Phase 4c (ProvenanceCollector + Persistence + NarrativeRenderer)

1. **Matching `InstalledByClaudeCode` to `Package` rows.** The natural key is
   `(packageName, manager)`. However, the same package name can appear in multiple
   contexts (e.g. `requests` installed in three different Pythons). For pip, the
   `projectPath`/`cwd` can narrow the interpreter. Decide whether the matcher should
   use `(name, manager, cwd)` for pip or fall back to date proximity.

2. **Preference ordering when both signals exist.** `provenance.md` says prefer the
   Claude Code match over the shell-history match when both are present for the same
   package. Implement this merge in `ProvenanceCollector`, not in either collector.

3. **Timestamp proximity matching.** Both `ShellHistoryCollector` and
   `ClaudeCodeLogCollector` produce records with timestamps. `ProvenanceCollector` needs
   a tolerance window (±1h per `provenance.md`) to match these to `Package.installedAt`.
   Define a shared helper or decide if the match runs per-manager.

4. **Consent gating.** `provenance.md` describes a first-launch consent flow for reading
   `~/.claude`. Phase 4b implemented `ClaudeCodeLogCollector` as a passive reader with
   injected `directoryAccess`. Phase 4c should wire the consent check: if the user has
   not granted permission, pass a no-op `DirectoryAccessProvider` (or simply don't call
   `collect()`). This is a policy decision for the app shell, not the library.

5. **`ProvenanceEvidence` persistence.** `ProvenanceEvidence` has GRDB conformances.
   `ProvenanceCollector` should write one record per package after all three signals are
   composed. Decide whether the collector re-runs on every app launch (and overwrites
   existing evidence) or only runs for packages with no existing evidence.

6. **`NarrativeRenderer` template selection.** The renderer needs to know which signals
   are present. Propose a `NarrativeInput` enum or a set of presence flags derived from
   `ProvenanceEvidence` so templates can be selected without inspecting optionals directly.

---

# Phase 4a Handoff

## What Was Built

Phase 4a adds the shell-history provenance signal: reading zsh, bash, and fish history files
and extracting install commands as structured `InstallCommandRecord` values.
`swift build` and `swift test` both pass: 205 tests, zero warnings, Swift 6 strict concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       ├── Models/
│       │   └── ProvenanceEvidence.swift  # CHANGED: InstallCommandRecord.timestamp → Date?
│       └── Provenance/                   # NEW directory
│           ├── InstallCommandDetector.swift  # NEW: parses a command line into (name, manager) tuples
│           └── ShellHistoryCollector.swift   # NEW: reads zsh/bash/fish history files
└── Tests/
    └── BackshelfCoreTests/
        ├── Fixtures/
        │   └── shell-history/            # NEW directory
        │       ├── zsh_history           # synthetic fixture: extended + bare format mix
        │       ├── bash_history          # synthetic fixture: with + without HISTTIMEFORMAT
        │       └── fish_history          # synthetic fixture: YAML-like cmd/when pairs
        ├── InstallCommandDetectorTests.swift  # NEW: 31 tests
        ├── ShellHistoryCollectorTests.swift   # NEW: 16 tests
        └── ModelTests.swift                   # +1 nil-timestamp Codable round-trip test

files/data-model.md                       # CHANGED: InstallCommandRecord.timestamp → Date?
HANDOFF.md                                # this file
```

---

## Phase 4a Decisions

### 1. `InstallCommandRecord.timestamp` changed to `Date?`

The existing model had `timestamp: Date` (non-optional). Every non-extended zsh line, every
bash command without a preceding `#<ts>` line, and every fish entry without a `when:` key
produces no timestamp. Forcing a non-nil `Date` there would have required inventing fake
timestamps (worse than honest uncertainty) or crashing on real input. Changed to `Date?`
with an explicit doc comment explaining when nil is expected. All existing callers already
access through the optional chain `evidence.installCommand?.timestamp`, so the only breakage
was at direct `InstallCommandRecord(timestamp:)` initialiser call sites — both were in test
factories, and `Date(…)` is assignable to `Date?` so they compiled unchanged.

### 2. `ShellCommand` intermediate struct skipped

`provenance.md` described a `ShellCommand` intermediate type. In practice, going directly
from a raw history line to `InstallCommandRecord` is simpler and loses nothing — the
`InstallCommandDetector` is already the correct place to check whether a command is an
install operation. `ShellCommand` was documentation-only before any code existed, and was
never committed. Note this when reading `provenance.md`: the doc's parser sketch no longer
matches the implementation, by design.

### 3. `InstallCommandDetector` uses token-based matching, not regex

The detector splits each command by whitespace and matches on token sequences
(`["brew", "install", "--cask"]`, `["pip3", "install"]`, etc.). This avoids compiling
regexes at call time and handles multiple consecutive spaces naturally. The tradeoff is
that the detector only matches the canonical flag position (e.g. `-g` must appear before
the package names in `npm install -g <pkg>`, not after). This matches the spec patterns
and covers all real-world common forms.

### 4. `brew reinstall --cask` maps to `.brew`, not `.brewCask`

The task spec lists `^brew reinstall\s+(.+)$ → .brew`. If someone writes
`brew reinstall --cask foo`, the `--cask` flag is skipped and `foo` is classified as `.brew`.
This is technically wrong (cask reinstalls exist), but follows the spec. If Phase 4c or the
UI layer needs accurate cask-reinstall attribution, `brew reinstall --cask` should be added
as a separate pattern above `brew reinstall` in `InstallCommandDetector`.

### 5. Fish history parser is line-by-line, not a real YAML parser

The fish history format is "YAML-like" — it uses two fixed prefixes: `- cmd: ` and
`  when: `. No other keys are examined. This is simpler and more robust than importing a
YAML library, which would be a new SPM dependency. Fish never emits keys other than `cmd`,
`when`, and `paths` in its history file, so line-by-line is sufficient for v0.

### 6. Bash comment lines do not clear a pending timestamp

A non-numeric `#` line (e.g., `# my comment`) is ignored. The pending HISTTIMEFORMAT
timestamp carries forward until it is consumed by the next command line. This is consistent
with how bash itself handles comments inside history: they do not produce commands and the
preceding timestamp still applies to the next real command.

---

## Phase 4a Known Limitations

1. **`pip install -r requirements.txt` produces no records.** The `-r` flag and the
   following argument are skipped. Reading the referenced file (which may no longer exist
   at the path recorded in history) introduces filesystem-access timing complexity.
   Deferred to post-v0.

2. **`brew install --cask` requires `--cask` as the third token.** `brew install
   --no-quarantine --cask foo` would classify `foo` as `.brew` because `--no-quarantine`
   occupies the third position. The spec pattern anchors `--cask` immediately after
   `install`, which covers the canonical form used by all Homebrew documentation.

3. **`brew reinstall --cask` → `.brew`, not `.brewCask`.** See Decision #4 above.

4. **Local-file installs (`.whl`, paths with `/`, `./`) are silently skipped.** Parsing
   wheel filenames and resolving relative paths requires knowing the shell's CWD at the
   time of the command, which history does not record reliably. Skipping is the honest
   choice.

5. **Multi-line zsh history entries are not handled.** Commands with backslash continuation
   (e.g., a `pip install` split across lines) appear as separate fragments; the install
   fragment would be detected if it forms a complete pattern by itself, but the package
   list may be truncated. Real install commands are almost always single-line, so this is
   acceptable for v0.

6. **`ShellHistoryCollector.collect()` is synchronous.** File reads block the calling
   thread. Shell history files are small (usually <10 MB) so this is acceptable. If
   `ProvenanceCollector` needs to call `collect()` from an actor context, the caller is
   responsible for dispatching to a background thread.

---

## Phase 4a Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `InstallCommandDetector` — brew install | Full | Formula, cask, legacy cask, reinstall |
| `InstallCommandDetector` — brew multi-package | Full | 3 packages → 3 records |
| `InstallCommandDetector` — pip / pip3 | Full | Both forms |
| `InstallCommandDetector` — python -m pip / python3 -m pip | Full | Both forms |
| `InstallCommandDetector` — uv pip install | Full | |
| `InstallCommandDetector` — pip flags ignored | Full | `--upgrade` skipped |
| `InstallCommandDetector` — version specifier == | Full | `requests==2.31.0` → `requests` |
| `InstallCommandDetector` — version specifier >= | Full | `requests>=1.0` → `requests` |
| `InstallCommandDetector` — extras stripped | Full | `requests[security]` → `requests` |
| `InstallCommandDetector` — -r requirements.txt | Full | Produces no records |
| `InstallCommandDetector` — pip multi-package | Full | 3 packages → 3 records |
| `InstallCommandDetector` — pipx install | Full | |
| `InstallCommandDetector` — npm install -g | Full | |
| `InstallCommandDetector` — npm i -g | Full | |
| `InstallCommandDetector` — npm without -g flag | Full | Produces no records |
| `InstallCommandDetector` — yarn global add | Full | |
| `InstallCommandDetector` — cargo install | Full | |
| `InstallCommandDetector` — gem install | Full | |
| `InstallCommandDetector` — mas install | Full | |
| `InstallCommandDetector` — non-install commands | Full | cd, vim, ls, git, empty, whitespace |
| `ShellHistoryCollector` — all three shells | Full | Record contains .zsh, .bash, .fish |
| `ShellHistoryCollector` — total count | Full | 14 records from 3 fixture files |
| `ShellHistoryCollector` — per-shell count | Full | zsh=6, bash=4, fish=4 |
| `ShellHistoryCollector` — missing zsh | Full | Skips silently; bash+fish present |
| `ShellHistoryCollector` — missing bash | Full | Skips silently; zsh+fish present |
| `ShellHistoryCollector` — missing fish | Full | Skips silently; zsh+bash present |
| `ShellHistoryCollector` — empty home | Full | Returns empty array |
| `ShellHistoryCollector` — zsh extended timestamp | Full | `brew install ffmpeg` at ts=1715000000 |
| `ShellHistoryCollector` — zsh malformed header | Full | `brew install wget` → nil timestamp |
| `ShellHistoryCollector` — zsh bare format | Full | `gem install bundler` → nil timestamp |
| `ShellHistoryCollector` — bash HISTTIMEFORMAT | Full | `npm install -g prettier` at ts=1715000100 |
| `ShellHistoryCollector` — bash no timestamp | Full | `brew install jq` → nil timestamp |
| `ShellHistoryCollector` — bash orphaned timestamp | Full | No extra record emitted |
| `ShellHistoryCollector` — fish `when` field | Full | `brew install --cask vscode` at ts=1715000200 |
| `ShellHistoryCollector` — fish missing `when` | Full | `cargo install bat` → nil timestamp |
| `ShellHistoryCollector` — no-install history | Full | Returns empty array |
| `ProvenanceEvidence` — nil timestamp Codable | Full | Round-trips correctly; key absent in JSON |

---

## Questions for Phase 4b (ClaudeCodeLogCollector)

1. **JSONL parsing strategy.** Each session file is a JSONL (one JSON object per line).
   The collector needs to walk `~/.claude/projects/*/` directories and read each
   `<session-uuid>.jsonl`. `DirectoryAccessProvider.contentsOfDirectory` is the right
   primitive; the walker should be tolerant of non-JSONL files (skip them).

2. **`sessions-index.json` field names.** The `provenance.md` design references
   `sessionSummary` from `sessions-index.json`. The exact field names in the real file
   need to be confirmed by reading an actual `sessions-index.json` on a populated machine.
   Save a sanitised example as a fixture before writing the parser.

3. **Project path reconstruction.** Directory names under `~/.claude/projects/` are the
   project path with `/` replaced by `-`. The reverse transform is
   `directoryName.replacingOccurrences(of: "-", with: "/")` prefixed with `/`. Edge case:
   a project path that contains a literal `-` becomes ambiguous. Decide whether to use the
   `cwd` field in the JSONL event (more reliable) or the directory name (simpler).

4. **Tool-use filtering.** Only `tool_use` events with `name == "Bash"` are relevant.
   The `input.command` field contains the command. Other tool types (`Read`, `Edit`,
   `Write`, etc.) should be silently skipped.

5. **Timestamp format.** The example in `provenance.md` shows
   `"timestamp": "2025-08-14T15:23:11.000Z"` — ISO 8601 with milliseconds. Confirm
   this format matches actual files before hard-coding the `DateFormatter` strategy.

6. **Privacy gating.** `provenance.md` describes a first-launch consent flow for reading
   `~/.claude`. Phase 4b should implement `ClaudeCodeLogCollector` as a passive reader
   (no writes, no network); the consent UI is Phase 5 scope. For Phase 4b, inject
   `directoryAccess` and `claudeDirectory` the same way `ShellHistoryCollector` injects
   `homeDirectory`.

---

# Phase 3a Handoff

## What Was Built

Phase 3a adds `Denylist` and `ScriptGenerator` — the first half of Phase 3 (cleanup script
generation). `swift build` and `swift test` both pass: 157 tests, zero warnings, Swift 6 strict
concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       └── Cleanup/
│           ├── Denylist.swift          # NEW: DenylistEntry + Denylist struct
│           └── ScriptGenerator.swift  # NEW: SnapshotContext + GeneratedScript + ScriptGenerator
└── Tests/
    └── BackshelfCoreTests/
        ├── DenylistTests.swift         # NEW: 14 tests
        └── ScriptGeneratorTests.swift  # NEW: 21 tests

HANDOFF.md                             # this file
```

---

## Phase 3a Decisions

### 1. `set -euo pipefail` not `set -e`

safety.md wins over the initial prompt. `-e` exits on error, `-u` errors on unset variables,
`-o pipefail` propagates failures through pipes. Strictly more defensive.

### 2. `echo "→ <command>"` before every active command

Each command is preceded by an echo line so the user sees what is about to run before
it runs. Double-quote characters that appear in the command (e.g., pip's interpreter path,
npm's package name) are escaped as `\"` in the echo string; `\`, `` ` ``, and `$` are also
escaped to prevent bash expansion inside the echo's double-quoted context.

### 3. Denylist warning section at the bottom of the script

All denylisted packages — regardless of manager — are collected into a single WARNING
block at the end of the script, not interleaved with the per-manager sections. This keeps
the "safe to copy-paste as-is" portion clean: everything above the WARNING block is
active; everything below it is commented out for the user to opt into consciously.

### 4. `SnapshotContext` parameter, not `SnapshotManager` dependency

`ScriptGenerator` is a pure value type. It accepts `snapshot: SnapshotContext? = nil` —
a `(UUID, Date)` pair that appears in the script header — so the script can reference the
snapshot without `ScriptGenerator` knowing about the database. The snapshot contract is
documented on `generate(packages:snapshot:)` via a doc comment: callers MUST capture a
snapshot before calling this method.

### 5. Pip sections grouped per interpreter

Pip packages from different interpreters each get their own section header:
`# === pip (interpreter: /path/to/python) ===`. This keeps the uninstall commands
co-located with the interpreter that owns the packages, which is important because the
interpreter path is embedded in the command itself.

### 6. Denylist as hardcoded Swift struct, JSON bundle deferred

For Phase 3a (pure SPM library, no `Bundle.main`), the 17 default entries are hardcoded
in `Denylist.default`. Migration path to JSON: decode `[DenylistEntry]` from a bundled
resource and pass to `Denylist(entries:)`. Documented in `Denylist.swift`.

### 7. Topological sort direction

Edge A → B means "A depends on B, so A is removed first." Kahn's algorithm begins with
nodes whose in-degree is 0 among the selected set (nothing selected depends on them). These
are removed first, then their dependencies, and so on — exactly the safe uninstall order.
Cycles are detected as nodes that remain after the traversal; they are emitted with a
`# WARNING: dependency cycle detected` comment on the line immediately preceding them.

### 8. Canonical manager output order

`brew → brewCask → pip → npm → pipx → cargo → gem → mas`

Managers not in this list (added in future phases) are appended alphabetically by raw value.

---

## Phase 3a Known Limitations

1. **No `SnapshotManager` integration.** The `generate(packages:snapshot:)` contract places
   the snapshot obligation on the caller. Phase 3b or the app shell must call
   `await snapshotManager.capture(packages:reason:note:)` before generating a script and
   pass the result as `SnapshotContext`.

2. **Denylist is hardcoded.** The 17 default entries cover brew, pip, and npm essentials.
   Adding entries requires a code change until the JSON-bundle loading path is wired up.
   No UI for user-editable denylist yet.

3. **`mas` uninstall is comment-only.** mas has no CLI uninstall command. Mas packages
   appear as comment lines in both the active section and the denylist section. If mas
   support needs an `open` or `trash` command in the future, `renderCommand` is the right
   place to add it.

4. **Cross-manager dependency edges are ignored.** The topological sort operates strictly
   within a single `(manager, qualifier)` group. A brew formula that a pip package depends
   on will not affect ordering. This matches the spec: cross-manager deps are not modelled.

5. **Pip `qualifier == nil` fallback uses `"python3"`.** If a pip package somehow has a
   nil qualifier (should not happen with current scanners), the command uses `"python3"` as
   the interpreter. This is a defensive fallback, not an expected code path.

6. **Echo arrow character.** The `→` (U+2192) is embedded as a literal UTF-8 character in
   the echo line. It renders correctly in all modern terminal emulators. If a user has a
   terminal that doesn't support Unicode, they will see a replacement character before the
   command text — cosmetic only, does not affect script execution.

---

## Phase 3a Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `Denylist` — default brew matches (git, curl, openssl) | Full | 3 dedicated tests |
| `Denylist` — python@* glob (3.10, 3.12, 3.13) | Full | All three variants |
| `Denylist` — pip matches (pip, setuptools) | Full | |
| `Denylist` — npm matches (npm, corepack) | Full | |
| `Denylist` — non-match returns false | Full | jq, "python" without @ |
| `Denylist` — wrong manager isolation | Full | pip "git" ≠ brew "git" |
| `Denylist` — reason(for:) | Full | Returns string / nil |
| `Denylist` — custom entries + glob | Full | |
| `ScriptGenerator` — empty package list | Full | Header only, no uninstall |
| `ScriptGenerator` — brew formula command + echo | Full | |
| `ScriptGenerator` — brew cask + artifactPaths comments | Full | Position-verified |
| `ScriptGenerator` — pip command uses qualifier as interpreter | Full | |
| `ScriptGenerator` — pip path with spaces | Full | Quoting verified |
| `ScriptGenerator` — npm command | Full | |
| `ScriptGenerator` — scoped npm (@types/node) | Full | |
| `ScriptGenerator` — read-only filtered out | Full | Absent + in skippedReadOnly |
| `ScriptGenerator` — denylisted commented at bottom | Full | Active absent, comment present |
| `ScriptGenerator` — denylist section after active section | Full | Position verified |
| `ScriptGenerator` — python@3.12 glob match | Full | |
| `ScriptGenerator` — dependency ordering (A before B) | Full | Range position verified |
| `ScriptGenerator` — independent packages both included | Full | |
| `ScriptGenerator` — dependency cycle warning | Full | Warning + both packages emitted |
| `ScriptGenerator` — multiple managers, correct headers | Full | Order: brew < pip < npm |
| `ScriptGenerator` — SnapshotContext in header | Full | UUID appears in script |
| `ScriptGenerator` — no snapshot → no snapshot lines | Full | |
| `ScriptGenerator` — set -euo pipefail preamble | Full | |
| `ScriptGenerator` — trailing newline | Full | |

---

## Questions for Phase 3b

1. **Snapshot integration at the call site.** The app shell (or a future `CleanupCoordinator`)
   needs to call `await snapshotManager.capture(packages:reason:note:)` and pass the result
   as `SnapshotContext` before invoking `ScriptGenerator.generate`. The contract is
   documented on the method; Phase 3b should wire the call site.

2. **`mas` uninstall UX.** Currently, mas packages get a comment-only line. Phase 3b should
   decide whether to emit an `open -a "App Store"` helper comment, point to the app's path,
   or keep the current minimal comment.

3. **Denylist JSON bundle.** When Phase 5 adds the Xcode target, `Denylist.default` should
   be loaded from `Bundle.main.url(forResource:withExtension:)` so operations staff can
   add entries without a code change.

4. **`pipx`, `cargo`, `gem` scanners.** These managers are handled by `ScriptGenerator`
   (commands emit correctly), but their scanners aren't implemented yet. Phase 3b or the
   post-v0 future work list should track this.

5. **User-editable denylist.** A power user may want to permanently skip certain packages
   (e.g., always skip `node` even if explicitly selected). The `Denylist(entries:)` API is
   ready; the UI and persistence layer for edits are Phase 5+ scope.

6. **Reinstall script generation.** `safety.md` describes generating reinstall scripts from
   snapshots (the additive counterpart to cleanup). This is the obvious next primitive to
   build after Phase 3a, since `ScriptGenerator` already has the per-manager command shapes.

---

# Phase 2d Handoff

## What Was Built

Phase 2d closes out Phase 2 by adding `withTimeout`, `SnapshotManager`, and `ScanCoordinator`.
`swift build` and `swift test` both succeed — 122 tests, zero warnings, Swift 6 strict concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       ├── Foundation/
│       │   └── Timeout.swift                   # NEW: withTimeout + TimeoutError
│       ├── Snapshots/
│       │   └── SnapshotManager.swift           # NEW: actor — capture / list / snapshot(id:) / delete
│       └── Scanners/
│           └── ScanCoordinator.swift           # NEW: ScanEvent enum + ScanCoordinator actor
└── Tests/
    └── BackshelfCoreTests/
        ├── TimeoutTests.swift                  # NEW: 3 tests
        ├── SnapshotManagerTests.swift          # NEW: 6 tests
        └── ScanCoordinatorTests.swift          # NEW: 6 tests

HANDOFF.md                                      # this file
```

---

## Phase 2d Decisions Where Docs Were Ambiguous

### 1. `withTimeout` drain loop prevents `CancellationError` propagation

`withThrowingTaskGroup` re-throws errors from remaining child tasks when the body
returns normally (Swift docs: "rethrows errors from child tasks only if the body
finishes without throwing"). After `group.next()!` returns the winning result and
`group.cancelAll()` cancels the peer, the cancelled sleep/operation task throws
`CancellationError`. Without a drain, `withThrowingTaskGroup` would surface this
as the function's return value.

Fix: `do { while try await group.next() != nil {} } catch {}` — consumes the
cancelled task and discards its `CancellationError`. The `while` loop exits when
`group.next()` returns nil (group empty) or throws (caught and discarded). For our
always-two-task setup, exactly one task is drained.

### 2. `Task.detached` in `ScanCoordinator.scan()`

`scan()` is actor-isolated (non-async). The `AsyncStream.init` closure runs
synchronously in that context. Using plain `Task { }` inside it inherits the actor's
isolation context, which means the task body and the `for await in group` collection
loop would run on the actor's executor, serialising against other actor messages.
`Task.detached` avoids this: the scanning work runs entirely on the global cooperative
executor. The actor's state is captured as local variables (`scanners`, `timeouts`)
before the `AsyncStream.init` closure is entered, so no actor-state access occurs
after the detach.

### 3. `ScanEvent.scannerStarted` ordering guarantee

`scannerStarted` is yielded inside each child task (in `group.addTask { }`) before
`scanner.scan()` is awaited. This guarantees that for any given manager, `started`
is always emitted before `finished` — they're sequential within the same task. Across
managers, events can interleave freely, which is expected concurrent behaviour. Tests
verify the per-manager ordering invariant.

### 4. `withTaskGroup` (non-throwing) for `ScanCoordinator`

Each child task catches all errors (`catch is TimeoutError` / `catch`) and always
returns a `(PackageManager, ScannerStatus, [Package])` tuple. Because no task can
propagate an unhandled throw, `withTaskGroup` (not `withThrowingTaskGroup`) is
correct here and avoids any need for error handling in the group body.

### 5. `SnapshotManager` uses GRDB's `Column` API for ordered queries

`Snapshot.order(Column("created_at").desc).fetchAll(db)` — GRDB's query-builder
ordering rather than raw SQL. Both work; the query builder is preferred for
type-safety and readability. `Snapshot` gains ordering for free because
`PersistableRecord` inherits `TableRecord` which enables the query builder API.

### 6. Schema is already correct from Phase 0 — no new migration needed

Verified: `snapshots` table (id TEXT PK, created_at REAL, reason TEXT, note TEXT,
payload TEXT) in `v1_initial` exactly matches `Snapshot`'s `FetchableRecord` /
`PersistableRecord` row-codec. No Phase 2d migration was added.

### 7. `durationMs` measurement uses `Date()` wall clock

`let start = Date()` before yielding `.scannerStarted`, `Int(Date().timeIntervalSince(start) * 1000)` after scanning completes. Minimum is 0 ms (clock granularity); tests assert `>= 0`. A monotonic clock would be more correct but `Date()` is sufficient for diagnostic display purposes and consistent with the existing codebase.

---

## Phase 2d Known Limitations

1. **`ScanCoordinator` has no default scanner list.** The initialiser takes
   `[any PackageScanner]` explicitly. Phase 3 or the App shell will wire up the
   concrete scanner instances with their real `DirectoryAccessProvider` and
   `PathDiscovery` dependencies.

2. **`SnapshotManager` GRDB operations block the actor's executor.** `database.pool.write/read` are synchronous GRDB calls. For fast operations (snapshot table is small), this is acceptable. If the user's snapshot table grows large, consider async GRDB reads in a future phase.

3. **`ScanCoordinator` does not persist a `ScanRun`.** `ScanRun` exists in the schema for diagnostics, but `ScanCoordinator` currently only yields `ScanEvent`s. Phase 3 or the app shell is responsible for constructing and writing a `ScanRun` record from the `allFinished` event payload.

4. **Default timeout map is a static constant.** The spec lists defaults for `.brew`,
   `.brewCask`, `.pip`, `.npm`, `.pipx`, `.cargo`, `.gem`, `.mas`. Managers not in
   this map fall back to 30s. Post-v0 managers (`.conda`, `.pnpm`, `.bun`) get 30s
   by default, which is fine since their scanners aren't implemented yet.

5. **`ScanCoordinator` calls `isAvailable()` is not implemented.** The coordinator runs every scanner in the list unconditionally. Callers are expected to filter the scanner list before passing it to `ScanCoordinator.init`. Alternatively, Phase 3 can add an `isAvailable()` check inside the task, turning unavailable scanners into `.skipped` status.

---

## Phase 2d Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `withTimeout` — success path | Full | Returns operation's value |
| `withTimeout` — timeout path | Full | Throws `TimeoutError`; 50ms timeout, 200ms operation |
| `withTimeout` — own error propagation | Full | MyError propagates; TimeoutError NOT thrown |
| `SnapshotManager.capture` + `list` | Full | Snapshot appears in list with correct fields |
| `SnapshotManager.list` ordering | Full | Newest-first; two captures with sleep between |
| `SnapshotManager.snapshot(id:)` round-trip | Full | Payload manager groupings verified |
| `SnapshotManager.delete` | Full | Snapshot removed from list |
| `SnapshotManager.capture` empty payload | Full | Empty package list → empty managers dict |
| `SnapshotManager.capture` GRDB persistence | Full | Raw SQL query against snapshots table |
| `ScanCoordinator` all succeed | Full | `allFinished` count + per-manager `.succeeded` |
| `ScanCoordinator` one throws | Full | `.failed` for thrower; `.succeeded` for others |
| `ScanCoordinator` one times out | Full | `.timedOut` at 50ms; `.succeeded` for others |
| `ScanCoordinator` empty list | Full | Single `.allFinished` event with empty state |
| `ScanCoordinator` event ordering | Full | `.scannerStarted` index < `.scannerFinished` index for both managers |
| `ScanCoordinator` durationMs | Full | `>= 0` for `.succeeded`, `.failed`, `.timedOut` |

---

## Questions for Phase 3

1. **`ScanCoordinator` default scanner list.** Phase 3 should define a factory or
   registry that constructs the full scanner set with real `DirectoryAccessProvider`
   and `PathDiscovery` instances. The coordinator takes `[any PackageScanner]` so any
   composition pattern works.

2. **`ScanRun` persistence.** The app shell or a coordinator wrapper should capture the
   `allFinished` event payload and write a `ScanRun` to the database. `ScanCoordinator`
   is deliberately free of database knowledge.

3. **`isAvailable()` filter.** Decide whether `ScanCoordinator` should call
   `isAvailable()` on each scanner before adding it to the task group (emitting
   `.skipped` for unavailable managers), or whether this filtering lives outside the
   coordinator. The current design leaves it to the caller.

4. **`SnapshotManager.capture(packages:reason:note:)` call site.** `safety.md` Rule 1
   mandates a snapshot before any cleanup script. The call site in `ScriptGenerator`
   (Phase 4/5) needs to `await snapshotManager.capture(...)` before generating. Make
   sure the actor-hop is properly `await`-ed at that boundary.

5. **Cleanup-script generation (Phase 3).** `safety.md` specifies read-only filter,
   denylist, dependency ordering, and the `set -euo pipefail` preamble. The
   `SnapshotManager.capture → ScriptGenerator.build` pipeline is now unblocked.

---

# Phase 2c Handoff

## What Was Built

Phase 2c adds `NpmScanner` — walks known global `node_modules` directories and reads each package's `package.json` directly. `swift build` and `swift test` both succeed — 107 tests, zero warnings, Swift 6 strict concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       └── Scanners/
│           └── NpmScanner.swift                # NEW: NpmScanner conforming to PackageScanner
└── Tests/
    └── BackshelfCoreTests/
        ├── Fixtures/
        │   └── npm/
        │       ├── opt/homebrew/lib/node_modules/
        │       │   ├── typescript/package.json  # regular package; has deps + devDeps + peerDeps
        │       │   └── @types/node/package.json # scoped package; no dependencies
        │       └── .nvm/versions/node/v20.0.0/lib/node_modules/
        │           └── lodash/package.json      # nvm-managed package; no dependencies
        └── NpmScannerTests.swift               # NEW: 8 tests

HANDOFF.md                                      # this file
```

---

## Phase 2c Decisions Where Docs Were Ambiguous

### 1. `dependencies` sorted for snapshot stability

`package.json`'s `"dependencies"` object is a JSON dictionary; Swift's `JSONDecoder` does not preserve key order. Without sorting, consecutive scans of the same package could produce different ordering in `Package.dependencies`, breaking snapshot diffing and change detection downstream. `NpmScanner` sorts dependency keys before assigning them. This is the first scanner that pulls deps from a JSON object rather than a JSON array (brew uses ordered `runtime_dependencies` array) — sorting is set as the precedent for any future JSON-object-sourced dep lists.

### 2. Missing `version` field → skip package

`Package.version` is non-optional (`String`). If a `package.json` has no `version` field (malformed or non-standard), `makePackage` returns `nil` and that package is silently skipped. Using `""` as a fallback was explicitly rejected: empty-version packages cause problems in snapshot comparison, sort order, and change detection. Documented as known behavior in Known Limitations below.

### 3. `description` not parsed from `package.json`

`Package` has no `description` field — descriptions come from `DescriptionStore` (a separate Phase 3+ concern). `NpmScanner` reads only `name`, `version`, and `dependencies` from `package.json`. This mirrors `BrewScanner`, which does not store brew formula descriptions either.

### 4. `homeDirectory` injection for nvm/Volta discovery

Same pattern as `PythonInterpreterDiscovery`: `homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())`, defaulting to the real home directory in production. Tests pass `URL(fileURLWithPath: "/")` so that fixture paths like `/.nvm/versions/node/v20.0.0/...` are found without touching the real filesystem.

### 5. Static dirs always in candidate list; missing dirs silently skipped

`/opt/homebrew/lib/node_modules` and `/usr/local/lib/node_modules` are always included in `nodeModulesDirs()`. Dirs that don't exist cause `contentsOfDirectory` to throw; `packagesIn` catches this and returns `[]`. No explicit `fileExists` gate in `scan()` — same pattern as `BrewScanner` (`packagesIn(subdirectory:)` catches the missing-dir error).

### 6. `isAvailable()` checks `fileExists` against the full candidate list

Calls `nodeModulesDirs()` (which also enumerates nvm/Volta versions) and returns `true` if any candidate directory passes `fileExists`. This is slightly heavier than brew's prefix check but consistent with pip's `discover()` call inside `isAvailable()`.

---

## Phase 2c Known Limitations

1. **Packages with no `version` in `package.json` are silently dropped.** This is intentional (see Decision #2). If a user has a self-published or patched global package without a version field, it won't appear in the inventory. Unlikely in practice for standard npm globals.

2. **`installedAt` is `nil` in all tests.** `InMemoryDirectoryAccessProvider.modificationDate` always returns `nil`. Real scans return the mtime of `package.json`. `installedAtConfidence` is correctly `.low` in all cases.

3. **`isExplicit` is always `true` for npm packages.** npm has no `installed_on_request` equivalent for global installs. All globally installed packages are treated as explicit.

4. **pnpm, bun, yarn global installs are not scanned.** Documented as post-v0 in `scanners.md`. These managers use different directory layouts or symlink structures that require separate scanner implementations.

5. **`isAvailable()` and `scan()` both call `nodeModulesDirs()`**, which enumerates nvm/Volta version directories. If `ScanCoordinator` calls both, directory enumeration runs twice. Acceptable since it's synchronous and fast. Same tradeoff as PipScanner's double `discover()` call.

---

## Phase 2c Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `NpmScanner.scan` — count | Full | 3 packages from 2 fixture node_modules dirs |
| `NpmScanner.scan` — scoped package name | Full | `@types/node` name and id verified |
| `NpmScanner.scan` — scoped package id format | Full | `npm:/opt/homebrew/lib/node_modules:@types/node` |
| `NpmScanner.scan` — qualifier | Full | All packages have qualifier = node_modules path |
| `NpmScanner.scan` — id format | Full | `id.hasPrefix("npm:<qualifier>:")` for all |
| `NpmScanner.scan` — manager | Full | All `.npm` |
| `NpmScanner.scan` — dependencies key filtering | Full | typescript fixture: devDeps + peerDeps excluded |
| `NpmScanner.scan` — same name, two installations | Full | Two distinct Package rows, different ids |
| `NpmScanner.scan` — empty filesystem | Full | Returns [] |
| `NpmScanner.scan` — malformed package.json | Full | Invalid JSON skipped; valid package in same dir returned |
| `NpmScanner.scan` — isExplicit | Covered indirectly | Always true; verified by fixture tests |
| `NpmScanner.scan` — installedAtConfidence | Covered indirectly | Always .low; verified by fixture tests |
| `NpmScanner.isAvailable` | Not tested directly | Tested implicitly via scan; explicit test deferred |

---

## Questions for Phase 2d

1. **ScanCoordinator registration.** `NpmScanner` needs to be registered in `ScanCoordinator`'s default scanner list. The 15s default timeout from `scanners.md` should be wired up.

2. **`nodeModulesDirs()` double-call.** If `ScanCoordinator` calls `isAvailable()` then `scan()`, nvm/Volta version enumeration runs twice. Consider a lazy-cached property or having `ScanCoordinator` skip the `isAvailable()` check for npm specifically.

3. **`isExplicit` for npm.** Like pip, there's no install-receipt signal. Always `true`. Decide before Phase 2d whether to attempt a two-pass dep-tagging approach (cross-reference `dependencies` of other installed packages) or document the gap in the UI.

4. **Package name vs. directory name divergence.** `Package.name` uses `json.name ?? directoryName`. For well-formed packages these are equal. If they diverge (corrupted or developer-patched install), the id uses the directory-derived name but `Package.name` shows the JSON name. Decide whether to enforce consistency (always use directory name) or leave the current behavior.

5. **`version` field absent → package skipped.** This is intentional but invisible to the user. If the gap between discovered directories and returned packages is surprising during debug, consider logging a warning to `ScanRun.perManagerResults` when packages are skipped for this reason.

---

# Phase 2b Handoff

## What Was Built

Phase 2b adds `PipScanner` — the orchestration layer that connects `PythonInterpreterDiscovery`
and `DistInfoParser` into the `PackageScanner` protocol. `swift build` and `swift test` both succeed —
99 tests, zero warnings, Swift 6 strict concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       └── Foundation/
│           ├── DirectoryAccessProvider.swift   # + modificationDate(at:) -> Date?
│           └── DistInfoParser.swift            # DistInfo gains requiresDist: [String]
│           PipScanner.swift                    # NEW: PipScanner conforming to PackageScanner
└── Tests/
    └── BackshelfCoreTests/
        ├── Fixtures/
        │   └── python/
        │       └── .pyenv/versions/3.11.7/…/requests-2.31.0.dist-info/METADATA
        │           # Extended: +4 Requires-Dist headers with version constraints
        │           # and environment markers, to exercise dependency stripping
        ├── Support/
        │   └── InMemoryDirectoryAccessProvider.swift  # + modificationDate always nil
        └── PipScannerTests.swift               # NEW: 12 tests

HANDOFF.md                                     # this file
```

---

## Phase 2b Decisions Where Docs Were Ambiguous

### 1. `modificationDate(at:)` added to `DirectoryAccessProvider`

`PipScanner` needs dist-info directory mtimes for `installedAt`. Added
`modificationDate(at:) -> Date?` to the protocol. `SystemDirectoryAccessProvider`
delegates to `FileManager.attributesOfItem`. `InMemoryDirectoryAccessProvider`
always returns `nil` (no mtime tracking in the fake). This keeps `installedAt`
optional and `installedAtConfidence` always `.medium` regardless of whether
mtime was readable.

### 2. `DistInfo` gains `requiresDist: [String]`

Added as a defaulted parameter (`= []`) so existing callsites (including all
existing tests) compile unchanged. `DistInfoParser` extracts `Requires-Dist`
values via a separate pass over the raw header text — the existing
`parseHeaders` dict is left-as-is (last-value-wins for duplicate keys) because
changing it would risk breaking the block-description logic.

### 3. `Requires-Dist` stripping

Format: `<name> [(<version_spec>)] [; <env_marker>]`. `PipScanner` strips
everything from the first occurrence of `(`, `;`, or whitespace onwards, leaving
only the bare package name. Implemented as `private static func barePackageName`.
Exercised by four fixture entries in `requests-2.31.0.dist-info/METADATA`.

### 4. `isExplicit` always `true` for pip — known limitation

pip has no `installed_on_request` equivalent. `PipScanner` sets `isExplicit: true`
for every package. This means pip dependency packages are indistinguishable from
top-level user installs. Documented as a known limitation (see below).

### 5. `PipScanner` injects `PythonInterpreterDiscovery` + `DistInfoParser` + `DirectoryAccessProvider`

Following the BrewScanner pattern: all three are injected with production defaults.
In tests, the same `InMemoryDirectoryAccessProvider` is passed to all three so
fixture data is consistent. `isAvailable()` and `scan()` both call
`discovery.discover()` — if called together they run discovery twice; acceptable
since discovery is synchronous file-existence checks.

### 6. System Python `isReadOnly` tested with a custom provider

The fixture system Python (`/usr/bin/python3`) has no site-packages by design
(the existing `PythonInterpreterDiscovery` test asserts `sitePackages.isEmpty`).
Adding packages to the system fixture would break that test. Instead,
`PipScannerTests.systemPackagesAreReadOnly` builds a minimal custom provider with
a fake system Python that does have a package. This is cleaner than touching the
shared fixture.

---

## Phase 2b Known Limitations

1. **`isExplicit` is always `true` for pip packages.** pip tracks installation
   metadata in `METADATA` but has no field equivalent to Homebrew's
   `installed_on_request`. The closest approximation would be to cross-reference
   `Requires-Dist` of other installed packages and mark anything that appears
   only as a transitive dependency as `isExplicit: false`. This is deferred:
   it requires a two-pass algorithm and is fragile (a package may be both a
   user install and a dep of another package). See Phase 2c or later.

2. **`installedAt` is `nil` in all tests.** `InMemoryDirectoryAccessProvider`
   returns `nil` from `modificationDate`. Real scans return real mtimes.
   `installedAtConfidence` is correctly set to `.medium` in all cases.

3. **`DistInfoParser.parseHeaders` is last-value-wins for duplicate keys.**
   For `Requires-Dist`, `PipScanner` now uses a separate extraction pass. Any
   other multi-value PEP 566 field (e.g., `Classifier`) would need the same
   treatment. Not a problem for v0.

4. **Discovery runs twice when `isAvailable` + `scan` are both called.**
   Acceptable for now since discovery is synchronous and fast. If
   `ScanCoordinator` calls both, consider caching the result.

---

## Phase 2b Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `PipScanner.scan` — count | Full | 3 packages from 2 fixture interpreters |
| `PipScanner.scan` — id format | Full | Exact format `pip:<path>:<name>` verified |
| `PipScanner.scan` — qualifier | Full | Matches executable path |
| `PipScanner.scan` — manager | Full | All `.pip` |
| `PipScanner.scan` — isReadOnly false | Full | pyenv + homebrew packages not read-only |
| `PipScanner.scan` — isReadOnly true | Full | System Python packages marked read-only (custom provider) |
| `PipScanner.scan` — isExplicit | Full | Always true |
| `PipScanner.scan` — dependencies stripped | Full | version constraints + env markers stripped; 4 entries for requests |
| `PipScanner.scan` — no Requires-Dist | Full | urllib3 gets empty deps |
| `PipScanner.scan` — installedAtConfidence | Full | Always .medium |
| `PipScanner.scan` — installPath | Full | Points to .dist-info directory |
| `PipScanner.scan` — multi-interpreter duplicates | Full | Same package in two pyenv versions → 2 distinct rows |
| `PipScanner.scan` — empty filesystem | Full | Returns [] |
| `PipScanner.scan` — missing site-packages | Full | System Python in fixture has no packages; scan completes without crash |
| `DirectoryAccessProvider.modificationDate` | Covered indirectly | System impl exercised by real filesystem; fake always returns nil |
| `DistInfo.requiresDist` | Covered | requests fixture has 4 entries, stripped correctly |

---

## Questions for Phase 2c

1. **NpmScanner.** The prompt constrains Phase 2b to PipScanner only. Phase 2c
   adds NpmScanner. Key decision: how does `PathDiscovery` surface nvm/Volta/
   Homebrew node roots? `ManagerDirectory` enum may need new cases.

2. **`isExplicit` for pip.** See Known Limitation #1. Decide before Phase 2d
   (ScanCoordinator + snapshotting) whether to implement the two-pass dep-tagging
   or just leave it as always-true and document the gap in the UI.

3. **`PipScanner.isAvailable` calls `discover()` again.** If `ScanCoordinator`
   calls `isAvailable()` before `scan()`, discovery runs twice. Consider caching
   `discover()` result inside `PipScanner` or having `ScanCoordinator` not call
   `isAvailable()` for pip specifically.

4. **pipx and uv package scanning.** The enum cases exist. Phase 2c or 2d should
   decide whether pipx packages are scanned via `PipScanner` (since they're also
   `.dist-info` directories) or a dedicated `PipxScanner`.

5. **`modificationDate` for directory vs. file.** The protocol now has
   `modificationDate(at:)`. For dist-info directories, this is the mtime of the
   directory itself. Some filesystems have coarse mtime granularity. If users
   report confusing install times, consider using the mtime of `RECORD` or
   `METADATA` within the dist-info as an alternative signal.

---

# Phase 2a Handoff

## What Was Built

Phase 2a adds the Python scanner foundations only: interpreter discovery and
`.dist-info` parsing. No `PipScanner`, `NpmScanner`, `SnapshotManager`, UI, shell
execution, networking, or new SPM dependencies were added. `swift build` and
`swift test` both succeed — 82 tests, zero warnings, Swift 6 strict concurrency.

```
Backshelf/
├── Sources/
│   └── BackshelfCore/
│       └── Foundation/
│           ├── DirectoryAccessProvider.swift        # + fileExists(at:)
│           ├── PythonInterpreterDiscovery.swift     # NEW: PythonInterpreter + discovery
│           └── DistInfoParser.swift                 # NEW: METADATA / RECORD / INSTALLER parser
└── Tests/
    └── BackshelfCoreTests/
        ├── Fixtures/
        │   └── python/
        │       ├── .pyenv/versions/3.11.7/bin/python
        │       ├── .pyenv/versions/3.11.7/lib/python3.11/site-packages/
        │       │   ├── requests-2.31.0.dist-info/
        │       │   └── urllib3-2.2.1.dist-info/
        │       ├── opt/homebrew/opt/python@3.12/bin/python3.12
        │       ├── opt/homebrew/opt/python@3.12/lib/python3.12/site-packages/
        │       │   └── flask-3.0.2.dist-info/
        │       └── usr/bin/python3
        ├── Support/
        │   └── InMemoryDirectoryAccessProvider.swift # + fileExists(at:)
        ├── PythonInterpreterDiscoveryTests.swift     # NEW: 6 tests
        └── DistInfoParserTests.swift                 # NEW: 8 tests

HANDOFF.md                                           # this file
```

---

## Phase 2a Decisions Where Docs Were Ambiguous

### 1. `DirectoryAccessProvider` gained `fileExists(at:)`

Interpreter discovery needs existence checks for executable and package directories.
Rather than infer existence by enumerating parent directories, the protocol now has
`fileExists(at:)`. `SystemDirectoryAccessProvider` delegates to `FileManager`, and
`InMemoryDirectoryAccessProvider` checks its registered files/directories. Existing
`BrewScanner` code was not changed.

### 2. `PythonInterpreter.Kind` includes all documented cases

The enum includes `.system`, `.commandLineTools`, `.homebrew`, `.pyenv`, `.uv`,
`.conda`, `.pipx`, and `.projectVenv`. Phase 2a discovery returns candidates only
for system, Homebrew, and pyenv fixtures. The other kind-specific candidate methods
currently return `[]` so Phase 2b can fill them in without changing public API.

### 3. `PythonVersion` is nested under `PythonInterpreter`

Per the Phase 2a prompt, `PythonInterpreter.PythonVersion` stays nested because no
module-wide consumer exists yet. It is `Comparable`, `Codable`, `Hashable`, and
`Sendable`, and parses both `"3.11.7"` and `"Python 3.11.7"`.

### 4. System Python fixture version fallback is intentionally coarse

The fixture system Python is only `/usr/bin/python3`, with no readable
`site-packages`. Since the path does not encode minor/patch, discovery falls back to
`3.0.0` so the interpreter can still be represented and flagged `isSystem=true`.
Real minor-version inference can improve later when CLT/system layouts are expanded.

### 5. `METADATA` description supports both inline and block forms

`DistInfoParser` reads RFC 822-style headers up to the blank line. If body text is
present after the blank line, that body is the description and newlines are preserved.
If no body exists, an inline `Description:` header is used.

### 6. Parser errors are specific to `DistInfoParser`

Malformed metadata throws `DistInfoParser.Error.malformedMetadata(line:)`; missing
required `Name` or `Version` throws `.missingRequiredField`. Missing optional fields
return `nil`.

### 7. Doc-layout mismatch is recorded, not fixed

`CLAUDE.md` and some docs reference root-level files or `docs/...`, but this repo
currently stores docs under `files/...`. `files/README.md` exists and was read. This
should be fixed in a separate doc-layout cleanup, not in Phase 2a. Also, `files/` is
a poor name for what is effectively `docs/`; rename later as a dedicated cleanup.

---

## Phase 2a Known Limitations

1. **No `PipScanner` yet.** Discovery and `.dist-info` parsing are ready for it, but
   no orchestration maps Python packages into `Package` rows yet.

2. **No uv, conda, pipx, or project venv discovery yet.** The enum cases and empty
   candidate methods exist. Actual path walking is deferred to Phase 2b or later.

3. **Python version parsing is intentionally simple.** It handles dotted numeric
   versions, including strings like `"Python 3.11.7"`, but not pre-release suffixes
   such as `3.13.0rc1`, build metadata, or non-CPython naming schemes.

4. **Homebrew version from `python@3.12` becomes `3.12.0`.** The opt symlink layout
   often encodes only major/minor. The scanner can infer exact patch only from layouts
   that expose it, such as Cellar version directories.

5. **`RECORD` parsing is path-focused.** It handles quoted CSV enough to return the
   first column and tolerates empty hash/size fields, but it does not validate hashes
   or sizes.

6. **No install-time extraction yet.** `dist-info` mtime is a Phase 2b `PipScanner`
   concern; `DirectoryAccessProvider` still has no metadata/stat API.

7. **`DirectoryAccessProvider` remains synchronous.** Same limitation as Phase 1:
   filesystem work happens through synchronous calls.

---

## Phase 2a Test Coverage

| Area | Coverage | Notes |
|---|---|---|
| `DirectoryAccessProvider.fileExists` | Covered indirectly | Python discovery tests exercise fake file/dir existence |
| `PythonInterpreterDiscovery` — count | Full for 2a | Finds pyenv, Homebrew, and system fixture interpreters |
| `PythonInterpreterDiscovery` — kinds | Full for 2a | `.pyenv`, `.homebrew`, `.system` verified |
| `PythonInterpreterDiscovery` — versions | Full for requested parsing | `"3.11.7"` and `"Python 3.11.7"` verified |
| `PythonInterpreterDiscovery` — site packages | Full for 2a | pyenv and Homebrew fixture paths verified |
| `PythonInterpreterDiscovery` — system flag | Full for 2a | `/usr/bin/python3` is `isSystem=true`; others false |
| `PythonInterpreterDiscovery` — empty filesystem | Full | Empty fake provider returns `[]` |
| `DistInfoParser` — metadata fields | Full for requested fields | Name, Version, Summary, Home-page, Author, License |
| `DistInfoParser` — optional fields | Full | Missing Home-page/Author returns nil |
| `DistInfoParser` — description | Full for 2a | Block description preserves newlines; inline fallback covered |
| `DistInfoParser` — RECORD | Full for 2a | Expected path list + empty RECORD covered |
| `DistInfoParser` — INSTALLER | Full for 2a | Present and missing installer covered |
| `DistInfoParser` — malformed metadata | Full | Throws `DistInfoParser.Error.malformedMetadata(line:)` |

---

## Questions for Phase 2b

1. **Should `DirectoryAccessProvider` grow a metadata/stat API?** `PipScanner` needs
   `dist-info` mtimes for install-time confidence. Adding `attributes(at:)` or a
   focused `modificationDate(at:)` would keep that provider-clean.

2. **How much discovery belongs in Phase 2b?** The enum already includes uv, conda,
   pipx, and project venv. Decide whether Phase 2b implements only pyenv/Homebrew/
   system package scanning or also fills in pipx and uv path walking.

3. **Should system Python without exact minor version be surfaced?** Current fallback
   is coarse (`3.0.0`) if no `lib/pythonX.Y` directory exists. The UI may prefer
   "unknown version" instead, which would require making `version` optional or adding
   an `.unknown` representation.

4. **Does `DistInfo` need `Requires-Dist` soon?** `python-problem.md` says not to infer
   pip dependency trees in v0, but showing raw `Requires-Dist` may still be useful.

---

# Phase 1 Handoff

## What Was Built

Phase 1 adds `PackageScanner`, `DirectoryAccessProvider`, and `BrewScanner` to the
`BackshelfCore` library, plus GRDB round-trip tests for `ProvenanceEvidence`, `Snapshot`,
and `ScanRun`. No external dependencies were added. No SwiftUI, no networking, no
`Process`/`NSTask`. `swift build` and `swift test` both succeed — 65 tests, zero
warnings, Swift 6 strict concurrency.

```
Backshelf/
├── Package.swift                                 # resources: [.copy("Fixtures")] added to test target
├── Sources/
│   └── BackshelfCore/
│       ├── Models/                               # unchanged from Phase 0
│       ├── Foundation/
│       │   ├── PathDiscovery.swift               # unchanged
│       │   └── DirectoryAccessProvider.swift     # NEW: protocol + SystemDirectoryAccessProvider
│       ├── Persistence/                          # unchanged
│       └── Scanners/                             # NEW directory
│           ├── PackageScanner.swift              # NEW: protocol + ScannerError
│           └── BrewScanner.swift                 # NEW: reads Cellar/ + Caskroom/ receipts
└── Tests/
    └── BackshelfCoreTests/
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

A pure Swift Package (`BackshelfCore`) at `Backshelf/` with no Xcode project.
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
`BackshelfCore` as a protocol. Answer: yes. `SystemDirectoryAccessProvider` is the
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
