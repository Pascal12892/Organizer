import Foundation

/// Wiederholungsregel im Format des Obsidian-Plugins „Tasks“ (`🔁 every week on Monday`).
///
/// Verstanden wird die gängige Teilmenge:
/// `every day`, `every 3 days`, `every other week`, `every weekday`, `every Monday`,
/// `every week on Monday, Thursday`, `every 2 weeks on Friday`, `every month`, `every month on the 15th`,
/// `every month on the last`, `every year`, jeweils optional mit `when done`.
/// Die Regel bleibt englisch, damit Obsidian sie weiterhin versteht.
public struct RecurrenceRule: Sendable, Hashable {
    public enum Frequency: Sendable, Hashable { case day, week, month, year }

    public var frequency: Frequency
    public var interval: Int
    /// Wochentage wie in `Calendar` (1 = Sonntag … 7 = Samstag). Leer = wie das Ausgangsdatum.
    public var weekdays: Set<Int>
    /// Tag im Monat; `-1` steht für den letzten Tag.
    public var monthDay: Int?
    /// `when done`: vom Erledigt-Datum aus rechnen statt vom Fälligkeitsdatum.
    public var whenDone: Bool

    public init(frequency: Frequency, interval: Int = 1, weekdays: Set<Int> = [], monthDay: Int? = nil, whenDone: Bool = false) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = weekdays
        self.monthDay = monthDay
        self.whenDone = whenDone
    }

    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
    ]

    /// Gibt `nil` zurück, wenn die Regel nicht verstanden wird. Dann bleibt das Abhaken wie bisher.
    public init?(_ text: String) {
        var words = text.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard words.first == "every" else { return nil }
        words.removeFirst()

        var whenDone = false
        if Array(words.suffix(2)) == ["when", "done"] {
            whenDone = true
            words.removeLast(2)
        }
        guard !words.isEmpty else { return nil }

        var interval = 1
        if let number = Int(words[0]) {
            interval = number
            words.removeFirst()
        } else if words[0] == "other" {
            interval = 2
            words.removeFirst()
        }
        guard interval > 0, let unit = words.first else { return nil }
        words.removeFirst()

        // `every weekday` und `every Monday` sind Kurzformen für wöchentliche Regeln.
        if unit == "weekday" || unit == "weekdays" {
            guard words.isEmpty else { return nil }
            self.init(frequency: .week, interval: interval, weekdays: [2, 3, 4, 5, 6], whenDone: whenDone)
            return
        }
        if let day = Self.weekdayNames[Self.singular(unit)] {
            guard let more = Self.weekdays(in: words) else { return nil }
            self.init(frequency: .week, interval: interval, weekdays: more.union([day]), whenDone: whenDone)
            return
        }

        let frequency: Frequency
        switch Self.singular(unit) {
        case "day": frequency = .day
        case "week": frequency = .week
        case "month": frequency = .month
        case "year": frequency = .year
        default: return nil
        }

        var weekdays: Set<Int> = []
        var monthDay: Int?
        if !words.isEmpty {
            guard words.removeFirst() == "on" else { return nil }
            switch frequency {
            case .week:
                guard let days = Self.weekdays(in: words), !days.isEmpty else { return nil }
                weekdays = days
            case .month:
                words.removeAll { $0 == "the" || $0 == "day" }
                guard words.count == 1 else { return nil }
                if words[0] == "last" {
                    monthDay = -1
                } else {
                    let digits = words[0].prefix { $0.isNumber }
                    guard let day = Int(digits), (1...31).contains(day) else { return nil }
                    monthDay = day
                }
            case .day, .year:
                return nil
            }
        }
        self.init(frequency: frequency, interval: interval, weekdays: weekdays, monthDay: monthDay, whenDone: whenDone)
    }

    private static func singular(_ word: String) -> String {
        word.hasSuffix("s") ? String(word.dropLast()) : word
    }

    /// Liest „monday tuesday and friday“. `nil`, wenn ein Wort kein Wochentag ist.
    private static func weekdays(in words: [String]) -> Set<Int>? {
        var result: Set<Int> = []
        for word in words where word != "and" {
            guard let day = weekdayNames[singular(word)] ?? weekdayNames[word] else { return nil }
            result.insert(day)
        }
        return result
    }

    /// Nächster Termin strikt nach `base` (nur das Datum zählt, nicht die Uhrzeit).
    public func next(after base: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: base)
        func adding(_ component: Calendar.Component, _ value: Int, to date: Date) -> Date {
            calendar.date(byAdding: component, value: value, to: date) ?? date
        }

        switch frequency {
        case .day:
            return adding(.day, interval, to: start)

        case .year:
            return adding(.year, interval, to: start)

        case .week:
            guard !weekdays.isEmpty else { return adding(.weekOfYear, interval, to: start) }
            // Erst die restlichen Tage dieser Woche, dann die Woche im Abstand `interval`.
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            var day = adding(.day, 1, to: start)
            while day < adding(.day, 7, to: weekStart) {
                if weekdays.contains(calendar.component(.weekday, from: day)) { return day }
                day = adding(.day, 1, to: day)
            }
            let nextWeek = adding(.weekOfYear, interval, to: weekStart)
            for offset in 0..<7 {
                let candidate = adding(.day, offset, to: nextWeek)
                if weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
            }
            return nextWeek

        case .month:
            // Ohne Tag: gleicher Tag im Folgemonat, bei kürzeren Monaten der letzte Tag.
            guard let monthDay else { return adding(.month, interval, to: start) }
            if let sameMonth = day(monthDay, inMonthOf: start, calendar: calendar), sameMonth > start {
                return sameMonth
            }
            let monthStart = calendar.dateInterval(of: .month, for: start)?.start ?? start
            let target = adding(.month, interval, to: monthStart)
            return day(monthDay, inMonthOf: target, calendar: calendar) ?? target
        }
    }

    /// Tag `monthDay` im Monat von `date`; zu große Tage werden auf den Monatsletzten gekürzt.
    private func day(_ monthDay: Int, inMonthOf date: Date, calendar: Calendar) -> Date? {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let length = calendar.range(of: .day, in: .month, for: date)?.count else { return nil }
        let day = monthDay == -1 ? length : min(monthDay, length)
        return calendar.date(byAdding: .day, value: day - 1, to: month.start)
    }
}
