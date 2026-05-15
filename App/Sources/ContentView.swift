import BackshelfCore
import SwiftUI

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator

    private var homeDir: String { NSHomeDirectory() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Backshelf")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Package Managers") {
                VStack(alignment: .leading, spacing: 12) {
                    ManagerRow(
                        name: "Homebrew",
                        prefixes: ["/opt/homebrew", "/usr/local"],
                        suggestedURL: URL(fileURLWithPath: "/opt/homebrew"),
                        folderAccess: coordinator.folderAccess
                    )
                    Divider()
                    ManagerRow(
                        name: "pip",
                        prefixes: [homeDir + "/.pyenv", homeDir + "/.local"],
                        suggestedURL: URL(fileURLWithPath: homeDir + "/.pyenv"),
                        folderAccess: coordinator.folderAccess
                    )
                    Divider()
                    ManagerRow(
                        name: "npm",
                        prefixes: [homeDir + "/.nvm", "/opt/homebrew/lib/node_modules"],
                        suggestedURL: URL(fileURLWithPath: homeDir + "/.nvm"),
                        folderAccess: coordinator.folderAccess
                    )
                }
                .padding(4)
            }

            HStack(spacing: 10) {
                Button("Run Scan") {
                    Task { await coordinator.scan() }
                }
                .disabled(!coordinator.folderAccess.hasAnyGrant || coordinator.isScanning)

                if coordinator.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !coordinator.scanStatuses.isEmpty {
                GroupBox("Scan Results") {
                    VStack(alignment: .leading, spacing: 6) {
                        statusLine(manager: .brew, name: "Homebrew")
                        statusLine(manager: .pip, name: "pip")
                        statusLine(manager: .npm, name: "npm")
                    }
                    .padding(4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 440, minHeight: 360)
    }

    @ViewBuilder
    private func statusLine(manager: PackageManager, name: String) -> some View {
        if let status = coordinator.scanStatuses[manager] {
            Text(statusText(for: manager, name: name, status: status))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(status.isFailure ? .red : .primary)
        }
    }

    private func statusText(
        for manager: PackageManager,
        name: String,
        status: ScannerStatus
    ) -> String {
        switch status {
        case let .succeeded(count, durationMs):
            let secs = String(format: "%.1f", Double(durationMs) / 1000)
            if manager == .pip {
                let interpreterCount = Set(
                    coordinator.scanResults
                        .filter { $0.manager == .pip }
                        .compactMap { $0.qualifier }
                ).count
                if interpreterCount > 1 {
                    return "\(name): \(count) packages across \(interpreterCount) interpreters · \(secs)s"
                }
            }
            return "\(name): \(count) packages · \(secs)s"
        case let .timedOut(durationMs):
            let secs = String(format: "%.1f", Double(durationMs) / 1000)
            return "\(name): timed out · \(secs)s"
        case let .failed(reason, durationMs):
            let secs = String(format: "%.1f", Double(durationMs) / 1000)
            return "\(name): failed (\(reason)) · \(secs)s"
        case let .skipped(reason):
            return "\(name): skipped (\(reason))"
        }
    }
}

// MARK: -

private struct ManagerRow: View {
    let name: String
    let prefixes: [String]
    let suggestedURL: URL
    let folderAccess: FolderAccessManager

    private var grantedPath: String? {
        for prefix in prefixes {
            if let path = folderAccess.grantedPath(forPrefix: prefix) {
                return path
            }
        }
        return nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Group {
                    if let path = grantedPath {
                        Text("\(path) (granted)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not granted")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }

            Spacer()

            Button("Grant Access") {
                Task { await folderAccess.requestAccess(to: suggestedURL) }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - ScannerStatus helpers

private extension ScannerStatus {
    var isFailure: Bool {
        switch self {
        case .failed, .timedOut: true
        default: false
        }
    }
}
