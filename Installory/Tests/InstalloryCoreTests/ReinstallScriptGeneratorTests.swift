import Testing
import Foundation
@testable import InstalloryCore

@Suite("ReinstallScriptGenerator")
struct ReinstallScriptGeneratorTests {
    private let generator = ReinstallScriptGenerator()

    // MARK: - Helpers

    private func makeMissing(
        manager: PackageManager,
        name: String,
        version: String = "1.0.0",
        qualifier: String? = nil
    ) -> MissingPackage {
        MissingPackage(
            manager: manager,
            package: SnapshotPackage(name: name, version: version, qualifier: qualifier, isExplicit: true)
        )
    }

    private func lines(of script: String) -> [String] {
        script.components(separatedBy: "\n")
    }

    // MARK: - Header

    @Test func scriptHasShebangAndSafetyFlags() {
        let result = generator.generate(missing: [makeMissing(manager: .brew, name: "ffmpeg")])
        let script = result.scriptText
        #expect(script.hasPrefix("#!/usr/bin/env bash\n"))
        #expect(script.contains("set -euo pipefail"))
    }

    @Test func emptyMissingListProducesHeaderOnly() {
        let result = generator.generate(missing: [])
        let script = result.scriptText
        #expect(script.hasPrefix("#!/usr/bin/env bash\n"))
        #expect(script.contains("set -euo pipefail"))
        #expect(!script.contains("brew install"))
        #expect(!script.contains("pip install"))
        #expect(!script.contains("# ==="))
    }

    // MARK: - Brew (cannot pin)

    @Test func brewInstallsCurrentVersion() {
        let result = generator.generate(missing: [makeMissing(manager: .brew, name: "ffmpeg", version: "7.0.1")])
        let script = result.scriptText
        #expect(script.contains("brew install ffmpeg"))
        #expect(!script.contains("brew install ffmpeg@"))
        #expect(!script.contains("--version"))
    }

    @Test func brewEmitsVersionComment() {
        let result = generator.generate(missing: [makeMissing(manager: .brew, name: "ffmpeg", version: "7.0.1")])
        #expect(result.scriptText.contains("snapshot recorded 7.0.1"))
        #expect(result.scriptText.contains("Homebrew installs the current version"))
    }

    @Test func brewCaskInstallsCurrentVersion() {
        let result = generator.generate(missing: [makeMissing(manager: .brewCask, name: "visual-studio-code", version: "1.90.0")])
        let script = result.scriptText
        #expect(script.contains("brew install --cask visual-studio-code"))
        #expect(script.contains("snapshot recorded 1.90.0"))
    }

    // MARK: - pip (pins version)

    @Test func pipPinsVersion() {
        let result = generator.generate(missing: [
            makeMissing(manager: .pip, name: "requests", version: "2.31.0", qualifier: "/opt/homebrew/bin/python3.13")
        ])
        let script = result.scriptText
        #expect(script.contains("requests==2.31.0"))
        #expect(script.contains("-m pip install"))
    }

    @Test func pipEscapesInterpreterPath() {
        let result = generator.generate(missing: [
            makeMissing(manager: .pip, name: "requests", version: "2.31.0", qualifier: "/path/with $pecial/python3")
        ])
        #expect(result.scriptText.contains("'/path/with $pecial/python3'"))
    }

    @Test func pipNilQualifierFallsBackToPython3() {
        let result = generator.generate(missing: [
            makeMissing(manager: .pip, name: "requests", version: "2.31.0", qualifier: nil)
        ])
        let script = result.scriptText
        #expect(script.contains("python3 -m pip install"))
    }

    @Test func pipGroupsByInterpreter() {
        let result = generator.generate(missing: [
            makeMissing(manager: .pip, name: "requests", version: "2.31.0", qualifier: "/usr/bin/python3"),
            makeMissing(manager: .pip, name: "flask", version: "3.0.0", qualifier: "/opt/homebrew/bin/python3.13"),
        ])
        let script = result.scriptText
        #expect(script.contains("interpreter: /usr/bin/python3"))
        #expect(script.contains("interpreter: /opt/homebrew/bin/python3.13"))
    }

    // MARK: - npm (pins version)

    @Test func npmPinsVersion() {
        let result = generator.generate(missing: [makeMissing(manager: .npm, name: "typescript", version: "5.4.5")])
        #expect(result.scriptText.contains("npm install -g typescript@5.4.5"))
    }

    // MARK: - pipx (pins version)

    @Test func pipxPinsVersion() {
        let result = generator.generate(missing: [
            makeMissing(
                manager: .pipx,
                name: "black",
                version: "24.4.2",
                qualifier: "/Users/tester/.local/share/pipx/venvs/black"
            ),
        ])
        #expect(result.scriptText.contains("pipx install black==24.4.2"))
    }

    @Test("CORE25-004: same-name suffixed pipx installs reproduce distinct suffixes")
    func suffixedPipxInstallsReproduceDistinctSuffixes() {
        let script = generator.generate(missing: [
            makeMissing(
                manager: .pipx,
                name: "black",
                version: "24.4.2",
                qualifier: "/Users/tester/.local/share/pipx/venvs/black-3-12"
            ),
            makeMissing(
                manager: .pipx,
                name: "black",
                version: "24.4.2",
                qualifier: "/Users/tester/.local/share/pipx/venvs/black-3-11"
            ),
        ]).scriptText
        let commands = lines(of: script).filter { $0.hasPrefix("pipx install ") }

        #expect(commands == [
            "pipx install black==24.4.2 --suffix=-3-11",
            "pipx install black==24.4.2 --suffix=-3-12",
        ])
    }

    @Test("CORE25-004: pipx reinstall shell quotes the complete suffix option")
    func pipxReinstallShellQuotesSuffixOption() {
        let script = generator.generate(missing: [
            makeMissing(
                manager: .pipx,
                name: "black",
                version: "24.4.2",
                qualifier: "/Users/tester/.local/share/pipx/venvs/black-qa'$(touch PWNED)"
            ),
        ]).scriptText

        #expect(lines(of: script).contains(
            #"pipx install black==24.4.2 '--suffix=-qa'\''$(touch PWNED)'"#
        ))
    }

    @Test("CORE25-004: unsafe or ambiguous pipx qualifiers require manual review")
    func unsafeOrAmbiguousPipxQualifiersRequireManualReview() {
        let script = generator.generate(missing: [
            makeMissing(manager: .pipx, name: "black", version: "24.4.2", qualifier: nil),
            makeMissing(
                manager: .pipx,
                name: "ruff",
                version: "0.5.0",
                qualifier: "/Users/tester/.local/share/pipx/venvs/unrelated-environment"
            ),
            makeMissing(
                manager: .pipx,
                name: "poetry",
                version: "1.8.3",
                qualifier: "/Users/tester/.local/share/pipx/venvs/poetry\nprintf PWNED"
            ),
        ]).scriptText

        #expect(lines(of: script).filter { $0.hasPrefix("# Manual review required:") }.count == 3)
        #expect(!lines(of: script).contains { $0.hasPrefix("pipx install ") })
        #expect(!lines(of: script).contains { $0.hasPrefix("printf PWNED") })
    }

    // MARK: - cargo (pins version)

    @Test("CORE25-009: crates.io Cargo restore pins the recorded version")
    func cargoCratesIOPinsVersion() {
        let result = generator.generate(missing: [
            makeMissing(
                manager: .cargo,
                name: "ripgrep",
                version: "14.1.0",
                qualifier: "registry+https://github.com/rust-lang/crates.io-index"
            ),
        ])
        #expect(result.scriptText.contains("cargo install ripgrep --version 14.1.0"))
    }

    @Test("CORE25-009: Cargo git restore preserves branch, tag, revision, and precise commit")
    func cargoGitRestorePreservesSelectors() {
        let script = generator.generate(missing: [
            makeMissing(
                manager: .cargo,
                name: "branch-tool",
                qualifier: "git+https://github.com/example/tools?branch=stable"
            ),
            makeMissing(
                manager: .cargo,
                name: "tag-tool",
                qualifier: "git+https://github.com/example/tools?tag=v1.0.0"
            ),
            makeMissing(
                manager: .cargo,
                name: "rev-tool",
                qualifier: "git+https://github.com/example/tools?rev=deadbeef"
            ),
            makeMissing(
                manager: .cargo,
                name: "precise-tool",
                qualifier: "git+https://github.com/example/tools?branch=stable#0123456789abcdef"
            ),
        ]).scriptText

        #expect(script.contains("cargo install --git https://github.com/example/tools --branch stable branch-tool"))
        #expect(script.contains("cargo install --git https://github.com/example/tools --tag v1.0.0 tag-tool"))
        #expect(script.contains("cargo install --git https://github.com/example/tools --rev deadbeef rev-tool"))
        #expect(script.contains("cargo install --git https://github.com/example/tools --rev 0123456789abcdef precise-tool"))
    }

    @Test("CORE25-009: Cargo path restore uses the recorded local path")
    func cargoPathRestoreUsesRecordedPath() {
        let script = generator.generate(missing: [
            makeMissing(
                manager: .cargo,
                name: "local-tool",
                version: "0.4.0",
                qualifier: "path+file:///Users/tester/Code/local-tool"
            ),
        ]).scriptText

        #expect(lines(of: script).contains("cargo install --path /Users/tester/Code/local-tool"))
        #expect(!script.contains("cargo install local-tool --version"))
    }

    @Test("CORE25-009: custom Cargo registry uses its recorded index")
    func cargoCustomRegistryUsesRecordedIndex() {
        let script = generator.generate(missing: [
            makeMissing(
                manager: .cargo,
                name: "corp-tool",
                version: "2.3.4",
                qualifier: "registry+sparse+https://cargo.example/index/"
            ),
        ]).scriptText

        #expect(lines(of: script).contains(
            "cargo install corp-tool --version 2.3.4 --index sparse+https://cargo.example/index/"
        ))
    }

    @Test("CORE25-009: unknown or missing Cargo sources require manual review")
    func cargoUnknownSourcesRequireManualReview() {
        let script = generator.generate(missing: [
            makeMissing(manager: .cargo, name: "legacy-tool", qualifier: nil),
            makeMissing(
                manager: .cargo,
                name: "unknown-tool",
                qualifier: "future+https://example.invalid/source\nprintf PWNED"
            ),
        ]).scriptText

        #expect(lines(of: script).filter { $0.hasPrefix("# Manual review required:") }.count == 2)
        #expect(!lines(of: script).contains { $0.hasPrefix("cargo install ") })
        #expect(!lines(of: script).contains { $0.hasPrefix("printf PWNED") })
    }

    @Test("CORE25-009: Cargo source arguments are shell quoted end-to-end")
    func cargoSourceArgumentsAreShellQuoted() {
        let script = generator.generate(missing: [
            makeMissing(
                manager: .cargo,
                name: "local-tool",
                qualifier: "path+file:///Users/tester/Code/tool%20dir%27%24%28touch%20PWNED%29"
            ),
            makeMissing(
                manager: .cargo,
                name: "git-tool",
                qualifier: "git+ssh://git@example.com/team/tools.git?branch=release%2Fqa%27%24%28touch%20PWNED%29"
            ),
        ]).scriptText

        #expect(lines(of: script).contains(
            #"cargo install --path '/Users/tester/Code/tool dir'\''$(touch PWNED)'"#
        ))
        #expect(lines(of: script).contains(
            #"cargo install --git ssh://git@example.com/team/tools.git --branch 'release/qa'\''$(touch PWNED)' git-tool"#
        ))
        #expect(!lines(of: script).contains { $0.hasPrefix("touch PWNED") })
    }

    // MARK: - gem (pins version)

    @Test func gemPinsVersion() {
        let result = generator.generate(missing: [makeMissing(manager: .gem, name: "bundler", version: "2.5.7")])
        #expect(result.scriptText.contains("gem install bundler -v 2.5.7"))
    }

    // MARK: - mas (comment only)

    @Test func masEmitsCommentOnly() {
        let result = generator.generate(missing: [makeMissing(manager: .mas, name: "Xcode", version: "15.4")])
        let script = result.scriptText
        #expect(script.contains("# Xcode: reinstall from the Mac App Store"))
        #expect(!script.contains("mas install"))
        #expect(!script.contains("echo \"→"))
    }

    // MARK: - CORE25-003 / SEC25-003: comment injection

    @Test("CORE25-003/SEC25-003: hostile reinstall qualifier stays inside its section comment")
    func hostileQualifierCannotEscapeSectionComment() {
        let qualifier = "/tmp/python\nprintf REINSTALL_QUALIFIER_PWNED\u{001B}"
        let script = generator.generate(missing: [
            makeMissing(manager: .pip, name: "requests", qualifier: qualifier),
        ]).scriptText

        #expect(script.contains("# === pip (interpreter: /tmp/python printf REINSTALL_QUALIFIER_PWNED ) ==="))
        #expect(!script.contains("# === pip (interpreter: /tmp/python\n"))
    }

    @Test("CORE25-003/SEC25-003: hostile reinstall MAS name stays inside its comment")
    func hostileMASNameCannotEscapeComment() {
        let script = generator.generate(missing: [
            makeMissing(manager: .mas, name: "Xcode\nprintf REINSTALL_MAS_PWNED\u{0007}"),
        ]).scriptText

        #expect(script.contains("# Xcode printf REINSTALL_MAS_PWNED : reinstall from the Mac App Store"))
        #expect(!lines(of: script).contains(where: { $0.hasPrefix("printf REINSTALL_MAS_PWNED") }))
    }

    @Test("CORE25-003/SEC25-003: hostile recorded version stays inside its Homebrew comment")
    func hostileRecordedVersionCannotEscapeComment() {
        let script = generator.generate(missing: [
            makeMissing(manager: .brew, name: "ffmpeg", version: "7.0\nprintf VERSION_PWNED\u{001B}"),
        ]).scriptText

        #expect(script.contains("# snapshot recorded 7.0 printf VERSION_PWNED ; Homebrew installs the current version"))
        #expect(!lines(of: script).contains(where: { $0.hasPrefix("printf VERSION_PWNED") }))
    }

    // MARK: - Echo lines

    @Test func activeCommandsHaveEchoLine() {
        let result = generator.generate(missing: [makeMissing(manager: .brew, name: "ffmpeg", version: "7.0.0")])
        let script = result.scriptText
        #expect(script.contains("echo \"→ brew install ffmpeg\""))
    }

    @Test func echoLineAppearsBeforeCommand() {
        let result = generator.generate(missing: [makeMissing(manager: .gem, name: "bundler", version: "2.5.7")])
        let allLines = lines(of: result.scriptText)
        let echoIdx = allLines.firstIndex(where: { $0.contains("echo") && $0.contains("gem install") })
        let cmdIdx = allLines.firstIndex(where: { $0 == "gem install bundler -v 2.5.7" })
        if let e = echoIdx, let c = cmdIdx {
            #expect(e < c, "echo line must precede the command")
        } else {
            Issue.record("Expected both echo line and command to be present")
        }
    }

    // MARK: - Section headers

    @Test func sectionHeadersMatchManagers() {
        let result = generator.generate(missing: [
            makeMissing(manager: .brew, name: "ffmpeg"),
            makeMissing(manager: .npm, name: "typescript"),
        ])
        let script = result.scriptText
        #expect(script.contains("# === Homebrew Formulae ==="))
        #expect(script.contains("# === npm (global) ==="))
    }

    // MARK: - Manager output order

    @Test func brewAppearsBeforeNpm() {
        let result = generator.generate(missing: [
            makeMissing(manager: .npm, name: "typescript"),
            makeMissing(manager: .brew, name: "ffmpeg"),
        ])
        let script = result.scriptText
        let brewIdx = script.range(of: "Homebrew Formulae")!.lowerBound
        let npmIdx = script.range(of: "npm (global)")!.lowerBound
        #expect(brewIdx < npmIdx)
    }

    // MARK: - GeneratedReinstallScript public init

    @Test func generatedReinstallScriptHasPublicInit() {
        let gs = GeneratedReinstallScript(scriptText: "#!/usr/bin/env bash\n")
        #expect(gs.scriptText == "#!/usr/bin/env bash\n")
    }
}

// MARK: - CORE-03: npm/gem reinstall commands must target the recorded qualifier

@Suite("ReinstallScriptGenerator multi-qualifier targeting")
struct ReinstallScriptGeneratorQualifierTests {

    private let generator = ReinstallScriptGenerator()

    private func makeMissing(
        manager: PackageManager,
        name: String,
        version: String = "1.0.0",
        qualifier: String? = nil
    ) -> MissingPackage {
        MissingPackage(
            manager: manager,
            package: SnapshotPackage(name: name, version: version, qualifier: qualifier, isExplicit: true)
        )
    }

    private func commandLines(_ script: String, containing needle: String) -> [String] {
        script.components(separatedBy: "\n")
            .filter { $0.contains(needle) && !$0.hasPrefix("#") && !$0.hasPrefix("echo") }
    }

    private let node18 = "/Users/w/.nvm/versions/node/v18.19.1/lib/node_modules"
    private let node20 = "/Users/w/.nvm/versions/node/v20.11.0/lib/node_modules"
    private let ruby31 = "/Users/w/.rbenv/versions/3.1.4/lib/ruby/gems/3.1.0/specifications"
    private let ruby32 = "/Users/w/.rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/specifications"

    @Test("CORE-03: npm reinstall targets each Node install separately")
    func npmReinstallPerNodeInstall() {
        let script = generator.generate(missing: [
            makeMissing(manager: .npm, name: "typescript", version: "5.4.5", qualifier: node18),
            makeMissing(manager: .npm, name: "typescript", version: "5.4.5", qualifier: node20),
        ]).scriptText

        let commands = commandLines(script, containing: "install -g typescript@5.4.5")
        #expect(commands.count == 2)
        #expect(Set(commands).count == 2)
        #expect(commands.contains("/Users/w/.nvm/versions/node/v18.19.1/bin/npm install -g typescript@5.4.5"))
        #expect(commands.contains("/Users/w/.nvm/versions/node/v20.11.0/bin/npm install -g typescript@5.4.5"))
    }

    @Test("CORE-03: gem reinstall targets each Ruby install separately")
    func gemReinstallPerRubyInstall() {
        let script = generator.generate(missing: [
            makeMissing(manager: .gem, name: "bundler", version: "2.5.7", qualifier: ruby31),
            makeMissing(manager: .gem, name: "bundler", version: "2.5.7", qualifier: ruby32),
        ]).scriptText

        let commands = commandLines(script, containing: "install bundler -v 2.5.7")
        #expect(commands.count == 2)
        #expect(Set(commands).count == 2)
        #expect(commands.contains("/Users/w/.rbenv/versions/3.1.4/bin/gem install bundler -v 2.5.7"))
        #expect(commands.contains("/Users/w/.rbenv/versions/3.2.2/bin/gem install bundler -v 2.5.7"))
    }

    @Test("CORE-03: gem reinstall without a colocated client is scoped with --install-dir")
    func gemReinstallUsesInstallDirFallback() {
        let script = generator.generate(missing: [
            makeMissing(manager: .gem, name: "bundler", version: "2.5.7",
                        qualifier: "/Users/w/.gem/ruby/3.2.0/specifications"),
        ]).scriptText

        #expect(script.contains("gem install bundler -v 2.5.7 --install-dir /Users/w/.gem/ruby/3.2.0"))
    }

    @Test("CORE-03: reinstall sections are grouped per npm and gem qualifier")
    func reinstallSectionsGroupedByQualifier() {
        let script = generator.generate(missing: [
            makeMissing(manager: .npm, name: "typescript", qualifier: node18),
            makeMissing(manager: .gem, name: "bundler", qualifier: ruby32),
        ]).scriptText

        #expect(script.contains("# === npm (global: \(node18)) ==="))
        #expect(script.contains("# === Ruby Gems (\(ruby32)) ==="))
    }

    @Test("CORE-03: unqualified npm and gem reinstalls keep the ambient commands")
    func unqualifiedReinstallsUseAmbientCommands() {
        let script = generator.generate(missing: [
            makeMissing(manager: .npm, name: "typescript", version: "5.4.5"),
            makeMissing(manager: .gem, name: "bundler", version: "2.5.7"),
        ]).scriptText

        #expect(script.contains("npm install -g typescript@5.4.5"))
        #expect(script.contains("gem install bundler -v 2.5.7"))
    }
}
