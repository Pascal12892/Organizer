import Foundation

/// Datumsformate, wie sie im Frontmatter stehen (`2026-11-09T14:30`).
public enum OrganizerDateFormat {
    private static let formats = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
    ]

    /// Liest ein Datum in lokaler Zeit. ISO-8601 mit Zeitzone wird ebenfalls akzeptiert.
    public static func parse(_ string: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let date = fastParse(trimmed, timeZone: timeZone) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// Schneller Weg für die häufigen Formate `YYYY-MM-DD` und `YYYY-MM-DDTHH:MM(:SS)` ohne DateFormatter
    /// (dessen Erzeugung ist teuer und lief vorher für jede Aufgabe).
    static func fastParse(_ text: String, timeZone: TimeZone) -> Date? {
        let bytes = Array(text.utf8)
        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[range] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard bytes.count >= 10, bytes[4] == 45, bytes[7] == 45,
              let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents(year: year, month: month, day: day)
        if bytes.count > 10 {
            guard bytes.count == 16 || bytes.count == 19, bytes[10] == 84 || bytes[10] == 32, bytes[13] == 58,
                  let hour = number(11..<13), let minute = number(14..<16), hour < 24, minute < 60 else { return nil }
            components.hour = hour
            components.minute = minute
            if bytes.count == 19 {
                guard bytes[16] == 58, let second = number(17..<19) else { return nil }
                components.second = second
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil } // 31.02. o. Ä. ablehnen
        return date
    }

    /// Schreibt ein Datum so, wie Organizer es im Frontmatter ablegt.
    public static func string(from date: Date, includingTime: Bool = true, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = includingTime ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
