# Build and release

The operational doc. Read when setting up a new dev machine, when shipping a release, or when something in the build pipeline goes wrong.

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Installory.xcodeproj` is gitignored. To regenerate: `brew install xcodegen && ./scripts/regenerate-xcode.sh`.

Installory is a **Mac App Store app**. Distribution is via App Store Connect. Signing is automatic via Xcode's App Store distribution flow. Updates are delivered by the App Store. There is no notarization step, no Sparkle, and no appcast — the App Store handles all of that.

## Dev machine setup

Requirements:

- **macOS 14 or later** (we develop on current macOS; the app targets 13+)
- **Xcode 26 or later** (Swift 6.1+ required for GRDB 7)
- **Apple Developer Program membership** — $99/year, required for App Store distribution
- **An App Store Connect account** linked to that membership

Optional:

- A second Mac for testing TestFlight installs from a clean profile

## Xcode project layout

```
Installory.xcodeproj
Installory/                         # main app target
├── App/
├── Models/
├── Persistence/
├── Scanners/
├── Provenance/
├── Descriptions/
├── Safety/
├── Views/
└── Resources/
    ├── descriptions.json      # bundled corpus, read-only
    └── Assets.xcassets
Installory.entitlements             # sandbox + file-access entitlements
InstalloryTests/                    # unit tests
InstalloryIntegrationTests/         # integration tests, opt-in
scripts/
├── generate-descriptions/     # build-time corpus generator
└── release.sh
Package.swift                  # for SPM dependencies if not using Xcode resolution
```

Use **Xcode project**, not pure SPM. Reasons: Xcode signing config and App Store distribution are easier to manage, Xcode previews work better, and the entitlements file is a first-class Xcode concept.

## SPM dependencies

Pinned in the Xcode project:

| Package | URL | Version |
| --- | --- | --- |
| GRDB.swift | https://github.com/groue/GRDB.swift | `7.10.0+` |
| SharingGRDB | https://github.com/pointfreeco/sharing-grdb | (optional, add when needed) |

No others without updating `ARCHITECTURE.md`.

## Building locally

Three ways:

1. **Xcode**: open `Installory.xcodeproj`, ⌘R. Use the `Debug` scheme for development.
2. **CLI**:
   ```bash
   xcodebuild -scheme Installory -configuration Debug build
   ```
3. **SPM (for the corpus generator)**:
   ```bash
   python3 scripts/generate-descriptions/generate.py
   ```

## Sandboxing and entitlements

Installory is sandboxed. See `sandboxing.md` for the full model; this section covers the entitlement file specifically.

`Installory.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- File access: user-selected folders only, read-only -->
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>

    <!-- Security-scoped bookmarks: persist access across launches -->
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>

    <!-- Hardened runtime defaults (App Store builds set these automatically;
         listed for clarity) -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <false/>

    <!-- No network. Explicit absence of:
         com.apple.security.network.client
         com.apple.security.network.server
         The app makes zero network calls. -->
</dict>
</plist>
```

What we declare and why:

- `com.apple.security.app-sandbox` — required for App Store distribution. Confines us to our container.
- `com.apple.security.files.user-selected.read-only` — lets us read folders the user explicitly hands us through `NSOpenPanel`. We don't ask for `read-write` because we don't write to user folders; we only read package manager directories.
- `com.apple.security.files.bookmarks.app-scope` — lets us persist the user's grant across launches as a security-scoped bookmark in our container. Without this, every launch would re-prompt for every directory.

What we do *not* declare:

- Any network entitlement. The app has no `network.client` and no `network.server`. App Review can verify by inspection: the binary never opens a socket.
- Read-write entitlements for user folders. Read-only is sufficient and signals our intent honestly.
- Any temporary-exception entitlement.

## Code signing

For App Store builds, Xcode handles everything:

- Team: your Apple Developer team
- Provisioning: "Apple Distribution" (managed by Xcode)
- Bundle ID: matches the App Store Connect record

For Debug builds during development, Xcode uses "Sign to Run Locally". No certificate management is needed; Xcode mints local signing identities automatically.

## App Store Connect setup

The first time you push a build:

1. Create the app record in App Store Connect with the matching bundle ID.
2. Fill out the privacy nutrition label. Installory's answers:
   - **Data collected:** None.
   - **Data linked to user:** None.
   - **Data not linked to user:** None.
   - **Tracking:** No.
   The justification: zero network calls, no analytics, no telemetry. All processing is local.
3. Add screenshots (App Store requires several at minimum: 1280×800, 1440×900, 2560×1600, 2880×1800).
4. Marketing copy: app description, keywords, support URL, marketing URL.
5. App category: Developer Tools or Utilities (we want both reads — Utilities probably reaches the target user better; Developer Tools accurately describes the function).
6. Age rating: 4+.

## TestFlight (beta)

TestFlight is the beta channel:

1. Archive in Xcode: `Product → Archive`.
2. Distribute via Xcode Organizer → "App Store Connect" → "Upload".
3. Wait for processing to complete (5–20 minutes).
4. In App Store Connect, add the build to a TestFlight group.
5. Invite testers by email or via a public link.

TestFlight builds are valid for 90 days. Update the build, and testers get the update automatically.

## App Store Review

The hard part for Installory is explaining the file-access entitlement. Apple's reviewers want to understand *why* an app needs to read directories outside its container.

Prepare a Review Notes block to attach to the submission:

> Installory is an inventory and cleanup tool for macOS package managers (Homebrew, pip, npm, etc.). To present a list of packages installed on the user's machine, Installory reads on-disk metadata files in well-known locations: `/opt/homebrew/Cellar/.../INSTALL_RECEIPT.json`, `~/.local/share/pipx/venvs/`, `~/.cargo/.crates2.json`, and similar. These directories live outside the app's sandbox container, so Installory uses `com.apple.security.files.user-selected.read-only` plus `NSOpenPanel`: at first launch, the user explicitly grants Installory read access to each package manager directory. Access is persisted with security-scoped bookmarks (`com.apple.security.files.bookmarks.app-scope`). Installory never writes to these directories, never invokes external binaries, and never makes any network call. When the user wants to remove a package, Installory generates a shell script which the user reviews and runs themselves in Terminal — the app itself never modifies the user's packages.

Be ready to repeat this in a phone-review call if the reviewer requests one. The first submission for a tool like this commonly gets a "we need more information" round; the rejection is rarely fatal.

## Release workflow

`scripts/release.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="$1"   # e.g., 0.2.0

# 1. Bump version in Info.plist
agvtool new-marketing-version "$VERSION"
agvtool next-version -all

# 2. Archive for App Store distribution
xcodebuild -scheme Installory -configuration Release \
    -derivedDataPath build/ \
    -archivePath build/Installory.xcarchive \
    archive

# 3. Export for App Store and upload
xcodebuild -exportArchive \
    -archivePath build/Installory.xcarchive \
    -exportPath build/ \
    -exportOptionsPlist ExportOptions.plist
#    ExportOptions.plist sets:
#      method = app-store-connect
#      destination = upload

# 4. (No notarization step — App Store handles signing & review.)

# 5. Tag the release
git tag "v$VERSION"
git push origin "v$VERSION"
```

After the upload completes and App Store Connect finishes processing, the build is available to add to a TestFlight group or submit for review.

## Generating the bundled descriptions

The corpus generator lives at `scripts/generate-descriptions/`. It:

1. Pulls registry metadata from `formulae.brew.sh`, PyPI JSON API, and the npm registry
2. Normalizes the upstream `description` / `summary` field per `descriptions.md`
3. Writes the bundled `App/Resources/descriptions.json` file

Run periodically and commit the updated `descriptions.json` to the repo.

```bash
python3 scripts/generate-descriptions/generate.py
```

No API key required — all sources are public registries.

## CI

Defer until manual release cadence shows pain.

When we set it up, the minimum:

- Build and test on every push to `main`
- Run unit tests (not integration)
- Lint Swift via SwiftLint or SwiftFormat
- App Store builds on tag push (e.g., `v0.2.0`) — App Store Connect credentials and signing identity stored as encrypted CI secrets

## Local debugging tricks

- **Force a scanner timeout**: in Settings (advanced section, hidden behind a toggle), expose timeout overrides. Useful for testing the "scanner timed out" UI state.
- **Force a permission denial**: a debug-build affordance that pretends a user-granted folder isn't accessible, so we can exercise the "Can't see your Homebrew folder" UI without actually revoking access.
- **Use Console.app** to follow `os_log` output during scanning.
- **Database inspector**: open `~/Library/Containers/<bundle-id>/Data/Library/Application Support/Installory/installory.db` with [DB Browser for SQLite](https://sqlitebrowser.org/) to verify schema and contents. Note the sandbox container path — the app no longer writes to `~/Library/Application Support/Installory/` directly.

## When things break

- **App Store upload rejected**: check the email from App Store Connect — common causes are missing privacy nutrition label, missing screenshots, or a bundle-ID mismatch.
- **App Review rejected (entitlements concern)**: respond with the Review Notes blurb above. If the reviewer wants more, offer a screencast showing the first-launch NSOpenPanel flow and a sample generated cleanup script.
- **App launches but immediately quits in a TestFlight build**: check Console.app filtered to your bundle ID. Sandbox apps fail in subtle ways when an entitlement is missing — a `Sandbox: deny ...` line in Console will usually tell you which one.
- **SQLite errors after schema change**: you forgot to add a migration. Migrations are append-only; never modify an existing one.
- **NSOpenPanel grants disappear after launch**: the security-scoped bookmark wasn't persisted, or we forgot to call `startAccessingSecurityScopedResource()` before reading. See `sandboxing.md`.
