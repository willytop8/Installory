import BackshelfCore
import Foundation

@Observable
@MainActor
final class AppCoordinator {
    private(set) var scanResults: [Package] = []
    private(set) var scanStatuses: [PackageManager: ScannerStatus] = [:]
    private(set) var isScanning = false

    let folderAccess = FolderAccessManager()
    private(set) var database: Database?

    init() {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("Backshelf", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            database = try? Database(directory: dir)
        }

        // Restore bookmarks persisted from a previous session.
        folderAccess.loadPersistedBookmarks()
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        // Security-scoped bookmarks must be started before the scan begins.
        // All three scanners use SystemDirectoryAccessProvider, which goes through
        // FileManager.default. FileManager only sees directories outside the sandbox
        // container after startAccessingSecurityScopedResource() is called for each
        // bookmark the user has granted. stopAccessingSecurityScopedResource() is
        // called in the defer block below, after the stream is exhausted.
        var accessedURLs: [URL] = []
        for (_, data) in folderAccess.grantedBookmarks() {
            if let url = folderAccess.startAccessing(data) {
                accessedURLs.append(url)
            }
        }
        defer {
            for url in accessedURLs { folderAccess.stopAccessing(url) }
        }

        let scanners: [any PackageScanner] = [
            BrewScanner(),
            PipScanner(),
            NpmScanner(),
        ]
        let coordinator = ScanCoordinator(scanners: scanners)

        scanResults = []
        scanStatuses = [:]

        for await event in await coordinator.scan() {
            switch event {
            case .scannerStarted:
                break
            case let .scannerFinished(manager, status, pkgs):
                scanStatuses[manager] = status
                scanResults += pkgs
            case let .allFinished(perManager, allPackages):
                scanStatuses = perManager
                scanResults = allPackages
            }
        }
    }
}
