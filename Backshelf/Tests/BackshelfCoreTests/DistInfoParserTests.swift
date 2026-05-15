import Foundation
import Testing
@testable import BackshelfCore

@Suite("DistInfoParser")
struct DistInfoParserTests {
    private static let fixtureDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/python")

    private func buildProvider() throws -> InMemoryDirectoryAccessProvider {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Self.fixtureDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return InMemoryDirectoryAccessProvider.make { builder in
            while let fileURL = enumerator.nextObject() as? URL {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isFile else { continue }

                let relativePath = String(fileURL.path.dropFirst(Self.fixtureDir.path.count))
                let fakeURL = URL(fileURLWithPath: relativePath)
                if let data = try? Data(contentsOf: fileURL) {
                    builder.addFile(at: fakeURL, data: data)
                }
            }
        }
    }

    private func parser() throws -> DistInfoParser {
        DistInfoParser(directoryAccess: try buildProvider())
    }

    @Test("METADATA round-trips multi-field package metadata")
    func metadataRoundTrip() throws {
        let distInfo = try parser().parse(directory: requestsDistInfo)

        #expect(distInfo.name == "requests")
        #expect(distInfo.version == "2.31.0")
        #expect(distInfo.summary == "Synthetic HTTP client package for Backshelf tests")
        #expect(distInfo.homepage == "https://example.invalid/requests")
        #expect(distInfo.author == "Example Maintainers")
        #expect(distInfo.license == "Apache-2.0")
        #expect(distInfo.installer == "pip")
    }

    @Test("METADATA missing optional fields returns nil")
    func missingOptionalFields() throws {
        let distInfo = try parser().parse(directory: urllib3DistInfo)

        #expect(distInfo.name == "urllib3")
        #expect(distInfo.homepage == nil)
        #expect(distInfo.author == nil)
        #expect(distInfo.license == "MIT")
    }

    @Test("METADATA preserves block description after header separator")
    func blockDescription() throws {
        let distInfo = try parser().parse(directory: requestsDistInfo)
        let description = try #require(distInfo.description)

        #expect(description.hasPrefix("Requests fixture package.\n\n"))
        #expect(description.contains("It preserves newlines after the header separator."))
    }

    @Test("RECORD parsing returns expected path list")
    func recordPaths() throws {
        let distInfo = try parser().parse(directory: requestsDistInfo)

        #expect(distInfo.recordPaths == [
            "requests/__init__.py",
            "requests/api.py",
            "requests-2.31.0.dist-info/METADATA",
            "requests-2.31.0.dist-info/RECORD",
        ])
    }

    @Test("empty RECORD returns an empty array")
    func emptyRecord() throws {
        let recordURL = URL(fileURLWithPath: "/empty.dist-info/RECORD")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: recordURL, data: Data())
        }

        let parser = DistInfoParser(directoryAccess: provider)
        #expect(try parser.parseRecord(at: recordURL).isEmpty)
    }

    @Test("missing INSTALLER returns nil")
    func missingInstaller() throws {
        let directory = URL(fileURLWithPath: "/minimal.dist-info")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: directory.appendingPathComponent("METADATA"),
                data: Data("""
                Metadata-Version: 2.1
                Name: minimal
                Version: 1.0.0

                Minimal description.
                """.utf8)
            )
            builder.addFile(
                at: directory.appendingPathComponent("RECORD"),
                data: Data("minimal/__init__.py,,\n".utf8)
            )
        }

        let parser = DistInfoParser(directoryAccess: provider)
        let distInfo = try parser.parse(directory: directory)

        #expect(distInfo.installer == nil)
    }

    @Test("inline Description is used when block description is absent")
    func inlineDescription() throws {
        let directory = URL(fileURLWithPath: "/inline.dist-info")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: directory.appendingPathComponent("METADATA"),
                data: Data("""
                Metadata-Version: 2.1
                Name: inline
                Version: 1.0.0
                Description: Inline package description
                """.utf8)
            )
        }

        let parser = DistInfoParser(directoryAccess: provider)
        let distInfo = try parser.parse(directory: directory)

        #expect(distInfo.description == "Inline package description")
    }

    @Test("malformed METADATA throws a parser error")
    func malformedMetadataThrowsSpecificError() throws {
        let directory = URL(fileURLWithPath: "/broken.dist-info")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: directory.appendingPathComponent("METADATA"),
                data: Data("""
                Metadata-Version: 2.1
                Name broken
                Version: 1.0.0
                """.utf8)
            )
        }
        let parser = DistInfoParser(directoryAccess: provider)

        do {
            _ = try parser.parse(directory: directory)
            Issue.record("Expected malformed metadata to throw")
        } catch let error as DistInfoParser.Error {
            #expect(error == .malformedMetadata(line: "Name broken"))
        } catch {
            Issue.record("Expected DistInfoParser.Error, got \(error)")
        }
    }

    private var requestsDistInfo: URL {
        URL(fileURLWithPath: "/.pyenv/versions/3.11.7/lib/python3.11/site-packages/requests-2.31.0.dist-info")
    }

    private var urllib3DistInfo: URL {
        URL(fileURLWithPath: "/.pyenv/versions/3.11.7/lib/python3.11/site-packages/urllib3-2.2.1.dist-info")
    }
}
