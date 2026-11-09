import Foundation

/// Liest und ändert Aufgaben-Zeilen im Format des Obsidian-Plugins „Tasks“:
///
///     - [ ] Hausarbeit Kapitel 2 schreiben ⏫ 📅 2026-11-20 #uni
///
/// Alle Änderungen betreffen nur die eine Zeile und lassen unbekannte Teile unangetastet.
public enum TaskLine {
    /// Zerlegte Zeile: `prefix` ist alles bis einschließlich `] `, `description` der Rest.
    public struct Parts: Sendable, Hashable {
        public var prefix: String
        public var status: TaskStatus
        public var description: String
    }

    static let dateFieldEmojis: [String: [Character]] = [
        "due": ["📅", "📆", "🗓", "🗓️"],
        "scheduled": ["⏳", "⌛"],
        "start": ["🛫"],
        "done": ["✅"],
        "created": ["➕"],
        "cancelled": ["❌"],
    ]
    static let priorityEmojis: Set<Character> = ["🔺", "⏫", "🔼", "🔽", "⏬"]
    static let metadataEmojis: Set<Character> = priorityEmojis
        .union(dateFieldEmojis.values.flatMap { $0 })
        .union(["🔁"])

    // MARK: - Lesen

    public static func parts(of line: String) -> Parts? {
        guard let match = line.wholeMatch(of: #/(\s*(?:[-*+]|\d+[.)])\s+\[(.)\]\s?)(.*)/#) else { return nil }
        return Parts(prefix: String(match.output.1), status: TaskStatus(match.output.2.first!), description: String(match.output.3))
    }

    /// Erkennt eine Aufgabe. Gibt `nil` zurück, wenn die Zeile keine Checkbox ist.
    public static func parse(_ line: String, relativePath: String = "", lineNumber: Int = 0,
                             timeZone: TimeZone = .current) -> TaskItem? {
        guard let parts = parts(of: line) else { return nil }
        let description = parts.description

        func date(_ field: String) -> Date? {
            guard let emojis = dateFieldEmojis[field] else { return nil }
            for emoji in emojis {
                guard let range = description.range(of: String(emoji)) else { continue }
                let rest = description[range.upperBound...].drop { $0 == "\u{FE0F}" || $0 == " " }
                if let value = rest.prefixMatch(of: #/\d{4}-\d{2}-\d{2}/#) {
                    return OrganizerDateFormat.parse(String(value.output), timeZone: timeZone)
                }
            }
            return nil
        }

        let priority = description.compactMap { TaskPriority(emoji: $0) }.first ?? .none
        var recurrence: String?
        if let range = description.range(of: "🔁") {
            let rest = description[range.upperBound...]
            let end = rest.firstIndex { metadataEmojis.contains($0) } ?? rest.endIndex
            let text = rest[..<end].trimmingCharacters(in: .whitespaces)
            recurrence = text.isEmpty ? nil : text
        }

        return TaskItem(
            relativePath: relativePath,
            lineNumber: lineNumber,
            rawLine: line,
            title: title(of: description),
            status: parts.status,
            priority: priority,
            due: date("due"),
            scheduled: date("scheduled"),
            start: date("start"),
            doneDate: date("done"),
            created: date("created"),
            recurrence: recurrence,
            tags: TagExtractor.deduplicated(TagExtractor.inlineTags(in: description))
        )
    }

    /// Der Text vor den Metadaten (Emoji-Felder und Tags am Ende). Tags mitten im Satz bleiben stehen,
    /// damit eine Änderung des Titels nichts verliert.
    public static func title(of description: String) -> String {
        String(description[..<metadataStart(in: description)]).trimmingCharacters(in: .whitespaces)
    }

    /// Wo die Metadaten beginnen: erstes Emoji-Feld oder die Folge von Tags/Block-ID am Zeilenende.
    static func metadataStart(in description: String) -> String.Index {
        let emojiStart = description.firstIndex { metadataEmojis.contains($0) } ?? description.endIndex
        let trailingStart = trailingTokensStart(in: description)
        return min(emojiStart, trailingStart)
    }

    /// Beginn der Tags, Erledigt-Daten und Block-IDs am Ende der Zeile.
    static func trailingTokensStart(in text: String) -> String.Index {
        let pattern = #/(?:\s+(?:#[\p{L}\p{N}_\/-]+|✅\s*\d{4}-\d{2}-\d{2}|\^[A-Za-z0-9-]+))+\s*$/#
        // Mit vorangestelltem Leerzeichen, damit auch eine Zeile nur aus Tags erkannt wird.
        let padded = " " + text
        guard let match = padded.firstMatch(of: pattern) else { return text.endIndex }
        let offset = padded.distance(from: padded.startIndex, to: match.range.lowerBound)
        return offset == 0 ? text.startIndex : text.index(text.startIndex, offsetBy: offset - 1)
    }

    // MARK: - Schreiben

    /// Abhaken bzw. wieder öffnen. Beim Abhaken wird wie im Tasks-Plugin `✅ Datum` ergänzt.
    public static func setting(_ line: String, done: Bool, on date: Date = .now, timeZone: TimeZone = .current) -> String {
        guard var parts = parts(of: line) else { return line }
        parts.status = done ? .done : .open
        var description = removingField(["✅"], from: parts.description)
        if done {
            description = inserting("✅ " + OrganizerDateFormat.string(from: date, includingTime: false, timeZone: timeZone),
                                    into: description, beforeTrailingTags: false)
        }
        return rebuild(parts, description: description)
    }

    /// Deadline setzen oder entfernen (`nil`).
    public static func setting(_ line: String, due: Date?, timeZone: TimeZone = .current) -> String {
        guard let parts = parts(of: line) else { return line }
        var description = removingField(dateFieldEmojis["due"]!, from: parts.description)
        if let due {
            description = inserting("📅 " + OrganizerDateFormat.string(from: due, includingTime: false, timeZone: timeZone),
                                    into: description, beforeTrailingTags: true)
        }
        return rebuild(parts, description: description)
    }

    public static func setting(_ line: String, priority: TaskPriority) -> String {
        guard let parts = parts(of: line) else { return line }
        var description = String(parts.description.filter { !priorityEmojis.contains($0) })
            .replacingOccurrences(of: "  ", with: " ")
        if let emoji = priority.emoji {
            // Priorität steht direkt hinter dem Titel.
            let index = metadataStart(in: description)
            let head = description[..<index].trimmingCharacters(in: .whitespaces)
            let tail = description[index...].trimmingCharacters(in: .whitespaces)
            description = [head, emoji, tail].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return rebuild(parts, description: description.trimmingCharacters(in: .whitespaces))
    }

    /// Ersetzt nur den Titel; Metadaten und Tags am Ende bleiben unverändert.
    public static func setting(_ line: String, title: String) -> String {
        guard let parts = parts(of: line) else { return line }
        let index = metadataStart(in: parts.description)
        let tail = parts.description[index...].trimmingCharacters(in: .whitespaces)
        let description = [title.trimmingCharacters(in: .whitespaces), tail].filter { !$0.isEmpty }.joined(separator: " ")
        return rebuild(parts, description: description)
    }

    /// Neue Aufgaben-Zeile.
    public static func make(title: String, due: Date? = nil, priority: TaskPriority = .none, tags: [String] = [],
                            timeZone: TimeZone = .current) -> String {
        var pieces = [title.trimmingCharacters(in: .whitespaces)]
        if let emoji = priority.emoji { pieces.append(emoji) }
        if let due { pieces.append("📅 " + OrganizerDateFormat.string(from: due, includingTime: false, timeZone: timeZone)) }
        let existing = Set(TagExtractor.inlineTags(in: title).map { $0.lowercased() })
        pieces += tags.filter { !$0.isEmpty && !existing.contains($0.lowercased()) }.map { "#" + $0 }
        return "- [ ] " + pieces.joined(separator: " ")
    }

    // MARK: - Hilfen

    private static func rebuild(_ parts: Parts, description: String) -> String {
        var prefix = parts.prefix
        if let bracket = prefix.lastIndex(of: "[") {
            let statusIndex = prefix.index(after: bracket)
            prefix.replaceSubrange(statusIndex...statusIndex, with: String(parts.status.character))
        }
        if !prefix.hasSuffix(" "), !description.isEmpty { prefix += " " }
        return prefix + description
    }

    private static func removingField(_ emojis: [Character], from description: String) -> String {
        var result = description
        for emoji in emojis {
            while let range = result.range(of: String(emoji)) {
                var end = range.upperBound
                while end < result.endIndex, result[end] == " " || result[end] == "\u{FE0F}" { end = result.index(after: end) }
                if let date = result[end...].prefixMatch(of: #/\d{4}-\d{2}-\d{2}/#) { end = date.range.upperBound }
                var start = range.lowerBound
                if start > result.startIndex, result[result.index(before: start)] == " " { start = result.index(before: start) }
                result.removeSubrange(start..<end)
            }
        }
        return result
    }

    /// Fügt ein Feld vor den Tags (Deadline) bzw. vor der Block-ID (Erledigt) ein.
    private static func inserting(_ field: String, into description: String, beforeTrailingTags: Bool) -> String {
        let index: String.Index
        if beforeTrailingTags {
            // Vor ✅ und vor den Tags am Ende einfügen.
            let trailing = trailingTokensStart(in: description)
            index = trailing
        } else if let match = description.firstMatch(of: #/\s+\^[A-Za-z0-9-]+\s*$/#) {
            index = match.range.lowerBound
        } else {
            index = description.endIndex
        }
        let head = description[..<index].trimmingCharacters(in: .whitespaces)
        let tail = description[index...].trimmingCharacters(in: .whitespaces)
        return [head, field, tail].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
