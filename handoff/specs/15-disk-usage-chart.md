# Spec 15 — Disk-usage overview

**Workstream:** APP-F4. **Depends on:** CORE-05. **Framework:** Apple Charts from the macOS SDK; no third-party dependency.

## Problem

Installory now records bounded, best-effort `sizeBytes` for real scanned packages, but users can only inspect one row or choose “Largest First.” They cannot see which package managers account for most measured payload or quickly open the largest packages. At the same time, bounded measurements may legitimately be incomplete, so a chart must not turn missing data into a false zero or claim exact reclaimable space.

## Target state

Add a **Disk Usage** analysis entry to the sidebar. Its view shows:

1. a measured-payload summary with explicit coverage counts;
2. an Apple Charts horizontal bar chart of known logical bytes by package manager; and
3. a keyboard-selectable list of the ten largest packages with known sizes, opening the existing package detail pane.

Use the phrase **Measured package payload**, not “disk used,” “space available,” or “space you can free.” Scanner sizes are logical package payloads collected within time/entry/byte bounds. They are not volume-capacity data, usage telemetry, or a guarantee of reclaimable physical blocks; shared/hard-linked content and package-manager layouts can make a simple sum differ from Finder or Disk Utility.

## Core aggregation contract

Add a pure, public, `Sendable` aggregation surface in Core, for example:

```swift
public struct DiskUsageSummary: Sendable, Equatable {
    public let totalKnownBytes: Int64
    public let totalOverflowed: Bool
    public let measuredPackageCount: Int
    public let unknownPackageCount: Int
    public let managers: [ManagerDiskUsage]
    public let largestPackages: [Package]
}

public func diskUsageSummary(for packages: [Package], largestLimit: Int = 10) -> DiskUsageSummary
```

Exact semantics:

1. A size is measured only when `sizeBytes` is non-nil and non-negative. Nil or invalid negative values increment `unknownPackageCount`; they contribute no bytes and never enter the largest list.
2. A known zero-byte value is **measured zero**, not unknown. It increments `measuredPackageCount`, participates in its manager bucket, and may appear in the largest list when fewer than the limit have larger known values.
3. `totalKnownBytes` is the sum of measured package values. Each input `Package` contributes once to exactly its `PackageManager` bucket. Do not infer bytes for unknown packages or scale partial coverage into an estimate.
4. `ManagerDiskUsage` records manager, known bytes, an `overflowed` flag, and measured-package count. Include a manager with measured zero bytes; omit managers that have no measured packages. Order manager rows by overflow first, then bytes descending, then `manager.rawValue` ascending.
5. `largestPackages` contains at most `max(0, largestLimit)` measured packages, ordered by bytes descending and then stable `Package.id` ascending. Input order never affects output.
6. The function performs no clock, filesystem, persistence, process, or network access and never mutates its input.

Use `addingReportingOverflow` for totals so malformed persisted input cannot trap the app. On overflow, clamp only the affected aggregate to `Int64.max` and set its overflow flag; subsequent additions keep it clamped. Set `totalOverflowed` when the whole-inventory sum overflows and `ManagerDiskUsage.overflowed` when that manager's sum overflows. The UI renders “Exceeds supported display range” instead of formatting a clamped value as exact. Largest-package ordering still uses each package's valid non-negative value.

## Navigation and state

1. Extend `SidebarSelection` with `.diskUsage`, using the persisted key `diskUsage`. `filtered(by:query:)` returns `[]` for it because `DiskUsageView` consumes the aggregate, matching other dedicated analyses.
2. Show the sidebar entry whenever a live inventory is present, even when every size is unknown; hiding it would prevent the app from explaining incomplete measurement. Use `chart.bar.xaxis` and the title “Disk Usage.”
3. Route it through `RootView` to `DiskUsageView`. It does not support Cleanup Mode, so entering the section reconciles/exits bulk cleanup exactly like Read-only/AI/snapshots when no eligible cleanup scope exists.
4. Persist only the sidebar selection through the existing UI preference path. Chart hover, scroll position, top-package selection, and any transient focus are not separately persisted.
5. Selecting a top package sets `selectedPackage` by stable ID and opens `PackageDetailView`. If refresh/removal makes that package absent or no longer part of the displayed top list, reconcile the detail selection to nil.

## View behavior

### Summary

- Headline: formatted `totalKnownBytes` under “Measured package payload.”
- If `totalOverflowed` is true, replace the formatted headline with “Exceeds supported display range” and retain the coverage counts.
- Coverage: “X of Y packages measured.”
- When `unknownPackageCount > 0`, show a visible secondary notice: “Totals exclude N packages whose bounded size measurement was unavailable.” Do not call those packages zero-sized.
- While a scan is updating an existing inventory, keep the last complete inventory visible with an inline updating indicator; do not flash to an empty chart. With no inventory yet, reuse the truthful scanning/no-inventory analysis empty states.

### Manager chart

- Use `import Charts` and a horizontal `BarMark` for each `ManagerDiskUsage`, ordered by the Core result.
- Label every row with the user-facing manager name and formatted byte total. Color may reinforce manager identity, but text and position carry all meaning; never rely on color alone.
- An overflowed manager uses its clamped value only for relative bar placement and labels the value “Exceeds supported display range”; it is never announced as an exact byte count.
- Use semantic/system colors that remain legible in Light/Dark Mode and Increased Contrast. Do not add a legend when the y-axis labels already identify every bar.
- Provide an accessibility label/value per mark, for example “Homebrew, 3.2 gigabytes across 42 measured packages.”
- The chart is explanatory, not a filesystem control. Bars do not rescan, reveal folders, generate scripts, or navigate to manager sections.

### Largest packages

- Render the ten Core-ranked packages in a native single-selection `List`, with package name, manager badge, and formatted known size. Keep this list rather than making chart marks the only way to select a package; it preserves arrow-key navigation and precise VoiceOver behavior.
- Selection is ID-based and drives the detail column. Reuse the safe row context actions if practical, but do not add a direct destructive action; cleanup remains generated-script-only through the established package detail flow.
- The fixed top-ten limit prevents thousands of chart marks or rows. Copy says “Largest measured packages,” not simply “Largest packages.”

## Zero, unknown, and empty states

- **No live inventory:** use the existing scan/no-inventory/incomplete-coverage language; do not imply a completed zero-byte result.
- **Inventory, all sizes unknown:** show `ContentUnavailableView` titled “Size Data Unavailable,” the measured/unknown counts, and an explanation that bounded scans did not produce complete size measurements. Do not render an empty zero axis.
- **At least one measured package, total is zero:** show “0 bytes measured” plus coverage and an explicit “Measured packages contain no logical file bytes” state instead of a visually blank bar chart. This is distinct from unknown data.
- **Partial coverage:** chart only measured values and keep the exclusion notice adjacent to the total.
- **Complete positive coverage:** show the normal summary, chart, and largest list without an unnecessary warning.

## Accessibility and keyboard

- The sidebar entry participates in ordinary source-list arrow navigation. The largest-package list supports arrows and stable single selection; `Command-F` is not introduced because the view is a fixed aggregate/top-ten analysis.
- Give the chart an overall label (“Measured package payload by manager”) and each mark an exact manager/bytes/package-count value. The same values remain available as visible text.
- Unknown coverage and zero coverage are text, not color-only warnings. ByteCountFormatter supplies localized human-readable values; accessibility values include units.
- Use semantic text styles and standard controls. Avoid custom animation; refreshes should update without decorative transitions, satisfying Reduce Motion by construction.
- Verify VoiceOver order: summary, coverage notice, manager chart, then largest-package list.

## Performance

1. Compute aggregation once per inventory generation. Extend the coordinator's existing `InventoryDerivedCache` (including its invalidation/test instrumentation if appropriate) instead of sorting the entire inventory on every SwiftUI observation.
2. Core aggregation is one pass for counts/totals/buckets plus bounded ranking work; at worst `O(n log n)` for deterministic largest ordering. Manager ordering is bounded by `PackageManager.allCases`.
3. Render at most one chart mark per measured manager and ten package rows. Do not create a mark per package.
4. The view consumes persisted `Package.sizeBytes`; opening or interacting with it never walks directories, starts security-scoped access, queries GRDB, or triggers a scan.

## Regression tests

Add focused Core tests in `DiskUsageSummaryTests.swift`:

- **APP-F4: nil and negative sizes are unknown and contribute no bytes.**
- **APP-F4: measured zero remains measured and is not converted to unknown.**
- **APP-F4: totals and manager buckets contain each package exactly once.**
- **APP-F4: manager ordering is bytes descending with a stable manager tie-breaker.**
- **APP-F4: largest packages honor the limit, exclude unknowns, and break equal-size ties by ID.**
- **APP-F4: aggregation is deterministic, overflow-safe, and input-immutable.**

Add app-target regressions for:

- `.diskUsage` UserDefaults-key round-trip and dedicated-filter behavior;
- Disk Usage not advertising bulk cleanup support;
- aggregation cache reuse and invalidation after inventory replacement; and
- selected top-package reconciliation after the package disappears or falls outside the displayed largest set.

All existing size, list sort, cleanup-score, sidebar persistence, and selection-reconciliation tests remain green.

## Manual QA

1. Open Disk Usage in demo mode and after a real scan; verify manager totals equal the visible measured package totals and the top list is descending.
2. Exercise all-unknown, partial, measured-zero, and no-inventory previews/test fixtures. Confirm no unknown value appears as 0 bytes and no incomplete total is presented as exact disk capacity or reclaimable space.
3. Select a largest package with mouse and keyboard, inspect its detail, refresh, and navigate away/back. Confirm stable selection and correct reconciliation.
4. Resize from the minimum window to a wide window; verify labels do not overlap and the chart remains readable without horizontal page scrolling.
5. Verify Light/Dark Mode, Increase Contrast, Bold Text, VoiceOver mark/list announcements, Full Keyboard Access, and Reduce Motion.
6. Confirm opening and interacting with the view causes no security-scope prompt, filesystem activity, subprocess, network request, package mutation, or script execution.

## Implementation file scope

- `Installory/Sources/InstalloryCore/Models/DiskUsageSummary.swift` (new)
- `Installory/Sources/InstalloryCore/Models/SidebarSelection.swift`
- `Installory/Tests/InstalloryCoreTests/DiskUsageSummaryTests.swift` (new)
- relevant sidebar/filter model tests
- `App/Sources/AppCoordinator.swift` (generation-keyed aggregate and selection reconciliation)
- `App/Sources/Views/DiskUsageView.swift` (new; only app file importing `Charts`)
- `App/Sources/Views/RootView.swift`
- `App/Sources/Views/SidebarView.swift`
- `App/Tests/AppCoordinatorPersistenceTests.swift`
- `handoff/specs/15-disk-usage-chart.md`

Run core tests after Core work. Regenerate the Xcode project after adding app/test files, then run the generated app tests and compile gate. Apple Charts is an SDK framework; add no package dependency and never hand-edit `Installory.xcodeproj`.

## Invariants

Disk Usage visualizes inventory already collected under existing read-only grants. It never measures on demand, mutates the Mac, executes commands, starts a subprocess, uses the network, broadens sandbox access, or changes provenance's local opt-in behavior.
