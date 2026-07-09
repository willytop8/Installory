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
        let result = generator.generate(missing: [makeMissing(manager: .pipx, name: "black", version: "24.4.2")])
        #expect(result.scriptText.contains("pipx install black==24.4.2"))
    }

    // MARK: - cargo (pins version)

    @Test func cargoPinsVersion() {
        let result = generator.generate(missing: [makeMissing(manager: .cargo, name: "ripgrep", version: "14.1.0")])
        #expect(result.scriptText.contains("cargo install ripgrep --version 14.1.0"))
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
