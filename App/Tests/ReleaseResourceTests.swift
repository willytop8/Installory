import XCTest

final class ReleaseResourceTests: XCTestCase {
    func testBundledThirdPartyNoticePreservesBootstrapIconsMITLicense() throws {
        let noticeURL = try XCTUnwrap(
            Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
            "ThirdPartyNotices.txt must ship in the application bundle"
        )
        let notice = try String(contentsOf: noticeURL, encoding: .utf8)

        XCTAssertTrue(notice.contains("Copyright (c) 2019-2024 The Bootstrap Authors"))
        XCTAssertTrue(notice.contains("The above copyright notice and this permission notice"))
        XCTAssertTrue(notice.contains("https://icons.getbootstrap.com/icons/search/"))
    }

    func testBundledThirdPartyNoticePreservesGRDBMITLicense() throws {
        let noticeURL = try XCTUnwrap(
            Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
            "ThirdPartyNotices.txt must ship in the application bundle"
        )
        let notice = try String(contentsOf: noticeURL, encoding: .utf8)

        XCTAssertTrue(notice.contains("Copyright (C) 2015-2025 Gwendal Roué"))
        XCTAssertTrue(notice.contains("https://github.com/groue/GRDB.swift"))
    }

    func testExportComplianceFlagDeclaresNoNonExemptEncryption() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool,
            false
        )
    }
}
