# Next session — start here

**Current state: Phase 6 (cross-manager duplicate detection) complete (2026-05-17).**

For the full history of what was built and what's pending, see **HANDOFF.md** (Phase 6 entry at the top).

---

## Quick state summary

- **All phases 0–6** are implementation-complete.
- **Library tests:** 321, all passing (`swift test` in `Installory/`).
- **App-target verification** still requires hardware for the current release-candidate surface.

## Outstanding hardware verification

Run `./scripts/regenerate-xcode.sh`, clean build, and launch the app before checking:

1. **Phase 6 — duplicate detection:** "Duplicates (N)" sidebar row appears/hides correctly; grouped view opens; selecting an install routes to the existing detail/removal flow; selection persists across relaunch; brew+brewCask and pip multi-environment installs are excluded.
2. **Audit cleanup:** sandboxed launch succeeds with `app.installory.mac`; first-scan snapshot is captured once; snapshot-failure UX shows the red warning; context menu and detail pane use "Create Removal Script" / "Removal Script" language.
3. **Phase 5d-2:** Settings window works; provenance section appears, disappears, and renders expected unknown/evidence states; per-package removal honors Always / Ask / Never snapshot preferences while batch cleanup still snapshots.

## Next planned work

- **Phase 5d-3** — App Store preparation: app icon, screenshots, privacy nutrition label, TestFlight.
- No in-progress work is blocked; codebase is in a clean, verifiable state.
