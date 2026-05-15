import Testing
import Foundation
@testable import CruftCore

// MARK: - PackageManager

@Suite("PackageManager")
struct PackageManagerTests {
    @Test("All cases encode to distinct raw values")
    func rawValues() {
        let raws = PackageManager.allCases.map(\.rawValue)
        #expect(Set(raws).count == PackageManager.allCases.count)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for manager in PackageManager.allCases {
            let data = try JSONEncoder().encode(manager)
            let decoded = try JSONDecoder().decode(PackageManager.self, from: data)
            #expect(decoded == manager)
        }
    }
}

// MARK: - Confidence

@Suite("Confidence")
struct ConfidenceTests {
    @Test("Ordering: unknown < low < medium < high")
    func ordering() {
        #expect(Confidence.unknown < .low)
        #expect(Confidence.low < .medium)
        #expect(Confidence.medium < .high)
        #expect(!(Confidence.high < .medium))
        #expect(Confidence.unknown < .high)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for level in [Confidence.unknown, .low, .medium, .high] {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(Confidence.self, from: data)
            #expect(decoded == level)
        }
    }
}

// MARK: - Package

@Suite("Package")
struct PackageTests {
    private func makeBrewPackage() -> Package {
        Package(
            id: "brew::ffmpeg",
            manager: .brew,
            qualifier: nil,
            name: "ffmpeg",
            version: "6.1.1",
            installPath: URL(fileURLWithPath: "/opt/homebrew/Cellar/ffmpeg/6.1.1"),
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            installedAtConfidence: .high,
            sizeBytes: 123_456_789,
            isExplicit: true,
            isReadOnly: false,
            dependencies: ["x264", "x265", "libvpx"],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    private func makePipPackage() -> Package {
        Package(
            id: "pip:/Users/x/.pyenv/versions/3.11.7/bin/python:requests",
            manager: .pip,
            qualifier: "/Users/x/.pyenv/versions/3.11.7/bin/python",
            name: "requests",
            version: "2.31.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .unknown,
            sizeBytes: nil,
            isExplicit: false,
            isReadOnly: false,
            dependencies: ["certifi", "charset-normalizer", "idna", "urllib3"],
            lastSeen: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    @Test("brew id format: brew::<name>")
    func brewIdFormat() {
        let pkg = makeBrewPackage()
        #expect(pkg.id == "brew::ffmpeg")
    }

    @Test("pip id format includes interpreter path")
    func pipIdFormat() {
        let pkg = makePipPackage()
        #expect(pkg.id.hasPrefix("pip:"))
        #expect(pkg.id.hasSuffix(":requests"))
        #expect(pkg.id.contains("/python:"))
    }

    @Test("brewCask id format: brewCask::<name>")
    func brewCaskIdFormat() {
        let pkg = Package(
            id: "brewCask::visual-studio-code",
            manager: .brewCask,
            qualifier: nil,
            name: "visual-studio-code",
            version: "1.87.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .unknown,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date()
        )
        #expect(pkg.id == "brewCask::visual-studio-code")
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = makeBrewPackage()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Package.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable round-trip with nil optionals")
    func codableRoundTripNilFields() throws {
        let original = makePipPackage()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Package.self, from: data)
        #expect(decoded == original)
        #expect(decoded.installPath == nil)
        #expect(decoded.installedAt == nil)
        #expect(decoded.sizeBytes == nil)
    }

    @Test("Hashable: equal packages have equal hashes")
    func hashable() {
        let a = makeBrewPackage()
        let b = makeBrewPackage()
        var set = Set<Package>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }
}

// MARK: - ProvenanceEvidence

@Suite("ProvenanceEvidence")
struct ProvenanceEvidenceTests {
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return enc
    }()
    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return dec
    }()

    private func makeEvidence() -> ProvenanceEvidence {
        ProvenanceEvidence(
            packageId: "brew::ffmpeg",
            fsInstallTime: Date(timeIntervalSince1970: 1_700_000_000),
            fsInstallTimeSource: "INSTALL_RECEIPT.json",
            installCommand: ProvenanceEvidence.InstallCommandRecord(
                timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                command: "brew install ffmpeg",
                shell: .zsh,
                cwd: "/Users/x/projects/video-tool"
            ),
            claudeCodeContext: ProvenanceEvidence.ClaudeCodeContext(
                sessionId: "abc123",
                projectPath: "/Users/x/projects/video-tool",
                sessionSummary: "Building a video processing script",
                firstUserMessage: "I need to convert videos",
                bashInvocation: "brew install ffmpeg",
                timestamp: Date(timeIntervalSince1970: 1_700_000_050)
            ),
            nearbyProjects: [
                ProvenanceEvidence.NearbyProject(
                    path: "/Users/x/projects/video-tool",
                    modifiedFileCount: 5,
                    gitCommitsThatDay: 2
                )
            ],
            coInstalledWithin1h: ["brew::x264", "brew::x265"],
            overallConfidence: .high,
            collectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    @Test("Codable round-trip with all fields populated")
    func codableRoundTrip() throws {
        let original = makeEvidence()
        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(ProvenanceEvidence.self, from: data)
        #expect(decoded.packageId == original.packageId)
        #expect(decoded.overallConfidence == original.overallConfidence)
        #expect(decoded.installCommand?.command == original.installCommand?.command)
        #expect(decoded.installCommand?.shell == original.installCommand?.shell)
        #expect(decoded.claudeCodeContext?.sessionId == original.claudeCodeContext?.sessionId)
        #expect(decoded.coInstalledWithin1h == original.coInstalledWithin1h)
    }

    @Test("Codable round-trip with nil optional signals")
    func codableRoundTripNilSignals() throws {
        let sparse = ProvenanceEvidence(
            packageId: "cargo::ripgrep",
            fsInstallTime: nil,
            fsInstallTimeSource: nil,
            installCommand: nil,
            claudeCodeContext: nil,
            nearbyProjects: [],
            coInstalledWithin1h: [],
            overallConfidence: .unknown,
            collectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let data = try Self.encoder.encode(sparse)
        let decoded = try Self.decoder.decode(ProvenanceEvidence.self, from: data)
        #expect(decoded.installCommand == nil)
        #expect(decoded.claudeCodeContext == nil)
        #expect(decoded.nearbyProjects.isEmpty)
    }

    @Test("Shell enum encodes to lowercase string")
    func shellEncoding() throws {
        let enc = try JSONEncoder().encode(ProvenanceEvidence.Shell.zsh)
        let str = String(data: enc, encoding: .utf8)
        #expect(str == "\"zsh\"")
    }
}

// MARK: - Description

@Suite("Description")
struct DescriptionTests {
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = Description(
            manager: .brew,
            name: "ffmpeg",
            text: "A complete solution to record, convert and stream audio and video."
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Description.self, from: data)
        #expect(decoded.manager == original.manager)
        #expect(decoded.name == original.name)
        #expect(decoded.text == original.text)
    }
}

// MARK: - Snapshot

@Suite("Snapshot")
struct SnapshotTests {
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return enc
    }()
    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return dec
    }()

    private func makeSnapshot() -> Snapshot {
        Snapshot(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            reason: .manual,
            note: "Before cleaning up",
            payload: SnapshotPayload(managers: [
                .brew: [
                    SnapshotPackage(name: "ffmpeg", version: "6.1.1", qualifier: nil, isExplicit: true),
                    SnapshotPackage(name: "openssl@3", version: "3.2.1", qualifier: nil, isExplicit: false),
                ],
                .pip: [
                    SnapshotPackage(
                        name: "requests",
                        version: "2.31.0",
                        qualifier: "/Users/x/.pyenv/versions/3.11.7/bin/python",
                        isExplicit: true
                    ),
                ],
            ])
        )
    }

    @Test("Codable round-trip preserves all managers and packages")
    func codableRoundTrip() throws {
        let original = makeSnapshot()
        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(Snapshot.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.reason == original.reason)
        #expect(decoded.note == original.note)
        #expect(decoded.payload.managers[.brew]?.count == 2)
        #expect(decoded.payload.managers[.pip]?.count == 1)
        #expect(decoded.payload.managers[.pip]?.first?.qualifier != nil)
    }

    @Test("SnapshotPayload JSON uses string keys (not array-of-pairs)")
    func payloadUsesStringKeys() throws {
        let payload = SnapshotPayload(managers: [
            .brew: [SnapshotPackage(name: "git", version: "2.44.0", qualifier: nil, isExplicit: true)],
            .npm: [SnapshotPackage(name: "typescript", version: "5.4.3", qualifier: nil, isExplicit: true)],
        ])
        let data = try JSONEncoder().encode(payload)
        // The JSON must be an object with string keys, not an array.
        let raw = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(raw as? [String: Any], "SnapshotPayload must encode as a JSON object with string keys")
        #expect(dict.keys.contains("brew"))
        #expect(dict.keys.contains("npm"))
    }

    @Test("SnapshotReason Codable round-trip")
    func reasonRoundTrip() throws {
        for reason in [SnapshotReason.manual, .preUninstall, .autoFirstScan] {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(SnapshotReason.self, from: data)
            #expect(decoded == reason)
        }
    }
}

// MARK: - ScanRun + ScannerStatus

@Suite("ScanRun")
struct ScanRunTests {
    @Test("ScannerStatus encodes with explicit type field")
    func statusTypeField() throws {
        let cases: [ScannerStatus] = [
            .succeeded(count: 42, durationMs: 150),
            .failed(reason: "disk error", durationMs: 500),
            .timedOut(durationMs: 5000),
            .skipped(reason: "not installed"),
        ]
        for status in cases {
            let data = try JSONEncoder().encode(status)
            let raw = try JSONSerialization.jsonObject(with: data)
            let obj = try #require(raw as? [String: Any])
            #expect(obj["type"] is String, "ScannerStatus JSON must have a 'type' string key")
        }
    }

    @Test("ScannerStatus Codable round-trip — all cases")
    func statusRoundTrip() throws {
        let cases: [ScannerStatus] = [
            .succeeded(count: 247, durationMs: 1234),
            .failed(reason: "permission denied", durationMs: 99),
            .timedOut(durationMs: 15000),
            .skipped(reason: "sandboxed: mas not supported"),
        ]
        for original in cases {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ScannerStatus.self, from: data)
            #expect(decoded == original)
        }
    }

    @Test("ScanRun Codable round-trip")
    func scanRunRoundTrip() throws {
        let original = ScanRun(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            completedAt: Date(timeIntervalSince1970: 1_710_000_012),
            perManagerResults: [
                .brew: .succeeded(count: 247, durationMs: 1200),
                .pip: .succeeded(count: 89, durationMs: 800),
                .mas: .skipped(reason: "sandboxed: mas not supported"),
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScanRun.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.perManagerResults[.brew] == original.perManagerResults[.brew])
        #expect(decoded.perManagerResults[.mas] == original.perManagerResults[.mas])
    }

    @Test("ScanRun Codable round-trip with nil completedAt")
    func scanRunNilCompletedAt() throws {
        let original = ScanRun(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_710_000_000),
            completedAt: nil,
            perManagerResults: [:]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScanRun.self, from: data)
        #expect(decoded.completedAt == nil)
    }
}
