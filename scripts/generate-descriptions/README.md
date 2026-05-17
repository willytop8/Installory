# Backshelf Description Corpus Generator

Build-time tool that fetches one-line package descriptions from Homebrew, PyPI,
and npm registries and produces `App/Resources/descriptions.json`. The JSON file
is committed and bundled with the app; the app makes no network calls at runtime.

## Requirements

Python 3.9+ (no third-party packages — stdlib only).

## Usage

```bash
# Full run — all registries, all packages (~15–20 min on first run, fast on re-runs)
python3 scripts/generate-descriptions/generate.py

# Fast partial run — good for verifying the pipeline
python3 scripts/generate-descriptions/generate.py --limit 500

# Skip a registry
python3 scripts/generate-descriptions/generate.py --no-npm
python3 scripts/generate-descriptions/generate.py --no-pip
```

Run from the repo root or from this directory — the script resolves paths
relative to itself.

## Resumability

Per-package API responses are cached in `.cache/` (gitignored). Interrupting
mid-run and re-running picks up where it left off. A full first run fetches
~10 000+ individual package records; subsequent runs are near-instant.

## Seed lists

`seeds/pypi-seed-list.json` and `seeds/npm-seed-list.json` are the lists of
package names to fetch descriptions for. They are committed to the repo so
re-runs are reproducible without needing the upstream seed sources.

- **PyPI seed**: generated from [hukovk/top-pypi-packages](https://hukovk.github.io/top-pypi-packages/)
  (top packages by download count over the last 30 days). Re-fetched and saved
  the first time the script runs without an existing seed file.
- **npm seed**: started as a curated list of ~200 well-known packages and expanded
  via the npm registry search API on first run. If the search API fails, the
  committed list is used as a fallback.

## Updating the corpus

Run `generate.py` again and commit the updated `descriptions.json`. Re-runs are
fast because the `.cache/` already holds previously-fetched responses.

To pull a fresh seed list (after the npm/PyPI top-packages landscape shifts):

```bash
rm scripts/generate-descriptions/seeds/pypi-seed-list.json
rm scripts/generate-descriptions/seeds/npm-seed-list.json
python3 scripts/generate-descriptions/generate.py
```

## Output format

```json
{
  "generated": "2026-05-17T...",
  "counts": { "brew": 7234, "brewCask": 1456, "pip": 3997, "npm": 231 },
  "descriptions": {
    "brew:ffmpeg": "Play, record, convert, and stream audio and video",
    "pip:requests": "Python HTTP for Humans.",
    "npm:lodash": "Lodash modular utilities."
  }
}
```

Keys use the package manager's `rawValue` prefix (`brew`, `brewCask`, `pip`,
`npm`) followed by a colon and the normalized package name:

- Homebrew: exact formula/cask token, no normalization
- pip: PEP 503 normalization (lowercase, runs of `[-_.]` → `-`)
- npm: lowercased; scoped names (`@types/node`) preserved exactly

This normalization is mirrored in `DescriptionStore.swift` so lookups match
even when the installed package name has different casing or separator style.
