#!/usr/bin/env python3
"""
Installory descriptions corpus generator.

Fetches one-line package descriptions from:
  - Homebrew formulae and casks  (bulk API — two requests total)
  - PyPI top packages            (seed list from hukovk/top-pypi-packages)
  - npm popular packages         (seed list from seeds/npm-seed-list.json)

Output: ../../App/Resources/descriptions.json

Usage:
  python3 generate.py                  full run (all registries, all packages)
  python3 generate.py --limit 500      cap pip and npm to 500 packages each
  python3 generate.py --no-pip         skip PyPI
  python3 generate.py --no-npm         skip npm

The script is resumable: per-package responses are cached in .cache/ and
reused on re-runs. Interrupt at any time — the next run picks up where
this one left off.

Seed lists (the package names to fetch) are committed in seeds/. If an
upstream seed source fails, the committed list is the fallback, ensuring
reproducible re-runs on air-gapped or rate-limited machines.

Requires Python 3.9+. No third-party dependencies (stdlib only).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUTPUT = REPO_ROOT / "App" / "Resources" / "descriptions.json"
CACHE_DIR = SCRIPT_DIR / ".cache"
SEEDS_DIR = SCRIPT_DIR / "seeds"

MAX_DESC_LEN = 200  # Characters; longer descriptions are truncated with "…"

# ---------------------------------------------------------------------------
# Hardcoded npm fallback seed
# Used only when seeds/npm-seed-list.json is absent AND the npm search API
# is unreachable. Covers the most depended-upon packages as of 2026-05.
# ---------------------------------------------------------------------------

_NPM_HARDCODED_SEED: list[str] = [
    # Core utilities
    "lodash", "underscore", "ramda", "immer", "immutable",
    "rxjs", "async", "bluebird", "p-limit", "p-queue",
    # HTTP / networking
    "axios", "node-fetch", "got", "superagent", "ky",
    "cors", "helmet", "compression", "cookie-parser", "socket.io", "ws",
    # React ecosystem
    "react", "react-dom", "react-router", "react-router-dom",
    "redux", "react-redux", "@reduxjs/toolkit", "mobx", "zustand",
    "@testing-library/react", "react-query", "swr",
    # Meta-frameworks
    "next", "gatsby", "nuxt", "svelte", "@sveltejs/kit",
    # Vue / Angular
    "vue", "vuex", "vue-router", "@angular/core",
    # Build tools
    "webpack", "rollup", "parcel", "vite", "esbuild", "turbo", "nx", "lerna",
    # Babel
    "@babel/core", "@babel/preset-env", "@babel/preset-react",
    # TypeScript
    "typescript", "ts-node", "tsx",
    "@types/node", "@types/react", "@types/lodash",
    # Testing
    "jest", "vitest", "mocha", "chai", "jasmine",
    "cypress", "puppeteer", "playwright", "@playwright/test",
    "@testing-library/react",
    # Linting / formatting
    "eslint", "prettier", "stylelint",
    # Database / ORM
    "mongoose", "sequelize", "knex", "prisma", "typeorm",
    "pg", "mysql2", "sqlite3", "better-sqlite3", "redis", "ioredis",
    # Auth / security
    "jsonwebtoken", "passport", "bcrypt", "bcryptjs",
    # Validation
    "joi", "yup", "zod", "ajv",
    # CLI
    "commander", "yargs", "minimist", "inquirer",
    "chalk", "ora", "cli-progress", "boxen",
    # File system
    "glob", "rimraf", "mkdirp", "fs-extra", "chokidar",
    # Process management
    "nodemon", "pm2", "concurrently", "npm-run-all", "cross-env",
    # Date / time
    "moment", "dayjs", "date-fns", "luxon",
    # ID generation
    "uuid", "nanoid", "shortid",
    # Config / env
    "dotenv", "config", "convict",
    # Logging
    "winston", "pino", "morgan", "debug",
    # Web scraping / parsing
    "cheerio", "jsdom",
    # GraphQL
    "graphql", "@apollo/client", "apollo-server",
    # Misc
    "sharp", "nodemailer", "stripe", "aws-sdk",
    "tailwindcss", "sass", "postcss", "autoprefixer",
    "semver", "normalize-url", "husky", "lint-staged",
]

# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

def normalize_pip(name: str) -> str:
    """PEP 503: lowercase then collapse runs of [-_.] to a single hyphen."""
    return re.sub(r"[-_.]+", "-", name.lower())


def normalize_npm(name: str) -> str:
    """npm names are already lowercase; just lowercase defensively."""
    return name.lower()

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

_UA = "Installory-description-generator/1.0 (https://github.com/wricchiuti/Installory)"


def _get(url: str, retries: int = 3) -> bytes:
    """Fetch URL bytes with exponential-backoff retries. Raises on final failure."""
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": _UA, "Accept": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise  # permanent; don't retry
            if attempt == retries - 1:
                raise
            time.sleep(1.5 ** attempt)
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(1.5 ** attempt)
    raise RuntimeError("unreachable")


def fetch_json(url: str) -> object:
    return json.loads(_get(url))


def truncate(text: str) -> str:
    """Trim to MAX_DESC_LEN, appending ellipsis if cut."""
    text = (text or "").strip()
    if len(text) > MAX_DESC_LEN:
        text = text[:MAX_DESC_LEN].rstrip() + "…"
    return text

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------

def fetch_homebrew() -> dict[str, str]:
    result: dict[str, str] = {}

    print("Homebrew: fetching formulae …", flush=True)
    formulae = fetch_json("https://formulae.brew.sh/api/formula.json")
    assert isinstance(formulae, list)
    for item in formulae:
        name = (item.get("name") or "").strip()
        desc = (item.get("desc") or "").strip()
        if name and desc:
            result[f"brew:{name}"] = truncate(desc)
    brew_count = sum(1 for k in result if k.startswith("brew:"))
    print(f"  {brew_count} formulae", flush=True)

    print("Homebrew: fetching casks …", flush=True)
    casks = fetch_json("https://formulae.brew.sh/api/cask.json")
    assert isinstance(casks, list)
    for item in casks:
        token = (item.get("token") or "").strip()
        desc = (item.get("desc") or "").strip()
        if token and desc:
            result[f"brewCask:{token}"] = truncate(desc)
    cask_count = sum(1 for k in result if k.startswith("brewCask:"))
    print(f"  {cask_count} casks", flush=True)

    return result

# ---------------------------------------------------------------------------
# PyPI
# ---------------------------------------------------------------------------

def _load_pypi_seed(limit: int | None) -> list[str]:
    seed_file = SEEDS_DIR / "pypi-seed-list.json"

    if seed_file.exists():
        with open(seed_file) as f:
            names: list[str] = json.load(f)
        print(f"  Using {len(names)} names from seeds/pypi-seed-list.json", flush=True)
    else:
        url = (
            "https://hugovk.github.io/top-pypi-packages/"
            "top-pypi-packages-30-days.min.json"
        )
        try:
            data = fetch_json(url)
            assert isinstance(data, dict) and "rows" in data
            names = [row["project"] for row in data["rows"]]
            SEEDS_DIR.mkdir(parents=True, exist_ok=True)
            with open(seed_file, "w") as f:
                json.dump(names, f, indent=2)
            print(
                f"  Fetched {len(names)} names → seeds/pypi-seed-list.json",
                flush=True,
            )
        except Exception as exc:
            print(
                f"  WARNING: could not fetch PyPI seed list: {exc}",
                file=sys.stderr,
                flush=True,
            )
            names = []

    return names[:limit] if limit is not None else names


def fetch_pypi(limit: int | None) -> dict[str, str]:
    print("PyPI: loading seed list …", flush=True)
    names = _load_pypi_seed(limit)
    if not names:
        print("  No PyPI packages to fetch.", flush=True)
        return {}

    print(f"PyPI: fetching {len(names)} packages …", flush=True)
    cache_dir = CACHE_DIR / "pypi"
    cache_dir.mkdir(parents=True, exist_ok=True)

    result: dict[str, str] = {}
    fetched = cached = failed = 0
    _bad_summaries = {"unknown", "fixme", "todo", "tbd", "n/a", "none", ""}

    for i, name in enumerate(names, 1):
        cache_file = cache_dir / f"{urllib.parse.quote(name, safe='')}.json"
        data: dict | None = None

        if cache_file.exists():
            try:
                with open(cache_file) as f:
                    data = json.load(f)
                cached += 1
            except Exception:
                cache_file.unlink(missing_ok=True)

        if data is None:
            try:
                raw = _get(f"https://pypi.org/pypi/{urllib.parse.quote(name)}/json")
                data = json.loads(raw)
                with open(cache_file, "wb") as f:
                    f.write(raw)
                fetched += 1
                time.sleep(0.12)
            except Exception as exc:
                failed += 1
                if failed <= 10:
                    print(f"  SKIP {name}: {exc}", file=sys.stderr, flush=True)
                continue

        if data:
            summary = ((data.get("info") or {}).get("summary") or "").strip()
            if summary.lower() not in _bad_summaries:
                key = f"pip:{normalize_pip(name)}"
                result[key] = truncate(summary)

        if i % 500 == 0:
            print(
                f"  … {i}/{len(names)} "
                f"(fetched={fetched}, cached={cached}, failed={failed})",
                flush=True,
            )

    print(
        f"  {len(result)} descriptions "
        f"(fetched={fetched}, cached={cached}, failed={failed})",
        flush=True,
    )
    return result

# ---------------------------------------------------------------------------
# npm
# ---------------------------------------------------------------------------

def _load_npm_seed(limit: int | None) -> list[str]:
    seed_file = SEEDS_DIR / "npm-seed-list.json"

    if seed_file.exists():
        with open(seed_file) as f:
            names: list[str] = json.load(f)
        print(f"  Using {len(names)} names from seeds/npm-seed-list.json", flush=True)
        # Attempt to expand if fewer than 1000 packages in the committed list
        # and no --limit flag is forcing a small run.
        if limit is None and len(names) < 1000:
            names = _try_expand_npm_seed(names, seed_file)
    else:
        print("  seeds/npm-seed-list.json not found; fetching from npm …", flush=True)
        names = _try_expand_npm_seed([], seed_file)

    return names[:limit] if limit is not None else names


def _try_expand_npm_seed(existing: list[str], seed_file: Path) -> list[str]:
    """Try to fetch a larger npm seed list from the registry search API.

    Falls back to the hardcoded list if the API fails or returns nothing new.
    Saves the result to seed_file so future runs are reproducible.
    """
    existing_set = set(existing)
    fetched_names: list[str] = list(existing)
    page_size = 250
    max_results = 5000

    try:
        print("  Fetching npm seed list from registry search API …", flush=True)
        for from_idx in range(0, max_results, page_size):
            url = (
                "https://registry.npmjs.org/-/v1/search"
                f"?text=*&size={page_size}&from={from_idx}"
                "&quality=0.0&maintenance=0.0&popularity=1.0"
            )
            data = fetch_json(url)
            assert isinstance(data, dict)
            objects = data.get("objects") or []
            if not objects:
                break
            for obj in objects:
                pkg_name = (obj.get("package") or {}).get("name") or ""
                if pkg_name and pkg_name not in existing_set:
                    fetched_names.append(pkg_name)
                    existing_set.add(pkg_name)
            time.sleep(0.25)
            if len(objects) < page_size:
                break

        print(f"  Fetched {len(fetched_names)} names total.", flush=True)
    except Exception as exc:
        print(
            f"  WARNING: npm search API failed: {exc}. "
            "Falling back to hardcoded seed list.",
            file=sys.stderr,
            flush=True,
        )
        for name in _NPM_HARDCODED_SEED:
            if name not in existing_set:
                fetched_names.append(name)
                existing_set.add(name)
        print(f"  Using {len(fetched_names)} names (hardcoded fallback).", flush=True)

    if fetched_names:
        SEEDS_DIR.mkdir(parents=True, exist_ok=True)
        with open(seed_file, "w") as f:
            json.dump(fetched_names, f, indent=2)
        print(f"  Saved {len(fetched_names)} names → {seed_file.name}", flush=True)

    return fetched_names


def fetch_npm(limit: int | None) -> dict[str, str]:
    print("npm: loading seed list …", flush=True)
    names = _load_npm_seed(limit)
    if not names:
        print("  No npm packages to fetch.", flush=True)
        return {}

    print(f"npm: fetching {len(names)} packages …", flush=True)
    cache_dir = CACHE_DIR / "npm"
    cache_dir.mkdir(parents=True, exist_ok=True)

    result: dict[str, str] = {}
    fetched = cached = failed = 0

    for i, name in enumerate(names, 1):
        # Filesystem-safe cache key: @scope/pkg → AT_scope__pkg
        safe_name = name.replace("@", "AT_").replace("/", "__")
        cache_file = cache_dir / f"{safe_name}.json"
        data: dict | None = None

        if cache_file.exists():
            try:
                with open(cache_file) as f:
                    data = json.load(f)
                cached += 1
            except Exception:
                cache_file.unlink(missing_ok=True)

        if data is None:
            # Scoped packages: @types/node → @types%2Fnode (@ kept, / encoded)
            encoded = urllib.parse.quote(name, safe="@")
            url = f"https://registry.npmjs.org/{encoded}/latest"
            try:
                raw = _get(url)
                data = json.loads(raw)
                with open(cache_file, "wb") as f:
                    f.write(raw)
                fetched += 1
                time.sleep(0.12)
            except Exception as exc:
                failed += 1
                if failed <= 10:
                    print(f"  SKIP {name}: {exc}", file=sys.stderr, flush=True)
                continue

        if data:
            desc = (data.get("description") or "").strip()
            if desc:
                key = f"npm:{normalize_npm(name)}"
                result[key] = truncate(desc)

        if i % 500 == 0:
            print(
                f"  … {i}/{len(names)} "
                f"(fetched={fetched}, cached={cached}, failed={failed})",
                flush=True,
            )

    print(
        f"  {len(result)} descriptions "
        f"(fetched={fetched}, cached={cached}, failed={failed})",
        flush=True,
    )
    return result

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Installory package descriptions corpus."
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        metavar="N",
        help="Cap pip and npm to N packages each (useful for fast partial runs).",
    )
    parser.add_argument("--no-pip", action="store_true", help="Skip PyPI.")
    parser.add_argument("--no-npm", action="store_true", help="Skip npm.")
    args = parser.parse_args()

    descriptions: dict[str, str] = {}

    # Homebrew is always fetched — it's bulk and fast.
    descriptions.update(fetch_homebrew())

    if not args.no_pip:
        descriptions.update(fetch_pypi(args.limit))

    if not args.no_npm:
        descriptions.update(fetch_npm(args.limit))

    counts = {
        "brew": sum(1 for k in descriptions if k.startswith("brew:")),
        "brewCask": sum(1 for k in descriptions if k.startswith("brewCask:")),
        "pip": sum(1 for k in descriptions if k.startswith("pip:")),
        "npm": sum(1 for k in descriptions if k.startswith("npm:")),
    }
    corpus = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "counts": counts,
        "descriptions": descriptions,
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        # Compact JSON (no indentation) — keeps file size down.
        json.dump(corpus, f, ensure_ascii=False, separators=(",", ":"))

    total = sum(counts.values())
    print(f"\n✓ {total} descriptions written to {OUTPUT.relative_to(REPO_ROOT)}")
    print(
        f"  brew={counts['brew']}, cask={counts['brewCask']}, "
        f"pip={counts['pip']}, npm={counts['npm']}"
    )


if __name__ == "__main__":
    main()
