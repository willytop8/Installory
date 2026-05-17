import Foundation

/// Aggregates the three provenance signals — filesystem timestamps, shell history,
/// and Claude Code session logs — into one ``ProvenanceEvidence`` per package.
///
/// **Matching algorithm (O(n) per package):**
/// Both collectors' records are bucketed into `[PackageKey: [Record]]` dictionaries
/// keyed by `(manager, name)` before any per-package work begins. Each package then
/// does a single dictionary lookup and a linear scan of its (usually small) candidate
/// list to find the nearest timestamp match.
///
/// Records with `nil` timestamps in either collector are excluded from time-proximity
/// matching and never contribute to `installCommand` or `claudeCodeContext`.
///
/// **pip (manager, name) collision:** Multiple pip packages with the same name but
/// different interpreter qualifiers (e.g. `requests` in Python 3.11 and 3.12) all
/// share the same `(pip, "requests")` bucket and will both be attributed to the same
/// install command. A future improvement would match on `(manager, name, qualifier)`
/// when the command encodes interpreter context (e.g. `python3.11 -m pip install`).
///
/// **nearbyProjects** is always `[]` in v0. Filesystem walking for nearby git repos
/// is deferred — see HANDOFF.md.
public struct ProvenanceCollector: Sendable {
    private let shellCollector: ShellHistoryCollector
    private let claudeCodeCollector: ClaudeCodeLogCollector
    private let detector: InstallCommandDetector

    public init(
        shellCollector: ShellHistoryCollector = ShellHistoryCollector(),
        claudeCodeCollector: ClaudeCodeLogCollector = ClaudeCodeLogCollector()
    ) {
        self.shellCollector = shellCollector
        self.claudeCodeCollector = claudeCodeCollector
        self.detector = InstallCommandDetector()
    }

    /// Builds ``ProvenanceEvidence`` for every package by combining filesystem
    /// timestamps, shell-history install commands, and Claude Code Bash invocations.
    ///
    /// This method is synchronous; file I/O occurs inside both sub-collectors.
    /// Dispatch to a background thread when calling from an actor or async context.
    public func collect(packages: [Package]) -> [ProvenanceEvidence] {
        let shellRecords = shellCollector.collect()
        let claudeRecords = claudeCodeCollector.collect()

        // Bucket shell records by (manager, name). Skip nil-timestamp records —
        // they cannot participate in time-proximity matching.
        var shellByKey: [PackageKey: [ProvenanceEvidence.InstallCommandRecord]] = [:]
        for record in shellRecords where record.timestamp != nil {
            for (name, manager) in detector.detect(record.command) {
                shellByKey[PackageKey(manager: manager, name: name), default: []].append(record)
            }
        }

        // Bucket Claude Code records by (manager, name). Skip nil-timestamp records.
        var claudeByKey: [PackageKey: [InstalledByClaudeCode]] = [:]
        for record in claudeRecords where record.context.timestamp != nil {
            let key = PackageKey(manager: record.manager, name: record.packageName)
            claudeByKey[key, default: []].append(record)
        }

        // Pre-build the co-installed lookup: all (id, installedAt) pairs with a
        // non-nil timestamp, used for the ±1h sweep on every package.
        let timedPackages: [(id: String, time: TimeInterval)] = packages.compactMap { pkg in
            guard let t = pkg.installedAt else { return nil }
            return (id: pkg.id, time: t.timeIntervalSince1970)
        }

        return packages.map { package in
            buildEvidence(
                for: package,
                shellByKey: shellByKey,
                claudeByKey: claudeByKey,
                timedPackages: timedPackages
            )
        }
    }

    // MARK: - Per-package evidence assembly

    private func buildEvidence(
        for package: Package,
        shellByKey: [PackageKey: [ProvenanceEvidence.InstallCommandRecord]],
        claudeByKey: [PackageKey: [InstalledByClaudeCode]],
        timedPackages: [(id: String, time: TimeInterval)]
    ) -> ProvenanceEvidence {
        let key = PackageKey(manager: package.manager, name: package.name)
        let fsTime = package.installedAt

        let claudeMatch = nearestClaude(fsTime: fsTime, candidates: claudeByKey[key] ?? [])
        let shellMatch = nearestShell(fsTime: fsTime, candidates: shellByKey[key] ?? [])

        return ProvenanceEvidence(
            packageId: package.id,
            fsInstallTime: fsTime,
            fsInstallTimeSource: fsTime != nil ? installTimeSource(for: package.manager) : nil,
            installCommand: shellMatch,
            claudeCodeContext: claudeMatch,
            nearbyProjects: [],
            coInstalledWithin1h: coInstalled(for: package, from: timedPackages),
            overallConfidence: confidence(
                fsInstallTime: fsTime,
                installCommand: shellMatch,
                claudeCodeContext: claudeMatch
            ),
            collectedAt: Date()
        )
    }

    // MARK: - Nearest-match helpers

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

    /// Returns the ids of all OTHER packages whose `installedAt` is within ±1 hour,
    /// sorted ascending by id for determinism.
    private func coInstalled(
        for package: Package,
        from timedPackages: [(id: String, time: TimeInterval)]
    ) -> [String] {
        guard let pkgTime = package.installedAt?.timeIntervalSince1970 else { return [] }
        return timedPackages
            .filter { $0.id != package.id && abs($0.time - pkgTime) <= 3600 }
            .map(\.id)
            .sorted()
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
        case .pip:
            return "dist-info mtime"
        case .npm:
            return "package.json mtime"
        default:
            return "directory mtime"
        }
    }
}

// MARK: - Private key type

private struct PackageKey: Hashable {
    let manager: PackageManager
    let name: String
}
