import AppKit
import Foundation

@Observable
@MainActor
final class FolderAccessManager {
    /// Paths whose stored bookmarks failed to resolve on launch.
    /// The user will be prompted to re-grant on the next scan attempt.
    private(set) var staleBookmarkPaths: Set<String> = []

    private var storedBookmarks: [String: Data] = [:]
    private let defaultsKey = "app.installory.bookmarks"

    // MARK: - Launch

    func loadPersistedBookmarks() {
        guard let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] else { return }

        var valid: [String: Data] = [:]
        for (path, data) in raw {
            var isStale = false
            if (try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )) != nil, !isStale {
                valid[path] = data
            } else {
                staleBookmarkPaths.insert(path)
            }
        }

        storedBookmarks = valid
        // Persist only the non-stale entries so stale paths don't accumulate.
        UserDefaults.standard.set(valid, forKey: defaultsKey)
    }

    // MARK: - Task-spec API

    /// Opens an NSOpenPanel pre-navigated to `suggestedURL`, creates a
    /// security-scoped bookmark, persists it to UserDefaults, and returns the
    /// granted URL. Returns nil if the user cancels or bookmark creation fails.
    func requestAccess(to suggestedURL: URL?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Grant Installory read access to this folder"
        panel.prompt = "Grant Access"
        panel.directoryURL = suggestedURL

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }

        let path = url.path
        storedBookmarks[path] = data
        staleBookmarkPaths.remove(path)

        var raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
        raw[path] = data
        UserDefaults.standard.set(raw, forKey: defaultsKey)

        return url
    }

    /// Resolves `bookmarkData` and starts security-scoped access.
    /// Returns the resolved URL on success, nil if resolution or access fails.
    /// The caller must eventually call `stopAccessing(_:)` on the returned URL.
    func startAccessing(_ bookmarkData: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else { return nil }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    func grantedBookmarks() -> [(path: String, bookmark: Data)] {
        storedBookmarks.map { (path: $0.key, bookmark: $0.value) }
    }

    // MARK: - Helpers

    var hasAnyGrant: Bool { !storedBookmarks.isEmpty }

    /// All currently-granted directory paths.
    var grantedPaths: [String] { Array(storedBookmarks.keys) }

    /// Returns a stored path that is equal to or a parent/child of `prefix`,
    /// or nil if no such grant exists.
    func grantedPath(forPrefix prefix: String) -> String? {
        storedBookmarks.keys.first { $0.hasPrefix(prefix) || prefix.hasPrefix($0) }
    }
}
