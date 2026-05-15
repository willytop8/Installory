# Backshelf

A native macOS app that inventories your installed packages across Homebrew, pip, and npm — and helps you understand when you installed them and why. For the full product story, see [files/PRODUCT.md](files/PRODUCT.md).

## Building

**Prerequisites:**
- macOS 14 (Sonoma) or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

**Steps:**
```bash
./scripts/regenerate-xcode.sh   # generates Backshelf.xcodeproj from project.yml
open Backshelf.xcodeproj         # open in Xcode
```

In Xcode, go to the Backshelf target → Signing & Capabilities → set your Development Team, then press ⌘R.

> The `Backshelf.xcodeproj` file is gitignored intentionally. `project.yml` is the source of truth; regenerate the project any time you pull changes that touch it.

## Library tests

The `BackshelfCore` library has its own test suite (248 tests). Run without Xcode:

```bash
cd Backshelf
swift test
```

## Repo layout

```
project.yml          XcodeGen source of truth for the Xcode project
Backshelf/           Swift Package containing BackshelfCore library
App/
├── Sources/         App-layer Swift sources
├── Resources/       Assets.xcassets (app icon, etc.)
├── Backshelf.entitlements
└── Info.plist
scripts/
└── regenerate-xcode.sh
files/               Design docs, roadmap, architecture
```
