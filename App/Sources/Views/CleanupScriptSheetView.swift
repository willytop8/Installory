import InstalloryCore
import SwiftUI

/// Cleanup-specific script sheet. Wraps `ScriptSheetView` with the snapshot-status
/// line and optional denylist warning that are specific to the uninstall flow.
///
/// Takes a `CleanupResult` rather than a bare `GeneratedScript` so it can report
/// truthfully whether a snapshot was captured — when the user chose to skip the
/// snapshot, the sheet must not claim one was taken.
struct CleanupScriptSheetView: View {
    let result: CleanupResult

    var body: some View {
        ScriptSheetView(
            title: "Cleanup Script Ready",
            filename: "installory-cleanup.sh",
            scriptText: result.script.scriptText
        ) {
            snapshotStatusLine
            if !result.script.warnedDenylisted.isEmpty {
                denylistWarning
            }
        }
    }

    @ViewBuilder
    private var snapshotStatusLine: some View {
        if result.snapshotTaken {
            Label("Snapshot captured before generation", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if result.snapshotFailed {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Snapshot could not be saved")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("A snapshot was requested but failed to write. Your packages are not protected — if something goes wrong after running this script, you may not be able to restore them from Installory.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Label(
                "No snapshot taken — you won\u{2019}t be able to undo this from Installory.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
            .font(.callout)
        }
    }

    @ViewBuilder
    private var denylistWarning: some View {
        let names = result.script.warnedDenylisted.map(\.name).joined(separator: ", ")
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Common essentials detected")
                    .fontWeight(.semibold)
                Text("\(names) — these appear in the script as commented-out lines. Uncomment only if you are certain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Snapshot taken") {
    let sample = Package(
        id: "brew::ffmpeg",
        manager: .brew,
        qualifier: nil,
        name: "ffmpeg",
        version: "7.0.1",
        installPath: nil,
        installedAt: nil,
        installedAtConfidence: .low,
        sizeBytes: nil,
        isExplicit: true,
        isReadOnly: false,
        dependencies: [],
        artifactPaths: nil,
        lastSeen: Date()
    )
    let script = ScriptGenerator().generate(packages: [sample])
    return CleanupScriptSheetView(
        result: CleanupResult(script: script, snapshotTaken: true, snapshotFailed: false)
    )
}

#Preview("Snapshot skipped") {
    let sample = Package(
        id: "brew::ffmpeg",
        manager: .brew,
        qualifier: nil,
        name: "ffmpeg",
        version: "7.0.1",
        installPath: nil,
        installedAt: nil,
        installedAtConfidence: .low,
        sizeBytes: nil,
        isExplicit: true,
        isReadOnly: false,
        dependencies: [],
        artifactPaths: nil,
        lastSeen: Date()
    )
    let script = ScriptGenerator().generate(packages: [sample])
    return CleanupScriptSheetView(
        result: CleanupResult(script: script, snapshotTaken: false, snapshotFailed: false)
    )
}

#Preview("Snapshot failed") {
    let sample = Package(
        id: "brew::ffmpeg",
        manager: .brew,
        qualifier: nil,
        name: "ffmpeg",
        version: "7.0.1",
        installPath: nil,
        installedAt: nil,
        installedAtConfidence: .low,
        sizeBytes: nil,
        isExplicit: true,
        isReadOnly: false,
        dependencies: [],
        artifactPaths: nil,
        lastSeen: Date()
    )
    let script = ScriptGenerator().generate(packages: [sample])
    return CleanupScriptSheetView(
        result: CleanupResult(script: script, snapshotTaken: false, snapshotFailed: true)
    )
}
