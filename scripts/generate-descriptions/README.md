# Description corpus generator

This dependency-free Python tool builds
`App/Resources/descriptions.json` from Homebrew, PyPI, and npm metadata. The
generated JSON is committed and bundled with Installory; the shipping app never
uses the network.

## Requirements

Python 3.9 or newer. Run commands from the repository root.

## Common commands

Generate the production corpus using the current ignored cache:

```bash
python3 scripts/generate-descriptions/generate.py
```

For a release refresh, discard cached API responses first so upstream metadata
is fetched again:

```bash
rm -rf scripts/generate-descriptions/.cache
python3 scripts/generate-descriptions/generate.py
```

Fetch and validate without replacing the output corpus:

```bash
python3 scripts/generate-descriptions/generate.py --check
```

`--check` may update ignored response caches or create a missing seed file. It
does not replace `descriptions.json`.

Use a separate output for partial development runs:

```bash
python3 scripts/generate-descriptions/generate.py \
  --limit 500 \
  --output /tmp/installory-descriptions.json
```

`--limit`, `--no-pip`, and `--no-npm` cannot replace the production corpus
unless `--allow-partial` is explicitly supplied. That override is intentionally
unsafe and must never be used for a release.

## Safety and reproducibility

- The production file is validated before an atomic replacement.
- Counts must match the emitted keys, names must use the expected normalization,
  and descriptions must be non-empty and bounded.
- Full runs must satisfy absolute count floors and retain at least 80% of every
  manager in the last-good corpus.
- Per-package responses live in the ignored `.cache/` directory so interrupted
  runs can resume.
- Committed PyPI and npm seed lists make package selection reproducible. Delete a
  seed deliberately only when updating the selected package population.

The JSON schema is:

```json
{
  "generated": "<ISO-8601 timestamp>",
  "counts": { "brew": 0, "brewCask": 0, "pip": 0, "npm": 0 },
  "descriptions": {
    "brew:ffmpeg": "Package summary",
    "pip:requests": "Package summary",
    "npm:lodash": "Package summary"
  }
}
```

Homebrew names are stored exactly, pip names use PEP 503 normalization, and npm
names are lowercased while retaining scopes. `DescriptionStore` mirrors these
rules at runtime.

## Tests and attribution

```bash
python3 -m unittest discover \
  -s scripts/generate-descriptions/tests \
  -p 'test_*.py'
```

Source and licensing notes are in [LICENSES.md](LICENSES.md).
