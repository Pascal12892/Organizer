import Foundation
import Testing
@testable import OrganizerCore

@Suite("Frontmatter")
struct FrontmatterParserTests {
    @Test func parsesOrganizerFrontmatter() throws {
        let text = """
        ---
        bereich: Uni
        thema: Data Science
        erstellt: 2026-11-09T14:30
        tags: [uni, data-science]
        ---
        # Vorlesung 1
        Inhalt
        """
        let result = FrontmatterParser.parse(text)
        let frontmatter = try #require(result.frontmatter)
        #expect(frontmatter.string("bereich") == "Uni")
        #expect(frontmatter.string("thema") == "Data Science")
        #expect(frontmatter.string("erstellt") == "2026-11-09T14:30")
        #expect(frontmatter["tags"] == .list(["uni", "data-science"]))
        #expect(result.body == "# Vorlesung 1\nInhalt")
        #expect(result.bodyStartLine == 6)
        #expect(result.issues.isEmpty)
    }

    @Test func keepsEntryOrder() throws {
        let result = FrontmatterParser.parse("---\nz: 1\na: 2\nm: 3\n---\n")
        #expect(try #require(result.frontmatter).entries.map(\.key) == ["z", "a", "m"])
    }

    @Test func parsesBlockList() throws {
        let text = """
        ---
        tags:
          - uni
          - "data science"
        aliases:
        - Erste
        titel: Test
        ---
        """
        let frontmatter = try #require(FrontmatterParser.parse(text).frontmatter)
        #expect(frontmatter["tags"] == .list(["uni", "data science"]))
        #expect(frontmatter["aliases"] == .list(["Erste"]))
        #expect(frontmatter.string("titel") == "Test")
    }

    @Test func emptyValueWithoutListStaysEmptyString() throws {
        let frontmatter = try #require(FrontmatterParser.parse("---\nthema:\nbereich: Uni\n---\n").frontmatter)
        #expect(frontmatter["thema"] == .string(""))
        #expect(frontmatter.string("thema") == nil)
        #expect(frontmatter.string("bereich") == "Uni")
    }

    @Test func unquotesValues() throws {
        let text = """
        ---
        a: "Mit: Doppelpunkt"
        b: 'It''s'
        c: "Sag \\"Hallo\\""
        d: [ "x, y", 'z' ]
        ---
        """
        let frontmatter = try #require(FrontmatterParser.parse(text).frontmatter)
        #expect(frontmatter.string("a") == "Mit: Doppelpunkt")
        #expect(frontmatter.string("b") == "It's")
        #expect(frontmatter.string("c") == "Sag \"Hallo\"")
        #expect(frontmatter["d"] == .list(["x, y", "z"]))
    }

    @Test func keyLookupIgnoresCase() throws {
        let frontmatter = try #require(FrontmatterParser.parse("---\nBereich: Arbeit\n---").frontmatter)
        #expect(frontmatter.string("bereich") == "Arbeit")
    }

    @Test func noFrontmatterReturnsWholeText() {
        let result = FrontmatterParser.parse("# Titel\n---\nText")
        #expect(result.frontmatter == nil)
        #expect(result.body == "# Titel\n---\nText")
        #expect(result.bodyStartLine == 0)
    }

    @Test func unterminatedFrontmatterIsReported() {
        let result = FrontmatterParser.parse("---\nbereich: Uni\n# Titel")
        #expect(result.frontmatter == nil)
        #expect(result.body == "---\nbereich: Uni\n# Titel")
        #expect(result.issues.count == 1)
    }

    @Test func handlesWindowsLineEndingsAndBOM() throws {
        let result = FrontmatterParser.parse("\u{FEFF}---\r\nbereich: Uni\r\n---\r\nText\r\n")
        #expect(try #require(result.frontmatter).string("bereich") == "Uni")
        #expect(result.body == "Text\n")
    }

    @Test func skipsNestedStructuresAndComments() throws {
        let text = """
        ---
        # Kommentar
        meta:
          autor: Ich
        bereich: Uni
        ---
        """
        let result = FrontmatterParser.parse(text)
        let frontmatter = try #require(result.frontmatter)
        #expect(frontmatter.string("bereich") == "Uni")
        #expect(result.issues.isEmpty)
    }

    @Test func reportsUnreadableLines() {
        let result = FrontmatterParser.parse("---\nnur text\nbereich: Uni\n---")
        #expect(result.issues.count == 1)
        #expect(result.frontmatter?.string("bereich") == "Uni")
    }

    @Test func parsesDates() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let date = try #require(OrganizerDateFormat.parse("2026-11-09T14:30", timeZone: berlin))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 9 && parts.hour == 14 && parts.minute == 30)
        #expect(OrganizerDateFormat.parse("2026-11-09", timeZone: berlin) != nil)
        #expect(OrganizerDateFormat.parse("gestern") == nil)
        #expect(OrganizerDateFormat.string(from: date, timeZone: berlin) == "2026-11-09T14:30")
    }
}
