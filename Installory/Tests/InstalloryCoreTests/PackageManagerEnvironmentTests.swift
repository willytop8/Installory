import Foundation
import Testing
@testable import InstalloryCore

@Suite("PackageManagerEnvironment")
struct PackageManagerEnvironmentTests {
    private let fallback = URL(fileURLWithPath: "/Users/tester/default")

    @Test("CORE-08: valid absolute overrides take precedence and are standardized")
    func validAbsoluteOverridesTakePrecedence() {
        let environment = PackageManagerEnvironment(values: [
            "CARGO_HOME": "/Volumes/Dev/roots/../cargo",
            "GEM_HOME": "/Volumes/Dev/gems",
            "PYENV_ROOT": "/Volumes/Dev/pyenv",
            "NVM_DIR": "/Volumes/Dev/nvm",
            "PIPX_HOME": "/Volumes/Dev/pipx",
        ])

        #expect(environment.cargoHome(fallback: fallback).path == "/Volumes/Dev/cargo")
        #expect(environment.gemHome(fallback: fallback).path == "/Volumes/Dev/gems")
        #expect(environment.pyenvRoot(fallback: fallback).path == "/Volumes/Dev/pyenv")
        #expect(environment.nvmDirectory(fallback: fallback).path == "/Volumes/Dev/nvm")
        #expect(environment.pipxHome(fallback: fallback).path == "/Volumes/Dev/pipx")
    }

    @Test("CORE-08: absent and invalid overrides preserve default roots")
    func invalidOverridesPreserveDefaults() {
        let environment = PackageManagerEnvironment(values: [
            "CARGO_HOME": "relative/cargo",
            "GEM_HOME": "",
            "PYENV_ROOT": " /Volumes/Dev/pyenv",
            "NVM_DIR": "/Volumes/Dev/nvm\n",
            "PIPX_HOME": "relative/pipx",
        ])

        #expect(environment.cargoHome(fallback: fallback) == fallback)
        #expect(environment.gemHome(fallback: fallback) == fallback)
        #expect(environment.pyenvRoot(fallback: fallback) == fallback)
        #expect(environment.nvmDirectory(fallback: fallback) == fallback)
        #expect(environment.pipxHome(fallback: fallback) == fallback)
        #expect(PackageManagerEnvironment.empty.cargoHome(fallback: fallback) == fallback)
    }
}
