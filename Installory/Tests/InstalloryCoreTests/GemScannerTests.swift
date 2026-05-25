import Foundation
import Testing
@testable import InstalloryCore

@Suite("GemScanner")
struct GemScannerTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("reads Ruby gemspec filenames and dependencies")
    func readsGemspecs() async throws {
        let specs = home.appendingPathComponent(".rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/specifications")
        let gems = specs.deletingLastPathComponent().appendingPathComponent("gems")
        let gemspec = specs.appendingPathComponent("rubocop-ast-1.31.1.gemspec")
        let gemDir = gems.appendingPathComponent("rubocop-ast-1.31.1")
        let installedAt = Date(timeIntervalSince1970: 1_716_000_000)
        let text = """
            Gem::Specification.new do |s|
              s.name = "rubocop-ast"
              s.version = "1.31.1"
              s.add_runtime_dependency "parser", ">= 3.3.0.4"
            end
            """

        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: gemspec, data: Data(text.utf8), modificationDate: installedAt)
            builder.addFile(at: gemDir.appendingPathComponent("README.md"), data: Data())
        }

        let packages = try await GemScanner(directoryAccess: provider, homeDirectory: home).scan()

        #expect(packages.count == 1)
        let gem = try #require(packages.first)
        #expect(gem.id == "gem:\(specs.path):rubocop-ast")
        #expect(gem.manager == .gem)
        #expect(gem.qualifier == specs.path)
        #expect(gem.name == "rubocop-ast")
        #expect(gem.version == "1.31.1")
        #expect(gem.installPath == gemDir)
        #expect(gem.installedAt == installedAt)
        #expect(gem.installedAtConfidence == .low)
        #expect(gem.dependencies == ["parser"])
        #expect(gem.isReadOnly == false)
    }

    @Test("system Ruby gems are read-only")
    func systemRubyGemsAreReadOnly() async throws {
        let specs = URL(fileURLWithPath: "/Library/Ruby/Gems/2.6.0/specifications")
        let gemspec = specs.appendingPathComponent("json-2.6.3.gemspec")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(at: gemspec, data: Data("Gem::Specification.new\n".utf8))
        }

        let packages = try await GemScanner(directoryAccess: provider, homeDirectory: home).scan()

        let json = try #require(packages.first)
        #expect(json.name == "json")
        #expect(json.version == "2.6.3")
        #expect(json.isReadOnly == true)
    }

    @Test("availability follows readable specification directories")
    func availabilityFollowsSpecificationDirectories() async throws {
        let missing = InMemoryDirectoryAccessProvider.make { _ in }
        #expect(await GemScanner(directoryAccess: missing, homeDirectory: home).isAvailable() == false)

        let present = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".gem/ruby/3.3.0/specifications/bundler-2.5.7.gemspec"),
                data: Data()
            )
        }
        #expect(await GemScanner(directoryAccess: present, homeDirectory: home).isAvailable() == true)
    }
}
