import Testing
import Foundation
@testable import InstalloryCore

@Suite("ShellHistoryCollector")
struct ShellHistoryCollectorTests {
    private let home = URL(fileURLWithPath: "/fake-home")

    private func fixtureData(_ name: String) throws -> Data {
        try FixtureResource.data("shell-history/\(name)")
    }

    /// Builds a provider with any combination of the three fixture history files.
    private func makeProvider(zsh: Bool = true, bash: Bool = true, fish: Bool = true) throws -> InMemoryDirectoryAccessProvider {
        let fishURL = home
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("fish")
            .appendingPathComponent("fish_history")

        let zshData = zsh ? try fixtureData("zsh_history") : nil
        let bashData = bash ? try fixtureData("bash_history") : nil
        let fishData = fish ? try fixtureData("fish_history") : nil

        return InMemoryDirectoryAccessProvider.make { builder in
            if let zshData {
                builder.addFile(at: home.appendingPathComponent(".zsh_history"), data: zshData)
            }
            if let bashData {
                builder.addFile(at: home.appendingPathComponent(".bash_history"), data: bashData)
            }
            if let fishData {
                builder.addFile(at: fishURL, data: fishData)
            }
        }
    }

    // MARK: - Shell coverage

    @Test("reads install commands from all three shells when all files are present")
    func readsAllThreeShells() throws {
        let provider = try makeProvider()
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.contains { $0.shell == .zsh })
        #expect(records.contains { $0.shell == .bash })
        #expect(records.contains { $0.shell == .fish })
    }

    @Test("total install-command count across all three fixture files is 14")
    func totalCount() throws {
        let provider = try makeProvider()
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        // zsh: 6, bash: 4, fish: 4
        #expect(records.count == 14)
    }

    @Test("per-shell counts match fixture contents")
    func perShellCounts() throws {
        let provider = try makeProvider()
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.filter { $0.shell == .zsh }.count == 6)
        #expect(records.filter { $0.shell == .bash }.count == 4)
        #expect(records.filter { $0.shell == .fish }.count == 4)
    }

    // MARK: - Missing files

    @Test("skips silently when zsh history is absent")
    func skipsMissingZsh() throws {
        let provider = try makeProvider(zsh: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(!records.contains { $0.shell == .zsh })
        #expect(records.contains { $0.shell == .bash })
        #expect(records.contains { $0.shell == .fish })
    }

    @Test("skips silently when bash history is absent")
    func skipsMissingBash() throws {
        let provider = try makeProvider(bash: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.contains { $0.shell == .zsh })
        #expect(!records.contains { $0.shell == .bash })
        #expect(records.contains { $0.shell == .fish })
    }

    @Test("skips silently when fish history is absent")
    func skipsMissingFish() throws {
        let provider = try makeProvider(fish: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.contains { $0.shell == .zsh })
        #expect(records.contains { $0.shell == .bash })
        #expect(!records.contains { $0.shell == .fish })
    }

    @Test("empty homeDirectory yields empty result")
    func emptyHomeDirectory() {
        let provider = InMemoryDirectoryAccessProvider.make { _ in }
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        #expect(records.isEmpty)
    }

    // MARK: - Timestamp population: zsh

    @Test("zsh extended-format timestamp is populated correctly")
    func zshExtendedTimestamp() throws {
        let provider = try makeProvider(bash: false, fish: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        let record = records.first { $0.command == "brew install ffmpeg" }
        #expect(record?.timestamp == Date(timeIntervalSince1970: 1_715_000_000))
    }

    @Test("zsh malformed extended-format header produces nil timestamp")
    func zshMalformedHeaderNilTimestamp() throws {
        // `: invalid:0;brew install wget` → command extracted, timestamp nil
        let provider = try makeProvider(bash: false, fish: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        let record = records.first { $0.command == "brew install wget" }
        #expect(record != nil)
        #expect(record?.timestamp == nil)
    }

    @Test("zsh bare-format install line has nil timestamp")
    func zshBareFormatNilTimestamp() throws {
        // `gem install bundler` with no `: ts:elapsed;` prefix
        let provider = try makeProvider(bash: false, fish: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        let record = records.first { $0.command == "gem install bundler" && $0.shell == .zsh }
        #expect(record != nil)
        #expect(record?.timestamp == nil)
    }

    // MARK: - Timestamp population: bash

    @Test("bash HISTTIMEFORMAT prefix populates timestamp correctly")
    func bashTimestamp() throws {
        let provider = try makeProvider(zsh: false, fish: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        let record = records.first { $0.command == "npm install -g prettier" }
        #expect(record?.timestamp == Date(timeIntervalSince1970: 1_715_000_100))
    }

    @Test("bash command without preceding timestamp marker has nil timestamp")
    func bashNoTimestamp() throws {
        // `brew install jq` has no `#<ts>` line before it in the fixture
        let provider = try makeProvider(zsh: false, fish: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        let record = records.first { $0.command == "brew install jq" }
        #expect(record != nil)
        #expect(record?.timestamp == nil)
    }

    @Test("orphaned bash timestamp marker at end-of-file produces no extra record")
    func bashOrphanedTimestamp() throws {
        // The fixture ends with `#1715000102` but no following command.
        let provider = try makeProvider(zsh: false, fish: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        // Bash fixture has exactly 4 install commands; orphan adds no record.
        #expect(records.count == 4)
    }

    // MARK: - Timestamp population: fish

    @Test("fish 'when' field populates timestamp correctly")
    func fishTimestamp() throws {
        let provider = try makeProvider(zsh: false, bash: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        let record = records.first { $0.command == "brew install --cask visual-studio-code" }
        #expect(record?.timestamp == Date(timeIntervalSince1970: 1_715_000_200))
    }

    @Test("fish entry without 'when' field has nil timestamp")
    func fishMissingWhenNilTimestamp() throws {
        // `cargo install bat` has no `when:` line in the fixture
        let provider = try makeProvider(zsh: false, bash: false)
        let records = ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect()
        let record = records.first { $0.command == "cargo install bat" }
        #expect(record != nil)
        #expect(record?.timestamp == nil)
    }

    // MARK: - No-install histories

    @Test("history containing only non-install commands returns empty result")
    func noInstallCommands() {
        let content = "ls -la\ncd ~/projects\nvim ~/.zshrc\ngit status\n"
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".zsh_history"),
                data: Data(content.utf8)
            )
        }
        #expect(ShellHistoryCollector(directoryAccess: provider, homeDirectory: home).collect().isEmpty)
    }

    @Test("CORE25-013: invalid UTF-8 discards only its shell-history line")
    func invalidUTF8DiscardsOnlyCorruptLine() {
        var history = Data("brew install wget\n".utf8)
        history.append(contentsOf: [0xFF, 0x0A])
        history.append(Data("npm install --global prettier\n".utf8))
        let provider = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: home.appendingPathComponent(".zsh_history"),
                data: history
            )
        }

        let records = ShellHistoryCollector(
            directoryAccess: provider,
            homeDirectory: home
        ).collect()

        #expect(records.map(\.command) == [
            "brew install wget", "npm install --global prettier",
        ])
    }

    @Test("PERF25-005: oversized history is rejected before loading its bytes")
    func oversizedHistoryIsNotLoaded() {
        let historyURL = home.appendingPathComponent(".zsh_history")
        let base = InMemoryDirectoryAccessProvider.make { builder in
            builder.addFile(
                at: historyURL,
                data: Data("brew install wget\n".utf8),
                logicalSizeBytes: 100 * 1_024 * 1_024
            )
        }
        let trace = DirectoryAccessTrace()
        let provider = TracingDirectoryAccessProvider(base: base, trace: trace)

        let records = ShellHistoryCollector(
            directoryAccess: provider,
            homeDirectory: home
        ).collect()

        #expect(records.isEmpty)
        #expect(trace.entries.contains { $0.operation == .metadata && $0.url == historyURL })
        #expect(!trace.entries.contains { $0.operation == .data && $0.url == historyURL })
    }

    @Test("PERF25-005: cancellation stops provenance before filesystem reads")
    func cancellationStopsCollection() async throws {
        let provider = try makeProvider()
        let collector = ShellHistoryCollector(
            directoryAccess: provider,
            homeDirectory: home
        )
        let task = Task.detached {
            do { try await Task.sleep(for: .milliseconds(50)) } catch {}
            return collector.collect()
        }

        task.cancel()

        #expect(await task.value.isEmpty)
    }
}

// MARK: - Builder throwing overload

extension InMemoryDirectoryAccessProvider {
    /// Convenience overload that allows the `populate` closure to throw.
    static func make(_ populate: (inout Builder) throws -> Void) throws -> InMemoryDirectoryAccessProvider {
        var builder = Builder()
        try populate(&builder)
        return builder.build()
    }
}
