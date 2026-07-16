import AppKit
import InstalloryCore
import SwiftUI
import Testing
@testable import Installory

@Suite("Package table rendering", .serialized)
@MainActor
struct PackageTableRenderingTests {
    @Test("APP-F3: table cells retain the coordinator environment during layout")
    func tableCellsRetainCoordinatorEnvironmentDuringLayout() throws {
        let dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalloryTableRenderingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let coordinator = AppCoordinator(dataDirectoryOverride: dataDirectory)
        coordinator.enterDemoMode()

        let hostingView = NSHostingView(
            rootView: PackageListView()
                .environment(coordinator)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { window.close() }
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 1_000, height: 700))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let selectedPackage = try #require(coordinator.packages.first { $0.name == "ruff" })
        coordinator.selectedPackage = selectedPackage
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        coordinator.inventoryViewMode = .table
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let tableView = hostingView.firstDescendant(ofType: NSTableView.self)
        #expect(tableView?.numberOfRows == coordinator.packages.count)
    }
}

private extension NSView {
    func firstDescendant<ViewType: NSView>(ofType type: ViewType.Type) -> ViewType? {
        if let match = self as? ViewType { return match }
        return subviews.lazy.compactMap { $0.firstDescendant(ofType: type) }.first
    }
}
