# Sandboxing

How Backshelf works as a sandboxed Mac App Store app. Read before touching anything related to file access, entitlements, or first-launch onboarding.

## The model

Backshelf is sandboxed. That has two big consequences:

1. **We cannot invoke external binaries.** No `Process`, no `posix_spawn`, no shelling out to `brew`, `pip`, `npm`, or anything else. Every scanner works by reading files directly.
2. **We cannot read user files outside our container by default.** To read `/opt/homebrew/Cellar/`, `~/.cargo/.crates2.json`, `~/.pyenv/versions/`, etc., the user has to grant us access explicitly through `NSOpenPanel`. Once granted, we persist the grant as a *security-scoped bookmark* so it survives launches.

The trade-off: we ship through the App Store, the user gets automatic updates, Apple has reviewed the app, and the user has explicit control over which folders Backshelf can see. We give up the ability to run anything; we gain a much stronger trust posture.

## Entitlements

The complete entitlements file is in `docs/build-and-release.md`. The relevant declarations:

- **`com.apple.security.app-sandbox`** — required for App Store distribution. Confines us to our container by default.
- **`com.apple.security.files.user-selected.read-only`** — allows us to read files and folders the user explicitly selects through an `NSOpenPanel`. Read-only because we never modify the user's package manager directories; we only read.
- **`com.apple.security.files.bookmarks.app-scope`** — allows us to persist user grants as security-scoped bookmarks tied to this app, so a folder the user granted once stays granted across launches.

What we deliberately do **not** declare:

- **No network entitlements.** No `network.client`, no `network.server`. The app makes zero network calls; this is verifiable by inspection.
- **No read-write file access.** We don't need it and asking for it would be dishonest.
- **No temporary-exception entitlements.** None.

## User-granted folder access

The whole sandbox dance hinges on `NSOpenPanel` + security-scoped bookmarks.

### How the grant works

1. We show an `NSOpenPanel` with `canChooseFiles = false`, `canChooseDirectories = true`, the dialog message tailored to the directory we're asking for ("Grant Backshelf read access to your Homebrew folder"), and `directoryURL` set as a hint.
2. The user picks a folder.
3. We receive a `URL` for which the sandbox has granted *transient* access.
4. We immediately create a security-scoped bookmark from that URL and persist it (in our own UserDefaults under our container).
5. To use the URL across launches, we resolve the bookmark, call `startAccessingSecurityScopedResource()` before reading, and `stopAccessingSecurityScopedResource()` after.

### `FolderAccessManager`

A single Foundation-layer service wraps all of this:

```swift
@Observable
final class FolderAccessManager {
    enum GrantedDirectory: String, CaseIterable {
        case homebrewPrefix
        case cargoHome
        case pyenvVersions
        case pipxVenvs
        case uvPythons
        case nvmNode
        case zshHistory
        case claudeProjects
        // ...
    }

    private(set) var grants: [GrantedDirectory: GrantState] = [:]

    enum GrantState {
        case granted(url: URL, bookmarkData: Data)
        case denied
        case notAsked
    }

    func requestAccess(to: GrantedDirectory) async -> GrantState
    func resolvedURL(for: GrantedDirectory) -> URL?         // resolves bookmark
    func withAccess<T>(to: GrantedDirectory, _ work: (URL) throws -> T) throws -> T
}
```

Scanners always go through `withAccess` so they can't forget to call `startAccessingSecurityScopedResource`.

### First-launch onboarding

On first launch, Backshelf asks for access to the package manager directories we can detect on the user's machine. The flow:

1. Welcome card explaining what Backshelf does and that it needs read access to a few directories.
2. For each detected manager directory (Homebrew prefix, ~/.cargo, ~/.pyenv/versions if it exists, ~/.local/share/pipx/venvs if it exists, etc.), show a row with:
   - The directory path
   - A one-line explanation ("Reading this lets Backshelf see your Homebrew formulae")
   - A "Grant access" button
3. The user can grant any subset they're comfortable with. Skipping is fine; that manager will simply show "permission denied" status in the inventory.
4. Provenance signals (`~/.zsh_history`, `~/.bash_history`, `~/.claude`) are asked for separately, with extra explanation because they contain sensitive content. The default is "Skip for now"; the user can grant later in Settings → Permissions.

A user who grants nothing still gets a working app — it just shows an empty inventory and a "Get started" screen pointing back at Settings → Permissions.

## Graceful degradation

The defining UX principle for the sandbox is: **never hide that a scanner is missing data**.

When a scanner can't see its target directory, the per-manager row in the sidebar (and the per-manager status pill in scan results) reads:

```
Homebrew    ⚠ Permission needed    [ Grant access ]
```

Clicking "Grant access" opens the Permissions tab with the relevant row pre-focused. The empty list state for an inaccessible manager is similarly explicit:

```
We can't see your Homebrew folder.

Backshelf needs read access to /opt/homebrew (or /usr/local on Intel Macs)
to list your installed formulae.

[ Grant access in Settings ]
```

No silent skips. No fake empty states. The user always knows what we missed and how to fix it.

If the user revokes access later (deletes the bookmark, moves the directory, or grants to a non-existent path), the next scan reports the affected manager as "permission needed" again. We never crash; we never quietly drop the manager from the count.

## What we cannot do as a sandboxed app

These are real product gaps the user should expect, and they should be documented in the Permissions tab and in the FAQ:

- **No execution of any command.** Backshelf generates a cleanup script; the user runs it. This is by design and we'd keep it even without the sandbox, but the sandbox makes it a hard constraint, not a choice.
- **Mac App Store apps (the `mas` manager) cannot be enumerated.** Listing `/Applications` is too noisy to be useful, and the `mas` CLI is the only practical inventory source. We report this as a known gap (see `docs/scanners.md`).
- **No system-wide hooks.** No background daemon, no LaunchAgent. Backshelf is a foreground app only.
- **No automatic interactive directory walks beyond the granted root.** If the user grants `/opt/homebrew`, we can walk inside that subtree freely. But if a package's metadata points to `/Users/will/something-else`, we can't follow that link unless that path is also granted.
- **No invocation of the user's shell to read environment.** We can't ask `zsh` for the user's `$PATH`. We have hardcoded prefix discovery in `PathDiscovery` instead.

## When access is denied: defensive coding

Every scanner is responsible for handling permission errors as first-class outcomes, not exceptions to swallow:

```swift
do {
    try folderAccess.withAccess(to: .homebrewPrefix) { url in
        // walk and parse
    }
} catch FolderAccessManager.Error.notGranted {
    return .permissionDenied(.homebrewPrefix)
} catch FolderAccessManager.Error.bookmarkResolutionFailed {
    return .permissionLost(.homebrewPrefix)
}
```

The two failure modes — "user never granted" and "user previously granted but the bookmark no longer resolves" — get distinct status values so the UI can tell the user which one happened.

## Future: the non-sandboxed direct-download build

`ROADMAP.md` notes the possibility of a non-sandboxed Developer-ID-signed build for users who want Backshelf to perform the uninstall itself. If we ship that, this document needs a companion section explaining the symmetric set of behaviors: that build would *not* go through NSOpenPanel for every directory (it'd just read), would *not* need security-scoped bookmarks, but *would* still treat the cleanup script as the source of truth — running it via the user's preferred shell rather than asking the user to copy-paste. The two builds would share 95%+ of their code; the differences live entirely in `FolderAccessManager` and the cleanup wizard's final action.
