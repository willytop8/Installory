import Foundation

/// Resolves which user-granted directory, if any, lexically contains a target path.
///
/// Security-scoped bookmarks grant access from an ancestor directory downward.
/// Matching is therefore intentionally one-way and path-component aware: a grant
/// for `/Users/me` covers `/Users/me/project`, but not `/Users/me2`, and a child
/// grant never implies access to its parent.
public enum GrantedPathResolver {
    /// Returns the deepest granted path that contains `targetPath`.
    ///
    /// Equal-depth ties are resolved lexicographically so callers do not inherit
    /// nondeterminism from dictionary iteration order.
    public static func deepestCoveringPath(
        for targetPath: String,
        among grantedPaths: [String]
    ) -> String? {
        let targetComponents = pathComponents(targetPath)
        return grantedPaths
            .compactMap { grantedPath -> (path: String, depth: Int)? in
                let grantComponents = pathComponents(grantedPath)
                guard components(grantComponents, cover: targetComponents) else {
                    return nil
                }
                return (grantedPath, grantComponents.count)
            }
            .sorted {
                if $0.depth != $1.depth { return $0.depth > $1.depth }
                return $0.path < $1.path
            }
            .first?.path
    }

    /// Compares paths after removing redundant separators and `.` / `..` segments.
    public static func referToSameLocation(_ lhs: String, _ rhs: String) -> Bool {
        pathComponents(lhs) == pathComponents(rhs)
    }

    private static func pathComponents(_ path: String) -> [String] {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .pathComponents
    }

    private static func components(_ ancestor: [String], cover target: [String]) -> Bool {
        guard ancestor.count <= target.count else { return false }
        return zip(ancestor, target).allSatisfy { pair in pair.0 == pair.1 }
    }
}
