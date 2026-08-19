import Foundation
import Testing
@testable import InstalloryCore

@Suite("AgentStackAnalysis")
struct AgentStackAnalysisTests {
    private let claudeRoot = "/Users/tester/.claude/skills"
    private let agentsRoot = "/Users/tester/.agents/skills"
    private let opencodeRoot = "/Users/tester/.config/opencode/skills"

    private func skill(
        _ name: String,
        root: String,
        broken: Bool = false,
        missingManifest: Bool = false
    ) -> Package {
        let rootURL = URL(fileURLWithPath: root)
        return Package(
            id: "agentSkill:\(root):\(name)",
            manager: .agentSkill,
            qualifier: root,
            name: name,
            version: broken || missingManifest ? "" : "1.0.0",
            installPath: broken || missingManifest ? nil : rootURL.appendingPathComponent(name),
            installedAt: Date(timeIntervalSince1970: 1_717_000_000),
            installedAtConfidence: .medium,
            sizeBytes: broken || missingManifest ? nil : 1_000,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            artifactPaths: broken ? ["/Users/tester/skills-src/\(name)"] : nil,
            lastSeen: Date(timeIntervalSince1970: 1_717_000_000)
        )
    }

    @Test("groups skills by tool root and flags cross-root duplicates")
    func duplicatesAcrossRoots() {
        let packages = [
            skill("polish", root: claudeRoot),
            skill("polish", root: opencodeRoot),
            skill("unique", root: claudeRoot),
        ]

        let analysis = AgentStackAnalysis(skills: packages)

        #expect(analysis.toolRoots == [claudeRoot, opencodeRoot].sorted())
        #expect(analysis.duplicatedSkillNames == ["polish"])
        #expect(analysis.containsDuplicatedName("polish"))
        #expect(!analysis.containsDuplicatedName("unique"))
        #expect(analysis.brokenSymlinkIDs.isEmpty)
        #expect(analysis.missingManifestIDs.isEmpty)
    }

    @Test("normalization collapses case so a case-variant counts as duplicate")
    func duplicateNormalization() {
        let packages = [
            skill("MySkill", root: claudeRoot),
            skill("myskill", root: opencodeRoot),
        ]

        let analysis = AgentStackAnalysis(skills: packages)

        #expect(analysis.duplicatedSkillNames == ["myskill"])
        #expect(analysis.duplicatedSkillCount == 1)
    }

    @Test("broken symlinks are reported by id")
    func brokenSymlinks() {
        let broken = skill("deprecated", root: claudeRoot, broken: true)
        let healthy = skill("healthy", root: claudeRoot)

        let analysis = AgentStackAnalysis(skills: [broken, healthy])

        #expect(analysis.brokenSymlinkIDs == [broken.id])
        #expect(analysis.brokenSymlinkCount == 1)
        #expect(analysis.missingManifestIDs.isEmpty)
    }

    @Test("missing-manifest directories are reported by id")
    func missingManifests() {
        let missing = skill("half-baked", root: agentsRoot, missingManifest: true)
        let healthy = skill("healthy", root: agentsRoot)

        let analysis = AgentStackAnalysis(skills: [missing, healthy])

        #expect(analysis.missingManifestIDs == [missing.id])
        #expect(analysis.missingManifestCount == 1)
        #expect(analysis.brokenSymlinkIDs.isEmpty)
    }

    @Test("ignores non-skill packages entirely")
    func ignoresOtherManagers() {
        let brew = Package(
            id: "brew::ffmpeg",
            manager: .brew,
            qualifier: nil,
            name: "ffmpeg",
            version: "6.0",
            installPath: URL(fileURLWithPath: "/opt/homebrew/Cellar/ffmpeg/6.0"),
            installedAt: Date(timeIntervalSince1970: 1_717_000_000),
            installedAtConfidence: .high,
            sizeBytes: 1,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_717_000_000)
        )

        let analysis = AgentStackAnalysis(skills: [brew])

        #expect(analysis.toolRoots.isEmpty)
        #expect(analysis.duplicatedSkillNames.isEmpty)
        #expect(analysis.brokenSymlinkIDs.isEmpty)
        #expect(analysis.missingManifestIDs.isEmpty)
    }

    @Test("Package helpers classify rows consistently")
    func packageStatusHelpers() {
        let healthy = skill("healthy", root: claudeRoot)
        let broken = skill("deprecated", root: claudeRoot, broken: true)
        let missing = skill("half-baked", root: claudeRoot, missingManifest: true)

        #expect(!healthy.isBrokenAgentSkillLink)
        #expect(!healthy.isMissingManifestAgentSkill)
        #expect(broken.isBrokenAgentSkillLink)
        #expect(!broken.isMissingManifestAgentSkill)
        #expect(!missing.isBrokenAgentSkillLink)
        #expect(missing.isMissingManifestAgentSkill)
    }
}
