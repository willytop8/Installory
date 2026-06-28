import AppKit
import InstalloryCore
import Foundation
import SwiftUI

struct PackageDetailView: View {
    let package: Package
    @Environment(AppCoordinator.self) private var coordinator
    @State private var showRawRecord = false
    @State private var copiedCommand = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                fieldsSection
                Divider()
                provenanceSection
                Divider()
                removalSection
                Divider()
                rawRecordSection
            }
            .padding(20)
        }
        .frame(minWidth: 300)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(package.version)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let desc = coordinator.descriptionStore.description(
                    for: package.manager,
                    name: package.name
                ) {
                    Text(desc)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No description available")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                }
            }
            Spacer(minLength: 0)
            ManagerBadge(manager: package.manager)
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let installedAt = package.installedAt {
                LabeledContent("Installed") {
                    Text("\(relativeTime(installedAt)) (\(absoluteDate(installedAt)))")
                        .foregroundStyle(.secondary)
                }
            }

            if let installPath = package.installPath {
                LabeledContent("Install path") {
                    HStack(spacing: 8) {
                        Text(installPath.path)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        let exists = FileManager.default.fileExists(atPath: installPath.path)
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([installPath])
                        }
                        .buttonStyle(.borderless)
                        .font(.callout)
                        .disabled(!exists)
                        .help(exists ? "Open the install path in Finder" : "File no longer exists at this path")
                    }
                }
            }

            if !package.dependencies.isEmpty {
                LabeledContent("Dependencies") {
                    Text(package.dependencies.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }

            if package.isReadOnly {
                LabeledContent("") {
                    Text("System (read-only)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    // MARK: - Provenance section

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it was installed")
                .font(.headline)

            if !coordinator.provenanceCollection {
                // Provenance is off — show a subtle nudge rather than an empty section.
                Text("Turn on provenance tracing in Settings \u{2192} Privacy to see how this was installed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let evidence = coordinator.provenanceByPackageId[package.id] {
                // Evidence found — render the narrative sentence.
                let nameByPackageId = Dictionary(
                    uniqueKeysWithValues: coordinator.packages.map { ($0.id, $0.name) }
                )
                Text(NarrativeRenderer().render(evidence, package: package, nameByPackageId: nameByPackageId))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Provenance is on but no trace found for this package.
                Text("No install trace found for this package.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Shell history may be truncated, or this package was installed before your history began.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Removal section

    private var removalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Removal Script")
                .font(.headline)

            if package.isReadOnly {
                removalMessage(
                    icon: "lock.fill",
                    text: "This is a system package and cannot be removed."
                )
            } else if package.manager == .mas {
                removalMessage(
                    icon: "info.circle",
                    text: "Mac App Store apps are removed by dragging them from /Applications to the Trash \u{2014} mas has no uninstall command."
                )
            } else if let cmd = ScriptGenerator().removalCommand(for: package) {
                removableContent(cmd)
            }
        }
    }

    @ViewBuilder
    private func removalMessage(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    @ViewBuilder
    private func removableContent(_ cmd: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if Denylist.default.isDenylisted(package) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Other software commonly depends on this package. Review carefully before removing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button {
                Task { await coordinator.requestRemoval([package]) }
            } label: {
                Label("Create Removal Script\u{2026}", systemImage: "doc.text")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text(removalScriptCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            rawCommandDisclosure(cmd)
        }
    }

    @ViewBuilder
    private func rawCommandDisclosure(_ cmd: String) -> some View {
        if Denylist.default.isDenylisted(package) {
            Text("Raw command hidden for safety. Use the script flow above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            DisclosureGroup("Advanced command") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(cmd)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                        copiedCommand = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedCommand = false
                        }
                    } label: {
                        Label(
                            copiedCommand ? "Copied" : "Copy command",
                            systemImage: copiedCommand ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)

                    Text("Skips the snapshot and review steps. For advanced users.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
    }

    private var removalScriptCaption: String {
        switch coordinator.snapshotBeforeRemoval {
        case .always:
            return "Saves a snapshot so you can undo, then builds a script you review and run yourself."
        case .never:
            return "Builds a script you review and run yourself. No snapshot is saved."
        case .ask:
            return "You\u{2019}ll be asked whether to save a snapshot first, then given a script you review and run yourself."
        }
    }

    // MARK: - Raw record section

    private var rawRecordSection: some View {
        DisclosureGroup("Show raw record", isExpanded: $showRawRecord) {
            let json = encodedJSON()
            ScrollView(.horizontal, showsIndicators: true) {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 6)
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func absoluteDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func encodedJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(package),
              let string = String(data: data, encoding: .utf8) else {
            return "// Error encoding package"
        }
        return string
    }
}

#Preview {
    PackageDetailView(
        package: Package(
            id: "brew::ffmpeg",
            manager: .brew,
            qualifier: nil,
            name: "ffmpeg",
            version: "6.0_1",
            installPath: URL(fileURLWithPath: "/opt/homebrew/Cellar/ffmpeg/6.0_1"),
            installedAt: Calendar.current.date(byAdding: .month, value: -3, to: Date()),
            installedAtConfidence: .high,
            sizeBytes: 223_000_000,
            isExplicit: true,
            isReadOnly: false,
            dependencies: ["aom", "dav1d", "fdk-aac", "lame", "libass"],
            artifactPaths: nil,
            lastSeen: Date()
        )
    )
    .environment(AppCoordinator())
    .frame(width: 400, height: 600)
}
