# PRODUCT.md

The "why" that anchors every decision in this repo. When in doubt about a design choice, check it against this document.

## The problem

In the last 18–24 months, a new audience has emerged: people who write code with AI assistants as their primary mode, often without prior CS background. They're called "vibe coders" sometimes. They use Claude Code, Cursor, Lovable, v0. They follow instructions like "run `brew install ffmpeg`" or "pip install whisper" hundreds of times across dozens of half-finished projects.

A year in, their Macs look like this:

- Hundreds of packages across Homebrew, pip (across multiple Python versions), npm globals, cargo, gem, pipx
- They can't identify most of them
- They're afraid to remove anything because something might break
- They have no idea when they installed anything or why
- They have no mental model of which package belongs to which manager
- Disk space is gone, performance is degrading, anxiety is rising

Existing tools fail this user. The Homebrew CLI is fine if you already know what each formula does. GUI wrappers like Taphouse cover only one manager. Multi-manager dashboards like GlazePKG and `mpm` show unified lists but assume technical literacy. None of them explain anything to a non-developer. None of them tell you *why* something is on your machine.

## The user

Primary: **the non-technical user** who codes with AI.

- Learned to code by talking to Claude, Cursor, or similar
- Has shipped a few small projects; perhaps maintains a side project or two
- Uses AI coding tools daily
- Confident at the conceptual level, anxious at the system level
- Knows enough to be dangerous; not enough to be confident
- Treats the terminal as a place where Bad Things Can Happen

Secondary: **the power user**. Engineers who want a faster way to audit their own machines. They benefit from the same tool but should be able to see raw commands, dependency graphs, and exact install times without the friendly framing getting in the way. The UI exposes more depth to them rather than hiding it from the primary user.

## What we are

Backshelf is a **trustworthy guide to what's actually on your Mac and what's safe to remove.**

Three things in priority order:

1. **A unified, comprehensible inventory.** Every package, every manager, in one searchable view, with plain-English descriptions of what each thing does.
2. **Provenance.** When you installed it, what you were doing, what other related things you installed at the same time. Best evidence we have, with honest confidence labels.
3. **Cleanup scripts.** When you decide to remove something, Backshelf generates a shell script with the exact commands — annotated, ordered, and safe to read — that you run yourself in Terminal. Backshelf never touches your packages directly. This is the safer design: you see every command before it executes, in the tool you already trust for irreversible work.

## What we are not

Backshelf is **not**:

- A package manager itself — we don't install, upgrade, **or uninstall**. Cleanup is generated as a script you run yourself; Backshelf never modifies your packages directly.
- A development environment manager. We don't create venvs, manage Node versions, or set up new machines. (Adjacent tools do this.)
- A security scanner. We may surface advisories eventually, but vulnerability detection is not the wedge.
- A monitoring tool. No background daemons, no constant scanning, no telemetry by default.
- A cross-platform tool. macOS only, for now. The audience is Mac-heavy and going cross-platform from day 1 is a tax we don't need to pay.

## Differentiators

What makes Backshelf different from the dozen existing package-management tools:

1. **Plain-language descriptions of every package.** Sourced from upstream registry metadata (formulae.brew.sh, PyPI, npm, crates.io) and bundled into the app — free of jargon, available offline, no API calls. Every user should be able to read any row in the list and understand what that package is.
2. **Provenance via Claude Code logs.** For the subset of users who code with Claude Code, we can reconstruct exactly when and why a package was installed by reading `~/.claude/projects/<...>.jsonl`. This is unique to Backshelf and only became feasible in the last year.
3. **Trust framing.** The UI surfaces what we know, what we're guessing at, and what we don't know — separately. We never present a guess as fact. This is the opposite of every "AI-powered" cleanup app, and it's the product.
4. **Native, sandboxed, App Store distributed.** A sandboxed Mac App Store presence is a stronger trust signal than any side-loaded utility — Apple has reviewed it, the app cannot escape its sandbox, and the user has explicit control over which folders it can read.

## Non-goals (so we don't drift)

Reject these even when they're tempting:

- **Auto-cleanup.** No background job that removes "obviously unused" packages. The user is always in the driver's seat.
- **Cloud sync.** A Mac-local utility with no account, no server, no sync.
- **Recommendations on what to install.** We're not an alternative App Store. We surface what's there.
- **Cross-machine comparison.** Maybe later. Not v0.
- **Modifying environment variables, shell config, or PATH.** We don't touch the user's shell.
- **Anything that requires sudo.** If a removal needs root, we explain and step out of the way.

## Trust principles

These shape every UI and every code path:

- **Honest about uncertainty.** Confidence labels are shown, not hidden.
- **Reversible by default.** We never run destructive commands ourselves — you do, in your Terminal, with full visibility. Before any cleanup script is generated, Backshelf captures a snapshot you can export as a reinstall script later.
- **Transparent.** Every command we suggest is right there in the generated script, fully readable. Nothing happens behind a button you can't audit.
- **Local-first.** Zero network calls at runtime. All package metadata is bundled; all evidence comes from your machine.
- **Slow is fine. Wrong is not.** Better to take an extra second and surface real evidence than to be fast and confidently incorrect.

## Success criteria for v1

We'll know we've shipped the right product if:

- A user can open the app fresh, scan, and within two minutes understand what's on their Mac better than they did in the last twelve months
- They feel safer about the contents of their machine after using it, not more anxious
- They can confidently remove at least one thing they couldn't have removed before
- They use the snapshot-and-restore once and find it works

If these aren't true, we missed.
