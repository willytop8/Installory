import Foundation

/// Aggregates the three provenance signals — filesystem timestamps, shell history,
/// and Claude Code session logs — into one ``ProvenanceEvidence`` per package.
///
/// **Matching algorithm (O(n) per package):**
/// Both collectors' records are bucketed by manager and normalized package name
/// before any per-package work begins. When an install command identifies a Python
/// interpreter, that scope must match the package qualifier. Unqualified commands
/// remain conservative fallback evidence for any same-manager, same-name scope.
///
/// Records with `nil` timestamps in either collector are excluded from time-proximity
/// matching and never contribute to `installCommand` or `claudeCodeContext`.
///
/// **nearbyProjects** is always `[]` in v0. Filesystem walking for nearby git repos
/// is deferred — see HANDOFF.md.
public struct ProvenanceCollector: Sendable {
    private let shellCollector: ShellHistoryCollector
    private let claudeCodeCollector: ClaudeCodeLogCollector
    private let detector: InstallCommandDetector
    private let redactor: ProvenanceRedactor

    public init(
        shellCollector: ShellHistoryCollector = ShellHistoryCollector(),
        claudeCodeCollector: ClaudeCodeLogCollector = ClaudeCodeLogCollector()
    ) {
        self.shellCollector = shellCollector
        self.claudeCodeCollector = claudeCodeCollector
        self.detector = InstallCommandDetector()
        self.redactor = ProvenanceRedactor()
    }

    /// Builds ``ProvenanceEvidence`` for every package by combining filesystem
    /// timestamps, shell-history install commands, and Claude Code Bash invocations.
    ///
    /// This method is synchronous; file I/O occurs inside both sub-collectors.
    /// Dispatch to a background thread when calling from an actor or async context.
    public func collect(packages: [Package]) -> [ProvenanceEvidence] {
        guard !Task.isCancelled else { return [] }
        let shellRecords = shellCollector.collect()
        guard !Task.isCancelled else { return [] }
        let claudeRecords = claudeCodeCollector.collect()
        guard !Task.isCancelled else { return [] }

        // Bucket shell records by manager and normalized name. Scope hints are
        // retained separately so unqualified records can remain fallback evidence.
        var shellByKey: [PackageKey: [ScopedCandidate<ProvenanceEvidence.InstallCommandRecord>]] = [:]
        for record in shellRecords where record.timestamp != nil {
            guard !Task.isCancelled else { return [] }
            for detection in detector.detectInstallations(record.command) {
                let key = PackageKey(manager: detection.manager, name: detection.name)
                shellByKey[key, default: []].append(ScopedCandidate(
                    value: record,
                    qualifierHint: detection.qualifierHint
                ))
            }
        }

        // Claude records expose the original Bash invocation, so recover the same
        // scope hints without changing their persisted/public representation.
        var claudeByKey: [PackageKey: [ScopedCandidate<InstalledByClaudeCode>]] = [:]
        var claudeHintsByCommand: [String: [PackageKey: Set<InstallQualifierHint?>]] = [:]
        for record in claudeRecords where record.context.timestamp != nil {
            guard !Task.isCancelled else { return [] }
            let key = PackageKey(manager: record.manager, name: record.packageName)
            let command = record.context.bashInvocation
            if claudeHintsByCommand[command] == nil {
                var hintsByKey: [PackageKey: Set<InstallQualifierHint?>] = [:]
                for detection in detector.detectInstallations(command) {
                    let detectionKey = PackageKey(
                        manager: detection.manager,
                        name: detection.name
                    )
                    hintsByKey[detectionKey, default: []].insert(detection.qualifierHint)
                }
                claudeHintsByCommand[command] = hintsByKey
            }
            let matchingHints = claudeHintsByCommand[command]?[key] ?? []

            // A collector record remains useful even if its original command can
            // no longer be classified in detail. Treat that case as unqualified,
            // never as guessed scope information.
            let hints: Set<InstallQualifierHint?> = matchingHints.isEmpty ? [nil] : matchingHints
            for hint in hints {
                claudeByKey[key, default: []].append(ScopedCandidate(
                    value: record,
                    qualifierHint: hint
                ))
            }
        }

        // Pre-build bounded co-install summaries with a sorted sliding window.
        // This avoids an O(n²) full-array filter for every package and prevents
        // dense installs from creating unbounded persistence payloads.
        let timedPackages: [(id: String, time: TimeInterval)] = packages.compactMap { pkg in
            guard let t = pkg.installedAt else { return nil }
            return (id: pkg.id, time: t.timeIntervalSince1970)
        }
        let coInstalledByPackageId = coInstalledSummaries(from: timedPackages)
        guard !Task.isCancelled else { return [] }

        var evidence: [ProvenanceEvidence] = []
        evidence.reserveCapacity(packages.count)
        for package in packages {
            guard !Task.isCancelled else { return [] }
            evidence.append(buildEvidence(
                for: package,
                shellByKey: shellByKey,
                claudeByKey: claudeByKey,
                coInstalled: coInstalledByPackageId[package.id] ?? .empty
            ))
        }
        return evidence
    }

    // MARK: - Per-package evidence assembly

    private func buildEvidence(
        for package: Package,
        shellByKey: [PackageKey: [ScopedCandidate<ProvenanceEvidence.InstallCommandRecord>]],
        claudeByKey: [PackageKey: [ScopedCandidate<InstalledByClaudeCode>]],
        coInstalled: CoInstalledSummary
    ) -> ProvenanceEvidence {
        let fsTime = package.installedAt
        let shellCandidates = candidateGroups(for: package, from: shellByKey)
        let claudeCandidates = candidateGroups(for: package, from: claudeByKey)

        let claudeMatch = nearestClaude(
            fsTime: fsTime,
            candidates: claudeCandidates.qualified
        ) ?? nearestClaude(
            fsTime: fsTime,
            candidates: claudeCandidates.unqualified
        )
        let shellMatch = nearestShell(
            fsTime: fsTime,
            candidates: shellCandidates.qualified
        ) ?? nearestShell(
            fsTime: fsTime,
            candidates: shellCandidates.unqualified
        )

        return redactor.redact(ProvenanceEvidence(
            packageId: package.id,
            fsInstallTime: fsTime,
            fsInstallTimeSource: fsTime != nil ? installTimeSource(for: package.manager) : nil,
            installCommand: shellMatch,
            claudeCodeContext: claudeMatch,
            nearbyProjects: [],
            coInstalledWithin1h: coInstalled.sampleIds,
            coInstalledWithin1hTotalCount: coInstalled.totalCount,
            overallConfidence: confidence(
                fsInstallTime: fsTime,
                installCommand: shellMatch,
                claudeCodeContext: claudeMatch
            ),
            collectedAt: Date()
        ))
    }

    // MARK: - Nearest-match helpers

    /// Separates candidates whose encoded scope matches this package from generic
    /// evidence. Callers first try qualified records, then fall back if none is
    /// usable in the time window. A command for another scope is never downgraded.
    private func candidateGroups<Value>(
        for package: Package,
        from buckets: [PackageKey: [ScopedCandidate<Value>]]
    ) -> CandidateGroups<Value> {
        let key = PackageKey(manager: package.manager, name: package.name)
        let candidates = buckets[key] ?? []
        let qualified = candidates.compactMap { candidate -> Value? in
            guard let hint = candidate.qualifierHint,
                  hint.matches(package.qualifier) else { return nil }
            return candidate.value
        }
        let unqualified = candidates.compactMap { candidate in
            candidate.qualifierHint == nil ? candidate.value : nil
        }
        return CandidateGroups(qualified: qualified, unqualified: unqualified)
    }

    private func nearestClaude(
        fsTime: Date?,
        candidates: [InstalledByClaudeCode]
    ) -> ProvenanceEvidence.ClaudeCodeContext? {
        guard let fsTs = fsTime?.timeIntervalSince1970 else { return nil }
        var best: (delta: TimeInterval, context: ProvenanceEvidence.ClaudeCodeContext)?
        for record in candidates {
            // Nil-timestamp records were excluded from the dict at build time.
            // The guard is a defensive double-check.
            guard let ts = record.context.timestamp?.timeIntervalSince1970 else { continue }
            let delta = abs(fsTs - ts)
            guard delta <= 3600 else { continue }
            if best == nil || delta < best!.delta {
                best = (delta, record.context)
            }
        }
        return best?.context
    }

    private func nearestShell(
        fsTime: Date?,
        candidates: [ProvenanceEvidence.InstallCommandRecord]
    ) -> ProvenanceEvidence.InstallCommandRecord? {
        guard let fsTs = fsTime?.timeIntervalSince1970 else { return nil }
        var best: (delta: TimeInterval, record: ProvenanceEvidence.InstallCommandRecord)?
        for record in candidates {
            guard let ts = record.timestamp?.timeIntervalSince1970 else { continue }
            let delta = abs(fsTs - ts)
            guard delta <= 3600 else { continue }
            if best == nil || delta < best!.delta {
                best = (delta, record)
            }
        }
        return best?.record
    }

    // MARK: - Co-installed computation

    /// Builds a deterministic, bounded sample for every timestamped package.
    ///
    /// Entries are sorted by install time and then id. Two monotonic pointers
    /// identify each package's ±1-hour window in O(n log n) overall; collecting
    /// at most `coInstalledSampleLimit` ids per package keeps the remaining work
    /// O(n * sampleLimit), even when thousands of packages share a timestamp.
    private func coInstalledSummaries(
        from timedPackages: [(id: String, time: TimeInterval)]
    ) -> [String: CoInstalledSummary] {
        let sorted = timedPackages.sorted {
            if $0.time == $1.time { return $0.id < $1.id }
            return $0.time < $1.time
        }
        guard !sorted.isEmpty else { return [:] }

        var summaries: [String: CoInstalledSummary] = [:]
        summaries.reserveCapacity(sorted.count)
        var left = 0
        var right = 0

        for index in sorted.indices {
            guard !Task.isCancelled else { return [:] }
            let package = sorted[index]
            while package.time - sorted[left].time > coInstalledWindow {
                left += 1
            }
            if right < index { right = index }
            while right + 1 < sorted.count,
                  sorted[right + 1].time - package.time <= coInstalledWindow {
                right += 1
            }

            var sampleIds: [String] = []
            sampleIds.reserveCapacity(min(coInstalledSampleLimit, right - left))
            for candidateIndex in left...right where candidateIndex != index {
                sampleIds.append(sorted[candidateIndex].id)
                if sampleIds.count == coInstalledSampleLimit { break }
            }

            summaries[package.id] = CoInstalledSummary(
                sampleIds: sampleIds,
                totalCount: right - left
            )
        }
        return summaries
    }

    // MARK: - Confidence

    /// Computes the overall confidence from the three signals.
    ///
    /// | fsInstallTime | installCommand                | claudeCodeContext | result  |
    /// |---------------|-------------------------------|-------------------|---------|
    /// | nil           | any                           | any               | unknown |
    /// | present       | nil                           | nil               | low     |
    /// | present       | present, no usable Δ          | nil               | medium  |
    /// | present       | present, Δ > 5 min            | nil               | medium  |
    /// | present       | present, Δ ≤ 5 min            | nil               | high    |
    /// | present       | any                           | present           | high    |
    private func confidence(
        fsInstallTime: Date?,
        installCommand: ProvenanceEvidence.InstallCommandRecord?,
        claudeCodeContext: ProvenanceEvidence.ClaudeCodeContext?
    ) -> Confidence {
        guard let fsTs = fsInstallTime?.timeIntervalSince1970 else { return .unknown }
        if claudeCodeContext != nil { return .high }
        guard let command = installCommand else { return .low }
        guard let cmdTs = command.timestamp?.timeIntervalSince1970 else {
            // Shell command matched by (manager, name) but no timestamp — can't confirm timing.
            return .medium
        }
        return abs(fsTs - cmdTs) <= 300 ? .high : .medium
    }

    // MARK: - Install-time source label

    private func installTimeSource(for manager: PackageManager) -> String {
        switch manager {
        case .brew, .brewCask:
            return "INSTALL_RECEIPT.json"
        case .pip, .uv:
            return "dist-info mtime"
        case .npm:
            return "package.json mtime"
        default:
            return "directory mtime"
        }
    }
}

private let coInstalledWindow: TimeInterval = 3600
private let coInstalledSampleLimit = 20

private struct CoInstalledSummary {
    let sampleIds: [String]
    let totalCount: Int

    static let empty = CoInstalledSummary(sampleIds: [], totalCount: 0)
}

private struct ScopedCandidate<Value> {
    let value: Value
    let qualifierHint: InstallQualifierHint?
}

private struct CandidateGroups<Value> {
    let qualified: [Value]
    let unqualified: [Value]
}

private extension InstallQualifierHint {
    func matches(_ packageQualifier: String?) -> Bool {
        guard let packageQualifier else { return false }

        switch self {
        case .exactPath(let commandPath):
            guard packageQualifier.hasPrefix("/") else { return false }
            return standardizedPath(commandPath) == standardizedPath(packageQualifier)
        case .executableName(let commandName):
            return URL(fileURLWithPath: packageQualifier).lastPathComponent == commandName
        }
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

// MARK: - Private key type

private struct PackageKey: Hashable {
    let manager: PackageManager
    let name: String

    init(manager: PackageManager, name: String) {
        self.manager = manager
        self.name = PackageIdentity.normalizedName(name, manager: manager)
    }
}
