import Foundation

/// Suche über Termine, Aufgaben und Notizen. Jeder Begriff muss vorkommen
/// (Groß-/Kleinschreibung und Akzente egal) – wie die Notizsuche.
public struct GlobalSearch: Sendable, Hashable {
    public let terms: [String]

    public init(_ text: String) {
        terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var isEmpty: Bool { terms.isEmpty }

    /// Kommt jeder Begriff in mindestens einem der Felder vor?
    public func matches(_ fields: [String?]) -> Bool {
        guard !terms.isEmpty else { return false }
        let fields = fields.compactMap { $0 }
        return terms.allSatisfy { term in fields.contains { $0.localizedStandardContains(term) } }
    }

    /// Offene Aufgaben zuerst (nach Datum, ohne Datum zuletzt), danach erledigte (neueste zuerst).
    public func tasks(in tasks: [TaskItem]) -> [TaskItem] {
        let found = tasks.filter { task in
            matches([task.title, task.noteTitle, task.area, task.topic] + task.tags.map { "#" + $0 })
        }
        let open = found.filter(\.isOpen).sorted { lhs, rhs in
            let l = lhs.relevantDate ?? .distantFuture, r = rhs.relevantDate ?? .distantFuture
            return l != r ? l < r : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        let closed = found.filter { !$0.isOpen }.sorted { ($0.doneDate ?? .distantPast) > ($1.doneDate ?? .distantPast) }
        return open + closed
    }

    /// Kommende Termine zuerst (nächster oben), danach vergangene (jüngster oben).
    public func events(in events: [CalendarEventInfo], now: Date = .now) -> [CalendarEventInfo] {
        let found = events.filter { matches([$0.title, $0.location, $0.notes]) }
        let upcoming = found.filter { $0.end >= now }.sorted { $0.start < $1.start }
        let past = found.filter { $0.end < now }.sorted { $0.start > $1.start }
        return upcoming + past
    }

    /// Notizen, deren Titel passt, vor solchen, bei denen nur der Text passt; sonst zuletzt bearbeitet zuerst.
    public func notes(in notes: [Note]) -> [Note] {
        guard !terms.isEmpty else { return [] }
        let found = NoteQuery(searchText: terms.joined(separator: " ")).apply(to: notes)
        let titleHits = found.filter { note in terms.allSatisfy { note.title.localizedStandardContains($0) } }
        let titleIDs = Set(titleHits.map(\.relativePath))
        let rest = found.filter { !titleIDs.contains($0.relativePath) }
        return titleHits.sorted { $0.modified > $1.modified } + rest.sorted { $0.modified > $1.modified }
    }
}
