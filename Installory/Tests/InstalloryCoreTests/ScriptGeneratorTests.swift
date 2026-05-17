import Testing
import Foundation
@testable import InstalloryCore

@Suite("ScriptGenerator")
struct ScriptGeneratorTests {

    // Custom denylist with no entries, so tests control denylist behaviour explicitly.
    private let generator = ScriptGenerator(denylist: Denylist(entries: []))
    // Generator with the real default denylist for denylist-specific tests.
    private let defaultGenerator = ScriptGenerator()

    // MARK: - Helpers

    private func makePackage(
        manager: PackageManager,
        name: String,
        qualifier: String? = nil,
        isReadOnly: Bool = false,
        dependencies: [String] = [],
        artifactPaths: [String]? = nil
    ) -> Package {
        Package(
            id: "\(manager.rawValue):\(qualifier ?? ""):\(name)",
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: isReadOnly,
            dependencies: dependencies,
            artifactPaths: artifactPaths,
            lastSeen: Date()
        )
    }

    private func lines(of script: String) -> [String] {
        script.components(separatedBy: "\n")
    }

    // MARK: - Empty package list

    @Test func emptyPackageListProducesHeaderOnly() {
        let result = generator.generate(packages: [])
        let script = result.scriptText

        #expect(script.hasPrefix("#!/bin/bash\n"))
        #expect(script.contains("set -euo pipefail"))
        #expect(result.skippedReadOnly.isEmpty)
        #expect(result.warnedDenylisted.isEmpty)

        // No uninstall commands or manager section headers
        #expect(!script.contains("uninstall"))
        #expect(!script.contains("# ==="))
    }

    // MARK: - Brew formula

    @Test func brewFormulaProducesCorrectCommand() {
        let pkg = makePackage(manager: .brew, name: "jq")
        let result = generator.generate(packages: [pkg])
        let script = result.scriptText

        #expect(script.contains(#"echo "→ brew uninstall jq""#))
        #expect(lines(of: script).contains("brew uninstall jq"))
        #expect(script.contains("# === Homebrew Formulae ==="))
    }

    // MARK: - Brew cask

    @Test func brewCaskProducesCommandAndArtifactComments() {
        let pkg = makePackage(
            manager: .brewCask,
            name: "warp",
            artifactPaths: ["/Applications/Warp.app", "~/Library/Application Support/Warp"]
        )
        let result = generator.generate(packages: [pkg])
        let script = result.scriptText

        #expect(script.contains(#"echo "→ brew uninstall --cask warp""#))
        #expect(lines(of: script).contains("brew uninstall --cask warp"))
        #expect(script.contains("# === Homebrew Casks ==="))

        // Artifact path comments appear immediately after the command
        let scriptLines = lines(of: script)
        let cmdIndex = scriptLines.firstIndex(of: "brew uninstall --cask warp")
        if let cmdIndex {
            #expect(scriptLines[cmdIndex + 1] == "# Files brew may not remove automatically:")
            #expect(scriptLines[cmdIndex + 2] == "#   /Applications/Warp.app")
            #expect(scriptLines[cmdIndex + 3] == "#   ~/Library/Application Support/Warp")
        }
    }

    @Test func brewCaskWithNoArtifactPathsHasNoArtifactComment() {
        let pkg = makePackage(manager: .brewCask, name: "alfred")
        let result = generator.generate(packages: [pkg])
        #expect(!result.scriptText.contains("Files brew may not remove"))
    }

    // MARK: - pip

    @Test func pipCommandUsesQualifierAsInterpreter() {
        let interpreter = "/Users/x/.pyenv/versions/3.11.7/bin/python"
        let pkg = makePackage(manager: .pip, name: "requests", qualifier: interpreter)
        let result = generator.generate(packages: [pkg])
        let script = result.scriptText

        // The actual command line (unquoted form in the script)
        let expectedCmd = #""/Users/x/.pyenv/versions/3.11.7/bin/python" -m pip uninstall -y "requests""#
        #expect(lines(of: script).contains(expectedCmd))

        // Section header includes the interpreter path
        #expect(script.contains("# === pip (interpreter: \(interpreter)) ==="))
    }

    @Test func pipCommandWithSpaceInInterpreterPath() {
        // Spaces in the path must not break the generated command
        let interpreter = "/Users/my user/.pyenv/versions/3.12.0/bin/python"
        let pkg = makePackage(manager: .pip, name: "flask", qualifier: interpreter)
        let result = generator.generate(packages: [pkg])
        let script = result.scriptText

        // Command must double-quote the interpreter path
        #expect(script.contains("\"\(interpreter)\" -m pip uninstall -y \"flask\""))
    }

    // MARK: - npm

    @Test func npmPackageProducesCorrectCommand() {
        let pkg = makePackage(manager: .npm, name: "typescript")
        let result = generator.generate(packages: [pkg])
        let script = result.scriptText

        #expect(lines(of: script).contains(#"npm uninstall -g "typescript""#))
        #expect(script.contains("# === npm (global) ==="))
    }

    @Test func scopedNpmPackageRendersCorrectly() {
        let pkg = makePackage(manager: .npm, name: "@types/node")
        let result = generator.generate(packages: [pkg])
        let script = result.scriptText

        #expect(lines(of: script).contains(#"npm uninstall -g "@types/node""#))
    }

    // MARK: - Read-only filter

    @Test func readOnlyPackageIsAbsentFromScriptAndReturnedInSkipped() {
        let readOnly = makePackage(manager: .pip, name: "six", qualifier: "/usr/bin/python3", isReadOnly: true)
        let normal   = makePackage(manager: .brew, name: "jq")

        let result = generator.generate(packages: [readOnly, normal])
        let script = result.scriptText

        // Read-only package must not appear anywhere in the script
        #expect(!script.contains("six"))
        #expect(!script.contains("/usr/bin/python3"))

        // Normal package must appear
        #expect(script.contains("brew uninstall jq"))

        // Return value must capture the skipped package
        #expect(result.skippedReadOnly.count == 1)
        #expect(result.skippedReadOnly[0].name == "six")
    }

    // MARK: - Denylist

    @Test func denylistedPackageIsCommentedOutAtBottomWithWarning() {
        let git = makePackage(manager: .brew, name: "git")
        let result = defaultGenerator.generate(packages: [git])
        let script = result.scriptText
        let scriptLines = lines(of: script)

        // No active command for git
        #expect(!scriptLines.contains("brew uninstall git"))
        // Echo line for git must not appear either
        #expect(!script.contains(#"echo "→ brew uninstall git""#))

        // The WARNING banner must appear
        #expect(script.contains("WARNING"))

        // The commented command must appear (with reason)
        #expect(script.contains("# brew uninstall git"))
        #expect(script.contains("reason:"))

        // Return value
        #expect(result.warnedDenylisted.count == 1)
        #expect(result.warnedDenylisted[0].name == "git")
    }

    @Test func denylistedSectionIsAlwaysAtTheBottomOfTheScript() {
        // Mix of active and denylisted packages
        let jq  = makePackage(manager: .brew, name: "jq")       // not denylisted
        let git = makePackage(manager: .brew, name: "git")       // denylisted

        let result = defaultGenerator.generate(packages: [jq, git])
        let script = result.scriptText

        let activePos  = script.range(of: "brew uninstall jq")
        let warningPos = script.range(of: "WARNING")

        // Both must be present
        #expect(activePos != nil)
        #expect(warningPos != nil)

        if let a = activePos, let w = warningPos {
            #expect(a.lowerBound < w.lowerBound)
        }
    }

    @Test func python312MatchesDenylistGlob() {
        let py312 = makePackage(manager: .brew, name: "python@3.12")
        let result = defaultGenerator.generate(packages: [py312])
        #expect(result.warnedDenylisted.count == 1)
        #expect(result.warnedDenylisted[0].name == "python@3.12")
        #expect(!result.scriptText.contains("brew uninstall python@3.12\n"))
        #expect(result.scriptText.contains("# brew uninstall python@3.12"))
    }

    // MARK: - Dependency-aware ordering

    @Test func dependentPackageAppearesBeforeItsDependency() {
        // app-a depends on lib-b → app-a must appear before lib-b in the script
        let appA = makePackage(manager: .brew, name: "app-a", dependencies: ["lib-b"])
        let libB = makePackage(manager: .brew, name: "lib-b", dependencies: [])

        let result = generator.generate(packages: [appA, libB])
        let script = result.scriptText

        let posA = script.range(of: "brew uninstall app-a")
        let posB = script.range(of: "brew uninstall lib-b")

        #expect(posA != nil)
        #expect(posB != nil)
        if let a = posA, let b = posB {
            #expect(a.lowerBound < b.lowerBound, "app-a (dependent) must appear before lib-b (dependency)")
        }
    }

    @Test func independentPackagesAreIncluded() {
        // Packages with no inter-dependencies: both must appear
        let pkgA = makePackage(manager: .brew, name: "htop")
        let pkgB = makePackage(manager: .brew, name: "tree")
        let result = generator.generate(packages: [pkgA, pkgB])
        let script = result.scriptText
        #expect(script.contains("brew uninstall htop"))
        #expect(script.contains("brew uninstall tree"))
    }

    @Test func dependencyCycleEmitsWarningComment() {
        // A depends on B, B depends on A — cycle
        let pkgA = makePackage(manager: .brew, name: "cycler-a", dependencies: ["cycler-b"])
        let pkgB = makePackage(manager: .brew, name: "cycler-b", dependencies: ["cycler-a"])
        let result = generator.generate(packages: [pkgA, pkgB])
        let script = result.scriptText
        #expect(script.contains("# WARNING: dependency cycle detected"))
        // Both packages must still appear
        #expect(script.contains("brew uninstall cycler-a"))
        #expect(script.contains("brew uninstall cycler-b"))
    }

    // MARK: - Multiple managers

    @Test func multipleManagersEachGetOwnSectionHeader() {
        let brew = makePackage(manager: .brew, name: "jq")
        let npm  = makePackage(manager: .npm,  name: "typescript")
        let pip  = makePackage(manager: .pip,  name: "requests", qualifier: "/usr/local/bin/python3")

        let result = generator.generate(packages: [brew, npm, pip])
        let script = result.scriptText

        #expect(script.contains("# === Homebrew Formulae ==="))
        #expect(script.contains("# === npm (global) ==="))
        #expect(script.contains("# === pip (interpreter: /usr/local/bin/python3) ==="))

        // Canonical order: brew → pip → npm  (matches managerOrder in ScriptGenerator)
        let brewPos = script.range(of: "# === Homebrew Formulae ===")
        let pipPos  = script.range(of: "# === pip (interpreter:")
        let npmPos  = script.range(of: "# === npm (global) ===")

        #expect(brewPos != nil && pipPos != nil && npmPos != nil)
        if let b = brewPos, let p = pipPos, let n = npmPos {
            #expect(b.lowerBound < p.lowerBound)
            #expect(p.lowerBound < n.lowerBound)
        }
    }

    // MARK: - Snapshot context

    @Test func snapshotContextAppearsInHeader() {
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let ctx = SnapshotContext(id: id, createdAt: createdAt)

        let result = generator.generate(packages: [], snapshot: ctx)
        let script = result.scriptText

        #expect(script.contains(id.uuidString))
        #expect(script.contains("Snapshot taken before this script was generated"))
    }

    @Test func noSnapshotContextMeansNoSnapshotLines() {
        let result = generator.generate(packages: [])
        #expect(!result.scriptText.contains("Snapshot taken"))
        #expect(!result.scriptText.contains("Export as reinstall script"))
    }

    // MARK: - Preamble correctness

    @Test func scriptUsesStrictBashPreamble() {
        let result = generator.generate(packages: [])
        #expect(result.scriptText.contains("set -euo pipefail"))
        // Must NOT use the weaker "set -e" alone on its own line
        let strictLine = lines(of: result.scriptText).contains("set -euo pipefail")
        #expect(strictLine)
    }

    @Test func scriptEndsWithNewline() {
        let result = generator.generate(packages: [makePackage(manager: .brew, name: "jq")])
        #expect(result.scriptText.hasSuffix("\n"))
    }

    // MARK: - removalCommand(for:)

    @Test func removalCommandBrewFormula() {
        let pkg = makePackage(manager: .brew, name: "jq")
        #expect(generator.removalCommand(for: pkg) == "brew uninstall jq")
    }

    @Test func removalCommandBrewCask() {
        let pkg = makePackage(manager: .brewCask, name: "visual-studio-code")
        #expect(generator.removalCommand(for: pkg) == "brew uninstall --cask visual-studio-code")
    }

    @Test func removalCommandPipWithQualifier() {
        let interpreter = "/opt/homebrew/bin/python3.12"
        let pkg = makePackage(manager: .pip, name: "requests", qualifier: interpreter)
        #expect(generator.removalCommand(for: pkg) == #""/opt/homebrew/bin/python3.12" -m pip uninstall -y "requests""#)
    }

    @Test func removalCommandPipNoQualifierFallsBackToPython3() {
        let pkg = makePackage(manager: .pip, name: "flask")
        #expect(generator.removalCommand(for: pkg) == #""python3" -m pip uninstall -y "flask""#)
    }

    @Test func removalCommandNpm() {
        let pkg = makePackage(manager: .npm, name: "typescript")
        #expect(generator.removalCommand(for: pkg) == #"npm uninstall -g "typescript""#)
    }

    @Test func removalCommandScopedNpm() {
        let pkg = makePackage(manager: .npm, name: "@types/node")
        #expect(generator.removalCommand(for: pkg) == #"npm uninstall -g "@types/node""#)
    }

    @Test func removalCommandPipx() {
        let pkg = makePackage(manager: .pipx, name: "black")
        #expect(generator.removalCommand(for: pkg) == "pipx uninstall black")
    }

    @Test func removalCommandCargo() {
        let pkg = makePackage(manager: .cargo, name: "ripgrep")
        #expect(generator.removalCommand(for: pkg) == "cargo uninstall ripgrep")
    }

    @Test func removalCommandGem() {
        let pkg = makePackage(manager: .gem, name: "bundler")
        #expect(generator.removalCommand(for: pkg) == "gem uninstall bundler")
    }

    @Test func removalCommandMasReturnsNil() {
        let pkg = makePackage(manager: .mas, name: "Xcode")
        #expect(generator.removalCommand(for: pkg) == nil)
    }

    @Test func removalCommandReadOnlyReturnsNil() {
        let pkg = makePackage(manager: .brew, name: "python3", isReadOnly: true)
        #expect(generator.removalCommand(for: pkg) == nil)
    }

    @Test func removalCommandPipWithSpecialCharsInInterpreterPath() {
        let interpreter = "/Users/my user/.pyenv/versions/3.12.0/bin/python"
        let pkg = makePackage(manager: .pip, name: "flask", qualifier: interpreter)
        let cmd = generator.removalCommand(for: pkg)
        #expect(cmd == #""/Users/my user/.pyenv/versions/3.12.0/bin/python" -m pip uninstall -y "flask""#)
    }
}
