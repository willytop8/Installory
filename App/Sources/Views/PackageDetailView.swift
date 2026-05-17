import AppKit
import BackshelfCore
import Foundation
import SwiftUI

struct PackageDetailView: View {
    let package: Package
    @Environment(AppCoordinator.self) private var coordinator
    @State private var showRawRecord = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                fieldsSection
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
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([installPath])
                        }
                        .buttonStyle(.borderless)
                        .font(.callout)
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

    private var removalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remove")
                .font(.headline)

            if package.isReadOnly {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("This is a system package and cannot be removed.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else if package.manager == .mas {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Mac App Store apps are removed by dragging them from /Applications to the Trash — mas has no uninstall command.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else if let cmd = ScriptGenerator().removalCommand(for: package) {
                VStack(alignment: .leading, spacing: 8) {
                    if Denylist.default.isDenylisted(package) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Other software commonly depends on this package. Review carefully before removing.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Text(cmd)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        Button("Copy command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        Spacer(minLength: 0)
                        Text("Paste into Terminal to run")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Button {
                        Task { await coordinator.generateAndShowCleanupScript(packages: [package]) }
                    } label: {
                        Label("Remove this package…", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
    }

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
