# Spec 12 — Machine-readable JSON inventory export

**Workstream:** APP-F5. **Depends on:** nothing. **Core scope:** `InventoryExporter` only; app wiring follows separately.

## Problem

Installory can export CSV and Markdown, but neither is an ideal interchange format for scripts, archives, or tools that need the complete typed inventory. `Package` already conforms to `Codable`, so maintaining a second export schema would add drift without adding value.

## Current state

- `InventoryExporter.Format` supports `.csv` and `.markdown` and maps them to `csv` and `md` file extensions.
- `InventoryExporter.export(_:format:)` is a pure, synchronous formatter. The app owns the save panel and filesystem write.
- `Package` is the shipped Codable model. Its synthesized representation includes stable identity, manager and qualifier, version, paths, install metadata, size, explicit/read-only state, dependencies, artifacts, and `lastSeen`.
- Package detail JSON already encodes dates as Unix seconds and uses Foundation's pretty-printed, sorted-key output.

## Export contract

Add `.json` without changing CSV or Markdown behavior.

- The document is a top-level array of the existing `Package` Codable representation. There is no parallel DTO, wrapper object, generated timestamp, or schema metadata.
- Codable property names remain camel-cased exactly as declared by `Package`; manager and confidence values use their existing enum raw values. Nil optionals follow synthesized Codable behavior and are omitted.
- Dates encode as numeric seconds since the Unix epoch, matching the existing package-detail JSON representation. URLs use their existing Codable string representation.
- Records are ordered by stable package identity (`id`) so the export does not vary with scanner completion or input ordering. Equivalent duplicate records are interchangeable.
- JSON object keys are sorted and the document is pretty-printed with a trailing newline. The same inventory therefore produces a diff-friendly byte-identical export.
- JSON strings use JSON escaping only. Spreadsheet formula neutralization remains specific to CSV; a package literally named `=tool` must round-trip unchanged through JSON.
- `Format.json.fileExtension` is `json`.

## Implementation notes

1. Extend the existing format switch and add a private JSON renderer in `InventoryExporter.swift`.
2. Encode `[Package]` directly with `JSONEncoder`, `.prettyPrinted`, `.sortedKeys`, and `.secondsSince1970`.
3. Keep the formatter side-effect free: no filesystem access, process execution, network access, or clock reads.
4. Do not reorder or otherwise change CSV/Markdown output as part of this feature.

## Tests

- `.json` advertises the `json` file extension and participates in `Format.allCases`.
- A package with every optional field populated decodes back to the same `Package` using Unix-second date decoding.
- Reversing input order produces the same JSON, with records ordered by `id`.
- Output is pretty-printed, keys are lexicographically ordered, and it ends with one newline.
- Formula-like and control-containing strings round-trip unchanged; CSV's existing neutralization tests remain green.
- Empty inventory exports as a valid empty JSON array.

## Guardrails

This remains a generated user-selected export. It does not write by itself, scan additional data, transmit data, execute a script, or weaken sandbox access.
