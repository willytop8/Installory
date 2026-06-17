# Installory App Store Submission Packet

Use this as the working copy for App Store Connect, TestFlight review notes, and final manual checks.

## App Identity

- App name: Installory
- Bundle ID: `app.installory.mac`
- SKU: `installory-mac`
- Primary category: Developer Tools
- Secondary category: Utilities
- Age rating: 4+
- Version: `1.0`
- Build: `4`  (build 2 rejected 2026-06-10 for Guidelines 2.1(a) + 1.5; build 3 rejected 2026-06-16 for Guideline 2.4.5(v); build 4 addresses 2.4.5(v) — see APP_REVIEW_REPLY_2.4.5.md)

## App Store Copy

### Subtitle

Understand your installed packages

### Promotional Text

Inventory Homebrew, pip, pipx, npm, Cargo, RubyGems, and Mac App Store installs from one native, read-only Mac app.

### Description

Installory helps you understand what developer packages are installed on your Mac and clean them up safely.

It scans package metadata from Homebrew, pip, pipx, npm, Cargo, RubyGems, and Mac App Store apps, then presents the result as a clear inventory with names, versions, install locations, dependencies, and install timing evidence.

Installory is designed for people who build with AI coding assistants and may not remember every package they installed along the way. It helps answer practical questions:

- What is installed on this Mac?
- Which package manager installed it?
- Where does it live?
- Is it probably safe to remove?
- What exact command would remove it?

Installory never removes packages itself. When you choose to clean up, it generates a reviewable shell script or uninstall command for you to run manually in Terminal. Read-only package inspection stays separate from destructive system changes.

Privacy is intentionally simple: Installory makes no network connections, collects no analytics, and sends no package inventory off your Mac. Package descriptions are bundled with the app.

### Keywords

homebrew,pip,npm,cargo,rubygems,pipx,packages,developer tools,cleanup,inventory

### Support URL

https://installory.app/support/

(The support page lists what the app does, how to grant folder access, how cleanup scripts work, a direct support email — will.ricchiuti@gmail.com — and a working contact form. This addresses the Guideline 1.5 rejection, which flagged the previous GitHub-profile-only contact as not providing a way to ask questions and request support.)

### Marketing URL

https://installory.app

## Privacy Nutrition Label

Installory's intended App Store Connect answers:

- Tracking: No
- Data collected: None
- Data linked to the user: None
- Data not linked to the user: None

Rationale:

- No network client/server entitlement.
- No analytics, telemetry, crash-reporting SDK, ads, account system, or third-party tracker.
- Package inventory is read locally and stored locally in the app sandbox.
- App Store v1 does not read shell history or AI assistant transcripts.
- Generated cleanup scripts are shown to the user; the app does not transmit them.

The bundled privacy manifest declares accessed API reasons for file timestamps and UserDefaults only:

- File timestamps: package install-time evidence and local inventory sorting.
- UserDefaults: local preferences such as onboarding, sort order, and settings.

## App Review Notes

Paste this into App Review Notes:

> Installory is an inventory and cleanup tool for macOS package managers: Homebrew, pip, pipx, npm, Cargo, RubyGems, and Mac App Store apps. To present a list of packages installed on the user's machine, Installory reads on-disk metadata files in well-known locations such as `/opt/homebrew/Cellar/.../INSTALL_RECEIPT.json`, `~/.local/share/pipx/venvs/`, `~/.cargo/.crates2.json`, Ruby gem `specifications/*.gemspec` files, and App Store app receipts under `Contents/_MASReceipt/receipt`. These directories live outside the app's sandbox container, so Installory uses `com.apple.security.files.user-selected.read-only` with `NSOpenPanel`: the user explicitly grants read access to each package manager directory. Access is persisted with security-scoped bookmarks. Installory never writes to those directories, never invokes external binaries, and never makes network calls. When the user wants to remove a package, Installory generates a shell script for the user to review and run manually in Terminal; the app itself never modifies the user's installed packages.
>
> DEMO MODE (addresses the Guideline 2.1(a) request): Because the app inventories package managers, a clean review device with no package managers installed would otherwise show an empty inventory. The app therefore ships a built-in demo mode with pre-populated sample content that exercises every feature — inventory across all eight managers, package descriptions and detail panes, the Read-only filter, the Duplicates view, snapshots and the restore flow, and cleanup-script generation (including the cautious "common essential" warning). No account, login, or network access is required.
>
> HOW TO ENTER DEMO MODE (any one of these):
> 1. On first launch, the onboarding window has an "Explore with Sample Data" button. Click it.
> 2. If onboarding is skipped, the main window's empty state shows a prominent "Explore with Sample Data" button.
> 3. In the app menu, open Settings… (⌘,) → "Demo Mode" → "Load Sample Data".
> 4. To launch straight into demo mode with no clicks, run with the `-demo` argument or set the environment variable `INSTALLORY_DEMO=1` (e.g. `open -a Installory --args -demo`).
>
> Demo mode is fully self-contained: the sample data lives only in memory, is never written to disk or a database, and never leaves the device. A "Demo data" indicator appears in the sidebar; "Exit Demo Mode" (sidebar or Settings) returns to scanning the real machine.

No demo account is required — use the built-in demo mode described above.

## Screenshot Requirements

Apple currently requires one to ten Mac screenshots. Each screenshot must be PNG/JPEG and exactly one of these 16:10 sizes:

- `1280 x 800`
- `1440 x 900`
- `2560 x 1600`
- `2880 x 1800`

Use the prepared exports under `files/app-store-screenshots/` when present.

Reference: Apple's App Store Connect screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications

## Final Manual Submission Steps

1. Confirm App Store Connect has the `app.installory.mac` bundle ID.
2. Set the signing team in Xcode.
3. Archive with `Product -> Archive`.
4. Upload from Organizer to App Store Connect.
5. Wait for processing.
6. Attach the build to TestFlight.
7. Run a clean TestFlight install on a second Mac or a fresh macOS user account.
8. Submit for review with the Review Notes above.

## Release QA Checklist

- Fresh launch shows onboarding.
- Declining directory access leaves a clear empty or permission-needed state.
- Granting `/opt/homebrew` or `/usr/local` triggers a scan automatically.
- Recommended grants include pipx, Cargo, RubyGems, `/Applications`, and `~/Applications`.
- Mac App Store rows appear only after Applications folder access and only for receipt-bearing apps.
- Package detail never claims Installory will uninstall directly.
- Cleanup script generation requires the user to review and run the script themselves.
- Provenance collection is unavailable in App Store v1.
- No network entitlements are present in the signed app.

Reference: Apple's App Privacy Details guidance: https://developer.apple.com/app-store/app-privacy-details/
