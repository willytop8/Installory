import Foundation
import Testing
@testable import InstalloryCore

@Suite("InventoryExporter")
struct InventoryExporterTests {
    @Test(
        "CSV formula prefixes are neutralized",
        arguments: ["=1+1", "+1+1", "-1+1", "@SUM(A1:A2)"]
    )
    func csvFormulaPrefixesAreNeutralized(name: String) {
        let csv = InventoryExporter().export([makePackage(name: name)], format: .csv)

        #expect(csv.contains("brew,'\(name),1.0.0"))
    }

    @Test("CSV formula prefixes hidden behind whitespace or control rows are neutralized")
    func csvFormulaWhitespacePrefixesAreNeutralized() {
        let spaced = InventoryExporter().export(
            [makePackage(name: "  =1+1")],
            format: .csv
        )
        let carriageReturn = InventoryExporter().export(
            [makePackage(name: "\r=1+1")],
            format: .csv
        )

        #expect(spaced.contains("brew,'  =1+1,1.0.0"))
        #expect(carriageReturn.contains("brew,\"'\r=1+1\",1.0.0"))
    }

    @Test("CSV ordinary values and RFC 4180 escaping remain unchanged")
    func csvOrdinaryValuesAndEscapingRemainUnchanged() {
        let ordinaryCSV = InventoryExporter().export(
            [makePackage(name: "ordinary-package")],
            format: .csv
        )
        let escapedCSV = InventoryExporter().export(
            [makePackage(name: "package, \"quoted\"")],
            format: .csv
        )

        #expect(ordinaryCSV.contains("brew,ordinary-package,1.0.0"))
        #expect(escapedCSV.contains("brew,\"package, \"\"quoted\"\"\",1.0.0"))
    }

    @Test("Markdown export does not apply CSV formula neutralization")
    func markdownExportDoesNotApplyCSVFormulaNeutralization() {
        let markdown = InventoryExporter().export(
            [makePackage(name: "=1+1")],
            format: .markdown
        )

        #expect(markdown.contains("| =1+1 |"))
        #expect(!markdown.contains("| '=1+1 |"))
    }

    private func makePackage(name: String) -> Package {
        Package(
            id: "brew::\(name)",
            manager: .brew,
            qualifier: nil,
            name: name,
            version: "1.0.0",
            installPath: URL(fileURLWithPath: "/opt/example"),
            installedAt: nil,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date(timeIntervalSince1970: 0)
        )
    }
}
