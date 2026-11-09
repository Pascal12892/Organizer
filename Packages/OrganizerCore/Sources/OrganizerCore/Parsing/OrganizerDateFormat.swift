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

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
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
