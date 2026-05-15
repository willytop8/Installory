# Descriptions

How Backshelf gets a plain-English description of every package on the user's machine. The bundled corpus is the whole story — there are no live lookups and no LLM in the runtime.

## Why this matters

A non-technical user looks at their inventory and sees `libpng`, `c-ares`, `libuv`, `ncurses`. Without descriptions, they have nothing to act on. The whole product depends on every row being readable.

## The model

Descriptions are sourced from upstream package registry metadata at build time, written into a SQLite file, and bundled with the app. The runtime app does a single `(manager, name)` lookup against that bundled file. No network calls. No API key. No live generation.

If a package isn't in the bundle, the UI shows the package name plus the literal text "No description available". We never fabricate.

## Coverage

| Manager | Approx. count | Upstream source |
| --- | --- | --- |
| brew (formulae) | ~7,000 | `https://formulae.brew.sh/api/formula.json` |
| brewCask | ~6,500 | `https://formulae.brew.sh/api/cask.json` |
| pip | top 5,000 by downloads | PyPI JSON API (`https://pypi.org/pypi/<name>/json`), package list via top-pypi-packages or BigQuery |
| npm | top 3,000 by downloads | npm registry API (`https://registry.npmjs.org/<name>`) |
| cargo | top 500 | crates.io API (`https://crates.io/api/v1/crates/<name>`) |
| gem | top 500 | rubygems.org API (`https://rubygems.org/api/v1/gems/<name>.json`) |

Total around 20,000 entries. At ~200 bytes per description, that's ~4MB compressed. Reasonable to ship.

These cover the long fat-head of what an AI-coding user actually installs. The long tail falls into "No description available", which is honest and rare in practice.

## Where the descriptions come from

Each registry exposes a short `description` or `summary` field that's already written by the package's own author. We use that text verbatim where it's good, lightly normalize where it's not (strip leading capitalization quirks, trim to two sentences, drop ALL CAPS), and write the result to SQLite. The intent is to use the upstream author's own words — they know best what their package does — not to rewrite them.

A small list of common style fixes (handled in the build-time script):

- Drop bracketed badge syntax often left at the top of `description` fields (`[![Build](...)](...)`)
- Collapse internal whitespace
- Trim to the first sentence or two if the upstream field is paragraph-length
- Skip entries that are blank, "TODO", or "Updated description coming soon"

If after normalization an entry is still empty, the package gets no row in the corpus — and the runtime UI shows "No description available".

## Build-time pipeline

A maintainer-only Swift CLI tool lives at `scripts/generate-descriptions/`. It is not part of the app target. It:

1. Fetches the package lists per registry (some are single JSON dumps; others require enumerating top-N by downloads from a separate source).
2. For each package, fetches its registry metadata.
3. Normalizes the `description` / `summary` field.
4. Writes a row to `Resources/descriptions.db`.
5. Resumes from a checkpoint file if the run is interrupted.
6. Is polite to upstream APIs (per-host rate limit, exponential backoff on transient errors).

Run periodically (quarterly?) and commit the updated `descriptions.db` to the repo.

```bash
cd scripts/generate-descriptions
swift run backshelf-descriptions \
    --output ../../Backshelf/Resources/descriptions.db \
    --checkpoint ./checkpoint.json
```

Total cost: free (just the upstream APIs, which are public). Total wall-clock: a few hours, dominated by being polite to registries.

## Schema

```sql
CREATE TABLE bundled_descriptions (
    manager   TEXT NOT NULL,
    name      TEXT NOT NULL,
    text      TEXT NOT NULL,
    PRIMARY KEY (manager, name)
);
```

That's it. No timestamps (regeneration replaces the whole file). No source URL (descriptions are derived, not copies; the homepage link comes from the live registry metadata at scan time when we have it).

## Lookup

`DescriptionStore.lookup(manager:name:)` checks the bundled SQLite. If the row exists, return it. If not, return `nil`. The caller renders "No description available" for `nil`.

There is no fallback layer, no cache table, no second tier. The corpus is the source.

## Read-only system Python packages

Packages installed under `/usr/bin/python3` or the CommandLineTools Python get a static placeholder regardless of corpus state: "Part of macOS or Xcode Command Line Tools." This is hardcoded, not in the corpus.

## What we deliberately don't do

- **No live API lookups.** No Anthropic, no OpenAI, no anything. The app makes zero network calls at runtime.
- **No LLM-generated descriptions.** Every description is the upstream author's own words, lightly normalized.
- **No personalized descriptions.** Every user sees the same description for the same package.
- **No multi-language.** English only. Add localization when there's demand.
- **No fact-checking of the upstream summary.** If PyPI says a package "does X," we trust it. We're not verifying claims.
- **No manual user overrides in v1.** Post-v1 feature; the schema can be extended with a user-writable table when we're ready.
