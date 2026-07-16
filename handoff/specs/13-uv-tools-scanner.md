# Spec 13 — uv persistent-tool scanner

**Workstream:** New scanner (Phase 5). **Depends on:** the existing bounded-size,
cancellation, environment, and scan-reconciliation fixes. **Model change:** adds
`PackageManager.uv`. **Product invariants:** filesystem-only, read-only, no
subprocesses, no network, and no access outside active user-granted security scopes.

## Problem and scope

`uv tool install` creates persistent, isolated Python environments for command-line
tools. Installory already recognizes uv-managed Python interpreters when scanning pip,
but it does not inventory uv's persistent tools as their own manager. Treating them as
ordinary pip packages would lose their ownership and generate the wrong cleanup target.

This feature inventories only tools installed persistently with `uv tool install`.
It deliberately excludes:

- `uvx` / `uv tool run` cache environments, which are disposable cache entries;
- project `.venv` environments, which remain part of pip/project-venv discovery;
- uv-managed Python runtimes under `.../uv/python`, which
  `PythonInterpreterDiscovery.uvCandidates()` already handles;
- the uv cache and uv executable itself.

The app reports one row per uv tool environment—the requested tool—not every
dependency inside that environment. This matches `PipxScanner` and avoids presenting
implementation dependencies as independently-managed tools.

## Primary-source contract (verified 2026-07-15)

The implementation must be based on these upstream contracts, not assumptions:

- Astral documents persistent tools at `$XDG_DATA_HOME/uv/tools` or
  `~/.local/share/uv/tools`, overridable by `UV_TOOL_DIR`; tool executables have a
  separate directory controlled by `UV_TOOL_BIN_DIR`:
  <https://docs.astral.sh/uv/reference/storage/#tools> and
  <https://docs.astral.sh/uv/reference/environment/#uv_tool_dir>.
- `uv tool install` environments are persistent and isolated, while `uvx` environments
  are disposable cache entries:
  <https://docs.astral.sh/uv/concepts/tools/#tool-environments>.
- Upstream enumerates direct child directories of the tool root, treats each child
  basename as the normalized tool name, and reads `<tool>/uv-receipt.toml`:
  <https://github.com/astral-sh/uv/blob/6fde283e7c26cce9504e3aa276121228c5500e8f/crates/uv-tool/src/lib.rs#L114-L200>.
- The receipt is TOML with a top-level `[tool]` table. Its current schema contains
  `requirements` (the first is the tool target; later entries are `--with` inputs),
  `entrypoints` (`name`, `install-path`, optional `from`), optional `python`, and
  `[tool.options]`. Upstream still accepts legacy string requirements:
  <https://github.com/astral-sh/uv/blob/6fde283e7c26cce9504e3aa276121228c5500e8f/crates/uv-tool/src/receipt.rs#L7-L41> and
  <https://github.com/astral-sh/uv/blob/6fde283e7c26cce9504e3aa276121228c5500e8f/crates/uv-tool/src/tool.rs#L14-L117>.
- A real upstream receipt fixture has
  `requirements = [{ name = "black" }]` and a multiline array of inline entrypoint
  tables:
  <https://github.com/astral-sh/uv/blob/6fde283e7c26cce9504e3aa276121228c5500e8f/crates/uv/tests/tool/tool_install.rs#L112-L127>.
- The receipt records the request, not necessarily the resolved version. uv obtains the
  installed version by finding the tool-named distribution in the environment's
  site-packages:
  <https://github.com/astral-sh/uv/blob/6fde283e7c26cce9504e3aa276121228c5500e8f/crates/uv-tool/src/lib.rs#L28-L50>.
- `uv tool uninstall <name>` uses that normalized environment name, removes its
  environment, then removes receipt-recorded entrypoints. It can also remove a dangling
  environment with a missing receipt:
  <https://github.com/astral-sh/uv/blob/6fde283e7c26cce9504e3aa276121228c5500e8f/crates/uv/src/commands/tool/uninstall.rs#L96-L159>.

The commit-pinned source links above describe uv main at
`6fde283e7c26cce9504e3aa276121228c5500e8f`. Keep anonymized copies of the fixture
shapes in Installory tests so an upstream schema change cannot silently change our
coverage.

## Root discovery and sandbox access

Add `UV_TOOL_DIR`, `UV_PYTHON_INSTALL_DIR`, and `XDG_DATA_HOME` to the injected
`PackageManagerEnvironment` allowlist. Apply the existing policy: only trimmed,
absolute, control-character-free directory values are accepted. Although uv can resolve
a relative `UV_TOOL_DIR` against its process working directory, Installory must reject
relative values because a sandboxed GUI app does not share the user's shell working
directory. `UV_TOOL_BIN_DIR` does not need to become discovery state: each valid receipt
already records its exact entrypoint paths, including custom bin directories.

Select exactly one authoritative tool root with uv's precedence:

1. valid `UV_TOOL_DIR`;
2. valid `$XDG_DATA_HOME/uv/tools`;
3. `$HOME/.local/share/uv/tools`;

Do not search other roots merely because they are readable. uv itself selects one root,
and Installory's reconciliation unit is the whole manager; merging dormant or partially
granted roots would make both emptiness and removal semantics ambiguous. Standardize and
resolve the selected root before using it, and retain it in each package qualifier.

App grant wiring:

- Add `~/.local/share/uv` to `CanonicalDirectory`, labeled for both `.uv` tools and
  `.pip` packages in uv-managed Python runtimes.
- Recognize that root in `GrantedDirectory.managersUnlocked`.
- Construct `UvToolScanner` in both full-scan and targeted-rescan paths while all stored
  directory grants are active, matching the existing scanner lifecycle.
- A relocated root is supported when `UV_TOOL_DIR`/`XDG_DATA_HOME` is visible to the GUI
  process and the user grants that root or an ancestor. Merely granting an arbitrary
  directory does not make it a uv root; Installory never recursively hunts for receipts.
- Keep every bookmark `startAccessing` paired with `stopAccessing`; the scanner itself
  receives already-active URLs and never creates or persists bookmarks.

Coordinate `PythonInterpreterDiscovery.uvCandidates()` with the same environment
object: its independent runtime root is `UV_PYTHON_INSTALL_DIR`, otherwise
`$XDG_DATA_HOME/uv/python`, otherwise `~/.local/share/uv/python`. Do not make the new
tool scanner walk `uv/python` or feed tool virtualenv interpreters into the global pip
inventory.

## Core scanner design

Add `UvToolScanner: PackageScanner` with manager `.uv`, an injected
`DirectoryAccessProvider`, `DistInfoParser`, home directory,
`PackageManagerEnvironment`. No production path may use `FileManager` directly except
through `SystemDirectoryAccessProvider`.

For the selected tool root:

1. Enumerate direct children with the throwing provider API. Ignore regular files such
   as `.gitignore`/`.lock` and uv's `.tmp*` directories. Never use
   `directoryContentsOrEmpty` for the authoritative root: unreadable must not become a
   successful empty inventory.
2. Require each candidate to be a real directory within the resolved tool root; never
   traverse a final symlink. Validate and PEP-503-normalize its basename. That basename
   is the authoritative uv uninstall target.
3. Read `<environment>/uv-receipt.toml` as a bounded regular file and parse the
   receipt-specific subset. Do not add a general TOML dependency. A small linear parser
   must honor TOML quoted strings and balanced arrays/inline tables, accept current
   requirement tables and legacy requirement strings, ignore unknown fields, and
   extract only the optional primary requirement name plus entrypoint name/path/from.
   Validate a parsed primary name against the normalized environment basename. Never
   persist the raw receipt, source/index URLs, or `[tool.options]` values.
4. Find `lib/python*/site-packages` using direct, sorted, containment-checked
   enumeration. Parse only `.dist-info/METADATA` files; do not read `RECORD`,
   `INSTALLER`, package payloads, or execute the environment's Python.
5. Select exactly one distribution whose PEP-503-normalized `Name` matches the
   environment target. Its `Name`, exact installed `Version`, and `Requires-Dist`
   headers are the installed truth. Zero or multiple matching distributions make the
   environment malformed—do not choose by filesystem order.
6. Measure the full environment tree with the scan-local `BoundedDirectorySizer`,
   constrained to the selected tool root. Publish `nil`, never a partial byte count,
   when a size bound is reached. Do not follow or separately measure entrypoint paths
   outside the tool root.

`DistInfoParser.parseMetadataOnly` currently avoids ancillary files but must also make
the `METADATA` read itself bounded before this scanner ships. Use a regular-file metadata
check plus the bounded provider read; reject truncation instead of parsing a prefix as a
complete file.

Recommended hard ceilings (injectable for tests): 256 KiB per receipt, 4 MiB per
`METADATA`, 10,000 tool-root entries, 64 `lib/python*` directories per environment,
and 10,000 direct site-packages entries per environment. Exceeding a structural/read
bound is a scanner failure, not a partial success. Directory-size limits remain those
of `BoundedDirectorySizer` and yield `sizeBytes == nil` rather than failing inventory.

Add `Task.checkCancellation()` before and after each enumeration/read, for every tool,
Python-lib directory, and dist-info item, and before returning. Yield at a small fixed
interval (the existing 32-entry convention is suitable) so `ScanCoordinator` timeouts
can cancel large roots. Use one scan-local sizer so aggregate budgets remain real.

## Package mapping and identity

For a valid environment at `<toolsRoot>/<target>` and selected distribution metadata:

```text
id                    uv:<absolute-environment-path>:<PEP-503-normalized-target>
manager               .uv
qualifier             <absolute-environment-path>
name                  METADATA Name (human-facing spelling)
version               METADATA Version (exact installed version)
installPath           <absolute-environment-path>
installedAt           target .dist-info mtime, falling back to receipt mtime
installedAtConfidence .medium
sizeBytes             complete bounded environment-tree size, otherwise nil
isExplicit            true
isReadOnly            false
dependencies          Requires-Dist distribution names
artifactPaths         validated absolute receipt entrypoint install-path values
lastSeen              scan observation time
```

Using the normalized environment target in `id` makes identity stable across metadata
capitalization changes; retaining the full environment path keeps identity tied to the
authoritative uv root and prevents a relocation from colliding with cached/snapshot
identity. Extend `PackageIdentity` and description lookup so `.uv` uses PEP 503
normalization. Description lookup should reuse the bundled `pip:<normalized-name>` corpus
rather than duplicating every Python description under `uv:`.

`artifactPaths` is appropriate here because the field stores manager-declared artifact
paths and cleanup already gates cask-specific behavior on `.brewCask`. Update its model
comment from “currently Homebrew casks” to mention uv entrypoints. Validate receipt
paths as absolute, standardized, control-free strings, but do not probe them: a separate
bin-directory grant is not required to inventory a tool.

## Malformed, unavailable, and empty semantics

- No accessible selected root: `.skipped` via `isAvailable == false`, reason
  “uv tool directory not granted or not found.”
- Accessible, readable root with no non-temporary tool directories: successful empty
  scan; reconciliation may clear that root's `.uv` inventory.
- Root exists but cannot be enumerated: failed scan; preserve the last-known `.uv`
  partition.
- Candidate environment has a missing/oversized/invalid receipt, unsafe path, missing
  or ambiguous target dist-info, or unreadable authoritative metadata: fail the scanner
  rather than silently omit a previously-known package. This intentionally differs
  from `uv tool list`'s per-tool warning because Installory has manager-level, not
  per-package, stale-state reconciliation; a “successful” partial result would falsely
  delete cached rows and provenance (the CORE25-001 class of bug).
- `.tmp*` directories are ignored as in-progress uv state. Cancellation propagates as
  `CancellationError`, never as skipped/empty/malformed.

## Cleanup, snapshots, and provenance

Removal must target both the recorded root and exact environment basename:

```bash
UV_TOOL_DIR='<tools-root>' uv tool uninstall '<environment-name>'
```

Derive `<tools-root>` as the qualifier's parent and validate the qualifier with a
dedicated `UvToolEnvironmentIdentity` helper. Quote both values through
`ShellScriptHelpers`; hostile or non-absolute qualifiers must produce a commented
manual-review line, never an ambient `uv tool uninstall <Package.name>` fallback. Add a
`# === uv tools ===` section and deterministic root/name ordering to bulk scripts.

Snapshot reinstall is a deliberate v1 gap. A uv receipt can preserve custom URLs,
editable paths, Python requests, indexes, constraints, `--with` packages, and options,
but `Package`/snapshot payloads do not retain that receipt. Generating
`uv tool install name==version` would silently change some installations. For `.uv`,
`ReinstallScriptGenerator` must emit a sanitized manual-review comment and no active
command until the snapshot model can faithfully retain the receipt's reinstall inputs.

Extend `InstallCommandDetector` so persistent `uv tool install <requirement>` commands
produce manager `.uv`, while existing `uv pip install` detections remain `.pip`.
Consume option values (`--python`, `--with`, `--with-executables-from`, index/source
options) and attribute only the primary persistent tool requirement. Do not tag `uvx`,
`uv tool run`, local paths, or unnameable Git/URL targets as installed uv tools. Add
`.uv` to PEP-503 matching and label its filesystem timestamp source “dist-info mtime.”

## App and exhaustive-switch wiring

- Add `.uv` to `PackageManager`, `ScanCoordinator`'s timeout table (8 seconds is a
  reasonable starting budget), full/targeted scanner construction, and app scan status.
- Add display name “uv tools”, badge “uv”, a Python-family blue badge color, and a
  terminal-style symbol. Update onboarding/manager copy without implying `uvx` cache is
  inventoried.
- Add exhaustive cases in cleanup/reinstall section order, manager capabilities,
  duplicate resolution/CLI heuristics, description normalization, provenance parsing,
  demo data, and all app switches. `.uv` does not use the generic
  `groupsByQualifier` rendering: every tool has a distinct environment qualifier, while
  each cleanup command already scopes its exact root. Render one uv section, ordered by
  tools root and environment name.
- For PATH analysis, use receipt entrypoint artifacts: return a directory only when the
  validated entrypoint parents agree; otherwise report unknown rather than guessing.
  This correctly handles custom `UV_TOOL_BIN_DIR`.
- No database migration is required for the enum raw value: the existing text columns
  and Codable snapshot payloads can store `"uv"`. Add persistence/snapshot round-trip
  tests so this remains proven.
- The new scanner lives in the SwiftPM core source tree. Run XcodeGen anyway after all
  feature wiring, per the campaign feature gate, and compile the app target.

## Deliberate v1 gaps

- No `uvx` cache, project-environment, cache, or managed-runtime inventory is added by
  this scanner; those locations have different ownership/lifetime semantics.
- `$CWD/.uv/tools` is not considered. The sandboxed app's working directory is unrelated
  to the directory in which the user ran uv, so scanning it would be misleading.
- Installory does not parse shell profiles to discover an environment override that was
  not inherited by the GUI process. Custom roots require a visible injected environment
  value plus a covering user grant.
- Snapshot reinstall stays manual-review-only until snapshots can preserve the complete,
  sanitized receipt request. Removal remains fully and exactly generated.
- Unknown future receipt fields are ignored, but a future incompatible shape fails the
  scanner visibly and preserves last-known inventory; Installory never guesses.

## Fixture shapes

Add source-controlled fixtures under
`Tests/InstalloryCoreTests/Fixtures/uv/` using `Bundle.module`:

```text
default/tools/ruff/
  uv-receipt.toml
  pyvenv.cfg
  bin/python                         # fixture file/symlink model only; never executed
  lib/python3.12/site-packages/
    ruff-0.6.9.dist-info/METADATA
    click-8.1.7.dist-info/METADATA   # dependency: must not become a second tool row

legacy/tools/black/
  uv-receipt.toml                    # requirements = ["black==24.2.0"]
  lib/python3.12/site-packages/black-24.2.0.dist-info/METADATA

custom-root/httpie/
  uv-receipt.toml                    # multiple entrypoints in a custom bin directory
  lib/python3.13/site-packages/httpie-3.2.4.dist-info/METADATA
```

The current receipt fixture should include harmless unknown `[tool.options]` keys so
forward-compatible ignoring is tested. Add focused in-memory shapes for malformed,
oversized, symlink-escape, ambiguous-dist-info, unreadable-root, and cancellation cases;
do not commit huge binary fixtures.

## Required tests

Core scanner and path discovery:

- `uvToolScannerReadsCurrentReceiptAndReportsMainDistributionOnly`
- `uvToolScannerAcceptsLegacyStringRequirementReceipt`
- `uvToolScannerUsesExactDistInfoVersionNotRequestedSpecifier`
- `uvToolIdentityChangesWhenAuthoritativeRootChanges`
- `uvToolDirectoryPrecedenceHonorsUVToolDirThenXDGThenDefault`
- `relativeOrControlCharacterUvEnvironmentOverridesAreRejected`
- `uvToolScannerDoesNotTreatArbitraryGrantedDirectoriesAsToolRoots`
- `uvToolScannerSuccessfulReadableEmptyRootReturnsEmpty`
- `uvToolScannerUnreadableRootThrowsInsteadOfReturningEmpty`
- `uvToolScannerMalformedReceiptPreservesLastKnownUvPartition`
- `uvToolScannerRejectsMissingOrAmbiguousTargetDistInfo`
- `uvToolScannerBoundsReceiptAndMetadataReads`
- `uvToolScannerCancellationPropagatesDuringLargeWalk`
- `uvToolSizeIncludesEnvironmentButNeverFollowsExternalEntrypointsOrSymlinks`
- `uvToolSizePublishesNilWhenBoundIsExceeded`

Identity, cleanup, provenance, and integration:

- `uvToolIdentityUsesRootQualifiedNormalizedTarget`
- `uvRemovalScopesExactToolRootAndEnvironmentName`
- `uvRemovalQuotesHostileRootAndRejectsUnsafeQualifier`
- `uvSnapshotRestoreEmitsManualReviewInsteadOfLossyInstallCommand`
- `uvToolInstallCommandIsDetectedButUvToolRunAndUvxAreNot`
- `uvToolDescriptionsReusePep503NormalizedPipCorpus`
- `uvEntrypointPathResolvesCustomToolBinDirectory`
- `uvPackageRoundTripsThroughDatabaseAndSnapshotPayload`
- Existing `uv pip install` provenance tests remain `.pip` (regression guard).
- Existing pip discovery still finds uv-managed runtimes without treating tool
  environments as global interpreters (regression guard).
- Full scan status/reconciliation and targeted rescan include exactly `.uv`.

Finish with the invariant gate: production `Installory/Sources` and `App/Sources` still
contain zero `Process(` and zero `URLSession`/network APIs; all external filesystem reads
occur only while the relevant security-scoped grant is active.
