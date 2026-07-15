import Foundation
import InstalloryCore

/// Small injectable boundary around sensitive provenance persistence.
///
/// Keeping these operations behind sendable closures lets app-logic tests prove
/// failure behavior without corrupting a real database, while production still
/// delegates to the GRDB-backed actor in InstalloryCore.
struct ProvenancePersistenceClient: Sendable {
    let fetchAll: @Sendable () async throws -> [ProvenanceEvidence]
    let upsertAll: @Sendable ([ProvenanceEvidence]) async throws -> Void
    let deleteAll: @Sendable () async throws -> Void

    init(
        fetchAll: @escaping @Sendable () async throws -> [ProvenanceEvidence],
        upsertAll: @escaping @Sendable ([ProvenanceEvidence]) async throws -> Void,
        deleteAll: @escaping @Sendable () async throws -> Void
    ) {
        self.fetchAll = fetchAll
        self.upsertAll = upsertAll
        self.deleteAll = deleteAll
    }

    init(dao: ProvenanceDAO) {
        self.init(
            fetchAll: { try await dao.fetchAll() },
            upsertAll: { try await dao.upsertAll($0) },
            deleteAll: { try await dao.deleteAll() }
        )
    }
}
