# Installory 1.4.0 App Store version notes

## What’s New — ready to paste

Installory 1.4 makes your developer-tool inventory easier to explore and safer to review:

• Scan persistent tools installed with uv, alongside Homebrew, pip, pipx, npm, Cargo, RubyGems, and Mac App Store apps.
• Switch between List and sortable Table views, and search Duplicates, Review Candidates, and AI Installed results by name, scope, or path.
• See measured package payload by manager and the largest measured packages in Disk Usage.
• Select multiple items in Duplicates or Review Candidates and generate one reviewable cleanup script.
• Export your inventory as JSON, in addition to CSV and Markdown.
• Improved scan reliability, snapshots, package matching, secret redaction, accessibility, and generated-script safety.

Installory remains read-only and offline. It never removes software or runs generated commands.

## App Review note — ready to paste

Installory is a fully offline, read-only inventory app. It scans only folders explicitly granted by the user through read-only security-scoped bookmarks. It never executes generated cleanup or reinstall scripts. The user-selected read-write entitlement is used only when the user explicitly chooses an export or generated-script destination through a Save panel. Provenance collection is disabled by default, requires a separate folder grant, and remains entirely local. Reviewers can choose “Explore with Sample Data” during onboarding to evaluate the app without granting filesystem access.

## Internal release notes

### New in 1.4

- Adds filesystem-only discovery of persistent uv tools, relocated uv roots,
  entrypoints, sizes, provenance, and exact uninstall identity. Disposable uvx
  environments stay intentionally excluded.
- Extends search to Duplicates, Review Candidates, and AI Installed, including
  package name, manager scope/qualifier, and install path.
- Adds a native sortable Table mode with persistent independent List/Table sorts.
- Adds Disk Usage analysis with measurement coverage, manager totals, and largest
  measured packages.
- Adds bulk cleanup selection in Duplicates and Review Candidates. Installory
  continues to generate scripts only.
- Adds deterministic full-shape JSON export alongside CSV and Markdown.
- Refreshes the bundled offline package-description corpus to 33,514 entries.

### Reliability and safety

- Computes bounded, cancellable, symlink-safe package payload sizes.
- Preserves last-known inventory partitions when scans fail, time out, or return
  malformed data while still allowing successful empty scans to clear results.
- Supports relocated Cargo, RubyGems, pyenv, nvm, pipx, and uv homes through an
  allowlisted environment boundary.
- Corrects scoped npm, interpreter-specific pip, suffixed pipx, platform/coexisting
  gem, and uv identity matching.
- Hardens generated scripts with exact targets, shell quoting, sanitized comments,
  and inert handling of hostile metadata.
- Improves snapshot hydration, persistence migrations, cancellation, and
  deterministic export/change ordering.
- Redacts bounded provenance before persistence and display; provenance remains
  opt-in and local.
- Improves bookmark lifetime balancing, read-only grant enforcement, VoiceOver
  labeling, keyboard navigation, empty states, and contrast behavior.

### Submission metadata checklist

- Version: `1.4.0`
- Build: `10`
- Category: retain the existing category unless intentionally changed in App
  Store Connect
- App Privacy: Data Not Collected
- Export compliance: no non-exempt encryption; Info property list includes
  `ITSAppUsesNonExemptEncryption = false`
- Review access: no account required; sample data is available from onboarding
- Public notes: use the “What’s New” text above
- Review notes: use the App Review note above
