/// The package managers Installory can inventory.
public enum PackageManager: String, Codable, CaseIterable, Sendable {
    case brew
    case brewCask
    case pip
    case pipx
    case uv
    case npm
    case cargo
    case gem
    case mas
    case agentSkill
    case agentCli
    case editorExtension
}

extension PackageManager {
    /// Whether packages managed by this manager take part in orphan/dependency
    /// analysis. Agent-managed rows (skills, CLI tools, editor extensions) are
    /// standalone leaf entries with no package-manager dependency graph, so they
    /// are always excluded.
    public var participatesInDependencyAnalysis: Bool {
        switch self {
        case .brew, .brewCask, .pip, .pipx, .uv, .npm, .cargo, .gem, .mas:
            return true
        case .agentSkill, .agentCli, .editorExtension:
            return false
        }
    }
}
