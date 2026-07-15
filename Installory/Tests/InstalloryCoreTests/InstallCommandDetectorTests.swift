import Testing
import Foundation
@testable import InstalloryCore

@Suite("InstallCommandDetector")
struct InstallCommandDetectorTests {
    private let detector = InstallCommandDetector()

    // MARK: - brew

    @Test("brew install detects .brew package")
    func brewInstall() {
        let results = detector.detect("brew install ffmpeg")
        #expect(results.count == 1)
        #expect(results[0].name == "ffmpeg")
        #expect(results[0].manager == .brew)
    }

    @Test("brew reinstall detects .brew package")
    func brewReinstall() {
        let results = detector.detect("brew reinstall wget")
        #expect(results.count == 1)
        #expect(results[0].name == "wget")
        #expect(results[0].manager == .brew)
    }

    @Test("brew install --cask detects .brewCask package")
    func brewInstallCask() {
        let results = detector.detect("brew install --cask visual-studio-code")
        #expect(results.count == 1)
        #expect(results[0].name == "visual-studio-code")
        #expect(results[0].manager == .brewCask)
    }

    @Test("brew cask install (legacy form) detects .brewCask package")
    func brewCaskInstallLegacy() {
        let results = detector.detect("brew cask install iterm2")
        #expect(results.count == 1)
        #expect(results[0].name == "iterm2")
        #expect(results[0].manager == .brewCask)
    }

    @Test("brew install multiple packages produces one record per package")
    func brewMultiplePackages() {
        let results = detector.detect("brew install ffmpeg libpng jpeg")
        #expect(results.count == 3)
        #expect(results.map(\.name) == ["ffmpeg", "libpng", "jpeg"])
        #expect(results.allSatisfy { $0.manager == .brew })
    }

    @Test("brew install with flags ignores flag tokens")
    func brewFlagsIgnored() {
        let results = detector.detect("brew install --formula ffmpeg")
        #expect(results.count == 1)
        #expect(results[0].name == "ffmpeg")
    }

    @Test("CORE25-017: tap-qualified Homebrew targets match their installed name")
    func brewTapQualifiedName() {
        let results = detector.detect("brew install owner/tools/custom-formula")

        #expect(results.map(\.name) == ["custom-formula"])
        #expect(results.allSatisfy { $0.manager == .brew })
    }

    // MARK: - pip / pip3 / python -m pip / uv

    @Test("pip install detects .pip package")
    func pipInstall() {
        let results = detector.detect("pip install requests")
        #expect(results.count == 1)
        #expect(results[0].name == "requests")
        #expect(results[0].manager == .pip)
    }

    @Test("pip3 install detects .pip package")
    func pip3Install() {
        let results = detector.detect("pip3 install flask")
        #expect(results.count == 1)
        #expect(results[0].name == "flask")
        #expect(results[0].manager == .pip)
    }

    @Test("python3 -m pip install detects .pip package")
    func python3MPipInstall() {
        let results = detector.detect("python3 -m pip install numpy")
        #expect(results.count == 1)
        #expect(results[0].name == "numpy")
        #expect(results[0].manager == .pip)
    }

    @Test("python -m pip install detects .pip package")
    func pythonMPipInstall() {
        let results = detector.detect("python -m pip install scipy")
        #expect(results.count == 1)
        #expect(results[0].name == "scipy")
        #expect(results[0].manager == .pip)
    }

    @Test("CORE25-011: versioned Python interpreter detects pip installs")
    func versionedPythonMPipInstall() {
        let results = detector.detect("python3.12 -m pip install httpx")
        #expect(results.count == 1)
        #expect(results[0].name == "httpx")
        #expect(results[0].manager == .pip)
    }

    @Test("CORE25-011: absolute Python interpreter detects pip installs")
    func absolutePythonMPipInstall() {
        let results = detector.detect("/opt/homebrew/bin/python3.11 -m pip install rich")
        #expect(results.count == 1)
        #expect(results[0].name == "rich")
        #expect(results[0].manager == .pip)
    }

    @Test("CORE25-011: Python executable lookalikes are rejected")
    func pythonExecutableLookalikesRejected() {
        #expect(detector.detect("python3.12-config -m pip install not-a-package").isEmpty)
        #expect(detector.detect("python3.12m -m pip install not-a-package").isEmpty)
    }

    @Test("uv pip install detects .pip package")
    func uvPipInstall() {
        let results = detector.detect("uv pip install ruff")
        #expect(results.count == 1)
        #expect(results[0].name == "ruff")
        #expect(results[0].manager == .pip)
    }

    @Test("pip flags ignored (--upgrade does not appear as package name)")
    func pipFlagIgnored() {
        let results = detector.detect("pip install --upgrade requests")
        #expect(results.count == 1)
        #expect(results[0].name == "requests")
    }

    @Test("pip version specifier == stripped")
    func pipVersionEqualEqual() {
        let results = detector.detect("pip install requests==2.31.0")
        #expect(results.count == 1)
        #expect(results[0].name == "requests")
    }

    @Test("pip version specifier >= stripped")
    func pipVersionGreaterOrEqual() {
        let results = detector.detect("pip install requests>=1.0")
        #expect(results.count == 1)
        #expect(results[0].name == "requests")
    }

    @Test("pip extras stripped (requests[security] → requests)")
    func pipExtrasStripped() {
        let results = detector.detect("pip install requests[security]")
        #expect(results.count == 1)
        #expect(results[0].name == "requests")
    }

    @Test("pip install -r requirements.txt produces no records (v0 limitation)")
    func pipRequirementsFileSkipped() {
        let results = detector.detect("pip install -r requirements.txt")
        #expect(results.isEmpty)
    }

    @Test("pip install multiple packages produces one record per package")
    func pipMultiplePackages() {
        let results = detector.detect("pip install numpy pandas scipy")
        #expect(results.count == 3)
        #expect(results.map(\.name) == ["numpy", "pandas", "scipy"])
        #expect(results.allSatisfy { $0.manager == .pip })
    }

    @Test("CORE25-011: pip option values are not treated as packages")
    func pipOptionValuesSkipped() {
        let results = detector.detect(
            "python3.12 -m pip install --python-version 3.12 --index-url index.example requests"
        )
        #expect(results.map(\.name) == ["requests"])
        #expect(results.allSatisfy { $0.manager == .pip })
    }

    // MARK: - pipx

    @Test("pipx install detects .pipx package")
    func pipxInstall() {
        let results = detector.detect("pipx install black")
        #expect(results.count == 1)
        #expect(results[0].name == "black")
        #expect(results[0].manager == .pipx)
    }

    @Test("CORE25-011: pipx interpreter option value is not treated as a package")
    func pipxOptionValueSkipped() {
        let results = detector.detect("pipx install --python python3.12 black")
        #expect(results.map(\.name) == ["black"])
        #expect(results.allSatisfy { $0.manager == .pipx })
    }

    // MARK: - npm / yarn

    @Test("npm install -g detects .npm package")
    func npmInstallG() {
        let results = detector.detect("npm install -g typescript")
        #expect(results.count == 1)
        #expect(results[0].name == "typescript")
        #expect(results[0].manager == .npm)
    }

    @Test("npm i -g detects .npm package")
    func npmIG() {
        let results = detector.detect("npm i -g prettier")
        #expect(results.count == 1)
        #expect(results[0].name == "prettier")
        #expect(results[0].manager == .npm)
    }

    @Test("CORE25-011: npm global flag after the package is detected")
    func npmGlobalFlagAfterPackage() {
        let results = detector.detect("npm install typescript --global")
        #expect(results.map(\.name) == ["typescript"])
        #expect(results.allSatisfy { $0.manager == .npm })
    }

    @Test("CORE25-011: npm option values before a later global flag are skipped")
    func npmOptionValueBeforeLaterGlobalFlag() {
        let results = detector.detect("npm i prettier --tag next -g")
        #expect(results.map(\.name) == ["prettier"])
        #expect(results.allSatisfy { $0.manager == .npm })
    }

    @Test("CORE25-011: npm option values after an earlier global flag are skipped")
    func npmOptionValueAfterEarlierGlobalFlag() {
        let results = detector.detect("npm install -g --tag next prettier")
        #expect(results.map(\.name) == ["prettier"])
        #expect(results.allSatisfy { $0.manager == .npm })
    }

    @Test("CORE25-011: npm global text after option terminator is not a global install")
    func npmGlobalAfterOptionTerminatorRejected() {
        #expect(detector.detect("npm install typescript -- --global").isEmpty)
    }

    @Test("npm install -g missing -g flag produces no records")
    func npmInstallWithoutGFlag() {
        // `npm install typescript` is a local install, not global — should not be detected.
        let results = detector.detect("npm install typescript")
        #expect(results.isEmpty)
    }

    @Test("CORE25-017: scoped npm targets strip only their trailing version")
    func npmScopedVersion() {
        let results = detector.detect("npm install --global @scope/tool@2.1.0 plain@next")

        #expect(results.map(\.name) == ["@scope/tool", "plain"])
        #expect(results.allSatisfy { $0.manager == .npm })
    }

    @Test("yarn global add detects .npm package")
    func yarnGlobalAdd() {
        let results = detector.detect("yarn global add eslint")
        #expect(results.count == 1)
        #expect(results[0].name == "eslint")
        #expect(results[0].manager == .npm)
    }

    // MARK: - cargo / gem / mas

    @Test("cargo install detects .cargo package")
    func cargoInstall() {
        let results = detector.detect("cargo install ripgrep")
        #expect(results.count == 1)
        #expect(results[0].name == "ripgrep")
        #expect(results[0].manager == .cargo)
    }

    @Test("CORE25-011: Cargo option values are not treated as packages")
    func cargoOptionValueSkipped() {
        let results = detector.detect("cargo install ripgrep --version 14.1.1")
        #expect(results.map(\.name) == ["ripgrep"])
        #expect(results.allSatisfy { $0.manager == .cargo })
    }

    @Test("gem install detects .gem package")
    func gemInstall() {
        let results = detector.detect("gem install bundler")
        #expect(results.count == 1)
        #expect(results[0].name == "bundler")
        #expect(results[0].manager == .gem)
    }

    @Test("CORE25-011: RubyGems option values are not treated as packages")
    func gemOptionValueSkipped() {
        let results = detector.detect("gem install rails --version 7.2.0")
        #expect(results.map(\.name) == ["rails"])
        #expect(results.allSatisfy { $0.manager == .gem })
    }

    @Test("mas install detects .mas package")
    func masInstall() {
        let results = detector.detect("mas install 497799835")
        #expect(results.count == 1)
        #expect(results[0].name == "497799835")
        #expect(results[0].manager == .mas)
    }

    // MARK: - Shell command chains and conservative parsing

    @Test("CORE25-011: quoted literal package requirements are parsed")
    func quotedLiteralPackageRequirement() {
        let singleQuoted = detector.detect("pip install 'requests>=2'")
        let doubleQuoted = detector.detect("pip install \"httpx==0.28\"")
        #expect(singleQuoted.map(\.name) == ["requests"])
        #expect(doubleQuoted.map(\.name) == ["httpx"])
    }

    @Test("CORE25-011: shell command chains detect each install invocation")
    func shellCommandChains() {
        let results = detector.detect(
            "cd ~/src && brew install ffmpeg; npm install typescript --global | tee installs.log"
        )
        #expect(results.map(\.name) == ["ffmpeg", "typescript"])
        #expect(results.map(\.manager) == [.brew, .npm])
    }

    @Test("CORE25-011: quoted command text is not parsed as an invocation")
    func quotedCommandTextRejected() {
        #expect(detector.detect("echo \"brew install ffmpeg && npm install evil --global\"").isEmpty)
    }

    @Test("CORE25-011: shell comments cannot introduce a synthetic command chain")
    func commentedCommandTextRejected() {
        #expect(detector.detect("echo complete # ; brew install not-executed").isEmpty)
    }

    @Test("CORE25-011: unterminated quoting rejects the whole command")
    func unterminatedQuotingRejected() {
        #expect(detector.detect("brew install ffmpeg; npm install \"evil --global").isEmpty)
    }

    @Test("CORE25-011: dynamic shell expressions are not package names")
    func dynamicShellExpressionsRejected() {
        #expect(detector.detect("brew install $(printf attacker-controlled)").isEmpty)
        #expect(detector.detect("brew install $(printf foo; echo bar)").isEmpty)
        #expect(detector.detect("brew install \"$(printf attacker-controlled)\"").isEmpty)
        #expect(detector.detect("npm install --global $PACKAGE").isEmpty)
    }

    // MARK: - Non-install commands produce no records

    @Test("cd command produces no records")
    func cdCommand() {
        #expect(detector.detect("cd ~/projects").isEmpty)
    }

    @Test("vim command produces no records")
    func vimCommand() {
        #expect(detector.detect("vim foo.py").isEmpty)
    }

    @Test("ls command produces no records")
    func lsCommand() {
        #expect(detector.detect("ls -la").isEmpty)
    }

    @Test("git command produces no records")
    func gitCommand() {
        #expect(detector.detect("git commit -m \"add feature\"").isEmpty)
    }

    @Test("empty string produces no records")
    func emptyString() {
        #expect(detector.detect("").isEmpty)
    }

    @Test("whitespace-only string produces no records")
    func whitespaceOnly() {
        #expect(detector.detect("   ").isEmpty)
    }

    // MARK: - CORE-06: editable installs, directory args, npm --global

    @Test("CORE-06: pip install -e . produces no records")
    func pipEditableCurrentDirectory() {
        #expect(detector.detect("pip install -e .").isEmpty)
    }

    @Test("CORE-06: pip install --editable . produces no records")
    func pipEditableLongFormCurrentDirectory() {
        #expect(detector.detect("pip install --editable .").isEmpty)
    }

    @Test("CORE-06: pip install -e .. produces no records")
    func pipEditableParentDirectory() {
        #expect(detector.detect("pip install -e ..").isEmpty)
    }

    @Test("CORE-06: pip install . produces no records")
    func pipInstallCurrentDirectory() {
        #expect(detector.detect("pip install .").isEmpty)
    }

    @Test("CORE-06: pip install -e ./pkg produces no records")
    func pipEditableRelativePath() {
        #expect(detector.detect("pip install -e ./pkg").isEmpty)
    }

    @Test("CORE-06: an editable install alongside a real package detects only the package")
    func pipEditableAlongsideRealPackage() {
        let results = detector.detect("pip install -e . requests")
        #expect(results.count == 1)
        #expect(results[0].name == "requests")
        #expect(results[0].manager == .pip)
    }

    @Test("CORE-06: npm install --global detects the package")
    func npmInstallGlobalLongForm() {
        let results = detector.detect("npm install --global typescript")
        #expect(results.count == 1)
        #expect(results[0].name == "typescript")
        #expect(results[0].manager == .npm)
    }

    @Test("CORE-06: npm i --global detects the package")
    func npmIGlobalLongForm() {
        let results = detector.detect("npm i --global prettier")
        #expect(results.count == 1)
        #expect(results[0].name == "prettier")
        #expect(results[0].manager == .npm)
    }

    @Test("CORE-06: npm install --global still requires the install verb")
    func npmGlobalWithoutInstallVerb() {
        #expect(detector.detect("npm ls --global").isEmpty)
    }
}
