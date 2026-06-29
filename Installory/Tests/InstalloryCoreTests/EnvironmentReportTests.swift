import Testing
import Foundation
@testable import InstalloryCore

@Suite("EnvironmentReport")
struct EnvironmentReportTests {

    // MARK: - Helpers

    private static let fixedDate: Date = {
        var comps = DateComponents()
        comps.year = 2025; comps.month = 6; comps.day = 15
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar(identifier: .gregorian).date(from: comps)!
    }()

    private func makePackage(
        manager: PackageManager,
        name: String,
        version: String = "1.0.0",
        qualifier: String? = nil,
        sizeBytes: Int64? = nil,
        installedDaysAgo: Int? = nil
    ) -> Package {
        let installedAt: Date? = installedDaysAgo.map {
            Calendar.current.date(byAdding: .day, value: -$0, to: Self.fixedDate) ?? Self.fixedDate
        }
        return Package(
            id: "\(manager.rawValue):\(qualifier ?? ""):\(name)",
            manager: manager,
            qualifier: qualifier,
            name: name,
            version: version,
            installPath: URL(fileURLWithPath: "/opt/\(name)"),
            installedAt: installedAt,
            installedAtConfidence: .high,
            sizeBytes: sizeBytes,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Self.fixedDate
        )
    }

    // MARK: - Overview section

    @Test func reportContainsPerManagerCountMatchingInput() {
        let packages = [
            makePackage(manager: .brew, name: "wget"),
            makePackage(manager: .brew, name: "ripgrep"),
            makePackage(manager: .npm, name: "typescript"),
        ]
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: packages,
            duplicateGroups: [],
            orphans: [],
            now: Self.fixedDate
        )
        // Should have the overview table
        #expect(output.contains("## Overview"))
        #expect(output.contains("| brew | 2 |"))
        #expect(output.contains("| npm | 1 |"))
        #expect(output.contains("| **Total** | **3** |"))
    }

    @Test func reportHeaderContainsGenerationTimestamp() {
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [],
            duplicateGroups: [],
            orphans: [],
            now: Self.fixedDate
        )
        #expect(output.hasPrefix("# Installory Environment Report"))
        #expect(output.contains("Generated: "))
    }

    // MARK: - Duplicates section

    @Test func duplicatesSectionListsDuplicatesWhenPresent() {
        let pkgBrew = makePackage(manager: .brew, name: "node")
        let pkgCargo = makePackage(manager: .cargo, name: "node")
        let groups = [DuplicateGroup(name: "node", packages: [pkgBrew, pkgCargo])]

        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [pkgBrew, pkgCargo],
            duplicateGroups: groups,
            orphans: [],
            now: Self.fixedDate
        )
        #expect(output.contains("## Cross-Manager Duplicates"))
        #expect(output.contains("node"))
        #expect(output.contains("brew"))
        #expect(output.contains("cargo"))
        #expect(!output.contains("No cross-manager duplicates found."))
    }

    @Test func duplicatesSectionSaysNoneWhenEmpty() {
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [makePackage(manager: .brew, name: "wget")],
            duplicateGroups: [],
            orphans: [],
            now: Self.fixedDate
        )
        #expect(output.contains("## Cross-Manager Duplicates"))
        #expect(output.contains("No cross-manager duplicates found."))
    }

    // MARK: - Orphans section

    @Test func orphansSectionListsOrphansWhenPresent() {
        let orphan = makePackage(manager: .brew, name: "legacy-tool")
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [orphan],
            duplicateGroups: [],
            orphans: [orphan],
            now: Self.fixedDate
        )
        #expect(output.contains("## Packages to Review"))
        #expect(output.contains("legacy-tool"))
        #expect(!output.contains("No explicit leaf packages found."))
    }

    @Test func orphansSectionSaysNoneWhenEmpty() {
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [],
            duplicateGroups: [],
            orphans: [],
            now: Self.fixedDate
        )
        #expect(output.contains("No explicit leaf packages found."))
    }

    // MARK: - Cleanup signals (optional section)

    @Test func largestOldestSectionAbsentWhenNoSignals() {
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [],
            duplicateGroups: [],
            orphans: [],
            now: Self.fixedDate
        )
        #expect(!output.contains("## Largest / Oldest"))
    }

    @Test func largestOldestSectionPresentWhenSignalsProvided() {
        let pkg = makePackage(manager: .brew, name: "xcode", sizeBytes: 7_000_000_000, installedDaysAgo: 300)
        let scores = cleanupScores(for: [pkg], now: Self.fixedDate)
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [pkg],
            duplicateGroups: [],
            orphans: [],
            now: Self.fixedDate,
            cleanupSignals: scores
        )
        #expect(output.contains("## Largest / Oldest"))
        #expect(output.contains("xcode"))
    }

    // MARK: - Regression guard: InventoryExporter unchanged

    @Test func csvExporterOutputUnchanged() {
        // Verifies InventoryExporter was not modified: CSV output still matches spec.
        let pkg = makePackage(manager: .brew, name: "wget", version: "1.24.5")
        let csv = InventoryExporter().export([pkg], format: .csv)
        // Header row must be present
        #expect(csv.hasPrefix("manager,name,version,qualifier,install_path,installed_at,confidence,is_explicit,is_read_only,dependencies\n"))
        // Data row must start with manager and name
        #expect(csv.contains("brew,wget,1.24.5"))
    }

    @Test func markdownExporterOutputUnchanged() {
        // Verifies InventoryExporter.markdown still produces a valid table.
        let pkg = makePackage(manager: .brew, name: "wget", version: "1.24.5")
        let md = InventoryExporter().export([pkg], format: .markdown)
        #expect(md.contains("# Installory Inventory"))
        #expect(md.contains("| Manager | Packages |"))
        #expect(md.contains("wget"))
    }

    // MARK: - Purity

    @Test func sameInputProducesSameOutput() {
        let packages = [
            makePackage(manager: .brew, name: "ffmpeg"),
            makePackage(manager: .npm, name: "typescript"),
        ]
        let groups: [DuplicateGroup] = []
        let renderer = EnvironmentReportRenderer()
        let r1 = renderer.render(
            packages: packages, duplicateGroups: groups, orphans: [], now: Self.fixedDate
        )
        let r2 = renderer.render(
            packages: packages, duplicateGroups: groups, orphans: [], now: Self.fixedDate
        )
        #expect(r1 == r2)
    }

    // MARK: - Markdown escaping

    @Test func pipeInPackageNameIsEscaped() {
        let pkg = makePackage(manager: .brew, name: "pipe|tool")
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [pkg], duplicateGroups: [], orphans: [], now: Self.fixedDate
        )
        // The pipe in the name must be escaped so the table stays well-formed
        #expect(output.contains("pipe\\|tool"))
        // There must be no unescaped literal pipe within the name cell
        // (A simple check: "| pipe|tool |" should NOT appear)
        #expect(!output.contains("| pipe|tool |"))
    }

    @Test func backtickInPackageNameIsEscaped() {
        let pkg = makePackage(manager: .brew, name: "back`tick")
        let renderer = EnvironmentReportRenderer()
        let output = renderer.render(
            packages: [pkg], duplicateGroups: [], orphans: [], now: Self.fixedDate
        )
        #expect(output.contains("back\\`tick"))
    }
}
