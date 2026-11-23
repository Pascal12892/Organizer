import Foundation
import Testing
@testable import OrganizerCore

@Suite("Wiederholungen")
struct RecurrenceTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        calendar.firstWeekday = 2
        return calendar
    }
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }
    func next(_ rule: String, after date: Date) -> Date? {
        RecurrenceRule(rule)?.next(after: date, calendar: calendar)
    }

    // MARK: - Regeln lesen

    @Test func parsesCommonRules() throws {
        #expect(RecurrenceRule("every day") == RecurrenceRule(frequency: .day))
        #expect(RecurrenceRule("every 3 days") == RecurrenceRule(frequency: .day, interval: 3))
        #expect(RecurrenceRule("every other week") == RecurrenceRule(frequency: .week, interval: 2))
        #expect(RecurrenceRule("every weekday") == RecurrenceRule(frequency: .week, weekdays: [2, 3, 4, 5, 6]))
        #expect(RecurrenceRule("Every Monday") == RecurrenceRule(frequency: .week, weekdays: [2]))
        #expect(RecurrenceRule("every week on Monday, Thursday") == RecurrenceRule(frequency: .week, weekdays: [2, 5]))
        #expect(RecurrenceRule("every month on the 15th") == RecurrenceRule(frequency: .month, monthDay: 15))
        #expect(RecurrenceRule("every month on the last") == RecurrenceRule(frequency: .month, monthDay: -1))
        #expect(RecurrenceRule("every year when done") == RecurrenceRule(frequency: .year, whenDone: true))
    }

    @Test func rejectsUnknownRules() {
        #expect(RecurrenceRule("jede Woche") == nil)
        #expect(RecurrenceRule("every") == nil)
        #expect(RecurrenceRule("every fortnight") == nil)
        #expect(RecurrenceRule("every week on Someday") == nil)
        #expect(RecurrenceRule("every 0 days") == nil)
    }

    // MARK: - Nächstes Datum

    @Test func simpleIntervals() {
        #expect(next("every day", after: day(2026, 11, 23)) == day(2026, 11, 24))
        #expect(next("every 2 weeks", after: day(2026, 11, 23)) == day(2026, 12, 7))
        #expect(next("every year", after: day(2026, 11, 23)) == day(2027, 11, 23))
    }

    @Test func monthEndIsClamped() {
        #expect(next("every month", after: day(2027, 1, 31)) == day(2027, 2, 28))
        #expect(next("every month on the last", after: day(2027, 1, 31)) == day(2027, 2, 28))
        #expect(next("every month on the 15th", after: day(2026, 11, 10)) == day(2026, 11, 15))
        #expect(next("every month on the 15th", after: day(2026, 11, 15)) == day(2026, 12, 15))
        #expect(next("every month on the 31st", after: day(2026, 11, 10)) == day(2026, 11, 30))
    }

    @Test func weekdays() {
        // 2026-11-20 ist ein Freitag.
        #expect(next("every weekday", after: day(2026, 11, 20)) == day(2026, 11, 23))
        #expect(next("every weekday", after: day(2026, 11, 23)) == day(2026, 11, 24))
        #expect(next("every week on Monday, Thursday", after: day(2026, 11, 23)) == day(2026, 11, 26))
        #expect(next("every week on Monday, Thursday", after: day(2026, 11, 26)) == day(2026, 11, 30))
        #expect(next("every 2 weeks on Monday", after: day(2026, 11, 23)) == day(2026, 12, 7))
    }

    // MARK: - Nächste Zeile

    @Test func nextOccurrenceShiftsAllDates() {
        let line = "- [x] Wäsche ⏫ 🔁 every week ⏳ 2026-11-19 📅 2026-11-20 #haushalt ✅ 2026-11-21 ^w1"
        let next = TaskLine.nextOccurrence(of: line, completedOn: day(2026, 11, 21), timeZone: berlin)
        #expect(next == "- [ ] Wäsche ⏫ 🔁 every week ⏳ 2026-11-26 📅 2026-11-27 #haushalt")
    }

    @Test func nextOccurrenceWhenDoneStartsFromCompletion() {
        let line = "- [ ] Haare schneiden 🔁 every 4 weeks when done 📅 2026-11-01"
        let next = TaskLine.nextOccurrence(of: line, completedOn: day(2026, 11, 23), timeZone: berlin)
        #expect(next == "- [ ] Haare schneiden 🔁 every 4 weeks when done 📅 2026-12-21")
    }

    @Test func nextOccurrenceWithoutDateGetsDue() {
        let line = "  - [ ] Pflanzen gießen 🔁 every 3 days #zuhause"
        let next = TaskLine.nextOccurrence(of: line, completedOn: day(2026, 11, 23), timeZone: berlin)
        #expect(next == "  - [ ] Pflanzen gießen 🔁 every 3 days 📅 2026-11-26 #zuhause")
    }

    @Test func nextOccurrenceResetsCreatedDate() {
        let line = "- [ ] Bericht 🔁 every month ➕ 2026-10-01 📅 2026-10-31"
        let next = TaskLine.nextOccurrence(of: line, completedOn: day(2026, 11, 2), timeZone: berlin)
        #expect(next == "- [ ] Bericht 🔁 every month ➕ 2026-11-02 📅 2026-11-30")
    }

    @Test func noOccurrenceWithoutRule() {
        #expect(TaskLine.nextOccurrence(of: "- [ ] Einmalig 📅 2026-11-20") == nil)
        #expect(TaskLine.nextOccurrence(of: "- [ ] Unklar 🔁 jede Woche 📅 2026-11-20") == nil)
    }

    @Test func recurrenceStopsBeforeTags() {
        #expect(TaskLine.parse("- [ ] Sport 🔁 every day #fit")?.recurrence == "every day")
    }

    // MARK: - Regel setzen und Status

    @Test func settingRecurrence() {
        #expect(TaskLine.setting("- [ ] A ⏫ 📅 2026-11-20 #uni", recurrence: "every week")
                == "- [ ] A ⏫ 🔁 every week 📅 2026-11-20 #uni")
        #expect(TaskLine.setting("- [ ] A 🔁 every day 📅 2026-11-20", recurrence: "every month")
                == "- [ ] A 🔁 every month 📅 2026-11-20")
        #expect(TaskLine.setting("- [ ] A 🔁 every day 📅 2026-11-20", recurrence: nil) == "- [ ] A 📅 2026-11-20")
        #expect(TaskLine.setting("- [ ] A 🔁 every day #uni", recurrence: nil) == "- [ ] A #uni")
        #expect(TaskLine.setting("- [ ] A", recurrence: "every year") == "- [ ] A 🔁 every year")
    }

    @Test func settingStatus() {
        let line = "- [ ] Aufgabe 📅 2026-11-20 #uni"
        #expect(TaskLine.setting(line, status: .inProgress) == "- [/] Aufgabe 📅 2026-11-20 #uni")
        let done = TaskLine.setting(line, status: .done, on: day(2026, 11, 23), timeZone: berlin)
        #expect(done == "- [x] Aufgabe 📅 2026-11-20 #uni ✅ 2026-11-23")
        #expect(TaskLine.setting(done, status: .open) == line)
        #expect(TaskLine.setting(done, status: .inProgress) == "- [/] Aufgabe 📅 2026-11-20 #uni")
    }

    // MARK: - Board

    @Test func boardGroupsByStatus() {
        let lines = [
            "- [ ] Offen 📅 2026-11-25 #uni",
            "- [ ] Früher fällig 📅 2026-11-24",
            "- [/] Läuft",
            "- [x] Gestern erledigt ✅ 2026-11-22",
            "- [x] Vor langer Zeit ✅ 2026-10-01",
            "- [x] Ohne Datum",
            "- [-] Abgebrochen",
        ]
        let tasks = lines.enumerated().compactMap { TaskLine.parse($1, lineNumber: $0, timeZone: berlin) }
        let board = TaskGrouping.board(tasks, now: day(2026, 11, 23), calendar: calendar)
        #expect(board[.open]?.map(\.title) == ["Früher fällig", "Offen"])
        #expect(board[.inProgress]?.map(\.title) == ["Läuft"])
        #expect(board[.done]?.map(\.title) == ["Gestern erledigt"])
    }
}
