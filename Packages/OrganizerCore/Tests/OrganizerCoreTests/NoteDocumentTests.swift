import Foundation
import Testing
@testable import OrganizerCore

@Suite("Notiz schreiben")
struct NoteDocumentTests {
    @Test(arguments: [
        "---\nbereich: Uni\n---\n# Titel\nText\n",
        "---\r\nbereich: Uni\r\n---\r\nZeile 1\r\nZeile 2",
        "Kein Frontmatter\n---\nText",
        "---\nkaputt\n# ohne Ende",
        "",
        "---\na: 1\n---",
    ])
    func roundTripIsLossless(raw: String) {
        #expect(NoteDocument(raw: raw).raw == raw)
    }

    @Test func editingBodyKeepsFrontmatterAndLineEndings() {
        var document = NoteDocument(raw: "---\r\nbereich:  Uni \r\n---\r\nAlt\r\n")
        #expect(document.body == "Alt\n")
        document.body = "Neu\nZweite\n"
        #expect(document.raw == "---\r\nbereich:  Uni \r\n---\r\nNeu\r\nZweite\r\n")
    }

    @Test func templateProducesParsableFrontmatter() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let date = try #require(OrganizerDateFormat.parse("2026-11-09T14:30", timeZone: berlin))
        let content = NoteTemplate.content(area: "Uni", topic: "Data Science", created: date, body: "Hallo", timeZone: berlin)
        #expect(content == "---\nbereich: Uni\nthema: Data Science\nerstellt: 2026-11-09T14:30\ntags: [uni, data-science]\n---\nHallo\n")

        let note = NoteFactory.makeNote(relativePath: "Inbox/x.md", url: URL(filePath: "/x"), content: content, modified: date, layout: VaultLayout())
        #expect(note.area == "Uni" && note.topic == "Data Science" && note.tags == ["uni", "data-science"])
    }

    @Test func templateQuotesWhenNeeded() throws {
        let content = NoteTemplate.content(area: "Arbeit", topic: "Projekt: Atlas", created: .now, body: "")
        #expect(content.contains("thema: \"Projekt: Atlas\""))
        let frontmatter = try #require(FrontmatterParser.parse(content).frontmatter)
        #expect(frontmatter.string("thema") == "Projekt: Atlas")
    }

    @Test func sanitizesFileNames() {
        #expect(NoteTemplate.fileName(for: "Kapitel 2: Regression / Teil #1") == "Kapitel 2- Regression - Teil -1")
        #expect(NoteTemplate.fileName(for: "  ...  ") == "Unbenannt")
        #expect(NoteTemplate.fileName(for: "Übung [3]") == "Übung -3-")
    }

    @Test func buildsObsidianURL() {
        let url = ObsidianURL.open(vaultName: "Mein Vault", relativePath: "Uni/Data Science/Vorlesung 1.md")
        #expect(url?.absoluteString == "obsidian://open?vault=Mein%20Vault&file=Uni%2FData%20Science%2FVorlesung%201")
    }
}
