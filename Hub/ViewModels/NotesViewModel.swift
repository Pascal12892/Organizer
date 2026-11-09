import HubCore
import Observation

/// Zustand der Notizliste: Auswahl, Suche und Tag-Filter.
@Observable
final class NotesViewModel {
    var selectedNoteID: Note.ID?
    var searchText = ""
    var tagFilter: String?

    private let vault: VaultService

    init(vault: VaultService) {
        self.vault = vault
    }

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return vault.notes.first { $0.id == selectedNoteID }
    }

    func notes(in scope: NoteScope) -> [Note] {
        NoteQuery(scope: scope, tag: tagFilter, searchText: searchText).apply(to: vault.notes)
    }

    func sections(in scope: NoteScope) -> [NoteSection] {
        NoteGrouping.byRecency(notes(in: scope))
    }

    /// Alle Tags im aktuellen Bereich, nach Häufigkeit sortiert.
    func availableTags(in scope: NoteScope) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for note in NoteQuery(scope: scope).apply(to: vault.notes) {
            for tag in note.tags {
                let key = tag.lowercased()
                counts[key] = (counts[key]?.name ?? tag, (counts[key]?.count ?? 0) + 1)
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.name)
    }

    var isFiltering: Bool { tagFilter != nil || !searchText.isEmpty }
}
