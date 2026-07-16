import Foundation
import Testing
@testable import InstalloryCore

@Suite("UvToolScanner")
struct UvToolScannerTests {
    private let root = URL(fileURLWithPath: "/Users/tester/.local/share/uv/tools")
    private let observedAt = Date(timeIntervalSince1970: 1_752_528_000)
    private let installedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("APP-F uv: current receipts report only the exact installed main distribution")
    func uvToolScannerReadsCurrentReceiptAndReportsMainDistributionOnly() async throws {
        let provider = try FixtureResource.provider(
            directory: "uv/default/tools",
            mappedTo: root,
            modificationDate: installedAt
        )

        let packages = try await UvToolScanner(
            toolDirectory: root,
            directoryAccess: provider,
            now: { observedAt }
        ).scan()

        #expect(packages.count == 1)
        let package = try #require(packages.first)
        let environment = root.appendingPathComponent("ruff")
        #expect(package.id == "uv:\(environment.path):ruff")
        #expect(package.manager == .uv)
        #expect(package.qualifier == environment.path)
        #expect(package.name == "Ruff")
        #expect(package.version == "0.6.9")
        #expect(package.installPath == environment)
        #expect(package.installedAt == installedAt)
        #expect(package.installedAtConfidence == .medium)
        #expect((package.sizeBytes ?? 0) > 0)
        #expect(package.isExplicit)
        #expect(!package.isReadOnly)
        #expect(package.dependencies == ["click", "platformdirs"])
        #expect(package.artifactPaths == ["/Users/tester/.local/bin/ruff"])
        #expect(package.lastSeen == observedAt)
    }

    @Test("APP-F uv: legacy string requirements remain readable")
    func uvToolScannerAcceptsLegacyStringRequirementReceipt() async throws {
        let provider = try FixtureResource.provider(
            directory: "uv/legacy/tools",
            mappedTo: root
        )

        let package = try #require(
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan().first
        )

        #expect(package.name == "black")
        #expect(package.version == "24.2.0")
        #expect(package.artifactPaths == [
            "/Users/tester/.local/bin/black",
            "/Users/tester/.local/bin/blackd",
        ])
    }

    @Test("APP-F uv: installed METADATA version wins over the requested specifier")
    func uvToolScannerUsesExactDistInfoVersionNotRequestedSpecifier() async throws {
        let provider = try FixtureResource.provider(
            directory: "uv/default/tools",
            mappedTo: root
        )

        let package = try #require(
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan().first
        )

        #expect(package.version == "0.6.9")
        #expect(package.version != ">=0.6")
    }

    @Test("APP-F uv: identity is root-qualified and uses the normalized target")
    func uvToolIdentityChangesWhenAuthoritativeRootChanges() async throws {
        let firstRoot = URL(fileURLWithPath: "/Users/tester/.local/share/uv/tools")
        let secondRoot = URL(fileURLWithPath: "/Volumes/Tools/uv/tools")
        let firstProvider = provider(
            root: firstRoot,
            targetDirectory: "friendly_bard",
            requirement: "friendly.bard",
            metadataName: "Friendly-Bard"
        )
        let secondProvider = provider(
            root: secondRoot,
            targetDirectory: "friendly_bard",
            requirement: "friendly.bard",
            metadataName: "Friendly-Bard"
        )

        let first = try #require(
            try await UvToolScanner(
                toolDirectory: firstRoot,
                directoryAccess: firstProvider
            ).scan().first
        )
        let second = try #require(
            try await UvToolScanner(
                toolDirectory: secondRoot,
                directoryAccess: secondProvider
            ).scan().first
        )

        #expect(first.id == "uv:\(firstRoot.path)/friendly_bard:friendly-bard")
        #expect(second.id == "uv:\(secondRoot.path)/friendly_bard:friendly-bard")
        #expect(first.id != second.id)
    }

    @Test("APP-F uv: a readable root with only markers and temporary state is empty")
    func uvToolScannerSuccessfulReadableEmptyRootReturnsEmpty() async throws {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
            builder.addFile(
                at: root.appendingPathComponent(".gitignore"),
                data: Data("*\n".utf8)
            )
            builder.addDirectory(at: root.appendingPathComponent(".tmp-install"))
        }

        let scanner = UvToolScanner(toolDirectory: root, directoryAccess: provider)
        #expect(await scanner.isAvailable())
        #expect(try await scanner.scan().isEmpty)
    }

    @Test("APP-F uv: an unreadable authoritative root throws instead of clearing inventory")
    func uvToolScannerUnreadableRootThrowsInsteadOfReturningEmpty() async {
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addDirectory(at: root)
            builder.makeUnreadable(at: root)
        }

        await #expect(throws: (any Error).self) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan()
        }
    }

    @Test("APP-F uv: malformed receipts fail the manager scan")
    func uvToolScannerMalformedReceiptThrows() async {
        let environment = root.appendingPathComponent("ruff")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: environment.appendingPathComponent("uv-receipt.toml"),
                data: Data("[tool]\nrequirements = [{ name = \"ruff\" }]\nentrypoints = [".utf8)
            )
            addMetadata(
                builder: &builder,
                environment: environment,
                name: "ruff",
                version: "1.0.0"
            )
        }

        await #expect(throws: UvToolScannerError.invalidReceipt(
            environment.appendingPathComponent("uv-receipt.toml")
        )) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan()
        }
    }

    @Test("APP-F uv: missing and ambiguous target dist-info are rejected")
    func uvToolScannerRejectsMissingOrAmbiguousTargetDistInfo() async {
        let missingEnvironment = root.appendingPathComponent("ruff")
        let missing = InMemoryDirectoryAccessProvider.make { builder in
            addReceipt(builder: &builder, environment: missingEnvironment, requirement: "ruff")
            addMetadata(
                builder: &builder,
                environment: missingEnvironment,
                name: "click",
                version: "8.1.7"
            )
        }
        await #expect(throws: UvToolScannerError.missingTargetDistribution(missingEnvironment)) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: missing
            ).scan()
        }

        let ambiguousEnvironment = root.appendingPathComponent("ruff")
        let ambiguous = InMemoryDirectoryAccessProvider.make { builder in
            addReceipt(builder: &builder, environment: ambiguousEnvironment, requirement: "ruff")
            addMetadata(
                builder: &builder,
                environment: ambiguousEnvironment,
                python: "python3.12",
                name: "ruff",
                version: "1.0.0"
            )
            addMetadata(
                builder: &builder,
                environment: ambiguousEnvironment,
                python: "python3.13",
                name: "ruff",
                version: "1.0.1"
            )
        }
        await #expect(throws: UvToolScannerError.ambiguousTargetDistribution(
            ambiguousEnvironment
        )) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: ambiguous
            ).scan()
        }
    }

    @Test("APP-F uv: receipt and metadata reads honor injected ceilings")
    func uvToolScannerBoundsReceiptAndMetadataReads() async {
        let receiptEnvironment = root.appendingPathComponent("ruff")
        let receipt = receiptData(requirement: "ruff")
        let oversizedReceipt = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: receiptEnvironment.appendingPathComponent("uv-receipt.toml"),
                data: receipt,
                logicalSizeBytes: Int64(receipt.count)
            )
            addMetadata(
                builder: &builder,
                environment: receiptEnvironment,
                name: "ruff",
                version: "1.0.0"
            )
        }
        await #expect(throws: UvToolScannerError.receiptExceedsLimit(
            receiptEnvironment.appendingPathComponent("uv-receipt.toml")
        )) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: oversizedReceipt,
                limits: .init(maximumReceiptBytes: receipt.count - 1)
            ).scan()
        }

        let metadataEnvironment = root.appendingPathComponent("ruff")
        let metadata = metadataData(name: "ruff", version: "1.0.0")
        let oversizedMetadata = InMemoryDirectoryAccessProvider.make { builder in
            addReceipt(builder: &builder, environment: metadataEnvironment, requirement: "ruff")
            builder.addFile(
                at: metadataURL(environment: metadataEnvironment, name: "ruff", version: "1.0.0"),
                data: metadata,
                logicalSizeBytes: Int64(metadata.count)
            )
        }
        let expectedMetadataURL = metadataURL(
            environment: metadataEnvironment,
            name: "ruff",
            version: "1.0.0"
        )
        await #expect(throws: UvToolScannerError.metadataExceedsLimit(expectedMetadataURL)) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: oversizedMetadata,
                limits: .init(maximumMetadataBytes: metadata.count - 1)
            ).scan()
        }
    }

    @Test("APP-F uv: cancellation propagates after a large-walk enumeration boundary")
    func uvToolScannerCancellationPropagatesDuringLargeWalk() async {
        let environment = root.appendingPathComponent("ruff")
        let base = provider(
            root: root,
            targetDirectory: "ruff",
            requirement: "ruff",
            metadataName: "ruff"
        )
        let cancellationURL = environment
            .appendingPathComponent("lib/python3.12/site-packages")
        let provider = CancellationInjectingDirectoryAccessProvider(
            base: base,
            cancellationURL: cancellationURL
        )

        let task = Task {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan()
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("APP-F uv: size stays inside the environment and never probes entrypoint targets")
    func uvToolSizeIncludesEnvironmentButNeverFollowsExternalEntrypointsOrSymlinks() async throws {
        let environment = root.appendingPathComponent("ruff")
        let externalEntrypoint = URL(fileURLWithPath: "/Volumes/External Tools/bin/ruff")
        let externalPayload = URL(fileURLWithPath: "/Volumes/External/payload")
        let receipt = receiptData(requirement: "ruff", entrypoint: externalEntrypoint.path)
        let metadata = metadataData(name: "ruff", version: "1.0.0")
        let base = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: environment.appendingPathComponent("uv-receipt.toml"),
                data: receipt
            )
            builder.addFile(
                at: metadataURL(environment: environment, name: "ruff", version: "1.0.0"),
                data: metadata
            )
            builder.addSymlink(
                at: environment.appendingPathComponent("bin/external-payload"),
                target: externalPayload
            )
        }
        let trace = DirectoryAccessTrace()
        let provider = TracingDirectoryAccessProvider(base: base, trace: trace)

        let package = try #require(
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan().first
        )

        #expect(package.sizeBytes == Int64(receipt.count + metadata.count))
        #expect(package.artifactPaths == [externalEntrypoint.path])
        #expect(!trace.entries.contains { entry in
            entry.url.path == externalEntrypoint.path
                || entry.url.path.hasPrefix(externalPayload.path)
        })
    }

    @Test("APP-F uv: incomplete bounded size measurements publish nil")
    func uvToolSizePublishesNilWhenBoundIsExceeded() async throws {
        let provider = provider(
            root: root,
            targetDirectory: "ruff",
            requirement: "ruff",
            metadataName: "ruff"
        )
        let sizeLimits = DirectorySizeLimits(
            maxEntriesPerMeasurement: 100,
            maxBytesPerMeasurement: 1,
            maxDurationPerMeasurement: .seconds(10),
            maxEntriesPerScan: 100,
            maxBytesPerScan: 1,
            maxDurationPerScan: .seconds(10)
        )

        let package = try #require(
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider,
                directorySizeLimits: sizeLimits
            ).scan().first
        )

        #expect(package.sizeBytes == nil)
    }

    @Test("APP-F uv: final environment symlinks cannot escape the selected root")
    func uvToolScannerRejectsSymlinkEnvironmentEscape() async {
        let externalEnvironment = URL(fileURLWithPath: "/Volumes/External/ruff")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            addReceipt(builder: &builder, environment: externalEnvironment, requirement: "ruff")
            addMetadata(
                builder: &builder,
                environment: externalEnvironment,
                name: "ruff",
                version: "1.0.0"
            )
            builder.addSymlink(
                at: root.appendingPathComponent("ruff"),
                target: externalEnvironment
            )
        }

        await #expect(throws: UvToolScannerError.unsafePath(
            root.appendingPathComponent("ruff")
        )) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan()
        }
    }

    @Test("APP-F uv: receipt entrypoint paths must be absolute and control-free")
    func uvToolScannerRejectsUnsafeEntrypointPath() async {
        let environment = root.appendingPathComponent("ruff")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: environment.appendingPathComponent("uv-receipt.toml"),
                data: receiptData(requirement: "ruff", entrypoint: "../bin/ruff")
            )
            addMetadata(
                builder: &builder,
                environment: environment,
                name: "ruff",
                version: "1.0.0"
            )
        }

        await #expect(throws: UvToolScannerError.invalidEntrypointPath(
            environment.appendingPathComponent("uv-receipt.toml")
        )) {
            try await UvToolScanner(
                toolDirectory: root,
                directoryAccess: provider
            ).scan()
        }
    }

    private func provider(
        root: URL,
        targetDirectory: String,
        requirement: String,
        metadataName: String
    ) -> InMemoryDirectoryAccessProvider {
        let environment = root.appendingPathComponent(targetDirectory)
        return InMemoryDirectoryAccessProvider.make { builder in
            addReceipt(builder: &builder, environment: environment, requirement: requirement)
            addMetadata(
                builder: &builder,
                environment: environment,
                name: metadataName,
                version: "1.2.3"
            )
        }
    }

    private func addReceipt(
        builder: inout InMemoryDirectoryAccessProvider.Builder,
        environment: URL,
        requirement: String
    ) {
        builder.addFile(
            at: environment.appendingPathComponent("uv-receipt.toml"),
            data: receiptData(requirement: requirement)
        )
    }

    private func addMetadata(
        builder: inout InMemoryDirectoryAccessProvider.Builder,
        environment: URL,
        python: String = "python3.12",
        name: String,
        version: String
    ) {
        builder.addFile(
            at: metadataURL(
                environment: environment,
                python: python,
                name: name,
                version: version
            ),
            data: metadataData(name: name, version: version)
        )
    }

    private func metadataURL(
        environment: URL,
        python: String = "python3.12",
        name: String,
        version: String
    ) -> URL {
        let stem = name.lowercased().replacingOccurrences(of: "-", with: "_")
        return environment.appendingPathComponent(
            "lib/\(python)/site-packages/\(stem)-\(version).dist-info/METADATA"
        )
    }

    private func receiptData(
        requirement: String,
        entrypoint: String = "/Users/tester/.local/bin/tool"
    ) -> Data {
        Data(
            """
            [tool]
            requirements = [{ name = "\(requirement)" }]
            entrypoints = [{ name = "tool", install-path = "\(entrypoint)", from = "\(requirement)" }]
            """.utf8
        )
    }

    private func metadataData(name: String, version: String) -> Data {
        Data(
            """
            Metadata-Version: 2.3
            Name: \(name)
            Version: \(version)

            """.utf8
        )
    }
}

private struct CancellationInjectingDirectoryAccessProvider: DirectoryAccessProvider, Sendable {
    let base: any DirectoryAccessProvider
    let cancellationURL: URL

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let contents = try base.contentsOfDirectory(at: url)
        if url.standardizedFileURL == cancellationURL.standardizedFileURL {
            withUnsafeCurrentTask { task in task?.cancel() }
        }
        return contents
    }

    func data(contentsOf url: URL) throws -> Data {
        try base.data(contentsOf: url)
    }

    func data(
        contentsOf url: URL,
        maximumBytes: Int,
        from origin: BoundedReadOrigin
    ) throws -> Data {
        try base.data(contentsOf: url, maximumBytes: maximumBytes, from: origin)
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func modificationDate(at url: URL) -> Date? {
        base.modificationDate(at: url)
    }

    func metadata(at url: URL) throws -> FileSystemItemMetadata {
        try base.metadata(at: url)
    }

    func resolvingSymlinks(at url: URL) -> URL {
        base.resolvingSymlinks(at: url)
    }
}
