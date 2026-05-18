# Next session — start here

**Current state: Phase 6 (cross-manager duplicate detection) complete (2026-05-17).**

For the full history of what was built and what's pending, see **HANDOFF.md** (Phase 6 entry at the top).

---

## Quick state summary

- **All phases 0–6** are implementation-complete.
- **Library tests:** 321, all passing (`swift test` in `Installory/`).
- **App-target verification** requires hardware (regenerate Xcode project, clean build, run the manual checklist in the relevant HANDOFF.md entry).

## What needs hardware verification

Multiple phases have been implemented but not yet verified on hardware. Pending checklists in HANDOFF.md:

1. **Phase 6 — Duplicate detection** — verify "Duplicates (N)" sidebar row appears/hides correctly; group view; removal routing via detail pane; persistence across relaunch; brew+brewCask and pip multi-env excluded.
2. **Audit Cleanup (2026-05-17)** — entitlements validity, first-scan snapshot, snapshot-failure UX, context menu language ("Create Removal Script…").
3. **Phase 5d-2** — Settings window, provenance section in detail pane, removal flow (Always/Ask/Never).

Full checklists: HANDOFF.md → each section's "William's manual checklist."

## Next planned work

- **Phase 5d-3** — App Store preparation: app icon, screenshots, privacy nutrition label, TestFlight.
- No in-progress work is blocked; codebase is in a clean, verifiable state.
