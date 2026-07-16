import Foundation
import Testing
@testable import InstalloryCore

@Suite("MasScanner")
struct MasScannerTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("TEST25-009: reads a bundled Info.plist and MAS receipt layout")
    func readsReceiptBearingApps() async throws {
        let applications = URL(fileURLWithPath: "/Applications")
        let fixtureApp = applications.appendingPathComponent("Fixture Reader.app")
        let receiptDate = Date(timeIntervalSince1970: 1_717_000_000)
        let provider = try FixtureResource.provider(
            directory: "mas",
            mappedTo: applications,
            modificationDate: receiptDate
        )

        let packages = try await MasScanner(directoryAccess: provider, homeDirectory: home).scan()

        #expect(packages.count == 1)
        let app = try #require(packages.first)
        #expect(app.id == "mas::app.installory.fixture-reader")
        #expect(app.manager == .mas)
        #expect(app.name == "Fixture Reader")
        #expect(app.version == "3.2.1")
        #expect(app.installPath?.path == fixtureApp.path)
        #expect(app.installedAt == receiptDate)
        #expect(app.installedAtConfidence == .low)
        #expect(app.artifactPaths == [fixtureApp.path])
        #expect((app.sizeBytes ?? 0) > 0)
    }

    @Test("falls back to bundle version and app bundle name")
    func fallsBackToBundleVersionAndAppName() async throws {
        let app = home.appendingPathComponent("Applications/Test App.app")
        let info = try infoPlistData([
            "CFBundleVersion": "42",
        ])
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: app.appendingPathComponent("Contents/_MASReceipt/receipt"), data: Data())
            builder.addFile(at: app.appendingPathComponent("Contents/Info.plist"), data: info)
        }

        let packages = try await MasScanner(directoryAccess: provider, homeDirectory: home).scan()

        let package = try #require(packages.first)
        #expect(package.id == "mas::Test App")
        #expect(package.name == "Test App")
        #expect(package.version == "42")
    }

    @Test("availability requires readable applications directory")
    func availabilityRequiresReadableApplicationsDirectory() async throws {
        let missing = InMemoryDirectoryAccessProvider.make { _ in }
        #expect(await MasScanner(directoryAccess: missing, homeDirectory: home).isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: URL(fileURLWithPath: "/Applications/App.app/Contents/_MASReceipt/receipt"),
                data: Data()
            )
        }
        #expect(await MasScanner(directoryAccess: present, homeDirectory: home).isAvailable() == true)
    }

    @Test("CORE-05: MAS size includes the entire app bundle")
    func sizeIncludesEntireAppBundle() async throws {
        let applications = URL(fileURLWithPath: "/Applications")
        let app = applications.appendingPathComponent("Sized.app")
        let info = try infoPlistData([
            "CFBundleIdentifier": "app.installory.sized",
            "CFBundleName": "Sized",
            "CFBundleShortVersionString": "1.0",
        ])
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: app.appendingPathComponent("Contents/_MASReceipt/receipt"),
                data: Data(),
                logicalSizeBytes: 3
            )
            builder.addFile(
                at: app.appendingPathComponent("Contents/Info.plist"),
                data: info,
                logicalSizeBytes: 5
            )
            builder.addFile(
                at: app.appendingPathComponent("Contents/Resources/archive.bin"),
                data: Data(),
                logicalSizeBytes: 12
            )
        }

        let packages = try await MasScanner(
            directoryAccess: provider,
            homeDirectory: home,
            applicationDirectories: [applications]
        ).scan()
        let package = try #require(packages.first)

        #expect(package.sizeBytes == 20)
    }

    @Test("CORE-05: MAS size skips internal symlinks and their targets")
    func sizeSkipsInternalSymlinksAndTargets() async throws {
        let applications = URL(fileURLWithPath: "/Applications")
        let app = applications.appendingPathComponent("Linked.app")
        let external = URL(fileURLWithPath: "/External/Large.framework")
        let info = try infoPlistData([
            "CFBundleIdentifier": "app.installory.linked",
            "CFBundleName": "Linked",
            "CFBundleShortVersionString": "1.0",
        ])
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: app.appendingPathComponent("Contents/_MASReceipt/receipt"),
                data: Data(),
                logicalSizeBytes: 2
            )
            builder.addFile(
                at: app.appendingPathComponent("Contents/Info.plist"),
                data: info,
                logicalSizeBytes: 3
            )
            builder.addFile(
                at: app.appendingPathComponent("Contents/MacOS/Linked"),
                data: Data(),
                logicalSizeBytes: 5
            )
            builder.addFile(
                at: external.appendingPathComponent("payload.bin"),
                data: Data(),
                logicalSizeBytes: 90_000
            )
            builder.addSymlink(
                at: app.appendingPathComponent("Contents/Frameworks/Large.framework"),
                target: external
            )
        }

        let packages = try await MasScanner(
            directoryAccess: provider,
            homeDirectory: home,
            applicationDirectories: [applications]
        ).scan()
        let package = try #require(packages.first)

        #expect(package.sizeBytes == 10)
    }

    @Test("CORE-05: MAS scan cancellation propagates")
    func cancellationPropagates() async {
        let applications = URL(fileURLWithPath: "/Applications")
        let app = applications.appendingPathComponent("Cancelled.app")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: app.appendingPathComponent("Contents/_MASReceipt/receipt"),
                data: Data()
            )
        }
        let scanner = MasScanner(
            directoryAccess: provider,
            homeDirectory: home,
            applicationDirectories: [applications]
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("explicit empty application directories disable scanning")
    func explicitEmptyApplicationDirectoriesDisableScanning() async throws {
        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: URL(fileURLWithPath: "/Applications/App.app/Contents/_MASReceipt/receipt"),
                data: Data()
            )
        }

        let scanner = MasScanner(
            directoryAccess: present,
            homeDirectory: home,
            applicationDirectories: []
        )
        #expect(await scanner.isAvailable() == false)
        #expect(try await scanner.scan().isEmpty)
    }

    private func infoPlistData(_ values: [String: String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }
}
