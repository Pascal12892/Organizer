import Foundation

/// Welche Notizen eine Liste zeigt.
public enum NoteScope: Sendable, Hashable {
    case all
    case area(String)
    case topic(area: String, name: String)
    /// Ein Ordner samt allen Unterordnern (relativer Pfad).
    case folder(String)
}

/// Filter für die Notizliste: Bereich/Thema, Tag und Volltextsuche.
public struct NoteQuery: Sendable, Hashable {
    public var scope: NoteScope
    public var tag: String?
    public var searchText: String

    public init(scope: NoteScope = .all, tag: String? = nil, searchText: String = "") {
        self.scope = scope
        self.tag = tag
        self.searchText = searchText
    }

    public func apply(to notes: [Note]) -> [Note] {
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        return notes.filter { matches($0, terms: terms) }
    }

    func matches(_ note: Note, terms: [String]) -> Bool {
        switch scope {
        case .all: break
        case .area(let area):
            guard note.area == area else { return false }
        case .topic(let area, let name):
            guard note.area == area, note.topic == name else { return false }
        case .folder(let path):
            guard note.relativePath.hasPrefix(path + "/") else { return false }
        }
        if let tag, !note.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            return false
        }
        // Jeder Suchbegriff muss irgendwo vorkommen (Groß-/Kleinschreibung und Akzente egal).
        return terms.allSatisfy { term in
            note.title.localizedStandardContains(term)
                || note.body.localizedStandardContains(term)
                || note.tags.contains { $0.localizedStandardContains(term) }
        }
    }
}

/// Eine Gruppe in der Notizliste („Heute“, „Gestern“, …).
public struct NoteSection: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let notes: [Note]
}

/// Gruppiert Notizen nach Änderungsdatum, wie Apple Notizen.
public enum NoteGrouping {
    public static func byRecency(_ notes: [Note], now: Date = .now, calendar: Calendar = .current) -> [NoteSection] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let start7 = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let start30 = calendar.date(byAdding: .day, value: -30, to: startOfToday)!

        var order: [String] = []
        var titles: [String: String] = [:]
        var buckets: [String: [Note]] = [:]

        for note in notes.sorted(by: { $0.modified > $1.modified }) {
            let key: String
            let title: String
            switch note.modified {
            case startOfToday...: (key, title) = ("today", "Heute")
            case startOfYesterday...: (key, title) = ("yesterday", "Gestern")
            case start7...: (key, title) = ("7days", "Vorherige 7 Tage")
            case start30...: (key, title) = ("30days", "Vorherige 30 Tage")
            default:
                let components = calendar.dateComponents([.year, .month], from: note.modified)
                let sameYear = components.year == calendar.component(.year, from: now)
                key = sameYear ? "m\(components.year!)-\(components.month!)" : "y\(components.year!)"
                title = sameYear
                    ? note.modified.formatted(.dateTime.month(.wide))
                    : note.modified.formatted(.dateTime.year())
            }
            if buckets[key] == nil {
                order.append(key)
                titles[key] = title
            }
            buckets[key, default: []].append(note)
        }

        return order.map { NoteSection(id: $0, title: titles[$0]!, notes: buckets[$0]!) }
    }
}
