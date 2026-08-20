import InstalloryCore
import Foundation
import Testing

@Suite("Removal safety analysis")
struct RemovalSafetyAnalysisTests {

    private static let ref = Date(timeIntervalSince1970: 1_710_000_000)

    private func pkg(
        _ name: String,
        manager: PackageManager = .brew,
        qualifier: String? = nil,
        deps: [String] = [],
        isExplicit: Bool = true,
        isReadOnly: Bool = false,
        installPath: URL? = nil,
        artifactPaths: [String]? = nil
    ) -> Package {
        let id = "\(manager.rawValue):\(qualifier ?? ""):\(name)"
        return Package(
            id: id,
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: "1.0.0",
            installPath: installPath,
            installedAt: Self.ref,
            installedAtConfidence: .high,
            sizeBytes: nil,
            isExplicit: isExplicit,
            isReadOnly: isReadOnly,
            dependencies: deps,
            artifactPaths: artifactPaths,
            lastSeen: Self.ref
        )
    }

    private func verdict(
        for package: Package,
        in packages: [Package]
    ) -> RemovalSafetyVerdict {
        let index = ReverseDependencyIndex(packages: packages)
        let orphanedIDs = Set(packages.orphanedPackages().map(\.id))
        return RemovalSafetyAnalysis.verdict(
            for: package,
            reverseDependencyIndex: index,
            orphanedIDs: orphanedIDs
        )
    }

    @Test("Read-only packages are always leave-alone")
    func readOnlyIsLeaveAlone() {
        let package = pkg("system-thing", isReadOnly: true)
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .leaveAlone)
        #expect(!result.reasons.isEmpty)
    }

    @Test("Mac App Store apps are leave-alone")
    func masIsLeaveAlone() {
        let package = pkg("Xcode", manager: .mas)
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .leaveAlone)
    }

    @Test("Denylisted packages are leave-alone")
    func denylistedIsLeaveAlone() {
        let package = pkg("git")
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .leaveAlone)
    }

    @Test("Packages with dependents are caution")
    func dependentsAreCaution() {
        let lib = pkg("mylib")
        let app = pkg("myapp", deps: ["mylib"])
        let result = verdict(for: lib, in: [lib, app])
        #expect(result.safety == .caution)
        #expect(result.reasons.contains { $0.contains("myapp") })
    }

    @Test("Implicitly-installed packages are caution")
    func implicitIsCaution() {
        let package = pkg("urllib3", manager: .pip, qualifier: "/venv", isExplicit: false)
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .caution)
    }

    @Test("Orphan candidates are safe")
    func orphanIsSafe() {
        let package = pkg("standalone-tool")
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .safe)
    }

    @Test("Broken agent-skill symlinks are safe to remove")
    func brokenSkillLinkIsSafe() {
        let package = pkg(
            "dead-skill",
            manager: .agentSkill,
            qualifier: "/Users/w/.claude/skills",
            installPath: nil,
            artifactPaths: ["/Users/w/.claude/skills/dead-skill-target"]
        )
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .safe)
    }

    @Test("Real agent-skill directories are caution (permanent delete)")
    func realSkillDirectoryIsCaution() {
        let package = pkg(
            "real-skill",
            manager: .agentSkill,
            qualifier: "/Users/w/.claude/skills",
            installPath: URL(fileURLWithPath: "/Users/w/.claude/skills/real-skill")
        )
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .caution)
    }

    @Test("Agent CLIs are caution")
    func agentCliIsCaution() {
        let package = pkg(
            "claude",
            manager: .agentCli,
            qualifier: "/Users/w/.claude",
            installPath: URL(fileURLWithPath: "/Users/w/.claude")
        )
        let result = verdict(for: package, in: [package])
        #expect(result.safety == .caution)
    }
}
