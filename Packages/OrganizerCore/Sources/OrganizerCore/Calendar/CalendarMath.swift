import Foundation

/// Ansicht im Kalender.
public enum CalendarScope: String, CaseIterable, Sendable, Hashable, Codable {
    case day, week, month

    public var title: String {
        switch self {
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        }
    }
}

/// Ein Termin unabhängig von EventKit – damit Layout und Logik testbar bleiben.
public struct CalendarEventInfo: Identifiable, Sendable, Hashable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var location: String?
    public var notes: String?
    /// Teil einer Terminserie (beim Löschen wird gefragt: nur dieser oder alle zukünftigen).
    public var isRecurring: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                calendarID: String, location: String? = nil, notes: String? = nil, isRecurring: Bool = false) {
        self.isRecurring = isRecurring
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.location = location
        self.notes = notes
    }

    /// Berührt der Termin den Tag, der bei `dayStart` beginnt?
    public func overlaps(dayStart: Date, calendar: Calendar) -> Bool {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        // Ganztägige Termine enden um 0:00 des Folgetags; das zählt nicht mehr.
        return start < dayEnd && (end > dayStart || (end == start && start >= dayStart))
    }
}

public enum CalendarMath {
    /// Der Zeitraum, den eine Ansicht zeigt (Monat: komplette Wochen inkl. Rand).
    public static func interval(for scope: CalendarScope, containing date: Date, calendar: Calendar) -> DateInterval {
        switch scope {
        case .day:
            let start = calendar.startOfDay(for: date)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            let days = weekDays(containing: date, calendar: calendar)
            return DateInterval(start: days[0], end: calendar.date(byAdding: .day, value: 7, to: days[0])!)
        case .month:
            let days = monthGrid(containing: date, calendar: calendar)
            return DateInterval(start: days[0], end: calendar.date(byAdding: .day, value: 1, to: days.last!)!)
        }
    }

    /// Die 7 Tage der Woche, beginnend mit dem ersten Wochentag des Kalenders (in DE: Montag).
    public static func weekDays(containing date: Date, calendar: Calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: day)!
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// Alle Tage im Monatsraster: volle Wochen vom ersten bis zum letzten Monatstag.
    public static func monthGrid(containing date: Date, calendar: Calendar) -> [Date] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
        let first = weekDays(containing: monthStart, calendar: calendar)[0]
        let lastWeekStart = weekDays(containing: monthEnd, calendar: calendar)[0]
        let weeks = (calendar.dateComponents([.day], from: first, to: lastWeekStart).day! / 7) + 1
        return (0..<(weeks * 7)).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }

    /// Einen Schritt vor oder zurück in der jeweiligen Ansicht.
    public static func step(_ date: Date, scope: CalendarScope, by value: Int, calendar: Calendar) -> Date {
        let component: Calendar.Component = switch scope {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.date(byAdding: component, value: value, to: date)!
    }

    /// Überschrift wie in Apple Kalender, z. B. „November 2026“ oder „9. November 2026“.
    public static func title(for scope: CalendarScope, date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch scope {
        case .day:
            style = style.day().month(.wide).year()
        case .week, .month:
            style = style.month(.wide).year()
        }
        return date.formatted(style)
    }

    /// Termine eines Tages, ganztägige zuerst, sonst nach Beginn.
    public static func events(_ events: [CalendarEventInfo], on day: Date, calendar: Calendar) -> [CalendarEventInfo] {
        let dayStart = calendar.startOfDay(for: day)
        return events
            .filter { $0.overlaps(dayStart: dayStart, calendar: calendar) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.title) < ($1.isAllDay ? 0 : 1, $1.start, $1.title) }
    }

    /// Startzeit für einen Zeitblock an einer Stelle der Zeitleiste: `hours` Stunden nach Mitternacht,
    /// auf `step` Minuten abgerundet und so begrenzt, dass ein Block der Länge `duration` noch am selben Tag endet.
    public static func timeBlockStart(on day: Date, hours: Double, step: Int = 15, duration: TimeInterval = 3600,
                                      calendar: Calendar) -> Date {
        let step = max(step, 1)
        let latest = max(24 * 60 - Int(duration / 60), 0)
        let minutes = min(max(Int((max(hours, 0) * 60) / Double(step)) * step, 0), latest)
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
}

/// Position eines Termins in der Zeitleiste: Spalte bei Überschneidungen.
public struct TimelinePlacement: Sendable, Hashable {
    public let column: Int
    public let columnCount: Int

    public init(column: Int, columnCount: Int) {
        self.column = column
        self.columnCount = columnCount
    }
}

public enum TimelineLayout {
    /// Ordnet sich überschneidende Termine nebeneinander an, wie in Apple Kalender.
    /// Termine, die sich (auch indirekt) überschneiden, bilden eine Gruppe mit gleicher Spaltenzahl.
    public static func placements(for events: [CalendarEventInfo], minimumDuration: TimeInterval = 15 * 60) -> [String: TimelinePlacement] {
        let sorted = events.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [String: TimelinePlacement] = [:]
        var group: [(event: CalendarEventInfo, column: Int)] = []
        var columnEnds: [Date] = []
        var groupEnd = Date.distantPast

        func flush() {
            let count = max(columnEnds.count, 1)
            for item in group { result[item.event.id] = TimelinePlacement(column: item.column, columnCount: count) }
            group = []
            columnEnds = []
        }

        for event in sorted {
            let end = max(event.end, event.start.addingTimeInterval(minimumDuration))
            if event.start >= groupEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= event.start }) {
                columnEnds[free] = end
                group.append((event, free))
            } else {
                columnEnds.append(end)
                group.append((event, columnEnds.count - 1))
            }
            groupEnd = max(groupEnd, end)
        }
        flush()
        return result
    }
}
