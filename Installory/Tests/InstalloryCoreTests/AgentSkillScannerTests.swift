import Foundation
import Testing
@testable import InstalloryCore

@Suite("AgentSkillScanner")
struct AgentSkillScannerTests {
    private let claudeRoot = URL(fileURLWithPath: "/Users/tester/.claude/skills")
    private let opencodeRoot = URL(fileURLWithPath: "/Users/tester/.config/opencode/skills")

    private let frontmatter = """
    ---
    name: app-design
    description: Apple-style interface guidance
    version: 2.1.0
    ---

    # App Design

    Guidance for building polished interfaces.
    """

    private func makeScanner(
        roots: [URL],
        provider: InMemoryDirectoryAccessProvider
    ) -> AgentSkillScanner {
        AgentSkillScanner(
            skillRoots: roots,
            directoryAccess: provider,
            limits: .default,
            now: { Date(timeIntervalSince1970: 1_717_000_000) }
        )
    }

    @Test("reads a healthy skill directory with SKILL.md frontmatter")
    func readsHealthySkill() async throws {
        let skill = claudeRoot.appendingPathComponent("app-design")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: skill.appendingPathComponent("SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addFile(
                at: skill.appendingPathComponent("guidance.md"),
                data: Data("# Design principles".utf8),
                logicalSizeBytes: 20
            )
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()

        #expect(packages.count == 1)
        let package = try #require(packages.first)
        #expect(package.manager == .agentSkill)
        #expect(package.id == "agentSkill:\(claudeRoot.path):app-design")
        #expect(package.qualifier == claudeRoot.path)
        #expect(package.name == "app-design")
        #expect(package.version == "2.1.0")
        #expect(package.installPath == skill)
        #expect(package.artifactPaths == nil)
        #expect(package.isExplicit)
        #expect(!package.isReadOnly)
        #expect(!package.isBrokenAgentSkillLink)
        #expect(!package.isMissingManifestAgentSkill)
        #expect((package.sizeBytes ?? 0) > 0)
    }

    @Test("version is empty when SKILL.md has no version field")
    func unversionedSkill() async throws {
        let skill = claudeRoot.appendingPathComponent("git-workflow")
        let manifest = """
        ---
        name: git-workflow
        ---

        # Git workflow
        """
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: skill.appendingPathComponent("SKILL.md"),
                data: Data(manifest.utf8)
            )
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "git-workflow")
        #expect(package.version == "")
        #expect(package.installPath == skill)
    }

    @Test("directory without SKILL.md is inventoried as missing manifest")
    func missingManifestDirectory() async throws {
        let skill = claudeRoot.appendingPathComponent("half-baked")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: skill)
            builder.addFile(
                at: skill.appendingPathComponent("notes.txt"),
                data: Data("unfinished".utf8),
                logicalSizeBytes: 10
            )
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "half-baked")
        #expect(package.version == "")
        #expect(package.installPath == nil)
        #expect(package.artifactPaths == nil)
        #expect(package.isMissingManifestAgentSkill)
        #expect(!package.isBrokenAgentSkillLink)
    }

    @Test("resolvable symlink records the link path and its resolved target")
    func resolvableSymlink() async throws {
        let target = URL(fileURLWithPath: "/Users/tester/.agents/skills/shared-skill")
        let link = claudeRoot.appendingPathComponent("shared-skill")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: target)
            builder.addFile(
                at: target.appendingPathComponent("SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addSymlink(at: link, target: target)
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "shared-skill")
        #expect(package.installPath == link)
        #expect(package.artifactPaths == [target.path])
        #expect(!package.isBrokenAgentSkillLink)
        #expect(!package.isMissingManifestAgentSkill)
    }

    @Test("broken symlink encodes nil installPath and the target string as artifact")
    func brokenSymlink() async throws {
        let missingTarget = URL(fileURLWithPath: "/Users/tester/skills-src/deprecated")
        let link = claudeRoot.appendingPathComponent("deprecated-skill")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            // The symlink points at a target that is never registered, so
            // fileExists(at: link) is false even though metadata says symbolicLink.
            builder.addSymlink(at: link, target: missingTarget)
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()
        let package = try #require(packages.first)
        #expect(package.name == "deprecated-skill")
        #expect(package.installPath == nil)
        #expect(package.artifactPaths == [missingTarget.path])
        #expect(package.isBrokenAgentSkillLink)
        #expect(!package.isMissingManifestAgentSkill)
    }

    @Test("skips hidden entries and skills.disabled")
    func skipsHiddenAndDisabled() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: claudeRoot.appendingPathComponent("app-design/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addDirectory(at: claudeRoot.appendingPathComponent(".hidden"))
            builder.addDirectory(at: claudeRoot.appendingPathComponent("skills.disabled"))
            builder.addFile(
                at: claudeRoot.appendingPathComponent(".hidden/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addFile(
                at: claudeRoot.appendingPathComponent("skills.disabled/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()
        #expect(packages.map(\.name) == ["app-design"])
    }

    @Test("ignores plain files and other kinds in the root")
    func skipsPlainFiles() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: claudeRoot.appendingPathComponent("real-skill"))
            builder.addFile(
                at: claudeRoot.appendingPathComponent("README.md"),
                data: Data("# skills".utf8),
                logicalSizeBytes: 8
            )
        }

        let packages = try await makeScanner(roots: [claudeRoot], provider: provider).scan()
        #expect(packages.map(\.name) == ["real-skill"])
    }

    @Test("scans multiple roots and tags each skill with its owning root")
    func scansMultipleRoots() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: claudeRoot.appendingPathComponent("a-skill/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addFile(
                at: opencodeRoot.appendingPathComponent("b-skill/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
        }

        let packages = try await makeScanner(
            roots: [claudeRoot, opencodeRoot],
            provider: provider
        ).scan()

        #expect(packages.count == 2)
        let claudeSkill = try #require(packages.first { $0.qualifier == claudeRoot.path })
        #expect(claudeSkill.name == "a-skill")
        let opencodeSkill = try #require(packages.first { $0.qualifier == opencodeRoot.path })
        #expect(opencodeSkill.name == "b-skill")
    }

    @Test("isAvailable is false when no root exists")
    func availabilityRequiresExistingRoot() async throws {
        let empty = InMemoryDirectoryAccessProvider.make { _ in }
        let scanner = makeScanner(roots: [claudeRoot], provider: empty)
        #expect(await scanner.isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: claudeRoot.appendingPathComponent("s/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
        }
        #expect(await makeScanner(roots: [claudeRoot], provider: present).isAvailable() == true)
    }

    @Test("discovery finds home and project-level skill roots, deduplicated")
    func discoveryFindsHomeAndProjectRoots() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let project = URL(fileURLWithPath: "/Users/tester/Projects/App")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".claude/skills/app-design/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addFile(
                at: home.appendingPathComponent(".agents/skills/git-workflow/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addFile(
                at: home.appendingPathComponent(".config/opencode/skills/polish/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            builder.addFile(
                at: project.appendingPathComponent(".claude/skills/proj-skill/SKILL.md"),
                data: Data(frontmatter.utf8)
            )
            // This root does not exist on disk → excluded.
            builder.addDirectory(at: home.appendingPathComponent(".opencode"))
        }

        let roots = AgentSkillDiscovery.skillRoots(
            homeDirectory: home,
            grantedURLs: [project],
            directoryAccess: provider
        )

        #expect(roots.map(\.path) == [
            home.appendingPathComponent(".agents/skills").path,
            home.appendingPathComponent(".claude/skills").path,
            home.appendingPathComponent(".config/opencode/skills").path,
            project.appendingPathComponent(".claude/skills").path,
        ])
    }
}
