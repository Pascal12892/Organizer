import Foundation
import Testing
@testable import OrganizerCore

@Suite("Kalender")
struct CalendarMathTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2 // Montag
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func weekStartsOnMonday() {
        let days = CalendarMath.weekDays(containing: date(2026, 11, 12, 15), calendar: calendar)
        #expect(days.first == date(2026, 11, 9))
        #expect(days.last == date(2026, 11, 15))
    }

    @Test func monthGridCoversFullWeeks() {
        // November 2026: 1. ist ein Sonntag, 30. ein Montag → 27.10. bis 6.12. = 6 Wochen
        let grid = CalendarMath.monthGrid(containing: date(2026, 11, 9), calendar: calendar)
        #expect(grid.count == 42)
        #expect(grid.first == date(2026, 10, 26))
        #expect(grid.last == date(2026, 12, 6))
        // Februar 2027 beginnt Montag und hat genau 4 Wochen
        #expect(CalendarMath.monthGrid(containing: date(2027, 2, 10), calendar: calendar).count == 28)
    }

    @Test func intervalsAndSteps() {
        let week = CalendarMath.interval(for: .week, containing: date(2026, 11, 9, 10), calendar: calendar)
        #expect(week.start == date(2026, 11, 9) && week.end == date(2026, 11, 16))
        #expect(CalendarMath.step(date(2026, 1, 31), scope: .month, by: 1, calendar: calendar) == date(2026, 2, 28))
        #expect(CalendarMath.title(for: .month, date: date(2026, 11, 9), calendar: calendar, locale: Locale(identifier: "de_DE")) == "November 2026")
    }

    @Test func allDayEventDoesNotSpillIntoNextDay() {
        let event = CalendarEventInfo(id: "a", title: "Ganztag", start: date(2026, 11, 9), end: date(2026, 11, 10), isAllDay: true, calendarID: "c")
        #expect(event.overlaps(dayStart: date(2026, 11, 9), calendar: calendar))
        #expect(!event.overlaps(dayStart: date(2026, 11, 10), calendar: calendar))
        let overnight = CalendarEventInfo(id: "b", title: "Nacht", start: date(2026, 11, 9, 22), end: date(2026, 11, 10, 2), calendarID: "c")
        #expect(overnight.overlaps(dayStart: date(2026, 11, 10), calendar: calendar))
    }

    @Test func sortsAllDayFirst() {
        let events = [
            CalendarEventInfo(id: "1", title: "Spät", start: date(2026, 11, 9, 15), end: date(2026, 11, 9, 16), calendarID: "c"),
            CalendarEventInfo(id: "2", title: "Ganztag", start: date(2026, 11, 9), end: date(2026, 11, 10), isAllDay: true, calendarID: "c"),
            CalendarEventInfo(id: "3", title: "Früh", start: date(2026, 11, 9, 8), end: date(2026, 11, 9, 9), calendarID: "c"),
        ]
        #expect(CalendarMath.events(events, on: date(2026, 11, 9), calendar: calendar).map(\.id) == ["2", "3", "1"])
    }

    @Test func overlappingEventsShareColumns() {
        func event(_ id: String, _ startHour: Int, _ endHour: Int) -> CalendarEventInfo {
            CalendarEventInfo(id: id, title: id, start: date(2026, 11, 9, startHour), end: date(2026, 11, 9, endHour), calendarID: "c")
        }
        let placements = TimelineLayout.placements(for: [
            event("a", 9, 11), event("b", 10, 12), event("c", 11, 13), event("d", 14, 15),
        ])
        #expect(placements["a"] == TimelinePlacement(column: 0, columnCount: 2))
        #expect(placements["b"] == TimelinePlacement(column: 1, columnCount: 2))
        #expect(placements["c"] == TimelinePlacement(column: 0, columnCount: 2))
        #expect(placements["d"] == TimelinePlacement(column: 0, columnCount: 1))
    }

    @Test func timeBlockSnapsToQuarterHours() {
        let day = date(2026, 11, 23)
        #expect(CalendarMath.timeBlockStart(on: day, hours: 9.4, calendar: calendar) == date(2026, 11, 23, 9, 15))
        #expect(CalendarMath.timeBlockStart(on: day, hours: 14, calendar: calendar) == date(2026, 11, 23, 14))
        #expect(CalendarMath.timeBlockStart(on: day, hours: -1, calendar: calendar) == date(2026, 11, 23))
        // Ganz unten: der Block endet noch vor Mitternacht.
        #expect(CalendarMath.timeBlockStart(on: day, hours: 23.9, calendar: calendar) == date(2026, 11, 23, 23))
        #expect(CalendarMath.timeBlockStart(on: day, hours: 23.9, duration: 1800, calendar: calendar) == date(2026, 11, 23, 23, 30))
    }
}
