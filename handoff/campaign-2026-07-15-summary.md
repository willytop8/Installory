# Installory audit-and-implement campaign summary — 2026-07-15

## Campaign state

- App repository branch: `campaign/2026-07-audit`
- Baseline: `bada41d` (`v1.3.1`, build 9)
- Campaign commits: 26 before this handoff/documentation unit
- Separate website repository: `main` at `9a2f045`
- Production website deploy: complete, Netlify deploy `6a5833cc0b1dbbd4c29d7e0f`
- Version bump: intentionally not applied
- App Store submission: not initiated

The campaign completed the fresh six-lane audit, all accepted correctness,
security, privacy, performance, infrastructure, and test-health repairs, the
approved website pass and production deployment, and the prioritized feature
expansion. The only audit refactor deferred by owner decision is APP-11. The
explicitly conditional scanner/content backlog is listed below.

## Verification delta

| Gate | Baseline | Final campaign gate |
|---|---:|---:|
| Swift Testing cases | 480 in 48 suites | 691 in 61 suites |
| XCTest cases in the Core package | 21 | 21 |
| App-target logic tests | 0 | 41 |
| Core failures | 0 | 0 |
| App-test failures | n/a | 0 |
| Release build | not part of baseline | passed, signing disabled |
| Production `Process(` / runtime network APIs | 0 / 0 | 0 / 0 |

Final commands:

```bash
cd Installory && swift test --quiet
xcodebuild -project Installory.xcodeproj -scheme Installory test -quiet
xcodebuild -project Installory.xcodeproj -scheme Installory \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build -quiet
./scripts/check-invariants.sh
python3 -m unittest discover -s scripts/generate-descriptions/tests -p 'test_*.py'
```

Results: 691 Swift Testing cases plus 21 XCTest cases passed; 41 app tests
passed; 18 description-tool tests passed; Release built successfully; the
invariant gate passed. Xcode emitted no compiler warnings. Its only diagnostic
was the scheme-level destination metadata notice already produced by the
generated local project.

## What shipped on the branch

### Correctness, safety, and privacy

- Failed, timed-out, skipped, or malformed manager scans preserve the last-known
  manager partition. Successful empty scans still clear their own partition,
  and targeted Homebrew scans no longer corrupt formula/cask state.
- Every scanner walk and size measurement is bounded, cancellable, symlink-safe,
  and grant-backed. Cargo, RubyGems, pyenv, nvm, pipx, and uv relocation variables
  are injected through a small allowlisted environment boundary.
- pip `REQUESTED`, pipx suffix identities, RubyGems `%q` dependencies/platform
  versions/coexisting versions, scoped npm executable paths, and manager/qualifier
  dependency identity are handled explicitly.
- Generated removal/reinstall scripts sanitize metadata-derived comments and
  quote exact active arguments. pipx environments and gem versions are targeted
  exactly; Cargo restore preserves recorded sources; hostile metadata cannot add
  an executable line.
- Provenance input is bounded, cancellable, invalid-UTF-8 tolerant, centrally
  redacted before persistence, bounded again at rendering, and written in one
  atomic batch. Co-install matching uses a sliding window and bounded samples.
- Saved inventory, scan state, snapshots, and provenance hydrate through async
  persistence. Snapshot lists are metadata-only and payloads load on selection.
- External path probes/reveals use the narrowest component-aware grant and
  balance security-scope lifetimes. Save panels are also balanced.
- The user-approved read-write entitlement authorizes only explicit Save-panel
  destinations. Persistent scan bookmarks still use
  `.securityScopeAllowOnlyReadAccess`, enforced by CI.
- CSV formula prefixes are neutralized. JSON export preserves the complete
  `Package` shape with deterministic ordering and encoding.

### Product features

- APP-F1: search in All/manager/read-only, Duplicates, Review Candidates, and AI
  Installed, matching name, qualifier, and install path.
- APP-F2: bulk cleanup selection in ordinary inventory, Duplicates, and Review
  Candidates using one eligibility/scope contract. It still generates scripts
  only.
- APP-F5: CSV, Markdown, and deterministic JSON inventory export.
- uv tools: a filesystem-only scanner for persistent receipt-backed uv tool
  environments, including relocated roots, sizes, provenance, exact uninstall
  identity, persistence, snapshots, descriptions, and app grant/display wiring.
  `uvx` disposable environments remain intentionally out of inventory.
- APP-F3: native sortable macOS Table mode with stable multi-column sorting,
  unknown-last size/date semantics in both directions, ID-based selection,
  cleanup/context-action parity, persistent independent List/Table sorts, and
  View-menu shortcuts.
- APP-F4: a cached Disk Usage analysis for **measured package payload** with
  explicit measurement coverage, overflow-safe manager totals, unknown and
  measured-zero states, an Apple Charts manager view, and a keyboard-selectable
  top-ten list.

### Infrastructure and website

- CI regenerates the ignored Xcode project, runs Core tests, builds Debug and
  Release app targets with signing disabled, and enforces subprocess/network,
  entitlement, read-only bookmark, and XcodeGen source-of-truth invariants.
- A real v1 database fixture now migrates through v2 with row, foreign-key, and
  schema assertions.
- The description generator has atomic/check/scratch paths, production count
  floors, partial-run protection, 18 stdlib tests, deterministic npm discovery,
  and a refreshed 33,514-entry corpus dated 2026-07-15.
- The separate website repository now contains the accepted mechanical,
  accessibility, SEO, privacy/support, differentiator, comparison, and FAQ work.
  Production was verified for routes, redirects, cache/security headers,
  responsive assets, FAQ structured data, and the App Store badge. Security
  Headers returned A+; Google Rich Results accepted the Software App/FAQ markup
  with only optional-field guidance.

## Audit resolution ledger

The finding document remains a point-in-time audit. This table records the final
campaign disposition.

| Findings | Disposition |
|---|---|
| CORE-05, CORE-07, CORE-08, CORE-10 | Fixed by `580a0d7` with bounded sizing, cancellation, environment discovery, consolidated filesystem helpers, and realistic provider tests. |
| CORE-09, CORE-11, CORE-12 | Fixed by `f39a351`; stale documentation was corrected, co-install work is sliding-window/bounded, and redaction occurs before persistence and at rendering. |
| APP-07, APP25-001/003/004/006/007/011/012/014/015/016/017 | Fixed by `065d8f8` and its app/Core regressions. |
| APP-08, APP-09, APP25-005/008/010/013/018/019/020/021/022 | Fixed by `cbdc50d`, with appearance/VoiceOver behavior retained in manual QA below. |
| APP-11 | **Deferred by explicit owner decision.** The coordinator is large, but a natural-seam split became a release-risk refactor after its scan, persistence, grant, and export lifecycles changed. |
| INF-02 | Verified satisfied: `website/.git` is a real clean repository with commits. |
| INF-04 | Audit correction: `DDA9.1` + `3B52.1` accurately cover displayed/user-granted file timestamps; `8FFB.1` is System Boot Time and was correctly not added. |
| INF-06 | Verified satisfied: Swift tools 6.1 and Swift language mode 6 are aligned. |
| INF-08 | Fixed by `3e3edf0`. |
| INF-09, TEST25-008 | Fixed by `125aa87`, `c438186`, `1669881`, and `b251912`. |
| CORE25-001/002/004/005/006/007/012/014/016, PERF25-001/002/003, TEST25-005/006/007/009 | Fixed by `580a0d7`. |
| CORE25-003/009, SEC25-003, PERF25-010 | Fixed by `f0e2ec5`. |
| CORE25-008/010, APP25-018/022 | Fixed by `5d65ed6` (with provenance-side scoped matching in `f39a351`). |
| CORE25-011/013/017, SEC25-005, PERF25-004/005/006 | Fixed by `f39a351`. |
| CORE25-015, PERF25-008 | Fixed by `fa43a3c` and the app-side lazy hydration in `065d8f8`. |
| SEC25-007 | Fixed by `c6b44ae`. |
| SEC25-001 | Fixed by the user-approved entitlement choice in `c81bacb`; scan bookmarks remain read-only. |
| SEC25-002/009 | Fixed by `b0d5d1e` and `065d8f8`. |
| SEC25-010 | Fixed by `72a57ac`. |
| PERF25-007/009/012 | Fixed by `065d8f8` and `cbdc50d`. |
| PERF25-011 | Fixed by `38874b2` and the METADATA follow-up `15a54e8`. |
| TEST25-001/002 | Fixed by `ae0b220`. |
| TEST25-003 | Fixed with the generated `InstalloryTests` target and 41 app logic tests. |
| TEST25-004 | Fixed by `3e3edf0`. |
| WEB-01–WEB-11, SEC25-004, WEB25-002–008, WEB-F1/F2/F3 | Fixed in separate website commits `3f67a45` and `9a2f045`, then deployed and verified. |
| APP-F1/F2/F3/F4/F5 and uv scanner | Implemented with specs and regression coverage in `ccba530`, `7463879`, `d2db275`, `4fea1fe`, `11f431e`, `311de9c`, and `67abf94`. |

## Explicit deferrals

- **APP-11 coordinator split:** owner-approved deferral; see ledger.
- **VS Code/Cursor extensions, non-MAS applications, and pnpm/yarn scanners:**
  deferred from the explicitly conditional scanner backlog. Each needs a separate
  spec, authoritative on-disk-format research, grant design, cleanup limitations,
  fixtures, and full manager integration. Adding them after the release gate would
  dilute review of the new uv scanner and size pipeline.
- **Go binary inventory:** deliberate product gap. Reliable module/version
  inspection generally requires executing `go version -m`; that would violate the
  zero-subprocess invariant.
- **WEB-F4 demo video:** requires representative release footage, editing, poster,
  and reduced-motion verification after the app version is finalized.
- **WEB-F5 changelog:** defer until the release version and public release date are
  chosen, so it does not announce an unshipped version.
- **WEB-F6 manager documentation and WEB-F7 provenance explainer:** useful larger
  content projects, but outside the approved one-pass WEB-F1/F2/F3 content scope.
- **WEB-F8 dark screenshots:** requires final-version App Store/marketing capture.
- **WEB-F9 social proof/press kit:** defer until ratings, review quotes, press assets,
  or a meaningful public star count exist; no placeholder proof was invented.
- **Version and submission:** no version/build change and no App Store submission
  were made. Recommendation: **1.4.0 (build 10)** because this is a user-visible
  feature release, followed by manual QA and an App Store submission only after
  owner confirmation.

## Manual QA checklist

### Launch, state, and grants

- [ ] Launch once with scan-on-launch disabled; verify cached packages, scan time,
      snapshots, and opt-in provenance appear without a rescan.
- [ ] Grant, revoke, move, and re-grant canonical/custom folders. Confirm unrelated
      grants remain, stale grants survive relaunch for recovery, and no repeated
      panel operation loses access.
- [ ] Cancel the onboarding folder panel and verify onboarding remains incomplete.
- [ ] Force one scanner failure/timeout while another succeeds. Confirm stale rows
      remain with truthful coverage, then confirm a successful empty scan clears
      only its own manager partition.

### Inventory and scanners

- [ ] Scan native and Rosetta Homebrew, pip/pyenv/project `.venv`, pipx (including
      a suffixed venv), uv persistent tools, npm/nvm, Cargo, RubyGems, and MAS
      receipts using only granted roots.
- [ ] Verify relocated `CARGO_HOME`, `GEM_HOME`, `PYENV_ROOT`, `NVM_DIR`,
      `PIPX_HOME`, `UV_TOOL_DIR`, `UV_PYTHON_INSTALL_DIR`, and `XDG_DATA_HOME`
      layouts where available.
- [ ] Verify uv tools show exact versions, entrypoints, environment paths, sizes,
      descriptions, and an exact `UV_TOOL_DIR=… uv tool uninstall …` command;
      confirm `uvx` use does not appear.
- [ ] Compare measured package sizes with representative package contents and
      verify a deliberately over-budget/unreadable tree becomes unknown, not zero.

### Search, Table, and Disk Usage

- [ ] Search ordinary inventory, Duplicates, Review Candidates, and AI Installed
      by name, qualifier, and path; verify search misses and detail clearing.
- [ ] Switch List/Table by picker and ⌘1/⌘2. Sort every column both directions,
      Shift-sort a secondary column, resize columns, relaunch, and verify stable
      selection plus independent List/Table sort restoration.
- [ ] In Table Cleanup Mode, select eligible rows, encounter locked rows, search,
      sort, and switch modes; confirm the footer count and checked IDs remain exact.
- [ ] Inspect Disk Usage with complete, partial, all-unknown, measured-zero, and
      overflow test inventories. Confirm wording always says measured package
      payload and never implies reclaimable volume space.
- [ ] Navigate the top-ten payload list by keyboard, open details, refresh so the
      selected package leaves the top ten, and confirm detail selection clears.

### Cleanup, snapshots, and exports

- [ ] Generate single and bulk removal scripts for Homebrew taps/casks, scoped npm,
      pip interpreters, pipx suffixes, uv custom roots, Cargo sources, and multiple
      gem versions. Inspect only; Installory must never execute them.
- [ ] Use hostile fixture names containing spaces, quotes, leading dashes,
      newlines, and shell metacharacters. Confirm active arguments are quoted and
      metadata comments stay on commented lines.
- [ ] Cancel the pre-removal snapshot sheet with Escape and verify no script is
      generated. Exercise snapshot capture failure, empty-current restore, scan-time
      restore disabling, lazy history loading, and deterministic change ordering.
- [ ] Export CSV, Markdown, JSON, environment report, cleanup script, and reinstall
      script. Confirm save errors surface, repeated panels work, JSON round-trips,
      and spreadsheet-formula prefixes remain inert.

### Privacy, accessibility, and release presentation

- [ ] With tracing off, confirm no shell/Claude evidence is read or displayed.
      Enable it with a home grant, inspect useful redacted evidence, then disable,
      erase, and verify both UI and persisted evidence are cleared.
- [ ] Exercise VoiceOver, Full Keyboard Access, Bold Text, Increase Contrast,
      Light/Dark Mode, and Reduce Motion across onboarding, badges, empty states,
      Table, Disk Usage, cleanup controls, snapshot restore, and sheets.
- [ ] Verify `App/Resources/PrivacyInfo.xcprivacy`, the read-write Save-panel
      entitlement, and read-only bookmark creation in the archived build.
- [ ] Smoke-test the live website homepage, privacy, support, FAQ, and 404 routes,
      including the support form, dark mode, keyboard focus, reduced motion, and
      responsive images.

## Owner decision remaining

Approve or change the proposed **1.4.0 (build 10)** version, and state whether the
manual-QA-approved build should be prepared for App Store submission. No release
metadata or submission action should occur before that decision.
