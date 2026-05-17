import XCTest
@testable import InstalloryCore

final class DescriptionStoreTests: XCTestCase {

    // MARK: - Empty store

    func testEmptyStoreReturnsNil() {
        let store = DescriptionStore()
        XCTAssertNil(store.description(for: .brew, name: "ffmpeg"))
    }

    func testMissingPackageReturnsNil() {
        let store = DescriptionStore(raw: ["brew:ffmpeg": "Audio/video tool"])
        XCTAssertNil(store.description(for: .brew, name: "not-in-corpus"))
    }

    // MARK: - Homebrew exact match

    func testBrewExactMatch() {
        let store = DescriptionStore(raw: ["brew:ffmpeg": "Audio and video converter"])
        XCTAssertEqual(store.description(for: .brew, name: "ffmpeg"), "Audio and video converter")
    }

    func testBrewCaskExactMatch() {
        let store = DescriptionStore(raw: ["brewCask:visual-studio-code": "Code editor"])
        XCTAssertEqual(store.description(for: .brewCask, name: "visual-studio-code"), "Code editor")
    }

    // MARK: - pip PEP 503 normalization

    func testPipExactLowercase() {
        let store = DescriptionStore(raw: ["pip:requests": "HTTP for Humans"])
        XCTAssertEqual(store.description(for: .pip, name: "requests"), "HTTP for Humans")
    }

    func testPipUppercaseNameIsNormalized() {
        // "Requests" in the installed package name should find "pip:requests"
        let store = DescriptionStore(raw: ["pip:requests": "HTTP for Humans"])
        XCTAssertEqual(store.description(for: .pip, name: "Requests"), "HTTP for Humans")
    }

    func testPipUnderscoreToHyphen() {
        // requests_oauthlib → requests-oauthlib
        let store = DescriptionStore(raw: ["pip:requests-oauthlib": "OAuth library"])
        XCTAssertEqual(store.description(for: .pip, name: "requests_oauthlib"), "OAuth library")
    }

    func testPipDotToHyphen() {
        // zope.interface → zope-interface
        let store = DescriptionStore(raw: ["pip:zope-interface": "Zope interfaces"])
        XCTAssertEqual(store.description(for: .pip, name: "zope.interface"), "Zope interfaces")
    }

    func testPipConsecutiveSeparatorsCollapse() {
        // some__package.name → some-package-name
        let store = DescriptionStore(raw: ["pip:some-package-name": "A package"])
        XCTAssertEqual(store.description(for: .pip, name: "some__package.name"), "A package")
    }

    func testPipMixedCaseAndUnderscores() {
        // Pillow vs pillow: stored as "pip:pillow"
        let store = DescriptionStore(raw: ["pip:pillow": "Python Imaging Library"])
        XCTAssertEqual(store.description(for: .pip, name: "Pillow"), "Python Imaging Library")
    }

    func testPipxFollowsSamePEP503Normalization() {
        let store = DescriptionStore(raw: ["pipx:my-tool": "A CLI tool"])
        XCTAssertEqual(store.description(for: .pipx, name: "my_tool"), "A CLI tool")
    }

    // MARK: - npm normalization

    func testNpmExactMatch() {
        let store = DescriptionStore(raw: ["npm:lodash": "Modular utilities"])
        XCTAssertEqual(store.description(for: .npm, name: "lodash"), "Modular utilities")
    }

    func testNpmScopedPackage() {
        // @types/node stored with normalized key "npm:@types/node"
        let store = DescriptionStore(raw: ["npm:@types/node": "Node type definitions"])
        XCTAssertEqual(store.description(for: .npm, name: "@types/node"), "Node type definitions")
    }

    func testNpmUppercaseIsNormalized() {
        let store = DescriptionStore(raw: ["npm:lodash": "Modular utilities"])
        XCTAssertEqual(store.description(for: .npm, name: "Lodash"), "Modular utilities")
    }

    func testNpmScopedPackageUppercaseScope() {
        // @Types/Node → @types/node
        let store = DescriptionStore(raw: ["npm:@types/node": "Node type definitions"])
        XCTAssertEqual(store.description(for: .npm, name: "@Types/Node"), "Node type definitions")
    }

    // MARK: - Other managers (no normalization)

    func testCargoExactMatch() {
        let store = DescriptionStore(raw: ["cargo:serde": "Serialization framework"])
        XCTAssertEqual(store.description(for: .cargo, name: "serde"), "Serialization framework")
    }

    func testGemExactMatch() {
        let store = DescriptionStore(raw: ["gem:rails": "Full-stack web framework"])
        XCTAssertEqual(store.description(for: .gem, name: "rails"), "Full-stack web framework")
    }

    // MARK: - Manager isolation

    func testBrewAndPipWithSameNameAreDistinct() {
        // A package named "curl" might exist in both brew and pip with different descriptions.
        let store = DescriptionStore(raw: [
            "brew:curl": "URL downloader",
            "pip:curl": "Python curl bindings",
        ])
        XCTAssertEqual(store.description(for: .brew, name: "curl"), "URL downloader")
        XCTAssertEqual(store.description(for: .pip, name: "curl"), "Python curl bindings")
    }

    // MARK: - Load from URL

    func testInitFromURLLoadsDescriptions() throws {
        let corpus = """
        {
          "generated": "2026-05-17T00:00:00+00:00",
          "counts": {"brew": 1, "brewCask": 0, "pip": 0, "npm": 0},
          "descriptions": {"brew:wget": "Internet file retriever"}
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-descriptions-\(UUID().uuidString).json")
        try corpus.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try DescriptionStore(contentsOf: url)
        XCTAssertEqual(store.description(for: .brew, name: "wget"), "Internet file retriever")
        XCTAssertNil(store.description(for: .pip, name: "wget"))
    }

    func testInitFromURLThrowsOnMalformedJSON() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bad-\(UUID().uuidString).json")
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try DescriptionStore(contentsOf: url))
    }

    func testInitFromURLThrowsOnMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/descriptions.json")
        XCTAssertThrowsError(try DescriptionStore(contentsOf: url))
    }
}
