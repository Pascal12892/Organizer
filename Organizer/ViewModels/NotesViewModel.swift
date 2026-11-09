import OrganizerCore
import Observation

/// Zustand der Notizliste: Auswahl, Suche und Tag-Filter.
@Observable
final class NotesViewModel {
    var selectedNoteID: Note.ID?
    /// Was im Suchfeld steht. Gefiltert wird mit kurzer Verzögerung (`appliedSearch`),
    /// damit Tippen flüssig bleibt, auch bei großen Vaults.
    var searchText = "" {
        didSet { scheduleSearch() }
    }
    private(set) var appliedSearch = ""
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private let sectionsMemo = Memo<SectionsKey, [NoteSection]>()
    @ObservationIgnored private let tagsMemo = Memo<TagsKey, [String]>()

    private struct SectionsKey: Equatable { let version: Int; let scope: NoteScope; let tag: String?; let search: String }
    private struct TagsKey: Equatable { let version: Int; let scope: NoteScope }

    private func scheduleSearch() {
        searchTask?.cancel()
        // Leeren sofort, Tippen nach 150 ms.
        guard !searchText.isEmpty else {
            appliedSearch = ""
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            appliedSearch = searchText
        }
    }
    var tagFilter: String?
    /// Bearbeiten statt Vorschau – gilt wie in Obsidian für jede geöffnete Notiz.
    var isEditing = false

    private let vault: VaultService

    init(vault: VaultService) {
        self.vault = vault
    }

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return vault.notes.first { $0.id == selectedNoteID }
    }

    func notes(in scope: NoteScope) -> [Note] {
        NoteQuery(scope: scope, tag: tagFilter, searchText: appliedSearch).apply(to: vault.notes)
    }

    func sections(in scope: NoteScope) -> [NoteSection] {
        let key = SectionsKey(version: vault.version, scope: scope, tag: tagFilter, search: appliedSearch)
        return sectionsMemo(key) { NoteGrouping.byRecency(notes(in: scope)) }
    }

    /// Alle Tags im aktuellen Bereich, nach Häufigkeit sortiert.
    func availableTags(in scope: NoteScope) -> [String] {
        tagsMemo(TagsKey(version: vault.version, scope: scope)) { computeTags(in: scope) }
    }

    private func computeTags(in scope: NoteScope) -> [String] {
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
