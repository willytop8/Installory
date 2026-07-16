import Foundation
import Testing
@testable import InstalloryCore

@Suite("InventoryExporter")
struct InventoryExporterTests {
    @Test("APP-F5: JSON format advertises its file extension")
    func jsonFormatMetadata() {
        #expect(InventoryExporter.Format.json.fileExtension == "json")
        #expect(InventoryExporter.Format.allCases == [.csv, .markdown, .json])
    }

    @Test("APP-F5: JSON export round-trips every Package field")
    func jsonExportRoundTripsEveryPackageField() throws {
        let package = Package(
            id: "pip:/Users/example/.venv/bin/python:formula-tool",
            manager: .pip,
            qualifier: "/Users/example/.venv/bin/python",
            name: "formula-tool",
            version: "2.3.4",
            installPath: URL(fileURLWithPath: "/Users/example/.venv/lib/python3.13/site-packages/formula_tool"),
            installedAt: Date(timeIntervalSince1970: 1_725_000_000),
            installedAtConfidence: .high,
            sizeBytes: 42_000,
            isExplicit: false,
            isReadOnly: true,
            dependencies: ["parser-core", "runtime"],
            artifactPaths: ["/Users/example/.venv/bin/formula-tool"],
            lastSeen: Date(timeIntervalSince1970: 1_725_000_123)
        )

        let json = InventoryExporter().export([package], format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode([Package].self, from: Data(json.utf8))

        #expect(decoded == [package])
    }

    @Test("APP-F5: JSON export is stable across input ordering")
    func jsonExportIsStableAcrossInputOrdering() throws {
        let alpha = makePackage(name: "alpha")
        let zulu = makePackage(name: "zulu")

        let forward = InventoryExporter().export([zulu, alpha], format: .json)
        let reverse = InventoryExporter().export([alpha, zulu], format: .json)
        let alphaPosition = try #require(forward.range(of: "brew::alpha"))
        let zuluPosition = try #require(forward.range(of: "brew::zulu"))

        #expect(forward == reverse)
        #expect(alphaPosition.lowerBound < zuluPosition.lowerBound)
    }

    @Test("APP-F5: JSON export is pretty-printed with sorted keys and one trailing newline")
    func jsonExportFormattingIsDeterministic() {
        let json = InventoryExporter().export([makePackage(name: "example")], format: .json)
        let keyLines = json.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("    \"") else { return nil }
            return line.dropFirst(5).split(separator: "\"", maxSplits: 1).first.map(String.init)
        }

        #expect(json.hasPrefix("[\n  {\n"))
        #expect(keyLines == keyLines.sorted())
        #expect(json.hasSuffix("\n"))
        #expect(!json.dropLast().hasSuffix("\n"))
    }

    @Test("APP-F5: JSON strings round-trip without CSV formula neutralization")
    func jsonStringsRoundTripWithoutCSVNeutralization() throws {
        let name = "\t=SUM(A1:A2)\n\"quoted\""
        let json = InventoryExporter().export([makePackage(name: name)], format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode([Package].self, from: Data(json.utf8))

        #expect(decoded.first?.name == name)
        #expect(!json.contains("\"name\" : \"'"))
    }

    @Test("APP-F5: empty inventory exports as a valid JSON array")
    func emptyInventoryExportsAsJSON() throws {
        let json = InventoryExporter().export([], format: .json)
        let decoded = try JSONDecoder().decode([Package].self, from: Data(json.utf8))

        #expect(json == "[]\n")
        #expect(decoded.isEmpty)
    }

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
