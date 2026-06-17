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
                if coordinator.isDemoMode {
                    Label("Demo mode is on — showing sample data.", systemImage: "wand.and.stars")
                        .foregroundStyle(.secondary)
                    Button("Exit Demo Mode") {
                        coordinator.exitDemoMode()
                    }
                    Text("Exit to scan your own Mac. Demo data is never saved and never leaves this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Load Sample Data") {
                        coordinator.enterDemoMode()
                    }
                    Text("Loads a pre-populated sample inventory so you can explore every feature without granting access to any folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Demo Mode")
            }
        }
        .formStyle(.grouped)
        .onChange(of: coordinator.snapshotBeforeRemoval) { _, _ in coordinator.persistSettings() }
        .onChange(of: coordinator.scanOnLaunch) { _, _ in coordinator.persistSettings() }
        .frame(width: 400)
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView()
        .environment(AppCoordinator())
}
