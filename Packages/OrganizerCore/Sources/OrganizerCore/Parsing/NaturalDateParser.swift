import Foundation

/// Ergebnis der Schnellerfassung: bereinigter Text plus erkanntes Datum, Uhrzeit und Priorität.
public struct ParsedCapture: Sendable, Hashable {
    public var title: String
    public var date: Date?
    /// `true`, wenn eine Uhrzeit angegeben war (sonst ist `date` Tagesbeginn).
    public var hasTime: Bool
    public var priority: TaskPriority
    public var tags: [String]
}

/// Versteht deutsche Zeitangaben in freiem Text:
/// „heute“, „morgen“, „übermorgen“, „Freitag“, „nächsten Montag“, „nächste Woche“, „Ende der Woche“,
/// „in 3 Tagen“, „in zwei Wochen“, „20.11.“, „20.11.2026“, „20. November“, „2026-11-20“,
/// „14 Uhr“, „um 9“, „14:30“, „18.30 Uhr“, „abends“ – dazu `!`/`!!`/`!!!` als Priorität.
public enum NaturalDateParser {
    private static let weekdays = ["sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6, "samstag": 7]
    private static let months = ["januar": 1, "jänner": 1, "februar": 2, "märz": 3, "maerz": 3, "april": 4, "mai": 5, "juni": 6,
                                 "juli": 7, "august": 8, "september": 9, "oktober": 10, "november": 11, "dezember": 12]
    private static let numberWords = ["ein": 1, "einem": 1, "einer": 1, "eine": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
                                      "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10]
    /// Wörter vor einer Zeitangabe, die mit entfernt werden („bis Freitag“).
    private static let lead = #"(?:(?:bis|am|ab|zum|für|fuer|spätestens|spaetestens|bis zum|bis spätestens)\s+)?"#

    public static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> ParsedCapture {
        let text = NSMutableString(string: input)
        let today = calendar.startOfDay(for: now)
        var day: Date?
        var time: (hour: Int, minute: Int)?
        var evening = false

        /// Sucht das erste Vorkommen, entfernt es und liefert die Gruppen.
        func take(_ pattern: String) -> [String?]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
            let groups = (0..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : text.substring(with: range)
            }
            text.replaceCharacters(in: match.range, with: " ")
            return groups
        }

        func number(_ word: String) -> Int? { Int(word) ?? numberWords[word.lowercased()] }

        func nextOccurrence(month: Int, day dayOfMonth: Int, year: Int?) -> Date? {
            if let year { return calendar.date(from: DateComponents(year: year < 100 ? 2000 + year : year, month: month, day: dayOfMonth)) }
            let thisYear = calendar.component(.year, from: today)
            guard let candidate = calendar.date(from: DateComponents(year: thisYear, month: month, day: dayOfMonth)) else { return nil }
            return candidate < today ? calendar.date(byAdding: .year, value: 1, to: candidate) : candidate
        }

        // Priorität: !, !! oder !!! als eigenes Wort
        var priority = TaskPriority.none
        if let groups = take(#"(?:^|\s)(!{1,3})(?=\s|$)"#), let marks = groups[1] {
            priority = marks.count >= 3 ? .highest : (marks.count == 2 ? .high : .medium)
        }

        // Feste Daten zuerst, damit „20.11.“ nicht als Uhrzeit gilt.
        if let g = take(#"\b"# + lead + #"(\d{4})-(\d{2})-(\d{2})\b"#) {
            day = calendar.date(from: DateComponents(year: Int(g[1]!), month: Int(g[2]!), day: Int(g[3]!)))
        } else if let g = take(#"\b"# + lead + #"(\d{1,2})\.(\d{1,2})\.(\d{2,4})?(?!\d)"#) {
            day = nextOccurrence(month: Int(g[2]!)!, day: Int(g[1]!)!, year: g[3].flatMap { Int($0) })
        } else if let g = take(#"\b"# + lead + #"(\d{1,2})\.?\s*(januar|jänner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember)(?:\s+(\d{4}))?\b"#) {
            day = nextOccurrence(month: months[g[2]!.lowercased()]!, day: Int(g[1]!)!, year: g[3].flatMap { Int($0) })
        } else if take(#"\b"# + lead + #"übermorgen\b"#) != nil || take(#"\b"# + lead + #"uebermorgen\b"#) != nil {
            day = calendar.date(byAdding: .day, value: 2, to: today)
        } else if take(#"\b"# + lead + #"morgen(?!s)\b"#) != nil {
            day = calendar.date(byAdding: .day, value: 1, to: today)
        } else if take(#"\b"# + lead + #"heute\b"#) != nil {
            day = today
        } else if let g = take(#"\b"# + lead + #"in\s+(\d+|ein|einem|einer|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn)\s+(tag|tagen|woche|wochen|monat|monaten)\b"#) {
            let amount = number(g[1]!) ?? 1
            let unit = g[2]!.lowercased()
            let component: Calendar.Component = unit.hasPrefix("tag") ? .day : (unit.hasPrefix("woche") ? .weekOfYear : .month)
            day = calendar.date(byAdding: component, value: amount, to: today)
        } else if take(#"\b"# + lead + #"(?:nächste|naechste|kommende)\s+woche\b"#) != nil {
            day = calendar.nextDate(after: today, matching: DateComponents(weekday: calendar.firstWeekday), matchingPolicy: .nextTime)
        } else if take(#"\b"# + lead + #"(?:ende\s+der\s+woche|wochenende)\b"#) != nil {
            let friday = calendar.nextDate(after: calendar.date(byAdding: .day, value: -1, to: today)!, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)
            day = friday
        } else if take(#"\b"# + lead + #"(?:nächsten|naechsten|kommenden)\s+monat\b"#) != nil {
            let next = calendar.date(byAdding: .month, value: 1, to: today)!
            day = calendar.date(from: calendar.dateComponents([.year, .month], from: next))
        } else if let g = take(#"\b"# + lead + #"(?:(?:nächsten|naechsten|kommenden|diesen)\s+)?(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\b"#) {
            // Immer der nächste solche Tag nach heute.
            day = calendar.nextDate(after: today, matching: DateComponents(weekday: weekdays[g[1]!.lowercased()]!), matchingPolicy: .nextTime)
        }

        // Uhrzeit
        if let g = take(#"\b(?:um\s+)?(\d{1,2}):(\d{2})(?:\s*uhr)?\b"#) ?? take(#"\b(?:um\s+)?(\d{1,2})\.(\d{2})\s*uhr\b"#) {
            time = (Int(g[1]!)!, Int(g[2]!)!)
        } else if let g = take(#"\b(?:um\s+)?(\d{1,2})\s*uhr\b"#) ?? take(#"\bum\s+(\d{1,2})\b"#) {
            time = (Int(g[1]!)!, 0)
        }
        if take(#"\b(?:abends|nachmittags|am abend|am nachmittag)\b"#) != nil { evening = true }
        if take(#"\b(?:morgens|vormittags|früh|frueh)\b"#) != nil, time == nil { time = (9, 0) }

        var date = day
        var hasTime = false
        if var time, (0...24).contains(time.hour), (0...59).contains(time.minute) {
            if evening, time.hour < 12 { time.hour += 12 }
            var base = day ?? today
            var candidate = calendar.date(bySettingHour: time.hour % 24, minute: time.minute, second: 0, of: base)!
            if day == nil, candidate <= now {
                // Nur eine Uhrzeit, die heute schon vorbei ist → morgen.
                base = calendar.date(byAdding: .day, value: 1, to: today)!
                candidate = calendar.date(bySettingHour: time.hour % 24, minute: time.minute, second: 0, of: base)!
            }
            date = candidate
            hasTime = true
        }

        let title = (text as String)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;-–")))
        return ParsedCapture(
            title: title,
            date: date,
            hasTime: hasTime,
            priority: priority,
            tags: TagExtractor.deduplicated(TagExtractor.inlineTags(in: title))
        )
    }
}
