import OrganizerCore
import QuickLook
import SwiftUI

/// Mittlere Spalte: Notizen eines Bereichs, gruppiert nach Änderungsdatum.
struct NoteListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var quickLookURL: URL?
    let scope: NoteScope

    var body: some View {
        @Bindable var notesModel = model.notes
        let sections = notesModel.sections(in: scope)
        let count = sections.reduce(0) { $0 + $1.notes.count }

        List(selection: $notesModel.selectedNoteID) {
            if case .folder(let path) = scope, !notesModel.isFiltering {
                LinkedFoldersSection(folder: path)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.notes) { note in
                        NoteRow(note: note, showsLocation: showsLocation)
                            .tag(note.id)
                            .draggable(DragPayload.note(note.relativePath)) {
                                Label(note.title, systemImage: "doc.text").padding(6)
                            }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: Note.ID.self) { ids in
            let selected = model.vault.notes.filter { ids.contains($0.id) }
            if !selected.isEmpty {
                if selected.count == 1, let note = selected.first {
                    Button("In Obsidian öffnen") { model.openInObsidian(note) }
                    Button("Bearbeiten") {
                        model.notes.selectedNoteID = note.id
                        model.notes.isEditing = true
                    }
                    Divider()
                }
                Button("Im Finder zeigen") { model.revealInFinder(selected) }
                Button(selected.count == 1 ? "Pfad kopieren" : "Pfade kopieren") {
                    copyPaths(selected)
                }
            }
        }
        .overlay { emptyState(isEmpty: count == 0) }
        // Leertaste: Quick Look der Markdown-Datei, Return: bearbeiten – wie im Finder bzw. in Notizen.
        .onKeyPress(.space) {
            guard let note = notesModel.selectedNote else { return .ignored }
            quickLookURL = note.url
            return .handled
        }
        .onKeyPress(.return) {
            guard notesModel.selectedNote != nil else { return .ignored }
            notesModel.isEditing = true
            return .handled
        }
        .quickLookPreview($quickLookURL)
        .navigationTitle(title)
        .navigationSubtitle(count == 1 ? "1 Notiz" : "\(count) Notizen")
        .toolbar {
            ToolbarItem {
                TagFilterMenu(tags: notesModel.availableTags(in: scope), selection: $notesModel.tagFilter)
            }
            if case .folder(let path) = scope {
                ToolbarItem {
                    Button {
                        model.folderLinks.chooseAndLink(to: path, undoManager: undoManager)
                    } label: {
                        Label("Mac-Ordner verknüpfen", systemImage: "folder.badge.plus")
                    }
                    .help("Mac-Ordner mit „\(title)“ verknüpfen")
                }
            }
            ToolbarItem {
                Button {
                    model.isShowingNewNote = true
                } label: {
                    Label("Neue Notiz", systemImage: "square.and.pencil")
                }
                .help("Neue Notiz (⌘N)")
                .disabled(model.vault.state != .ready)
            }
        }
    }

    private var title: String {
        switch scope {
        case .all: "Notizen"
        case .area(let area): area
        case .topic(_, let name): name
        case .folder(let path): path.split(separator: "/").last.map(String.init) ?? path
        }
    }

    /// In der Gesamtansicht hilft der Ort, in einem Thema wäre er überflüssig.
    private var showsLocation: Bool {
        if case .folder(let path) = scope {
            // Nur anzeigen, wenn es Unterordner gibt, in denen Notizen liegen können.
            return model.vault.snapshot.folders.contains { $0.hasPrefix(path + "/") }
        }
        return true
    }

    @ViewBuilder
    private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty {
            if !model.notes.searchText.isEmpty {
                ContentUnavailableView.search(text: model.notes.searchText)
            } else if let tag = model.notes.tagFilter {
                ContentUnavailableView {
                    Label("Keine Notizen mit #\(tag)", systemImage: "tag")
                } actions: {
                    Button("Filter entfernen") { model.notes.tagFilter = nil }
                }
            } else {
                ContentUnavailableView {
                    Label("Keine Notizen", systemImage: "note.text")
                } description: {
                    Text("Notizen, die du in Obsidian in diesem Ordner anlegst, erscheinen hier automatisch.")
                }
            }
        }
    }

    private func copyPaths(_ notes: [Note]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes.map { $0.url.path(percentEncoded: false) }.joined(separator: "\n"), forType: .string)
    }
}

/// Filter nach Tag in der Symbolleiste.
private struct TagFilterMenu: View {
    let tags: [String]
    @Binding var selection: String?

    var body: some View {
        Menu {
            Picker("Tag", selection: $selection) {
                Text("Alle Notizen").tag(String?.none)
                if !tags.isEmpty {
                    Divider()
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)").tag(String?.some(tag))
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Nach Tag filtern", systemImage: selection == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .help(selection.map { "Gefiltert nach #\($0)" } ?? "Nach Tag filtern")
        .disabled(tags.isEmpty && selection == nil)
    }
}

#Preview("Hell") {
    NavigationStack {
        NoteListView(scope: .all)
    }
    .environment(PreviewData.model())
    .frame(width: 340, height: 600)
}

#Preview("Dunkel") {
    NavigationStack {
        NoteListView(scope: .folder("Uni"))
    }
    .environment(PreviewData.model())
    .frame(width: 340, height: 600)
    .preferredColorScheme(.dark)
}
