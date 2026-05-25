import Foundation
import Testing
@testable import InstalloryCore

@Suite("MasScanner")
struct MasScannerTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("reads Mac App Store apps from receipt-bearing app bundles")
    func readsReceiptBearingApps() async throws {
        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")
        let receipt = xcode.appendingPathComponent("Contents/_MASReceipt/receipt")
        let receiptDate = Date(timeIntervalSince1970: 1_717_000_000)
        let info = try infoPlistData([
            "CFBundleIdentifier": "com.apple.dt.Xcode",
            "CFBundleName": "Xcode",
            "CFBundleShortVersionString": "16.4",
            "CFBundleVersion": "16F6",
        ])

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: receipt, data: Data("receipt".utf8), modificationDate: receiptDate)
            builder.addFile(at: xcode.appendingPathComponent("Contents/Info.plist"), data: info)
            builder.addFile(
                at: URL(fileURLWithPath: "/Applications/NotFromStore.app/Contents/Info.plist"),
                data: try! infoPlistData(["CFBundleName": "NotFromStore"])
            )
        }

        let packages = try await MasScanner(directoryAccess: provider, homeDirectory: home).scan()

        #expect(packages.count == 1)
        let app = try #require(packages.first)
        #expect(app.id == "mas::com.apple.dt.Xcode")
        #expect(app.manager == .mas)
        #expect(app.name == "Xcode")
        #expect(app.version == "16.4")
        #expect(app.installPath == xcode)
        #expect(app.installedAt == receiptDate)
        #expect(app.installedAtConfidence == .low)
        #expect(app.artifactPaths == [xcode.path])
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
