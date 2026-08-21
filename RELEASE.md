# Installory 1.5.0 release

Version `1.5.0` (build `11`) is the current release candidate. Core, app,
description-tool, invariant, Release-build, archive-inspection, and hands-on UI
gates are green.

Do not upload a local unsigned or ad-hoc QA archive. Create a fresh distribution
archive from the merged, clean `main` branch.

## What’s New

Installory now maps your whole AI-agent setup and helps you declutter without the fear:

• New Home dashboard: packages tracked, measured payload, safe to free up, AI installs this week, review candidates, duplicates, and broken skills.
• “Safe to remove” verdicts on every package, driven by reverse-dependency and orphan analysis.
• Restore points before bulk cleanup, plus a one-tap restore script.
• Move-to-Trash cleanup for file-backed items, alongside real uninstallers.
• Free-up-space bundle surfacing the highest-value safe packages and reclaimable bytes.
• Stale project workspaces detected from granted folders, sized and sorted by last activity.
• Inventory agent skills, agent CLIs (Claude Code, Codex, opencode, Cursor), and VS Code & Cursor extensions.
• See which packages you installed and which your AI assistant installed, from Claude Code, Codex, and opencode session records.
• Reverse-dependency tree, hide/pin/annotate, and baseline compare with change detection and reinstall scripts.
• Plain-English descriptions for every package, including agent skills, CLIs, and editor extensions.

Installory remains read-only and offline. It never removes software or runs generated commands.

## App Review note

Installory is a fully offline, read-only inventory app. It scans only folders
explicitly granted by the user through read-only security-scoped bookmarks. It
never executes generated cleanup or reinstall scripts. The user-selected
read-write entitlement is used only when the user explicitly chooses an export
or generated-script destination through a Save panel.

Provenance collection is off by default and requires a separate folder grant.
When enabled, it reads shell history and local agent-session logs (Claude Code,
Codex, and opencode) on-device, and every record is redacted before it is
stored. No data is transmitted; the app contains no networking code.

Project-workspace scanning similarly walks only folders the user has explicitly
granted read-only access to and never modifies them.

Reviewers can choose “Explore with Sample Data” during onboarding to evaluate
the app without granting filesystem access.

## Release checklist

1. Refresh the description corpus from fresh API responses using its
   [runbook](scripts/generate-descriptions/README.md). If it changes, rerun every
   verification gate.
2. Confirm `project.yml` contains version `1.5.0`, build `11`, bundle identifier
   `app.installory.mac`, and `ITSAppUsesNonExemptEncryption: false`; regenerate
   the Xcode project.
3. Run the Core and app commands in [README.md](README.md), the description-tool
   tests, `scripts/check-invariants.sh`, and an unsigned Release build. Require a
   clean worktree and green pull-request CI before merging to `main`.
4. From updated `main`, select the owner Apple Developer Team with managed
   distribution signing. Do not commit a personal team identifier.
5. Select Any Mac / Generic Mac, choose Product → Archive, and confirm version,
   build, bundle identifier, `arm64` and `x86_64`, sandbox entitlements,
   `PrivacyInfo.xcprivacy`, `ThirdPartyNotices.txt`, the icon, and
   `descriptions.json` in Organizer.
6. Run Validate App, then choose Distribute App → App Store Connect → Upload.
   Resolve any signing or App Store Connect validation finding before upload.
7. In App Store Connect, create or select macOS version 1.5.0, attach build 11,
   paste the text above, keep App Privacy at **Data Not Collected**, and answer
   export compliance consistently with the Info property-list declaration.
8. Submit for review and choose the intended manual or automatic release mode.

Build numbers cannot be reused.

## Known advisory

Command-F does not currently focus the SwiftUI search field. Search works when
focused normally. This is a nonblocking keyboard-polish follow-up, not a crash,
data-loss, privacy, or submission issue.

After release, tag the shipped commit, publish the same notes in the GitHub
release, mark this document shipped or remove its version-specific text, and
update the separate website repository only through its own reviewed deploy.
