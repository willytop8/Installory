# Next session — start here

**Current state: post-audit cleanup complete (2026-05-17).**

For the full history of what was built and what's pending, see **HANDOFF.md → RESUME HERE section** (the "Audit Cleanup (2026-05-17)" entry at the top).

---

## Quick state summary

- **Phase 5d-2** (Provenance UI + Settings) and all prior phases are implementation-complete.
- **Library tests:** 315, all passing (`swift test` in `Installory/`).
- **App-target verification** requires hardware (regenerate Xcode project, clean build, run the manual checklist in the "Audit Cleanup" HANDOFF entry).

## What needs hardware verification

The audit-cleanup session added:

1. `App/Installory.entitlements` — entitlements were missing; now set correctly. Sandboxed launch must be verified.
2. First-scan auto-snapshot — verify a "First Scan Snapshot" appears in the sidebar after the first scan, and does not appear on subsequent scans.
3. Snapshot-failure UX — verify the red warning box appears when a snapshot is requested but fails.
4. UI language changes — "Create Removal Script…" context menu, updated sheet headline, "Removal Script" section heading.

Full checklist: HANDOFF.md → "Audit Cleanup (2026-05-17)" → William's manual checklist.

## Next planned work

See ROADMAP.md for Phase 5e and beyond. No in-progress work is blocked; the app is in a clean, verifiable state.
