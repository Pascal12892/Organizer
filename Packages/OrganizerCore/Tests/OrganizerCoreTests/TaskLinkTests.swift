import Foundation
import Testing
@testable import OrganizerCore

@Suite("Aufgaben mit verlinkten Notizen")
struct TaskLinkTests {
    @Test func parsesLinksFromWholeLine() throws {
        let task = try #require(TaskLine.parse("- [ ] Kapitel 2 nach [[Gliederung]] schreiben 📅 2026-11-30 [[Uni/Quellen|Literatur]] #uni"))
        #expect(task.links == ["Gliederung", "Uni/Quellen"])
        #expect(task.title == "Kapitel 2 nach [[Gliederung]] schreiben")
        #expect(task.displayTitle == "Kapitel 2 nach Gliederung schreiben")
    }

    @Test func ignoresEmbedsAndDuplicates() {
        #expect(TaskLine.links(in: "A ![[Bild.png]] [[B]] [[b]]") == ["B"])
        #expect(TaskLine.links(in: "ohne Links") == [])
    }

    @Test func displayTitleUsesAliasOrFileName() {
        #expect(TaskLine.displayTitle("Lesen [[Uni/Data Science/Skript#Teil 2]]") == "Lesen Skript")
        #expect(TaskLine.displayTitle("Lesen [[Skript|das Skript]]") == "Lesen das Skript")
    }

    @Test func addingLinkGoesBeforeMetadata() {
        let line = "- [ ] Hausarbeit ⏫ 📅 2026-11-20 #uni"
        #expect(TaskLine.setting(line, addingLink: "Gliederung") == "- [ ] Hausarbeit [[Gliederung]] ⏫ 📅 2026-11-20 #uni")
        // Schon verlinkt (auch mit Pfad oder Alias): nichts ändern.
        let linked = "- [ ] Hausarbeit [[Gliederung|Plan]] #uni"
        #expect(TaskLine.setting(linked, addingLink: "Gliederung") == linked)
    }

    @Test func removingLinkKeepsRest() {
        #expect(TaskLine.setting("- [ ] Lies [[A]] heute 📅 2026-11-20", removingLink: "A") == "- [ ] Lies heute 📅 2026-11-20")
        #expect(TaskLine.setting("- [ ] Lies [[Ordner/A#x|Alias]] #uni", removingLink: "Ordner/A") == "- [ ] Lies #uni")
        #expect(TaskLine.setting("- [ ] Lies [[B]]", removingLink: "A") == "- [ ] Lies [[B]]")
    }

    @Test func linkTargetIsShortWhenUnique() {
        func note(_ path: String) -> Note {
            Note(relativePath: path, url: URL(fileURLWithPath: "/v/" + path),
                 title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                 tags: [], modified: .now, body: "", excerpt: "", issues: [], bodyStartLine: 0)
        }
        let notes = [note("Uni/Gliederung.md"), note("Uni/Index.md"), note("Arbeit/Index.md")]
        #expect(WikiLinks.linkTarget(for: notes[0], in: notes) == "Gliederung")
        #expect(WikiLinks.linkTarget(for: notes[1], in: notes) == "Uni/Index")
    }
}
