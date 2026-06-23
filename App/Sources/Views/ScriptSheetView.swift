import AppKit
import InstalloryCore
import SwiftUI
import UniformTypeIdentifiers

/// A generic sheet that displays a generated shell script with Copy, Save, and Done actions.
///
/// Used by both the cleanup flow (uninstall) and the restore flow (reinstall).
/// The `Warning` slot accepts any additional content shown between the title and the
/// script body — pass the denylist warning for cleanup, `EmptyView` for reinstall.
struct ScriptSheetView<Warning: View>: View {
    let title: String
    let filename: String
    let scriptText: String
    @ViewBuilder let warningContent: () -> Warning
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            warningContent()
            scriptSection
            safetyReminder
            buttonRow
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 480)
    }

    private var scriptSection: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(scriptText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(minHeight: 200)
    }

    private var safetyReminder: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Review this script here first. When you are ready, copy or save it and run it yourself in Terminal. **Installory never runs commands for you.**")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var buttonRow: some View {
        HStack {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(scriptText, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                Label(
                    copied ? "Copied" : "Copy to Clipboard",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
            }
            .keyboardShortcut("c", modifiers: .command)

            Button {
                saveScript()
            } label: {
                Label("Save as .sh\u{2026}", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func saveScript() {
        let panel = NSSavePanel()
        panel.title = "Save Script"
        panel.nameFieldStringValue = filename
        if let shellType = UTType(filenameExtension: "sh") {
            panel.allowedContentTypes = [shellType]
        }
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? scriptText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

extension ScriptSheetView where Warning == EmptyView {
    init(title: String, filename: String, scriptText: String) {
        self.init(
            title: title,
            filename: filename,
            scriptText: scriptText,
            warningContent: { EmptyView() }
        )
    }
}
