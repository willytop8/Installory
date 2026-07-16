# Installory 1.4.0 (10) App Store QA handoff

## Verdict

The source candidate at `55254b0` on `campaign/2026-07-audit` passed local
pre-submission QA on 2026-07-15. Core, app, description-tool, invariant, Release
build, archive inspection, and representative hands-on UI gates are green.

The remaining gate is owner-side Apple Distribution signing and App Store
Connect validation. The repository intentionally has no `DEVELOPMENT_TEAM`
selected, and this Mac currently has only an Apple Development identity. The
archive below is therefore an unsigned inspection artifact, and the runnable QA
app is ad-hoc signed. Neither is uploadable to App Store Connect. No upload or
submission was attempted.

## Candidate and automated evidence

- Version: `1.4.0` (`CFBundleVersion` `10`)
- Bundle identifier: `app.installory.mac`
- Candidate source commit: `55254b0`
- Toolchain: Xcode 26.5, Swift 6.3.2, macOS 26.5.1
- Architectures: Apple silicon (`arm64`) and Intel (`x86_64`)
- Core: 691 Swift Testing cases + 21 XCTest cases = 712 passing
- App target: 46 passing, 0 skipped, 0 failed
- Description generator: 18 passing
- Invariant gate: passed; no production `Process(` or runtime network API usage
- Final Release build result: 0 errors, 0 warnings, 0 analyzer warnings
- Final archive result: 0 errors, 0 warnings, 0 analyzer warnings

The final app-test result bundle is:

`/tmp/installory-app-tests-1.4.0-10-final.xcresult`

The final QA artifact root is:

`/tmp/installory-appstore-qa.oRjDzQ`

Key artifacts:

- Archive: `Installory-1.4.0-10-qa-final.xcarchive`
- Runnable Release app: `DerivedDataSubmissionFinalSigned/Build/Products/Release/Installory.app`
- Archive result: `SubmissionFinalArchive.xcresult`
- Signed-build result: `SubmissionFinalSignedBuild.xcresult`

Archive inspection confirmed the expected icon, asset catalog,
`PrivacyInfo.xcprivacy`, `ThirdPartyNotices.txt`, and bundled
`descriptions.json`; no quarantine attributes, world-writable files, or symlinks
were present. The privacy manifest declares no tracking or collected data and
records the used File Timestamp and User Defaults required-reason APIs. The Info
property list declares `ITSAppUsesNonExemptEncryption = false`.

Artifact fingerprints:

| Artifact | SHA-256 |
|---|---|
| Archived executable | `c428ca7de510904468f6bf0135d8b142277cef5c0d4407125164a66ad1b80407` |
| Privacy manifest | `480e9b4250561a311adad75a68d7ea57cd8604494ec52741b6965156b48a8b2e` |
| Description corpus | `744479ed3bd3e3bb66b332c6f53d1213f0aae6095d9dfe60bcd90664d8ffd785` |
| Third-party notices | `8d14cf140ad07f1286d05b3d0b0c3acfe4eb22cc4e2e3f6aa42849f96e9915fd` |

Executable UUIDs:

- `x86_64`: `700ECA76-3993-300E-B394-8597B15B1549`
- `arm64`: `1BAA744F-9FB0-3475-A7C4-F4F3BE365414`

## Hands-on Release smoke test

The ad-hoc signed Release app was exercised against sample data and then returned
to the real local inventory before quitting.

- Loaded 36 sample packages across nine managers, including uv.
- Reproduced a selected-row List-to-Table crash, traced it to missing environment
  injection in detached SwiftUI Table content, added a deterministic NSHostingView
  regression, fixed it, rebuilt, and repeated the exact sequence successfully.
- Verified Table columns, Name sorting in both directions, selected-row survival,
  keyboard List/Table shortcuts, and the row context menu.
- Searched Duplicates for `pyenv` and saw only the expected black/requests groups.
- Selected two black installations in bulk Cleanup Mode and inspected one inert
  generated script containing the correct pyenv pip and pipx uninstall commands.
  The script was not saved, copied, or executed.
- Searched Review Candidates for `rbenv`, selected two items in bulk mode, then
  exited without generating a script.
- Verified Disk Usage totals, measurement coverage, manager chart, top packages,
  selection, and keyboard navigation.
- Verified AI Installed's hedged language, install-path search, and local
  provenance detail.
- Captured a demo snapshot and verified 36 packages/nine managers including uv.
- Opened and cancelled CSV, Markdown, and JSON Save panels; no files were written.
- Inspected Privacy, General, Scanning, and About settings; About reported
  `1.4.0 (10)`, and the privacy language states offline/read-only/generated-only
  behavior.
- Verified dark appearance, cleared search, restored List mode, exited sample
  data, restored the real 122-package inventory, and quit normally.
- Confirmed no new crash report after the final post-fix launch.

One nonblocking polish issue remains: Command-F does not focus the SwiftUI
`.searchable` field, and the Edit menu has no Find command. Search works when
focused normally. Record this for a later macOS keyboard-polish pass.

## Owner-side distribution checklist

1. Open the regenerated project and select the owner Apple Developer team with
   managed distribution signing. Do not commit personal team identifiers.
2. Select Any Mac / Generic Mac and create a fresh Product > Archive from
   `campaign/2026-07-audit` at or after the documented candidate commit.
3. In Organizer, confirm `1.4.0 (10)`, `app.installory.mac`, the two intended
   architectures, privacy manifest, entitlements, notices, icon, and description
   corpus; then run Validate App.
4. Resolve any signing or App Store Connect-only validation finding before upload.
5. Distribute to App Store Connect and wait for build processing. Attach the
   processed build to the macOS version.
6. Confirm App Privacy remains “Data Not Collected,” answer export compliance
   consistently with the Info property-list declaration, and paste the review
   note below.
7. Add the public “What’s New” text from
   `handoff/app-store-version-notes-1.4.0.md` and submit only when desired.

## Suggested App Review note

Installory is a fully offline, read-only inventory app. It scans only folders
explicitly granted by the user through read-only security-scoped bookmarks. It
never executes generated cleanup or reinstall scripts. The user-selected
read-write entitlement is used only when the user explicitly chooses an export
or generated-script destination through a Save panel. Provenance collection is
disabled by default, requires a separate folder grant, and remains entirely
local. Reviewers can choose “Explore with Sample Data” during onboarding to
evaluate the app without granting filesystem access.
