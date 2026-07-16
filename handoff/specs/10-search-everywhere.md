# Spec 10 — Search across every package analysis

**Workstream:** Inventory navigation. **Depends on:** none. **Touches hot files:** Core `SidebarSelection`, `PackageFilterTests`, `OrphansView`, `DuplicatesView`, `AIInstalledView`.

## Problem

The primary package list can be searched, but Review Candidates, Duplicates, and AI Installed expose no search field. Existing matching also checks only `Package.name`, so an install known by its interpreter, environment, or filesystem location cannot be found by that context.

## Target state

Every live-inventory package view uses the standard macOS toolbar search field. Matching is case-insensitive across package name, manager-specific qualifier, and absolute install path. An empty or whitespace-only query preserves the input order and returns every candidate.

## Core contract

1. Add one public package predicate and array helper in Core so every view uses identical matching semantics.
2. Search fields are exactly:
   - `name`
   - `qualifier`, when present
   - `installPath.path`, when present
3. Do not include provenance commands, descriptions, dependency names, or other potentially surprising fields.
4. `filtered(by:query:)` continues applying the sidebar filter before the query and remains order-preserving; the caller still owns sorting.
5. Dedicated analysis selections still return `[]` from `filtered(by:query:)` because their views own precomputed analysis data.

## App behavior

1. Add `.searchable` to Review Candidates, Duplicates, and AI Installed using the coordinator's existing search query so the toolbar behaves consistently while navigating.
2. Review Candidates and AI Installed filter their rows with the shared Core matcher.
3. A matching member keeps its entire duplicate or multi-location group visible; hiding the companion installs would remove the comparison context that makes the group useful.
4. When analysis data exists but the query matches nothing, show `ContentUnavailableView.search(text:)`. Do not reuse a positive “no findings” analysis state for a search miss.
5. Selection remains ID-based. If a query hides the selected row, clear the detail selection so the content and detail columns cannot disagree.

## Accessibility and keyboard behavior

- Use SwiftUI's standard toolbar `.searchable`, including Command-F behavior supplied by the platform.
- Prompts name the current content (“Search duplicates”, “Search review candidates”, “Search AI-attributed packages”).
- Search results remain ordinary keyboard-navigable `List` rows; no custom focus system is introduced.

## Regression tests

- APP-F1: qualifier-only query matches the package.
- APP-F1: install-path-only query matches case-insensitively.
- APP-F1: name matching remains case-insensitive.
- APP-F1: whitespace-only query returns all packages in original order.
- APP-F1: unrelated query returns no packages.
- Existing manager/read-only/dedicated-selection behavior remains unchanged.

## Invariants

Search is an in-memory view operation. It performs no filesystem access, subprocess execution, network request, persistence, or mutation.
