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
    static let fieldByEmoji: [Character: String] = Dictionary(
        dateFieldEmojis.flatMap { field, emojis in emojis.map { ($0, field) } },
        uniquingKeysWith: { first, _ in first }
    )
    static let priorityEmojis: Set<Character> = ["🔺", "⏫", "🔼", "🔽", "⏬"]
    static let metadataEmojis: Set<Character> = priorityEmojis
        .union(dateFieldEmojis.values.flatMap { $0 })
        .union(["🔁"])

    // MARK: - Lesen

    public static func parts(of line: String) -> Parts? {
        guard let match = line.wholeMatch(of: Patterns.taskLine) else { return nil }
        return Parts(prefix: String(match.output.1), status: TaskStatus(match.output.2.first!), description: String(match.output.3))
    }

    /// Erkennt eine Aufgabe. Gibt `nil` zurück, wenn die Zeile keine Checkbox ist.
    public static func parse(_ line: String, relativePath: String = "", lineNumber: Int = 0,
                             timeZone: TimeZone = .current) -> TaskItem? {
        guard let parts = parts(of: line) else { return nil }
        let description = parts.description

        // Einmal durch die Zeile: alle Emoji-Felder mit folgendem Datum einsammeln.
        var dates: [String: Date] = [:]
        var index = description.startIndex
        while index < description.endIndex {
            let character = description[index]
            index = description.index(after: index)
            guard metadataEmojis.contains(character), let field = fieldByEmoji[character], dates[field] == nil else { continue }
            let rest = description[index...].drop { $0 == "\u{FE0F}" || $0 == " " }
            let candidate = String(rest.prefix(10))
            if let date = OrganizerDateFormat.fastParse(candidate, timeZone: timeZone) {
                dates[field] = date
            }
        }
        func date(_ field: String) -> Date? { dates[field] }

        let priority = description.compactMap { TaskPriority(emoji: $0) }.first ?? .none
        var recurrence: String?
        if let range = description.range(of: "🔁") {
            let rest = description[range.upperBound...]
            // Die Regel endet am nächsten Emoji-Feld oder an den Tags am Zeilenende.
            let emojiEnd = rest.firstIndex { metadataEmojis.contains($0) } ?? rest.endIndex
            let end = min(emojiEnd, max(trailingTokensStart(in: description), range.upperBound))
            let text = description[range.upperBound..<end].trimmingCharacters(in: .whitespaces)
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
        let pattern = Patterns.trailingTaskTokens
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

    /// Wiederholung setzen (`every week`) oder entfernen (`nil`). Steht wie im Tasks-Plugin vor den Datumsfeldern.
    public static func setting(_ line: String, recurrence: String?) -> String {
        guard let parts = parts(of: line) else { return line }
        var description = parts.description
        if let range = description.range(of: "🔁") {
            let rest = description[range.upperBound...]
            let emojiEnd = rest.firstIndex { metadataEmojis.contains($0) } ?? description.endIndex
            let end = max(min(emojiEnd, trailingTokensStart(in: description)), range.upperBound)
            let offset = description.distance(from: description.startIndex, to: range.lowerBound)
            description.removeSubrange(range.lowerBound..<end)
            // Zwei Leerzeichen an der Schnittstelle zu einem machen, den Rest der Zeile nicht anfassen.
            let cut = description.index(description.startIndex, offsetBy: offset)
            if cut > description.startIndex, cut < description.endIndex,
               description[description.index(before: cut)] == " ", description[cut] == " " {
                description.remove(at: cut)
            }
        }
        if let rule = recurrence?.trimmingCharacters(in: .whitespaces), !rule.isEmpty {
            let dateEmojis = Set(dateFieldEmojis.values.flatMap { $0 })
            let index = min(description.firstIndex { dateEmojis.contains($0) } ?? description.endIndex,
                            trailingTokensStart(in: description))
            let head = description[..<index].trimmingCharacters(in: .whitespaces)
            let tail = description[index...].trimmingCharacters(in: .whitespaces)
            description = [head, "🔁 " + rule, tail].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return rebuild(parts, description: description.trimmingCharacters(in: .whitespaces))
    }

    /// Status direkt setzen (offen, in Arbeit, erledigt, abgebrochen), z. B. beim Verschieben im Board.
    /// Erledigt bekommt `✅ Datum`, alle anderen Status verlieren es wieder.
    public static func setting(_ line: String, status: TaskStatus, on date: Date = .now, timeZone: TimeZone = .current) -> String {
        guard var parts = parts(of: line) else { return line }
        if status == .done { return setting(line, done: true, on: date, timeZone: timeZone) }
        parts.status = status
        return rebuild(parts, description: removingField(["✅"], from: parts.description))
    }

    /// Die nächste Wiederholung einer Aufgabe mit `🔁`, wie das Tasks-Plugin sie beim Abhaken anlegt:
    /// offen, Fälligkeit, Geplant und Start um denselben Abstand verschoben, ohne Erledigt-Datum und Block-ID.
    /// `nil`, wenn die Zeile keine verständliche Wiederholung hat.
    public static func nextOccurrence(of line: String, completedOn: Date = .now, timeZone: TimeZone = .current) -> String? {
        guard let task = parse(line, timeZone: timeZone), let text = task.recurrence,
              let rule = RecurrenceRule(text), var parts = parts(of: line) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = Calendar.current.firstWeekday

        let completed = calendar.startOfDay(for: completedOn)
        let reference = task.due ?? task.scheduled ?? task.start
        var description = removingField(["✅", "❌"], from: parts.description)
        if let match = description.firstMatch(of: Patterns.blockID) {
            description.removeSubrange(match.range)
        }
        func string(_ date: Date) -> String {
            OrganizerDateFormat.string(from: date, includingTime: false, timeZone: timeZone)
        }

        if let reference {
            let base = rule.whenDone ? completed : calendar.startOfDay(for: reference)
            let next = rule.next(after: base, calendar: calendar)
            let shift = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: next).day ?? 0
            for field in ["due", "scheduled", "start"] {
                guard let emojis = dateFieldEmojis[field] else { continue }
                description = replacingDate(of: emojis, in: description, timeZone: timeZone) { old in
                    calendar.date(byAdding: .day, value: shift, to: old).map(string)
                }
            }
        } else {
            // Ohne Datum bekommt die Wiederholung eine Fälligkeit, sonst wäre sie von der alten nicht zu unterscheiden.
            let next = rule.next(after: completed, calendar: calendar)
            description = inserting("📅 " + string(next), into: description, beforeTrailingTags: true)
        }
        // Erstellt-Datum auf heute, wie im Tasks-Plugin.
        description = replacingDate(of: dateFieldEmojis["created"] ?? [], in: description, timeZone: timeZone) { _ in string(completed) }

        parts.status = .open
        return rebuild(parts, description: description.trimmingCharacters(in: .whitespaces))
    }

    /// Ersetzt das Datum hinter dem ersten passenden Emoji an Ort und Stelle.
    private static func replacingDate(of emojis: [Character], in description: String, timeZone: TimeZone,
                                      _ transform: (Date) -> String?) -> String {
        var result = description
        for emoji in emojis {
            guard let range = result.range(of: String(emoji)) else { continue }
            var start = range.upperBound
            while start < result.endIndex, result[start] == " " || result[start] == "\u{FE0F}" { start = result.index(after: start) }
            guard let match = result[start...].prefixMatch(of: Patterns.isoDate),
                  let old = OrganizerDateFormat.fastParse(String(result[match.range]), timeZone: timeZone),
                  let replacement = transform(old) else { continue }
            result.replaceSubrange(match.range, with: replacement)
            return result
        }
        return result
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
                if let date = result[end...].prefixMatch(of: Patterns.isoDate) { end = date.range.upperBound }
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
        } else if let match = description.firstMatch(of: Patterns.blockID) {
            index = match.range.lowerBound
        } else {
            index = description.endIndex
        }
        let head = description[..<index].trimmingCharacters(in: .whitespaces)
        let tail = description[index...].trimmingCharacters(in: .whitespaces)
        return [head, field, tail].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
