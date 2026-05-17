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

    // MARK: - pipx

    @Test("pipx install detects .pipx package")
    func pipxInstall() {
        let results = detector.detect("pipx install black")
        #expect(results.count == 1)
        #expect(results[0].name == "black")
        #expect(results[0].manager == .pipx)
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

    @Test("npm install -g missing -g flag produces no records")
    func npmInstallWithoutGFlag() {
        // `npm install typescript` is a local install, not global — should not be detected.
        let results = detector.detect("npm install typescript")
        #expect(results.isEmpty)
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

    @Test("gem install detects .gem package")
    func gemInstall() {
        let results = detector.detect("gem install bundler")
        #expect(results.count == 1)
        #expect(results[0].name == "bundler")
        #expect(results[0].manager == .gem)
    }

    @Test("mas install detects .mas package")
    func masInstall() {
        let results = detector.detect("mas install 497799835")
        #expect(results.count == 1)
        #expect(results[0].name == "497799835")
        #expect(results[0].manager == .mas)
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
}
