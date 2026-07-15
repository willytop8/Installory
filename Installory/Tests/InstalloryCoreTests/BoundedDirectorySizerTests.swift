import Foundation
import Testing
@testable import InstalloryCore

@Suite("BoundedDirectorySizer")
struct BoundedDirectorySizerTests {
    private let root = URL(fileURLWithPath: "/packages/example")

    @Test("CORE-05: nested regular files produce their exact logical-byte sum")
    func nestedFilesProduceExactLogicalSize() async throws {
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

        #expect(try await sizer.measure([.tree(root)]) == .complete(154))
    }

    @Test("CORE-05: child symlinks are skipped without counting their targets")
    func childSymlinksAreSkipped() async throws {
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

        #expect(try await sizer.measure([.tree(root)]) == .complete(10))
    }

    @Test("CORE-05: a symlink root is incomplete")
    func symlinkRootIsIncomplete() async throws {
        let target = URL(fileURLWithPath: "/real/example")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: target)
            builder.addSymlink(at: root, target: target)
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        #expect(try await sizer.measure([.tree(root)]) == .incomplete(.unsafeRoot))
    }

    @Test("CORE-05: an intermediate symlink cannot escape a manager size boundary")
    func intermediateSymlinkCannotEscapeBoundary() async throws {
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

        #expect(try await sizer.measure([.tree(escapedRoot)], constrainedTo: allowed)
            == .incomplete(.unsafeRoot))
    }

    @Test("CORE-05: system provider identifies a final symlink without following it")
    func systemProviderDoesNotFollowFinalSymlink() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallorySizer-\(UUID().uuidString)", isDirectory: true)
        let target = temporaryRoot.appendingPathComponent("target", isDirectory: true)
        let link = temporaryRoot.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let metadata = try SystemDirectoryAccessProvider().metadata(at: link)

        #expect(metadata.kind == .symbolicLink)
        #expect(metadata.logicalSizeBytes == nil)
    }

    @Test("CORE-05: entry cap discards a partial result")
    func entryCapDiscardsPartialResult() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("one"), data: Data([1]))
            builder.addFile(at: root.appendingPathComponent("two"), data: Data([2]))
        }
        let limits = limits(maxEntriesPerMeasurement: 2)
        var sizer = BoundedDirectorySizer(directoryAccess: provider, limits: limits)

        #expect(try await sizer.measure([.tree(root)]) == .incomplete(.entryLimit))
    }

    @Test("CORE-05: byte cap discards a partial result")
    func byteCapDiscardsPartialResult() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("large"), data: Data(), logicalSizeBytes: 11)
        }
        var sizer = BoundedDirectorySizer(
            directoryAccess: provider,
            limits: limits(maxBytesPerMeasurement: 10)
        )

        #expect(try await sizer.measure([.tree(root)]) == .incomplete(.byteLimit))
    }

    @Test("CORE-05: zero duration budget performs no traversal")
    func zeroDurationBudgetPerformsNoTraversal() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
            builder.makeUnreadable(at: root)
        }
        var sizer = BoundedDirectorySizer(
            directoryAccess: provider,
            limits: limits(maxDurationPerMeasurement: .zero)
        )

        #expect(try await sizer.measure([.tree(root)]) == .incomplete(.timeLimit))
    }

    @Test("CORE-05: unreadable child discards a partial result")
    func unreadableChildDiscardsPartialResult() async throws {
        let blocked = root.appendingPathComponent("blocked")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: root.appendingPathComponent("readable"), data: Data([1]))
            builder.addFile(at: blocked, data: Data([2]))
            builder.makeUnreadable(at: blocked)
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        #expect(try await sizer.measure([.tree(root)]) == .incomplete(.unreadable))
    }

    @Test("CORE-05: a readable empty directory reports zero bytes")
    func readableEmptyDirectoryReportsZero() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
        }
        var sizer = BoundedDirectorySizer(directoryAccess: provider)

        #expect(try await sizer.measure([.tree(root)]) == .complete(0))
    }

    @Test("CORE-05: scan-wide exhaustion prevents later provider access")
    func scanWideExhaustionPreventsLaterAccess() async throws {
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

        #expect(try await sizer.measure([.tree(root)]) == .complete(1))
        #expect(try await sizer.measure([.tree(second)]) == .incomplete(.scanEntryLimit))
    }

    @Test("CORE-05: task cancellation throws instead of returning a partial size")
    func taskCancellationThrows() async {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
        }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var sizer = BoundedDirectorySizer(directoryAccess: provider)
            return try await sizer.measure([.tree(root)])
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
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
}
