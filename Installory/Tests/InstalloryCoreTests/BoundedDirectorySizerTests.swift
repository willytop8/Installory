import Foundation
import XCTest
@testable import InstalloryCore

@MainActor
final class BoundedDirectorySizerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/packages/example")

    func testCORE05NestedFilesProduceExactLogicalSize() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: root.appendingPathComponent("bin/tool"),
                data: Data(),
                logicalSizeBytes: 120
            )
            builder.addFile(
                at: root.appendingPathComponent("share/doc.txt"),
                data: Data(),
                logicalSizeBytes: 34
            )
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        let result = try await sizer.measure([.tree(root)])
        XCTAssertEqual(result, .complete(154))
    }

    func testCORE05ChildSymlinksAreSkipped() async throws {
        let outside = URL(fileURLWithPath: "/outside/large.bin")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: root.appendingPathComponent("owned.bin"),
                data: Data(),
                logicalSizeBytes: 10
            )
            builder.addFile(at: outside, data: Data(), logicalSizeBytes: 10_000)
            builder.addSymlink(at: root.appendingPathComponent("linked.bin"), target: outside)
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        let result = try await sizer.measure([.tree(root)])
        XCTAssertEqual(result, .complete(10))
    }

    func testCORE05SymlinkRootIsIncomplete() async throws {
        let target = URL(fileURLWithPath: "/real/example")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: target)
            builder.addSymlink(at: root, target: target)
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        let result = try await sizer.measure([.tree(root)])
        XCTAssertEqual(result, .incomplete(.unsafeRoot))
    }

    func testCORE05IntermediateSymlinkCannotEscapeBoundary() async throws {
        let allowed = URL(fileURLWithPath: "/allowed")
        let outside = URL(fileURLWithPath: "/outside")
        let escapedRoot = allowed.appendingPathComponent("linked/package")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addSymlink(at: allowed.appendingPathComponent("linked"), target: outside)
            builder.addFile(
                at: outside.appendingPathComponent("package/payload"),
                data: Data(),
                logicalSizeBytes: 10_000
            )
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        let result = try await sizer.measure([.tree(escapedRoot)], constrainedTo: allowed)
        XCTAssertEqual(result, .incomplete(.unsafeRoot))
    }

    func testCORE05SystemProviderDoesNotFollowFinalSymlink() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallorySizer-\(UUID().uuidString)", isDirectory: true)
        let target = temporaryRoot.appendingPathComponent("target", isDirectory: true)
        let link = temporaryRoot.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let metadata = try SystemDirectoryAccessProvider().metadata(at: link)

        XCTAssertEqual(metadata.kind, .symbolicLink)
        XCTAssertNil(metadata.logicalSizeBytes)
    }

    func testCORE05EntryCapDiscardsPartialResult() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("one"), data: Data([1]))
            builder.addFile(at: root.appendingPathComponent("two"), data: Data([2]))
        }
        let limits = limits(maxEntriesPerMeasurement: 2)
        var sizer = BoundedDirectorySizer(directoryAccess: provider, limits: limits)

        let result = try await sizer.measure([.tree(root)])
        XCTAssertEqual(result, .incomplete(.entryLimit))
    }

    func testCORE05ByteCapDiscardsPartialResult() async throws {
        trace("entered byte-cap test")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            trace("entered provider builder")
            builder.addFile(at: root.appendingPathComponent("large"), data: Data(), logicalSizeBytes: 11)
            trace("finished provider builder")
        }
        trace("created provider")
        var sizer = BoundedDirectorySizer(
            directoryAccess: provider,
            limits: limits(maxBytesPerMeasurement: 10)
        )
        trace("created sizer")

        trace("starting measurement")
        let result = try await sizer.measure([.tree(root)])
        trace("finished measurement")
        XCTAssertEqual(result, .incomplete(.byteLimit))
    }

    func testCORE05ZeroDurationBudgetPerformsNoTraversal() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
            builder.makeUnreadable(at: root)
        }
        var sizer = BoundedDirectorySizer(
            directoryAccess: provider,
            limits: limits(maxDurationPerMeasurement: .zero)
        )

        let result = try await sizer.measure([.tree(root)])
        XCTAssertEqual(result, .incomplete(.timeLimit))
    }

    func testCORE05UnreadableChildDiscardsPartialResult() async throws {
        let blocked = root.appendingPathComponent("blocked")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("readable"), data: Data([1]))
            builder.addFile(at: blocked, data: Data([2]))
            builder.makeUnreadable(at: blocked)
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        let result = try await sizer.measure([.tree(root)])
        XCTAssertEqual(result, .incomplete(.unreadable))
    }

    func testCORE05ReadableEmptyDirectoryReportsZero() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        let result = try await sizer.measure([.tree(root)])
        XCTAssertEqual(result, .complete(0))
    }

    func testCORE05ScanWideExhaustionPreventsLaterAccess() async throws {
        let second = URL(fileURLWithPath: "/packages/blocked")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("file"), data: Data([1]))
            builder.addDirectory(at: second)
            builder.makeUnreadable(at: second)
        }
        var sizer = BoundedDirectorySizer(
            directoryAccess: provider,
            limits: limits(maxEntriesPerScan: 2)
        )

        let firstResult = try await sizer.measure([.tree(root)])
        let secondResult = try await sizer.measure([.tree(second)])
        XCTAssertEqual(firstResult, .complete(1))
        XCTAssertEqual(secondResult, .incomplete(.scanEntryLimit))
    }

    func testCORE05TaskCancellationThrows() async {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
        }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var sizer = BoundedDirectorySizer(directoryAccess: provider)
            return try await sizer.measure([.tree(root)])
        }

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    private func limits(
        maxEntriesPerMeasurement: Int = 100,
        maxBytesPerMeasurement: Int64 = 1_000,
        maxDurationPerMeasurement: Duration = .seconds(60),
        maxEntriesPerScan: Int = 1_000,
        maxBytesPerScan: Int64 = 10_000,
        maxDurationPerScan: Duration = .seconds(60)
    ) -> DirectorySizeLimits {
        DirectorySizeLimits(
            maxEntriesPerMeasurement: maxEntriesPerMeasurement,
            maxBytesPerMeasurement: maxBytesPerMeasurement,
            maxDurationPerMeasurement: maxDurationPerMeasurement,
            maxEntriesPerScan: maxEntriesPerScan,
            maxBytesPerScan: maxBytesPerScan,
            maxDurationPerScan: maxDurationPerScan
        )
    }

    private func trace(_ message: String) {
        FileHandle.standardError.write(Data("INSTALLORY_SIZER_TRACE: \(message)\n".utf8))
    }
}
