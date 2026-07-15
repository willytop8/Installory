import Foundation
import Testing
@testable import InstalloryCore

@Suite("DirectoryAccessProvider bounded reads")
struct DirectoryAccessProviderTests {
    @Test("PERF25-005: suffix reads stay bounded and discard the partial first line")
    func boundedSuffixRead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalloryBoundedRead-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("history")
        let text = (0..<1_000)
            .map { "line-\(String(format: "%04d", $0))" }
            .joined(separator: "\n")
        try Data(text.utf8).write(to: url)

        let bytes = try SystemDirectoryAccessProvider().data(
            contentsOf: url,
            maximumBytes: 128,
            from: .suffix
        )
        let suffix = try #require(String(data: bytes, encoding: .utf8))

        #expect(bytes.count <= 128)
        #expect(suffix.hasPrefix("line-"))
        #expect(text.hasSuffix(suffix))
        #expect(suffix.hasSuffix("line-0999"))
    }

    @Test("negative bounded read limits are rejected")
    func invalidReadLimit() {
        let url = URL(fileURLWithPath: "/unused")

        #expect(throws: DirectoryAccessError.invalidReadLimit) {
            _ = try SystemDirectoryAccessProvider().data(
                contentsOf: url,
                maximumBytes: -1,
                from: .prefix
            )
        }
    }
}
