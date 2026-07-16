import Foundation
import Testing
@testable import InstalloryCore

@Suite("ScanInventoryReconciler")
struct ScanInventoryReconcilerTests {
    private func package(_ name: String, manager: PackageManager) -> Package {
        Package(
            id: "\(manager.rawValue)::\(name)",
            manager: manager,
            qualifier: nil,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .unknown,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    @Test(
        "failed, timed-out, and skipped scans preserve last-known packages",
        arguments: [
            ScannerStatus.failed(reason: "bad metadata", durationMs: 1),
            ScannerStatus.timedOut(durationMs: 2),
            ScannerStatus.skipped(reason: "folder not granted"),
        ]
    )
    func nonSuccessPreservesInventory(status: ScannerStatus) {
        let existing = [
            package("ripgrep", manager: .cargo),
            package("typescript", manager: .npm),
        ]

        let reconciled = ScanInventoryReconciler.reconcile(
            existing: existing,
            scanned: [],
            managedManagers: [.cargo],
            status: status
        )

        #expect(reconciled == existing)
    }

    @Test("a successful empty scan clears only its managed partition")
    func successfulEmptyScanClearsPartition() {
        let npm = package("typescript", manager: .npm)
        let reconciled = ScanInventoryReconciler.reconcile(
            existing: [package("ripgrep", manager: .cargo), npm],
            scanned: [],
            managedManagers: [.cargo],
            status: .succeeded(count: 0, durationMs: 1)
        )

        #expect(reconciled == [npm])
    }

    @Test("Homebrew reconciliation replaces formulae and casks as one partition")
    func homebrewReplacesBothManagedManagers() {
        let npm = package("typescript", manager: .npm)
        let freshFormula = package("git", manager: .brew)
        let freshCask = package("visual-studio-code", manager: .brewCask)

        let reconciled = ScanInventoryReconciler.reconcile(
            existing: [
                package("old-formula", manager: .brew),
                package("old-cask", manager: .brewCask),
                npm,
            ],
            scanned: [freshFormula, freshCask],
            managedManagers: [.brew, .brewCask],
            status: .succeeded(count: 2, durationMs: 1)
        )

        #expect(reconciled == [npm, freshFormula, freshCask])
        #expect(Set(reconciled.map(\.id)).count == reconciled.count)
    }

    @Test("scanner output outside its declared partitions is ignored")
    func ignoresUndeclaredManagerOutput() {
        let cargo = package("ripgrep", manager: .cargo)
        let reconciled = ScanInventoryReconciler.reconcile(
            existing: [cargo],
            scanned: [package("typescript", manager: .npm)],
            managedManagers: [.cargo],
            status: .succeeded(count: 1, durationMs: 1)
        )

        #expect(reconciled.isEmpty)
    }

    @Test("BrewScanner declares formula and cask ownership")
    func brewScannerOwnsBothPartitions() {
        #expect(BrewScanner().managedPackageManagers == [.brew, .brewCask])
    }

    @Test("UV-F1: malformed uv scans preserve the last-known uv partition")
    func malformedUvScanPreservesLastKnownPartition() {
        let uv = package("ruff", manager: .uv)
        let brew = package("git", manager: .brew)

        let reconciled = ScanInventoryReconciler.reconcile(
            existing: [uv, brew],
            scanned: [],
            managedManagers: UvToolScanner(
                toolDirectory: URL(fileURLWithPath: "/uv/tools")
            ).managedPackageManagers,
            status: .failed(reason: "invalid uv-receipt.toml", durationMs: 1)
        )

        #expect(reconciled == [uv, brew])
    }
}
