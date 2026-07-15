# Installory Description Corpus Generator

Build-time tool that fetches one-line package descriptions from Homebrew, PyPI,
and npm registries and produces `App/Resources/descriptions.json`. The JSON file
is committed and bundled with the app; the app makes no network calls at runtime.

## Requirements

Python 3.9+ (no third-party packages — stdlib only).

## Usage

```bash
# Full run — all registries, all packages (~15–20 min on first run, fast on re-runs)
python3 scripts/generate-descriptions/generate.py

# Full fetch + production safety validation, without writing anything
python3 scripts/generate-descriptions/generate.py --check

# Fast partial run — it must use a separate output or --check
python3 scripts/generate-descriptions/generate.py \
  --limit 500 \
  --output /tmp/installory-descriptions-partial.json

# Skip a registry while testing, without writing anything
python3 scripts/generate-descriptions/generate.py --no-npm --check
```

Run from the repo root or from this directory — the script resolves paths
relative to itself.

## Production-write safety

The checked-in `App/Resources/descriptions.json` is treated as the last-good
production corpus:

- `--limit`, `--no-pip`, and `--no-npm` cannot replace it by default. Use a
  separate `--output PATH` for partial artifacts or `--check` for a no-write run.
- `--allow-partial` is an explicit, intentionally unsafe escape hatch for a
  maintainer who truly wants a partial corpus at the production path.
- Every corpus is validated before writing: keys must use a known manager prefix,
  pip/npm keys must be normalized, descriptions must be non-empty and bounded,
  declared counts must exactly match the description keys, and manager counts
  must add up to the total.
- Full production runs must meet conservative absolute floors and retain at least
  80% of each manager's last-good count. A failed or badly truncated registry is
  rejected without changing the checked-in file.
- Output is written to a temporary file in the destination directory, flushed,
  and atomically renamed only after validation succeeds.

Run the generator's dependency-free regression suite with:

```bash
python3 -m unittest discover \
  -s scripts/generate-descriptions/tests \
  -p 'test_*.py'
```

## Resumability

Per-package API responses are cached in `.cache/` (gitignored). Interrupting
mid-run and re-running picks up where it left off. A full first run fetches
~10 000+ individual package records; subsequent runs are near-instant.

## Seed lists

`seeds/pypi-seed-list.json` and `seeds/npm-seed-list.json` are the lists of
package names to fetch descriptions for. They are committed to the repo so
re-runs are reproducible without needing the upstream seed sources.

- **PyPI seed**: generated from [hugovk/top-pypi-packages](https://hugovk.github.io/top-pypi-packages/)
  (top packages by download count over the last 30 days). Re-fetched and saved
  the first time the script runs without an existing seed file.
- **npm seed**: started as a curated list of ~200 well-known packages and expanded
  via the npm registry search API on first run. If the search API fails, the
  committed list is used as a fallback.

## Updating the corpus

Run `generate.py` again and commit the updated `descriptions.json`. Re-runs are
fast because the `.cache/` already holds previously-fetched responses.
Perform one complete refresh immediately before every Installory release;
partial runs are for testing only and must not be used as release input.

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
