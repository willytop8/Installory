import Testing
@testable import Installory

@Suite("Canonical directories")
struct CanonicalDirectoryTests {
    @Test("APP25-011: Apple Silicon offers both native and Rosetta Homebrew roots")
    func appleSiliconIncludesBothHomebrewRoots() {
        let paths = CanonicalDirectory.all(isAppleSilicon: true).map(\.path)

        #expect(paths.contains("/opt/homebrew"))
        #expect(paths.contains("/usr/local"))
    }

    @Test("Intel offers the Intel Homebrew root once")
    func intelIncludesUsrLocalOnce() {
        let paths = CanonicalDirectory.all(isAppleSilicon: false).map(\.path)

        #expect(paths.filter { $0 == "/usr/local" }.count == 1)
        #expect(!paths.contains("/opt/homebrew"))
    }
}
