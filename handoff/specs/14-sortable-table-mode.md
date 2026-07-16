# Spec 14 — Sortable inventory table mode

**Workstream:** APP-F3. **Depends on:** CORE-05, APP-F1, and APP-F2. **App-only feature:** no scanner, persistence-schema, or Core model changes are required.

## Problem

The live inventory is optimized for browsing one package at a time. Its `List` rows are readable, but comparing versions, sizes, and install dates requires scanning annotations, and sorting is limited to six mutually-exclusive presets in a menu. A Mac user with hundreds or thousands of packages needs a dense, native table without losing the existing approachable list.

## Target state

The ordinary live-inventory sections (`All packages`, a package manager, and `Read-only`) offer **List** and **Table** modes. List remains the default and keeps its current row design and sort picker. Table uses SwiftUI's native macOS `Table` with sortable **Name**, **Manager**, **Version**, **Size**, and **Installed** columns. Both modes share the same sidebar filter, search query, selected package, detail pane, cleanup selection, banners, and empty states.

Dedicated views for Duplicates, Review Candidates, AI Installed, Disk Usage, and snapshots keep their purpose-built layouts. This feature does not flatten grouped analysis into a table.

## View-mode behavior

1. Add a labeled segmented picker in `PackageListView`'s toolbar with `list.bullet` and `tablecells` choices. Its accessible label is “Inventory view.”
2. Add stable View-menu commands **Show as List** (`Command-1`) and **Show as Table** (`Command-2`). Commands update the same state as the picker and are disabled outside an ordinary live-inventory section if they would have no visible effect.
3. Switching modes preserves `searchQuery`, `selectedPackage`, `isCleanupMode`, and `selectedForCleanup`. It must not dismiss a valid detail selection or silently drop checked cleanup rows.
4. Persist the mode as a canonical `DefaultsKey` presentation preference. Restore unknown/corrupt values as `.list`; migrate no additional legacy key.
5. Keep list preset sorting and table column sorting as separate preferences. Returning to List restores the existing `PackageSortOrder`; returning to Table restores the table descriptor sequence. Persist the table descriptors using validated raw column/direction values, falling back to Name ascending if the stored value is absent or invalid.
6. Do not persist search text, row selection, cleanup selection, scroll position, or column widths. Those are session/document-view state; native table resizing remains available during the session.

## Native table contract

Use a single-selection `Table` bound by `Package.id`, not array index. Selecting a row immediately drives the existing `PackageDetailView`; clearing selection clears the detail. The visible source is the same order-preserving Core filter used by List, followed by table sorting rather than the list preset sort.

| Column | Cell | Sort value | Sizing |
|---|---|---|---|
| Name | Package name; prepend the shared cleanup toggle/lock while Cleanup Mode is active | Localized, case-insensitive name | Flexible, minimum 160 pt |
| Manager | User-facing `PackageManager.displayName` | Localized display name, then manager raw value | 110–150 pt |
| Version | Monospaced version text | Localized-standard/numeric-aware string comparison; this is deliberately not semantic-version parsing | 90–130 pt |
| Size | File-style `ByteCountFormatter` text, trailing aligned; “Unknown” for nil | Numeric bytes | 90–120 pt |
| Installed | Existing confidence-aware date wording; “Unknown” for nil | `installedAt` date | 120–170 pt |

The table must retain row context-menu parity with List: Copy Name, Copy Install Path when present, Reveal in Finder when available, and Create Removal Script when eligible. Extract a small shared action/menu helper if needed; do not duplicate filesystem or removal eligibility rules.

The table may truncate long cell text at narrow widths, but every truncated value has its full value in help/accessibility text. Let the native table own column resizing, header interaction, row highlight, scrolling, and arrow-key navigation; do not wrap it in a custom grid.

## Sorting contract

Bind the table's header state to an ordered descriptor sequence. Header clicks use native ascending/descending behavior and Shift-click may add a secondary descriptor. Apply descriptors in order, then always compare `Package.id` ascending as the final tie-breaker so scanner completion order never changes equal rows.

- Name and Manager use localized case-insensitive comparison.
- Version uses localized-standard comparison so numeric components are human-friendly, without claiming every manager uses SemVer.
- Size compares exact `Int64` bytes. `sizeBytes == nil` is **unknown, not zero**, and always follows every known size in both ascending and descending order.
- Installed compares exact dates. `installedAt == nil` always follows every known date in both directions. Confidence changes the label, not the chronological sort value.
- Reversing a primary direction reverses only known primary values; the stable ID tie-break remains ascending.
- Sorting is a pure in-memory presentation operation and never mutates `coordinator.packages`.

## Search and cleanup interaction

1. Table uses the existing `.searchable` field and shared name/qualifier/install-path matcher. A search miss shows the existing search empty state, not an empty table shell.
2. If search or sidebar filtering hides the selected package, the existing selection reconciliation clears the detail in either mode.
3. In Cleanup Mode, the Name cell shows `CleanupSelectionToggle`. Eligible rows can be checked; read-only and Mac App Store rows show the shared non-interactive lock. The existing `CleanupSelectionFooter` remains the only batch action surface.
4. Sorting, resizing columns, and switching modes never alter `selectedForCleanup`. Search can temporarily hide checked rows exactly as specified by APP-F2; the footer count remains authoritative.

## Accessibility and keyboard

- Rely on native `Table` semantics for row/column navigation, sortable headers, selection announcement, and Full Keyboard Access.
- The mode picker and View-menu commands expose the same state and names. `Command-F` continues focusing the standard search field.
- Unknown cells announce “Size unknown” and “Installed date unknown,” not a blank or zero. Estimated dates announce that the date is estimated.
- Cleanup controls retain package-specific labels and selected state. Context-menu actions remain reachable through keyboard/context-menu commands.
- Use semantic fonts and colors; verify Light/Dark Mode, Increase Contrast, and Bold Text. Add no decorative table animations.

## Performance

- Capture the filtered source and sorted result once per body evaluation. Do not repeatedly call whole-inventory computed properties from individual cells.
- Sorting is `O(n log n)` over only the filtered rows. Formatting is per visible native-table row; do not prebuild views or attributed strings for the entire inventory.
- Native `Table` must render the thousands-of-packages case without one chart/mark/view per hidden row outside its own virtualization.
- No table operation may read the filesystem, recompute package sizes, query GRDB, or trigger a scan.

## Regression tests

Add named app-target tests for the presentation helpers and persistence seam:

- **APP-F3: every table sort uses stable package identity as its final tie-breaker.**
- **APP-F3: unknown size sorts after known sizes in both directions.**
- **APP-F3: unknown install date sorts after known dates in both directions.**
- **APP-F3: version sorting uses localized-standard numeric ordering.**
- **APP-F3: descriptor priority is honored before the identity tie-breaker.**
- **APP-F3: List and Table mode plus validated table descriptors round-trip through UI preference persistence.**
- **APP-F3: invalid persisted view/sort values restore safe defaults without changing the existing list sort preference.**
- Existing APP-F1 search reconciliation, APP-F2 cleanup scope, and APP25-022 list-sort stability tests remain green.

## Manual QA

1. In demo mode and a real large inventory, switch List ↔ Table from both toolbar and `Command-1`/`Command-2`; relaunch and confirm the last mode and each mode's own sort return.
2. Sort every column ascending and descending, Shift-click a secondary column, resize columns, and verify equal values do not jump across refreshes.
3. Select a row, switch modes, search it away, clear search, and change sidebar managers; confirm the content and detail columns never disagree.
4. Enter Cleanup Mode in Table, select eligible and locked rows, sort/search/switch modes, and generate a script. Confirm the exact footer count and that Installory only displays/saves the script.
5. Verify context-menu parity, keyboard row navigation, VoiceOver header/cell announcements, Light/Dark Mode, Increased Contrast, and a narrow resizable window.

## Implementation file scope

- `App/Sources/Models/InventoryViewMode.swift` (new; mode and validated table sort representation)
- `App/Sources/AppCoordinator.swift` (state, canonical defaults, restore/persist)
- `App/Sources/Views/PackageListView.swift`
- `App/Sources/Views/PackageTableView.swift` (new, recommended natural seam)
- `App/Sources/InstalloryApp.swift` (View-menu commands)
- `App/Tests/AppCoordinatorPersistenceTests.swift` and/or a focused new table-sort test file
- `handoff/specs/14-sortable-table-mode.md`

Run `./scripts/regenerate-xcode.sh` after adding app/test files, then run core tests and the generated app test/build gates. Do not hand-edit `Installory.xcodeproj`.

## Invariants

Table mode is a local presentation of the already-scanned inventory. It performs no system mutation, process execution, network request, new filesystem access, or provenance collection, and it does not weaken sandbox grants.
