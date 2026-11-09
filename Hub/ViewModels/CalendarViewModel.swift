import Foundation
import HubCore
import Observation

/// Zustand der Kalenderansicht: angezeigtes Datum, ausgewählter Tag und Termin.
@Observable
final class CalendarViewModel {
    /// Bestimmt, welcher Tag, welche Woche bzw. welcher Monat gezeigt wird.
    var date = Date.now
    var selectedDay = Calendar.current.startOfDay(for: .now)
    var selectedEventID: CalendarEventInfo.ID?
    /// Startzeit für „Neuer Termin“; nicht `nil` zeigt das Blatt.
    var newEventStart: Date?

    func goToToday() {
        date = .now
        selectedDay = Calendar.current.startOfDay(for: .now)
    }

    func step(_ value: Int, scope: CalendarScope) {
        date = CalendarMath.step(date, scope: scope, by: value, calendar: .current)
        selectedDay = Calendar.current.startOfDay(for: date)
    }

    /// Vorschlag für einen neuen Termin: am gewählten Tag zur nächsten vollen Stunde (heute) bzw. um 9 Uhr.
    func suggestedStart(on day: Date? = nil) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day ?? selectedDay)
        if calendar.isDateInToday(day) {
            let next = calendar.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)!
            return calendar.isDate(next, inSameDayAs: day) ? next : day.addingTimeInterval(9 * 3600)
        }
        return day.addingTimeInterval(9 * 3600)
    }
}
