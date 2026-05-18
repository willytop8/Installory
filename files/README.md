# Installory

A native macOS app that helps you understand and clean up the packages cluttering your machine across every package manager you've used — Homebrew, pip, npm, and more.

> **Status:** Feature-complete and in pre-release hardening ahead of Mac App Store submission.

## What it does

If you've spent the last year coding with AI assistants, you've probably run `brew install` and `pip install` and `npm install -g` dozens of times based on whatever Claude or Cursor told you to. Installory scans every package manager on your Mac, explains each package in plain English, traces when and why you installed it, and helps you safely remove the stuff you don't need anymore.

## Why it exists

The existing tools — Homebrew's CLI, `pip list`, GUI wrappers like Taphouse, multi-manager dashboards like GlazePKG — all assume you already know what `libpng` is and why it's on your machine. They show lists. They don't explain. They don't tell you what you were doing the day you installed something. Installory is for everyone who let an AI install software on their behalf and now can't remember which projects depended on what.

## Tech stack

- **Swift 6.1+ / SwiftUI** — native macOS, Apple Silicon and Intel
- **GRDB.swift** for SQLite persistence
- **Mac App Store** for distribution and updates (sandboxed, file-access entitlements + user-granted folder access)
- **Bundled JSON description corpus** — plain-language descriptions sourced from upstream registry metadata (formulae.brew.sh, PyPI, npm) at build time
- No Electron. No web view. No telemetry. No network calls at runtime.

## Architecture at a glance

```
┌──────────────────────────────────────────────────────────┐
│                       SwiftUI Views                      │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────┴─────────────────────────────────┐
│      Coordinators / @Observable view-state objects       │
└────────────────────────┬─────────────────────────────────┘
                         │
   ┌─────────────────────┼─────────────────┬────────────────┐
   │                     │                 │                │
┌──┴──────┐      ┌───────┴──────┐   ┌──────┴──────┐   ┌─────┴──────┐
│Scanners │      │ Descriptions │   │ Provenance  │   │  Safety    │
│(brew,   │      │ (bundled,    │   │ (3-signal   │   │ (snapshots │
│ pip,    │      │  read-only)  │   │  pipeline + │   │  + cleanup │
│ npm…)   │      │              │   │  template   │   │  script    │
│  files- │      │              │   │  narratives)│   │  generator)│
│  only   │      │              │   │             │   │            │
└──┬──────┘      └───────┬──────┘   └──────┬──────┘   └─────┬──────┘
   │                     │                 │                │
┌──┴─────────────────────┴─────────────────┴────────────────┴──────┐
│      GRDB (SQLite) + sandboxed filesystem (user-granted)         │
└──────────────────────────────────────────────────────────────────┘
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for detail.

## Getting started

From the repository root:

```bash
./scripts/regenerate-xcode.sh
open Installory.xcodeproj
```

For more context:

- [`PRODUCT.md`](PRODUCT.md) — what Installory is and why it exists
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how the app and core library are structured
- [`safety.md`](safety.md) — cleanup script and snapshot safety model
- [`sandboxing.md`](sandboxing.md) — App Store sandbox and file-access model

## Status & license

License decisions deferred.
