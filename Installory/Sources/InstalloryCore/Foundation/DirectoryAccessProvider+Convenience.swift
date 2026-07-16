import Foundation

extension DirectoryAccessProvider {
    /// Returns direct directory contents while preserving the provider's order,
    /// or an empty collection when the location is absent or unreadable.
    ///
    /// Callers remain responsible for filtering, sorting, and cancellation so
    /// their existing scan semantics stay explicit at each traversal site.
    func directoryContentsOrEmpty(at url: URL) -> [URL] {
        (try? contentsOfDirectory(at: url)) ?? []
    }
}
