import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        Form {
            Section {
                Picker("Snapshot before removing a package", selection: $coordinator.snapshotBeforeRemoval) {
                    ForEach(SnapshotPreference.allCases, id: \.self) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.inline)
                Text("Batch cleanup always captures a snapshot regardless of this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Snapshots")
            }

            Section {
                Toggle("Scan on launch", isOn: $coordinator.scanOnLaunch)
                Text("When off, Installory shows the last scan result on launch. Use ⌘R to scan manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Scanning")
            }

            Section {
                Toggle("Collect provenance", isOn: $coordinator.provenanceCollection)
                Text("Optional. Reads granted local history sources to show when and why packages were installed. Runs locally — no network calls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Provenance")
            }
        }
        .formStyle(.grouped)
        .onChange(of: coordinator.snapshotBeforeRemoval) { _, _ in coordinator.persistSettings() }
        .onChange(of: coordinator.scanOnLaunch) { _, _ in coordinator.persistSettings() }
        .onChange(of: coordinator.provenanceCollection) { _, _ in coordinator.persistSettings() }
        .frame(width: 400)
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView()
        .environment(AppCoordinator())
}
