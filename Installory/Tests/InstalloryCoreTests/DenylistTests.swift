import Testing
import Foundation
@testable import InstalloryCore

@Suite("Denylist")
struct DenylistTests {

    // MARK: - Helpers

    private func makePackage(manager: PackageManager, name: String) -> Package {
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
            artifactPaths: nil,
            lastSeen: Date()
        )
    }

    // MARK: - Default denylist coverage

    @Test func defaultDenylistMatchesBrew_git() {
        let pkg = makePackage(manager: .brew, name: "git")
        #expect(Denylist.default.isDenylisted(pkg))
    }

    @Test func defaultDenylistMatchesBrew_curl() {
        let pkg = makePackage(manager: .brew, name: "curl")
        #expect(Denylist.default.isDenylisted(pkg))
    }

    @Test func defaultDenylistMatchesBrew_openssl() {
        let pkg = makePackage(manager: .brew, name: "openssl")
        #expect(Denylist.default.isDenylisted(pkg))
    }

    @Test func defaultDenylistMatchesBrew_pythonGlob() {
        // "python@*" should match any python@X.Y variant
        let py312 = makePackage(manager: .brew, name: "python@3.12")
        let py313 = makePackage(manager: .brew, name: "python@3.13")
        let py310 = makePackage(manager: .brew, name: "python@3.10")
        #expect(Denylist.default.isDenylisted(py312))
        #expect(Denylist.default.isDenylisted(py313))
        #expect(Denylist.default.isDenylisted(py310))
    }

    @Test func defaultDenylistMatchesPip_pip() {
        let pkg = makePackage(manager: .pip, name: "pip")
        #expect(Denylist.default.isDenylisted(pkg))
    }

    @Test func defaultDenylistMatchesNpm_npm() {
        let pkg = makePackage(manager: .npm, name: "npm")
        #expect(Denylist.default.isDenylisted(pkg))
    }

    @Test func defaultDenylistMatchesPip_setuptools() {
        let pkg = makePackage(manager: .pip, name: "setuptools")
        #expect(Denylist.default.isDenylisted(pkg))
    }

    @Test func defaultDenylistMatchesNpm_corepack() {
        let pkg = makePackage(manager: .npm, name: "corepack")
        #expect(Denylist.default.isDenylisted(pkg))
    }

    // MARK: - Non-matches

    @Test func nonDenylistedPackageReturnsFalse() {
        let pkg = makePackage(manager: .brew, name: "jq")
        #expect(!Denylist.default.isDenylisted(pkg))
    }

    @Test func pythonWithoutAtSignDoesNotMatch() {
        // "python" (no @) should not match the "python@*" glob
        let pkg = makePackage(manager: .brew, name: "python")
        #expect(!Denylist.default.isDenylisted(pkg))
    }

    // MARK: - Manager isolation

    @Test func wrongManagerDoesNotTriggerMatch() {
        // A pip package named "git" should NOT match the brew denylist entry for "git"
        let gitViaPip = makePackage(manager: .pip, name: "git")
        #expect(!Denylist.default.isDenylisted(gitViaPip))

        // Similarly, a brew package named "pip" should NOT match the pip denylist entry
        let pipViaBrew = makePackage(manager: .brew, name: "pip")
        #expect(!Denylist.default.isDenylisted(pipViaBrew))
    }

    // MARK: - Reason

    @Test func reasonForDenylistedPackage() {
        let pkg = makePackage(manager: .brew, name: "git")
        let reason = Denylist.default.reason(for: pkg)
        #expect(reason != nil)
        #expect(reason!.contains("development tools"))
    }

    @Test func reasonForNonDenylistedPackageIsNil() {
        let pkg = makePackage(manager: .brew, name: "jq")
        #expect(Denylist.default.reason(for: pkg) == nil)
    }

    // MARK: - Custom denylist

    @Test func customDenylistWithCustomEntries() {
        let entry = DenylistEntry(manager: .npm, namePattern: "danger-tool", reason: "just dangerous")
        let list = Denylist(entries: [entry])

        let match = makePackage(manager: .npm, name: "danger-tool")
        let noMatch = makePackage(manager: .npm, name: "safe-tool")

        #expect(list.isDenylisted(match))
        #expect(!list.isDenylisted(noMatch))
        #expect(list.reason(for: match) == "just dangerous")
    }

    @Test func customDenylistGlobPattern() {
        let entry = DenylistEntry(manager: .brew, namePattern: "mylib@*", reason: "pinned")
        let list = Denylist(entries: [entry])

        #expect(list.isDenylisted(makePackage(manager: .brew, name: "mylib@1")))
        #expect(list.isDenylisted(makePackage(manager: .brew, name: "mylib@2.0")))
        #expect(!list.isDenylisted(makePackage(manager: .brew, name: "mylib")))
        #expect(!list.isDenylisted(makePackage(manager: .brew, name: "other@1")))
    }
}
