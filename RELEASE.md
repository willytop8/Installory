# Installory 1.4.0 release

Version `1.4.0` (build `10`) passed local pre-submission QA on 2026-07-15. Core,
app, description-tool, invariant, Release-build, archive-inspection, and
hands-on UI gates are green. Later repository changes affect tests, CI, and
documentation only; they do not change the submitted app binary.

Do not upload a local unsigned or ad-hoc QA archive. Create a fresh distribution
archive from the merged, clean `main` branch.

## What’s New

Installory 1.4 makes your developer-tool inventory easier to explore and safer to review:

• Scan persistent tools installed with uv, alongside Homebrew, pip, pipx, npm, Cargo, RubyGems, and Mac App Store apps.
• Switch between List and sortable Table views, and search Duplicates, Review Candidates, and AI Installed results by name, scope, or path.
• See measured package payload by manager and the largest measured packages in Disk Usage.
• Select multiple items in Duplicates or Review Candidates and generate one reviewable cleanup script.
• Export your inventory as JSON, in addition to CSV and Markdown.
• Improved scan reliability, snapshots, package matching, secret redaction, accessibility, and generated-script safety.

Installory remains read-only and offline. It never removes software or runs generated commands.

## App Review note

Installory is a fully offline, read-only inventory app. It scans only folders
explicitly granted by the user through read-only security-scoped bookmarks. It
never executes generated cleanup or reinstall scripts. The user-selected
read-write entitlement is used only when the user explicitly chooses an export
or generated-script destination through a Save panel. Provenance collection is
disabled by default, requires a separate folder grant, and remains entirely
local. Reviewers can choose “Explore with Sample Data” during onboarding to
evaluate the app without granting filesystem access.

## Release checklist

1. Refresh the description corpus from fresh API responses using its
   [runbook](scripts/generate-descriptions/README.md). If it changes, rerun every
   verification gate.
2. Confirm `project.yml` contains version `1.4.0`, build `10`, bundle identifier
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
7. In App Store Connect, create or select macOS version 1.4.0, attach build 10,
   paste the text above, keep App Privacy at **Data Not Collected**, and answer
   export compliance consistently with the Info property-list declaration.
8. Submit for review and choose the intended manual or automatic release mode.

Build numbers cannot be reused. Build 10 was uploaded before the test, CI, and
documentation cleanup; those repository-only changes do not require build 11.

## Known advisory

Command-F does not currently focus the SwiftUI search field. Search works when
focused normally. This is a nonblocking keyboard-polish follow-up, not a crash,
data-loss, privacy, or submission issue.

After release, tag the shipped commit, publish the same notes in the GitHub
release, mark this document shipped or remove its version-specific text, and
update the separate website repository only through its own reviewed deploy.
