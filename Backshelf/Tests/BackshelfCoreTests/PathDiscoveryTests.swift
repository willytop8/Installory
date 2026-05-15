import Testing
import Foundation
@testable import BackshelfCore

@Suite("PathDiscovery")
struct PathDiscoveryTests {

    // MARK: - Helpers

    /// Returns a `PathDiscovery` whose filesystem is exactly `existing`.
    private func discovery(existing: Set<String>) -> PathDiscovery {
        PathDiscovery { existing.contains($0) }
    }

    /// Returns a `PathDiscovery` whose home is `fakeHome` and whose
    /// filesystem contains only the paths in `existing`.
    ///
    /// `ManagerDirectory.candidatePath(home:)` is tested through this helper;
    /// tests don't hard-code real user home paths.
    private func discovery(home: String, existing: Set<String>) -> PathDiscovery {
        PathDiscovery { path in
            // Redirect home-relative paths to fake home so tests are reproducible.
            let adjusted = path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: home
            )
            return existing.contains(adjusted) || existing.contains(path)
        }
    }

    // MARK: - Homebrew prefixes

    @Test("Apple Silicon Homebrew detected")
    func appleSiliconHomebrew() {
        let d = discovery(existing: ["/opt/homebrew"])
        #expect(d.homebrewPrefixes.map(\.path) == ["/opt/homebrew"])
    }

    @Test("Intel Homebrew detected")
    func intelHomebrew() {
        let d = discovery(existing: ["/usr/local"])
        #expect(d.homebrewPrefixes.map(\.path) == ["/usr/local"])
    }

    @Test("Both Homebrew prefixes coexist (Rosetta workloads)")
    func bothHomebrewPrefixes() {
        let d = discovery(existing: ["/opt/homebrew", "/usr/local"])
        let paths = Set(d.homebrewPrefixes.map(\.path))
        #expect(paths == ["/opt/homebrew", "/usr/local"])
        #expect(d.homebrewPrefixes.count == 2)
    }

    @Test("No Homebrew installed → empty array")
    func noHomebrew() {
        let d = discovery(existing: [])
        #expect(d.homebrewPrefixes.isEmpty)
    }

    @Test("Apple Silicon prefix is listed before Intel")
    func prefixOrder() {
        let d = discovery(existing: ["/opt/homebrew", "/usr/local"])
        #expect(d.homebrewPrefixes.first?.path == "/opt/homebrew")
    }

    // MARK: - ManagerDirectory

    private static let fakeHome = "/Users/testuser"

    @Test("Cargo home detected when ~/.cargo exists")
    func cargoDetected() {
        let d = discovery(
            home: Self.fakeHome,
            existing: ["\(Self.fakeHome)/.cargo"]
        )
        let url = d.locate(.cargoHome)
        #expect(url != nil)
    }

    @Test("Cargo home nil when ~/.cargo absent")
    func cargoAbsent() {
        let d = discovery(home: Self.fakeHome, existing: [])
        #expect(d.locate(.cargoHome) == nil)
    }

    @Test("pyenv versions detected")
    func pyenvDetected() {
        let d = discovery(
            home: Self.fakeHome,
            existing: ["\(Self.fakeHome)/.pyenv/versions"]
        )
        #expect(d.locate(.pyenvVersions) != nil)
    }

    @Test("nvm node detected")
    func nvmDetected() {
        let d = discovery(
            home: Self.fakeHome,
            existing: ["\(Self.fakeHome)/.nvm/versions/node"]
        )
        #expect(d.locate(.nvmNode) != nil)
    }

    @Test("Volta node detected")
    func voltaDetected() {
        let d = discovery(
            home: Self.fakeHome,
            existing: ["\(Self.fakeHome)/.volta/tools/image/node"]
        )
        #expect(d.locate(.voltaNode) != nil)
    }

    @Test("Bun global detected")
    func bunDetected() {
        let d = discovery(
            home: Self.fakeHome,
            existing: ["\(Self.fakeHome)/.bun/install/global"]
        )
        #expect(d.locate(.bunGlobal) != nil)
    }

    @Test("pipx venvs detected")
    func pipxDetected() {
        let d = discovery(
            home: Self.fakeHome,
            existing: ["\(Self.fakeHome)/.local/share/pipx/venvs"]
        )
        #expect(d.locate(.pipxVenvs) != nil)
    }

    @Test("rbenv versions detected")
    func rbenvDetected() {
        let d = discovery(
            home: Self.fakeHome,
            existing: ["\(Self.fakeHome)/.rbenv/versions"]
        )
        #expect(d.locate(.rbenvVersions) != nil)
    }

    @Test("None present → all locate() calls return nil")
    func nonePresent() {
        let d = discovery(home: Self.fakeHome, existing: [])
        for kind in ManagerDirectory.allCases {
            #expect(d.locate(kind) == nil, "Expected nil for \(kind)")
        }
    }

    // MARK: - candidatePath

    @Test("candidatePath(home:) never hard-codes a real username")
    func candidatePathUsesHome() {
        let home = "/Users/somebody"
        for kind in ManagerDirectory.allCases {
            let path = kind.candidatePath(home: home)
            #expect(path.hasPrefix(home), "\(kind).candidatePath should start with the provided home")
        }
    }
}
