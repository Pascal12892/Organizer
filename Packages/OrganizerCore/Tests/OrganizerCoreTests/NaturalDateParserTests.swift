import Foundation
import Testing
@testable import OrganizerCore

@Suite("Schnellerfassung")
struct NaturalDateParserTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Mittwoch, 11. November 2026, 10:00
    var now: Date { date(2026, 11, 11, 10) }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    func parse(_ text: String) -> ParsedCapture { NaturalDateParser.parse(text, now: now, calendar: calendar) }

    @Test(arguments: [
        ("Hausarbeit schreiben morgen", "Hausarbeit schreiben", 2026, 11, 12),
        ("übermorgen Wäsche", "Wäsche", 2026, 11, 13),
        ("Folien heute fertig", "Folien fertig", 2026, 11, 11),
        ("Abgabe bis Freitag", "Abgabe", 2026, 11, 13),
        ("Sport nächsten Mittwoch", "Sport", 2026, 11, 18),
        ("Planung nächste Woche", "Planung", 2026, 11, 16),
        ("Bericht Ende der Woche", "Bericht", 2026, 11, 13),
        ("Steuer in 3 Tagen", "Steuer", 2026, 11, 14),
        ("Arzt in zwei Wochen", "Arzt", 2026, 11, 25),
        ("Klausur am 20.11.", "Klausur", 2026, 11, 20),
        ("Urlaub 2.1.", "Urlaub", 2027, 1, 2),
        ("Prüfung 5.3.2027", "Prüfung", 2027, 3, 5),
        ("Geburtstag 24. Dezember", "Geburtstag", 2026, 12, 24),
        ("Release 2026-12-01", "Release", 2026, 12, 1),
        ("Rechnung nächsten Monat", "Rechnung", 2026, 12, 1),
    ])
    func recognisesDays(input: String, title: String, y: Int, m: Int, d: Int) {
        let result = parse(input)
        #expect(result.title == title)
        #expect(result.date == date(y, m, d))
        #expect(!result.hasTime)
    }

    @Test func recognisesTimes() {
        let meeting = parse("Lerngruppe Freitag 14 Uhr")
        #expect(meeting.title == "Lerngruppe")
        #expect(meeting.date == date(2026, 11, 13, 14))
        #expect(meeting.hasTime)

        #expect(parse("Call morgen um 9").date == date(2026, 11, 12, 9))
        #expect(parse("Essen 18.30 Uhr").date == date(2026, 11, 11, 18, 30))
        #expect(parse("Kino heute um 8 abends").date == date(2026, 11, 11, 20))
        #expect(parse("Telefonat 14:45").date == date(2026, 11, 11, 14, 45))
        // Schon vorbei → morgen
        #expect(parse("Joggen 7 Uhr").date == date(2026, 11, 12, 7))
    }

    @Test func keepsWordsThatOnlyLookLikeDates() {
        let result = parse("Morgens Kaffee kochen")
        #expect(result.title == "Kaffee kochen")
        #expect(result.date == date(2026, 11, 12, 9)) // „morgens“ = 9 Uhr, heute schon vorbei
        let plain = parse("Mittwochsrunde vorbereiten")
        #expect(plain.title == "Mittwochsrunde vorbereiten")
        #expect(plain.date == nil)
        #expect(parse("Kapitel 3.2 lesen").date == nil)
    }

    @Test func readsPriorityAndTags() {
        let result = parse("!! Hausarbeit #uni morgen")
        #expect(result.title == "Hausarbeit #uni")
        #expect(result.priority == .high)
        #expect(result.tags == ["uni"])
        #expect(parse("Wichtig !!!").priority == .highest)
        #expect(parse("Achtung! nicht vergessen").priority == .none)
    }
}
