import Foundation
import Testing
@testable import InstalloryCore

@Suite("Scanner cancellation")
struct ScannerCancellationTests {
    @Test("CORE-07: every scanner availability check rejects an already-cancelled task")
    func availabilityChecksRejectCancellation() async {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".cargo/.crates2.json"),
                data: Data(#"{"installs":{}}"#.utf8)
            )
            builder.addFile(
                at: home.appendingPathComponent(
                    ".gem/ruby/3.3.0/specifications/rake-13.2.1.gemspec"
                ),
                data: Data()
            )
            builder.addFile(
                at: applications.appendingPathComponent(
                    "Example.app/Contents/_MASReceipt/receipt"
                ),
                data: Data()
            )
            builder.addFile(
                at: URL(
                    fileURLWithPath: "/opt/homebrew/lib/node_modules/tool/package.json"
                ),
                data: Data(#"{"name":"tool","version":"1.0.0"}"#.utf8)
            )
            builder.addFile(
                at: home.appendingPathComponent(
                    ".pyenv/versions/3.12.4/bin/python"
                ),
                data: Data()
            )
            builder.addFile(
                at: home.appendingPathComponent(
                    ".local/share/pipx/venvs/ruff/pipx_metadata.json"
                ),
                data: Data(#"{"main_package":{"package":"ruff","package_version":"0.5.0"}}"#.utf8)
            )
        }
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: home,
            environment: .empty
        )
        let scanners: [any PackageScanner] = [
            BrewScanner(
                pathDiscovery: PathDiscovery(checkExists: { $0 == "/opt/homebrew" }),
                directoryAccess: provider
            ),
            CargoScanner(
                directoryAccess: provider,
                homeDirectory: home,
                environment: .empty
            ),
            GemScanner(
                directoryAccess: provider,
                homeDirectory: home,
                environment: .empty
            ),
            MasScanner(
                directoryAccess: provider,
                homeDirectory: home,
                applicationDirectories: [applications]
            ),
            NpmScanner(
                directoryAccess: provider,
                homeDirectory: home,
                environment: .empty
            ),
            PipScanner(
                discovery: discovery,
                parser: DistInfoParser(directoryAccess: provider),
                directoryAccess: provider
            ),
            PipxScanner(
                directoryAccess: provider,
                homeDirectory: home,
                environment: .empty
            ),
        ]

        for scanner in scanners {
            #expect(await scanner.isAvailable(), "\(scanner.manager) fixture must be available")
            let availableAfterCancellation = await Task {
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
                return await scanner.isAvailable()
            }.value
            #expect(
                !availableAfterCancellation,
                "\(scanner.manager) must not report available after cancellation"
            )
        }
    }

    @Test("CORE-07: npm availability stops when cancellation arrives during nvm enumeration")
    func npmAvailabilityStopsDuringEnumeration() async {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let nvmRoot = home.appendingPathComponent(".nvm/versions/node")
        let base = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: URL(
                    fileURLWithPath: "/opt/homebrew/lib/node_modules/tool/package.json"
                ),
                data: Data(#"{"name":"tool","version":"1.0.0"}"#.utf8)
            )
            builder.addDirectory(
                at: nvmRoot.appendingPathComponent("v22.0.0/lib/node_modules")
            )
        }
        let probe = DirectoryEnumerationProbe()
        let provider = CancellationInstrumentedDirectoryAccessProvider(
            base: base,
            probe: probe,
            cancellationEnumeration: 1
        )
        let scanner = NpmScanner(
            directoryAccess: provider,
            homeDirectory: home,
            environment: .empty
        )
        let availability = Task {
            await scanner.isAvailable()
        }

        #expect(await availability.value == false)
        #expect(probe.paths == [nvmRoot])
    }

    @Test("PERF25-001/TEST25-005: large synchronous discovery stops promptly after cancellation")
    func largeDiscoveryStopsAtCancellationCheckpoint() async {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let uvRoot = home.appendingPathComponent(".local/share/uv/python")
        let base = InMemoryDirectoryAccessProvider.make { builder in
            for index in 0..<500 {
                builder.addFile(
                    at: uvRoot.appendingPathComponent(
                        "cpython-3.12.\(index)-macos/bin/python3.12"
                    ),
                    data: Data()
                )
            }
        }
        let cancellationEnumeration = 25
        let probe = DirectoryEnumerationProbe()
        let provider = CancellationInstrumentedDirectoryAccessProvider(
            base: base,
            probe: probe,
            cancellationEnumeration: cancellationEnumeration
        )
        let discovery = PythonInterpreterDiscovery(
            directoryAccess: provider,
            homeDirectory: home,
            environment: .empty
        )
        let scanner = PipScanner(
            discovery: discovery,
            parser: DistInfoParser(directoryAccess: provider),
            directoryAccess: provider
        )
        let scan = Task {
            try await scanner.scan()
        }

        await #expect(throws: CancellationError.self) {
            try await scan.value
        }

        #expect(probe.paths.count == cancellationEnumeration)
        #expect(probe.paths.last?.lastPathComponent == "bin")
        #expect(probe.paths.count < 500, "the remaining large discovery walk must be skipped")
    }
}
