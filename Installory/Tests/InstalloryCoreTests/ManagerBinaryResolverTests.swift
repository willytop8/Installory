import Testing
import Foundation
@testable import InstalloryCore

@Suite("ManagerBinaryResolver")
struct ManagerBinaryResolverTests {

    // MARK: - npm

    @Test("npm resolves the client colocated with an nvm node_modules root")
    func npmResolvesNvmPrefix() {
        let npm = ManagerBinaryResolver.npm(
            forQualifier: "/Users/w/.nvm/versions/node/v20.11.0/lib/node_modules"
        )
        #expect(npm == "/Users/w/.nvm/versions/node/v20.11.0/bin/npm")
    }

    @Test("npm resolves the client colocated with a Volta node_modules root")
    func npmResolvesVoltaPrefix() {
        let npm = ManagerBinaryResolver.npm(
            forQualifier: "/Users/w/.volta/tools/image/node/21.6.2/lib/node_modules"
        )
        #expect(npm == "/Users/w/.volta/tools/image/node/21.6.2/bin/npm")
    }

    @Test("npm resolves the client colocated with a Homebrew node_modules root")
    func npmResolvesHomebrewPrefix() {
        #expect(ManagerBinaryResolver.npm(forQualifier: "/opt/homebrew/lib/node_modules")
            == "/opt/homebrew/bin/npm")
    }

    @Test("npm falls back to the ambient client when there is no qualifier")
    func npmAmbientWithoutQualifier() {
        #expect(ManagerBinaryResolver.npm(forQualifier: nil) == "npm")
        #expect(ManagerBinaryResolver.npm(forQualifier: "") == "npm")
    }

    @Test("npm falls back to the ambient client for an unrecognised qualifier shape")
    func npmAmbientForUnknownShape() {
        #expect(ManagerBinaryResolver.npm(forQualifier: "/somewhere/odd") == "npm")
        #expect(ManagerBinaryResolver.npm(forQualifier: "/lib/node_modules") == "npm")
    }

    // MARK: - gem

    @Test("gem resolves the client colocated with an rbenv specifications dir")
    func gemResolvesRbenvPrefix() {
        let gem = ManagerBinaryResolver.gem(
            forQualifier: "/Users/w/.rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/specifications"
        )
        #expect(gem.binary == "/Users/w/.rbenv/versions/3.2.2/bin/gem")
        #expect(gem.installDir == nil)
    }

    @Test("gem resolves the client colocated with a Homebrew specifications dir")
    func gemResolvesHomebrewPrefix() {
        let gem = ManagerBinaryResolver.gem(forQualifier: "/opt/homebrew/lib/ruby/gems/3.3.0/specifications")
        #expect(gem.binary == "/opt/homebrew/bin/gem")
        #expect(gem.installDir == nil)
    }

    @Test("gem handles a specifications dir directly under gems")
    func gemResolvesPrefixWithoutApiVersionDir() {
        let gem = ManagerBinaryResolver.gem(forQualifier: "/usr/local/lib/ruby/gems/specifications")
        #expect(gem.binary == "/usr/local/bin/gem")
        #expect(gem.installDir == nil)
    }

    @Test("gem scopes with --install-dir when no colocated client exists (system Ruby)")
    func gemScopesSystemRubyByInstallDir() {
        let gem = ManagerBinaryResolver.gem(forQualifier: "/Library/Ruby/Gems/2.6.0/specifications")
        #expect(gem.binary == "gem")
        #expect(gem.installDir == "/Library/Ruby/Gems/2.6.0")
    }

    @Test("gem scopes with --install-dir for a user GEM_HOME")
    func gemScopesUserGemHomeByInstallDir() {
        let gem = ManagerBinaryResolver.gem(forQualifier: "/Users/w/.gem/ruby/3.2.0/specifications")
        #expect(gem.binary == "gem")
        #expect(gem.installDir == "/Users/w/.gem/ruby/3.2.0")
    }

    @Test("gem falls back to the ambient client when there is no qualifier")
    func gemAmbientWithoutQualifier() {
        #expect(ManagerBinaryResolver.gem(forQualifier: nil) == .ambient)
        #expect(ManagerBinaryResolver.gem(forQualifier: "") == .ambient)
    }

    @Test("gem falls back to the ambient client for an unrecognised qualifier shape")
    func gemAmbientForUnknownShape() {
        #expect(ManagerBinaryResolver.gem(forQualifier: "/somewhere/odd") == .ambient)
    }

    // MARK: - Distinctness

    @Test("CORE-03: two Node installs of the same package resolve to different clients")
    func npmDistinctPerNodeInstall() {
        let a = ManagerBinaryResolver.npm(forQualifier: "/Users/w/.nvm/versions/node/v18.19.1/lib/node_modules")
        let b = ManagerBinaryResolver.npm(forQualifier: "/Users/w/.nvm/versions/node/v20.11.0/lib/node_modules")
        #expect(a != b)
    }

    @Test("CORE-03: two Ruby installs of the same gem resolve to different clients")
    func gemDistinctPerRubyInstall() {
        let a = ManagerBinaryResolver.gem(forQualifier: "/Users/w/.rbenv/versions/3.1.4/lib/ruby/gems/3.1.0/specifications")
        let b = ManagerBinaryResolver.gem(forQualifier: "/Users/w/.rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/specifications")
        #expect(a != b)
    }
}
