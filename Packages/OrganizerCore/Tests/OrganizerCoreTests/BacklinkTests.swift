import Foundation
import Testing
@testable import OrganizerCore

@Suite("Rückverweise")
struct BacklinkTests {
    func note(_ path: String, _ body: String, bodyStartLine: Int = 0) -> Note {
        Note(relativePath: path, url: URL(fileURLWithPath: "/v/" + path),
             title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
             tags: [], modified: .now, body: body, excerpt: "", issues: [], bodyStartLine: bodyStartLine)
    }

    @Test func findsNotesAndTasksLinkingToANote() throws {
        let notes = [
            note("Uni/Gliederung.md", "# Gliederung\nSiehe [[Gliederung]] selbst"),
            note("Uni/Hausarbeit.md", "## Plan\n- [ ] Kapitel 2 nach [[Gliederung]] ⏫ 📅 2026-11-30\nText mit [[Uni/Gliederung|Plan]] und [[Gliederung]]", bodyStartLine: 4),
            note("Arbeit/Notiz.md", "```\n[[Gliederung]] im Code\n```\n> Zitat [[Gliederung#Teil 1]]"),
            note("Freizeit/Bild.md", "![[Gliederung]]"),
        ]
        let index = BacklinkIndex.build(notes: notes)
        let links = try #require(index["Uni/Gliederung.md"])
        // Selbstverweis, Code und eingebettete Datei zählen nicht; zwei Links in einer Zeile ergeben einen Eintrag.
        #expect(links.map(\.id) == ["Uni/Hausarbeit.md#5", "Uni/Hausarbeit.md#6", "Arbeit/Notiz.md#3"])
        let task = try #require(links.first { $0.isTask })
        #expect(task.excerpt == "Kapitel 2 nach Gliederung")
        #expect(task.taskStatus == .open)
        #expect(links.first { $0.sourceTitle == "Notiz" }?.excerpt == "Zitat Gliederung")
    }

    @Test func pathWinsForDuplicateNames() {
        let notes = [
            note("Uni/Index.md", ""),
            note("Arbeit/Index.md", ""),
            note("Start.md", "[[Arbeit/Index]] und [[Index]]"),
        ]
        let index = BacklinkIndex.build(notes: notes)
        #expect(index["Arbeit/Index.md"]?.count == 1)
        // Ohne Pfad gewinnt wie in Obsidian die erste Notiz mit dem Namen.
        #expect(index["Uni/Index.md"]?.count == 1)
    }

    @Test func excerptIsShortened() {
        let long = String(repeating: "a", count: 300) + " [[X]]"
        #expect(BacklinkIndex.excerpt(of: long).count == BacklinkIndex.excerptLength)
        #expect(BacklinkIndex.excerpt(of: "## Siehe [[X|das X]]") == "Siehe das X")
    }
}
