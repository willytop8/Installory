import Testing
import Foundation
@testable import InstalloryCore

@Suite("PackageDAO")
struct PackageDAOTests {

    // MARK: - Helpers

    private func makeTempDatabase() throws -> (InstalloryCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalloryPackageDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try InstalloryCore.Database(directory: dir)
        return (db, dir)
    }

    private func makePackage(id: String, name: String, manager: PackageManager = .brew) -> Package {
        Package(
            id: id,
            manager: manager,
            qualifier: nil,
            name: name,
            version: "1.0.0",
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date()
        )
    }

    // MARK: - Tests

    @Test("loadAll returns empty list when no packages have been persisted")
    func loadAllEmpty() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageDAO(database: db)
        let loaded = try dao.loadAll()
        #expect(loaded.isEmpty)
    }

    @Test("replaceAll then loadAll round-trips all fields")
    func replaceAllAndLoadAll() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageDAO(database: db)
        let packages = [
            makePackage(id: "brew::git", name: "git", manager: .brew),
            makePackage(id: "npm:/opt/homebrew/lib/node_modules:typescript", name: "typescript", manager: .npm),
        ]

        try dao.replaceAll(with: packages)
        let loaded = try dao.loadAll()

        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.id)) == Set(packages.map(\.id)))
        #expect(Set(loaded.map(\.name)) == ["git", "typescript"])
    }

    @Test("replaceAll clears previously persisted packages before inserting the new set")
    func replaceAllClearsPreviousPackages() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageDAO(database: db)

        let firstSet = [
            makePackage(id: "brew::wget", name: "wget"),
            makePackage(id: "brew::curl", name: "curl"),
        ]
        try dao.replaceAll(with: firstSet)

        let secondSet = [makePackage(id: "brew::ffmpeg", name: "ffmpeg")]
        try dao.replaceAll(with: secondSet)

        let loaded = try dao.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "ffmpeg")
    }

    @Test("replaceAll with empty list leaves the table empty")
    func replaceAllWithEmptyListClearsTable() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = PackageDAO(database: db)
        try dao.replaceAll(with: [makePackage(id: "brew::git", name: "git")])
        try dao.replaceAll(with: [])

        let loaded = try dao.loadAll()
        #expect(loaded.isEmpty)
    }
}

// MARK: - ScanRunDAO tests

@Suite("ScanRunDAO")
struct ScanRunDAOTests {

    private func makeTempDatabase() throws -> (InstalloryCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalloryScanRunDAOTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try InstalloryCore.Database(directory: dir)
        return (db, dir)
    }

    @Test("mostRecentCompletedAt returns nil when no scan runs exist")
    func mostRecentCompletedAtEmpty() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = ScanRunDAO(database: db)
        let date = try dao.mostRecentCompletedAt()
        #expect(date == nil)
    }

    @Test("save then mostRecentCompletedAt returns the saved completion time")
    func saveThenMostRecent() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = ScanRunDAO(database: db)
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        let scanRun = ScanRun(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000 - 5),
            completedAt: completed,
            perManagerResults: [.brew: .succeeded(count: 10, durationMs: 100)]
        )
        try dao.save(scanRun)

        let retrieved = try dao.mostRecentCompletedAt()
        // Allow 1-second tolerance for floating-point timestamp round-trip
        let diff = abs((retrieved?.timeIntervalSince1970 ?? 0) - completed.timeIntervalSince1970)
        #expect(diff < 1.0)
    }

    @Test("mostRecentCompletedAt returns the newest scan run when multiple exist")
    func mostRecentAmongMultiple() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dao = ScanRunDAO(database: db)

        let older = ScanRun(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            completedAt: Date(timeIntervalSince1970: 1_000_010),
            perManagerResults: [:]
        )
        let newer = ScanRun(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 2_000_000),
            completedAt: Date(timeIntervalSince1970: 2_000_015),
            perManagerResults: [:]
        )
        try dao.save(older)
        try dao.save(newer)

        let retrieved = try dao.mostRecentCompletedAt()
        let diff = abs((retrieved?.timeIntervalSince1970 ?? 0) - 2_000_015)
        #expect(diff < 1.0)
    }
}

// MARK: - CORE-02: rescans must not cascade away provenance evidence

@Suite("PackageDAO provenance preservation")
struct PackageDAOProvenanceTests {

    private func makeTempDatabase() throws -> (InstalloryCore.Database, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalloryPackageDAOProvenanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try InstalloryCore.Database(directory: dir), dir)
    }

    private func makePackage(id: String, name: String, version: String = "1.0.0") -> Package {
        Package(
            id: id,
            manager: .brew,
            qualifier: nil,
            name: name,
            version: version,
            installPath: nil,
            installedAt: nil,
            installedAtConfidence: .low,
            sizeBytes: nil,
            isExplicit: true,
            isReadOnly: false,
            dependencies: [],
            lastSeen: Date()
        )
    }

    private func makeEvidence(packageId: String) -> ProvenanceEvidence {
        ProvenanceEvidence(
            packageId: packageId,
            fsInstallTime: Date(timeIntervalSince1970: 1_723_000_000),
            fsInstallTimeSource: "INSTALL_RECEIPT.json",
            installCommand: nil,
            claudeCodeContext: nil,
            nearbyProjects: [],
            coInstalledWithin1h: [],
            overallConfidence: .low,
            collectedAt: Date(timeIntervalSince1970: 1_723_100_000)
        )
    }

    @Test("CORE-02: replaceAll preserves provenance evidence for an unchanged package")
    func replaceAllPreservesEvidenceForUnchangedPackage() async throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let packages = PackageDAO(database: db)
        let provenance = ProvenanceDAO(database: db)

        let ffmpeg = makePackage(id: "brew::ffmpeg", name: "ffmpeg")
        try packages.replaceAll(with: [ffmpeg])
        try await provenance.upsert(makeEvidence(packageId: ffmpeg.id))

        try packages.replaceAll(with: [ffmpeg])

        let survived = try await provenance.fetch(packageId: ffmpeg.id)
        #expect(survived != nil)
    }

    @Test("CORE-02: replaceAll preserves evidence when the package version changes")
    func replaceAllPreservesEvidenceAcrossVersionBump() async throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let packages = PackageDAO(database: db)
        let provenance = ProvenanceDAO(database: db)

        try packages.replaceAll(with: [makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "6.0")])
        try await provenance.upsert(makeEvidence(packageId: "brew::ffmpeg"))

        try packages.replaceAll(with: [makePackage(id: "brew::ffmpeg", name: "ffmpeg", version: "7.1")])

        let survived = try await provenance.fetch(packageId: "brew::ffmpeg")
        #expect(survived != nil)
        #expect(try packages.loadAll().first?.version == "7.1")
    }

    @Test("CORE-02: replaceAll cascades evidence away only for packages that vanished")
    func replaceAllDropsEvidenceForRemovedPackageOnly() async throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let packages = PackageDAO(database: db)
        let provenance = ProvenanceDAO(database: db)

        let kept = makePackage(id: "brew::ffmpeg", name: "ffmpeg")
        let removed = makePackage(id: "brew::wget", name: "wget")
        try packages.replaceAll(with: [kept, removed])
        try await provenance.upsert(makeEvidence(packageId: kept.id))
        try await provenance.upsert(makeEvidence(packageId: removed.id))

        try packages.replaceAll(with: [kept])

        let keptEvidence = try await provenance.fetch(packageId: kept.id)
        let removedEvidence = try await provenance.fetch(packageId: removed.id)
        #expect(keptEvidence != nil)
        #expect(removedEvidence == nil)
        #expect(try packages.loadAll().map(\.id) == ["brew::ffmpeg"])
    }

    @Test("CORE-02: replaceAll upserts rather than duplicating on repeated calls")
    func replaceAllIsIdempotent() throws {
        let (db, dir) = try makeTempDatabase()
        defer { try? FileManager.default.removeItem(at: dir) }
        let packages = PackageDAO(database: db)

        let ffmpeg = makePackage(id: "brew::ffmpeg", name: "ffmpeg")
        try packages.replaceAll(with: [ffmpeg])
        try packages.replaceAll(with: [ffmpeg])
        try packages.replaceAll(with: [ffmpeg])

        #expect(try packages.loadAll().count == 1)
    }
}
