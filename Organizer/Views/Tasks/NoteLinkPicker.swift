import OrganizerCore
import SwiftUI

/// Auswahl einer Notiz, die mit einer Aufgabe verlinkt werden soll. Suche über Titel und Ordner,
/// zuletzt bearbeitete zuerst. ⏎ verlinkt die markierte Notiz, esc schließt.
struct NoteLinkPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    let task: TaskItem

    @State private var query = ""
    @State private var selection: Note.ID?
    @FocusState private var searchFocused: Bool

    /// Mehr Treffer bringen in einer Auswahlliste nichts; wer mehr braucht, tippt weiter.
    private static let limit = 200

    private var candidates: [Note] {
        let linked = Set(task.links.compactMap { WikiLinks.resolve($0, in: model.vault.notes)?.relativePath })
        let terms = query.lowercased().split(separator: " ")
        return model.vault.notes
            .filter { note in
                note.relativePath != task.relativePath && !linked.contains(note.relativePath)
                    && terms.allSatisfy { note.relativePath.lowercased().contains($0) }
            }
            .sorted { $0.modified > $1.modified }
            .prefix(Self.limit)
            .map { $0 }
    }

    var body: some View {
        let notes = candidates
        VStack(spacing: 0) {
            TextField("Notiz suchen", text: $query, prompt: Text("Titel oder Ordner"))
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { link(selection ?? notes.first?.id) }
                .padding(12)

            List(notes, selection: $selection) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                    if !note.folderPath.isEmpty {
                        Text(note.folderPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(note.id)
            }
            .contextMenu(forSelectionType: Note.ID.self) { _ in } primaryAction: { ids in
                link(ids.first)
            }
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Verlinken") { link(selection ?? notes.first?.id) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(notes.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 420, height: 460)
        .navigationTitle("Notiz verlinken")
        .onAppear { searchFocused = true }
    }

    private func link(_ id: Note.ID?) {
        guard let id, let note = model.vault.notes.first(where: { $0.id == id }) else { return }
        model.tasks.addLink(task, target: WikiLinks.linkTarget(for: note, in: model.vault.notes), undoManager: undoManager)
        dismiss()
    }
}
