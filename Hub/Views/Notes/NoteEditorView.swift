import AppKit
import HubCore
import SwiftUI

/// Bearbeiten einer Notiz als Markdown-Text. Speichert automatisch in die Datei im Vault.
struct NoteEditorView: View {
    @Bindable var editor: NoteEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch editor.status {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Speichern nicht möglich", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Erneut laden") { editor.load() }
                }
            case .conflict:
                ConflictBanner(editor: editor)
                textEditor
                    .disabled(true)
            case .ready:
                textEditor
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            editor.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            editor.saveNow()
        }
        .onDisappear { editor.saveNow() }
    }

    private var textEditor: some View {
        TextEditor(text: $editor.body)
            .font(.body)
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Notiztext")
    }
}

private struct ConflictBanner: View {
    let editor: NoteEditorModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Die Notiz wurde gleichzeitig außerhalb von Hub geändert.")
                    .font(.headline)
                Text("Welche Version soll gelten? Die andere geht verloren.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Version aus Obsidian") { editor.takeDiskVersion() }
            Button("Meine Version") { editor.keepMyVersion() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
