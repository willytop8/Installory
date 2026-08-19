import Foundation

extension Package {
    /// True when this skill row is a dangling symlink.
    ///
    /// Agent skills are encoded into existing ``Package`` fields only:
    /// - a real directory with `SKILL.md` → full row (`installPath` set, `artifactPaths` nil)
    /// - a resolvable symlink → `installPath` = the link, `artifactPaths` = [resolved target]
    /// - a broken symlink → `installPath` = nil, `artifactPaths` = [link target string]
    /// - a directory without `SKILL.md` → `installPath` = nil, `artifactPaths` = nil
    public var isBrokenAgentSkillLink: Bool {
        manager == .agentSkill
            && installPath == nil
            && (artifactPaths?.isEmpty == false)
    }

    /// True when this skill entry is a directory that lacks a `SKILL.md` manifest.
    public var isMissingManifestAgentSkill: Bool {
        manager == .agentSkill
            && installPath == nil
            && (artifactPaths?.isEmpty ?? true)
    }
}

/// Aggregate analysis over the agent-skill inventory.
///
/// Agent skills are flat leaf entries with no package-manager dependency graph,
/// so they are excluded from the generic orphans analysis (see
/// ``PackageManager.participatesInDependencyAnalysis``). This model answers the
/// questions that matter for a skills review: which skill names live in more
/// than one tool root, which entries are dangling symlinks, and which entries
/// are missing their `SKILL.md` manifest.
public struct AgentStackAnalysis: Equatable, Sendable {
    /// The tool-root paths that contribute skills, sorted lexicographically.
    public let toolRoots: [String]

    /// Skill names (normalized) that appear in more than one tool root.
    public let duplicatedSkillNames: [String]

    /// IDs of skill rows that are broken symlinks.
    public let brokenSymlinkIDs: [String]

    /// IDs of skill rows that are directories without a `SKILL.md` manifest.
    public let missingManifestIDs: [String]

    public init(skills: [Package]) {
        let skills = skills.filter { $0.manager == .agentSkill }
        self.toolRoots = Array(Set(skills.compactMap(\.qualifier))).sorted()

        var rootsByName: [String: Set<String>] = [:]
        for skill in skills {
            guard let qualifier = skill.qualifier else { continue }
            rootsByName[PackageIdentity.normalizedName(skill.name, manager: .agentSkill), default: []]
                .insert(qualifier)
        }
        self.duplicatedSkillNames = rootsByName
            .filter { $0.value.count > 1 }
            .keys
            .sorted()

        self.brokenSymlinkIDs = skills
            .filter(\.isBrokenAgentSkillLink)
            .map(\.id)
            .sorted()
        self.missingManifestIDs = skills
            .filter(\.isMissingManifestAgentSkill)
            .map(\.id)
            .sorted()
    }

    public var brokenSymlinkCount: Int { brokenSymlinkIDs.count }

    public var missingManifestCount: Int { missingManifestIDs.count }

    public var duplicatedSkillCount: Int { duplicatedSkillNames.count }

    /// Returns true when `name` (normalized the same way the analysis groups
    /// skills) appears in more than one tool root.
    public func containsDuplicatedName(_ name: String) -> Bool {
        duplicatedSkillNames.contains(
            PackageIdentity.normalizedName(name, manager: .agentSkill)
        )
    }
}
