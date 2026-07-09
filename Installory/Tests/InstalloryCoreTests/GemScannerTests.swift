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

    // MARK: - CORE-04: platform gems

    /// Builds a scanner over a single gemspec (plus its unpacked gem directory)
    /// under an rbenv Ruby, and returns the one package it finds.
    private func scanSingleGem(
        gemspecFilename: String,
        gemDirName: String? = nil
    ) async throws -> Package {
        let specs = home.appendingPathComponent(".rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/specifications")
        let gems = specs.deletingLastPathComponent().appendingPathComponent("gems")
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: specs.appendingPathComponent(gemspecFilename),
                data: Data("Gem::Specification.new\n".utf8)
            )
            if let gemDirName {
                builder.addFile(
                    at: gems.appendingPathComponent(gemDirName).appendingPathComponent("README.md"),
                    data: Data()
                )
            }
        }
        let packages = try await GemScanner(directoryAccess: provider, homeDirectory: home).scan()
        return try #require(packages.first)
    }

    @Test("CORE-04: a platform gem's version excludes the platform suffix")
    func platformGemVersionExcludesPlatform() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "nokogiri-1.15.4-arm64-darwin.gemspec")
        #expect(gem.name == "nokogiri")
        #expect(gem.version == "1.15.4")
    }

    @Test("CORE-04: a platform gem's installPath keeps the platform-suffixed directory")
    func platformGemInstallPathKeepsPlatformSuffix() async throws {
        let gem = try await scanSingleGem(
            gemspecFilename: "nokogiri-1.15.4-arm64-darwin.gemspec",
            gemDirName: "nokogiri-1.15.4-arm64-darwin"
        )
        #expect(gem.installPath?.lastPathComponent == "nokogiri-1.15.4-arm64-darwin")
    }

    @Test("CORE-04: an x86_64 platform gem parses correctly")
    func x86PlatformGemParses() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "nokogiri-1.15.4-x86_64-linux.gemspec")
        #expect(gem.name == "nokogiri")
        #expect(gem.version == "1.15.4")
    }

    @Test("CORE-04: a java platform gem parses correctly")
    func javaPlatformGemParses() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "psych-5.1.2-java.gemspec")
        #expect(gem.name == "psych")
        #expect(gem.version == "5.1.2")
    }

    @Test("CORE-04: a hyphenated name with a platform suffix parses correctly")
    func hyphenatedNameWithPlatformParses() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "libv8-node-18.16.0.0-arm64-darwin.gemspec")
        #expect(gem.name == "libv8-node")
        #expect(gem.version == "18.16.0.0")
    }

    @Test("CORE-04: a trailing numeric platform component is not mistaken for the version")
    func trailingNumericPlatformComponentIsNotTheVersion() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "mygem-1.0.0-x86-mswin32-60.gemspec")
        #expect(gem.name == "mygem")
        #expect(gem.version == "1.0.0")
    }

    @Test("CORE-04: a prerelease version survives intact")
    func prereleaseVersionSurvives() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "rails-7.1.0.beta1.gemspec")
        #expect(gem.name == "rails")
        #expect(gem.version == "7.1.0.beta1")
    }

    @Test("CORE-04: a numeric-led name segment is not mistaken for the version")
    func numericLedNameSegmentIsNotTheVersion() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "ruby-2captcha-1.2.0.gemspec")
        #expect(gem.name == "ruby-2captcha")
        #expect(gem.version == "1.2.0")
    }

    @Test("CORE-04: a plain gem still parses with no platform suffix")
    func plainGemStillParses() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "bundler-2.5.7.gemspec")
        #expect(gem.name == "bundler")
        #expect(gem.version == "2.5.7")
    }

    @Test("CORE-04: a platform gem yields a runnable reinstall command")
    func platformGemProducesRunnableReinstallCommand() async throws {
        let gem = try await scanSingleGem(gemspecFilename: "nokogiri-1.15.4-arm64-darwin.gemspec")
        let missing = MissingPackage(
            manager: .gem,
            package: SnapshotPackage(
                name: gem.name, version: gem.version, qualifier: gem.qualifier, isExplicit: true
            )
        )
        let script = ReinstallScriptGenerator().generate(missing: [missing]).scriptText

        #expect(script.contains("gem install nokogiri -v 1.15.4"))
        #expect(!script.contains("1.15.4-arm64-darwin"))
    }
}

