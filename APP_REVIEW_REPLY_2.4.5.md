# App Review reply — Guideline 2.4.5(v), Submission 077d80e8-b9d7-4a40-ad30-f47a2fd138b2

Paste the message below into the App Store Connect Resolution Center reply for this submission. It is also a good idea to add a short version to the "Notes" field of the App Review Information for build 4.

---

Hello, and thank you for the review.

We want to clarify that Installory does not request administrator (root) access at any point, and we have made a change in build 4 to ensure the macOS authentication sheet you encountered cannot appear during normal use.

Why the app does not request admin access:

- Installory is fully sandboxed (`com.apple.security.app-sandbox` is enabled). The app cannot, and does not, escalate privileges.
- The app contains no privileged APIs of any kind: no `AuthorizationExecuteWithPrivileges`, no `SMJobBless` or privileged helper tool, no `setuid`, no `NSAppleScript`/`osascript`, and it never launches any external process or shell.
- Installory is strictly read-only. Its only interaction with the file system is through `NSOpenPanel`, where the user explicitly selects a folder, after which we store a read-only security-scoped bookmark (`com.apple.security.files.user-selected.read-only`). The app never writes to those locations and never removes packages itself — when the user chooses to clean up, the app generates a shell script as text that the user reviews and runs themselves in Terminal.

What most likely happened: on a Mac without Homebrew installed, our onboarding's one-click "Grant Access to /opt/homebrew" button pointed the folder picker at a directory that did not exist, which could lead a reviewer to navigate to and select a system-owned directory. When a sandboxed app is granted access to a folder it cannot read by permission, macOS itself presents an authentication sheet to authorize that read. That is the operating system gating a file-access permission, not Installory requesting administrator rights.

What we changed in build 4:

- The folder picker now starts in the user's Home folder and never auto-targets a missing or system-owned directory.
- Onboarding only offers the one-click Homebrew grant when that folder actually exists; otherwise it presents a plain folder picker, so the app never steers the user toward a protected location.

How to verify all functionality with no permissions and no prompts:

The app includes a built-in Demo Mode with pre-populated sample data that exercises every feature — inventory across all supported package managers, package details and descriptions, duplicate detection, snapshots and restore, and cleanup-script generation — without granting access to any folder and without any authentication prompt. To enter it:

1. On first launch, click "Explore with Sample Data" on the onboarding screen, or
2. Use the menu bar: Inventory → "Load Sample Data" (⌘⇧D), or
3. Settings (⌘,) → Demo Mode → "Load Sample Data", or
4. Launch with the argument `-demo` (e.g. `open -a Installory --args -demo`).

If you are still able to reproduce an authentication prompt after these changes, we would be grateful if you could share the exact step or a screenshot so we can address it precisely.

Thank you very much for your time.

---
