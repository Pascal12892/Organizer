import Foundation
import Testing
@testable import OrganizerCore

@Suite("Frontmatter ändern")
struct FrontmatterEditorTests {
    @Test func insertsListBeforeClosingLine() {
        let raw = "---\nbereich: Uni\ntags: [uni]\n---\n# Text\n"
        let result = FrontmatterEditor.setting("ordner", list: ["/Users/p/Desktop/Statistik"], in: raw)
        #expect(result == "---\nbereich: Uni\ntags: [uni]\nordner:\n  - /Users/p/Desktop/Statistik\n---\n# Text\n")
        #expect(FrontmatterParser.parse(result).frontmatter?["ordner"] == .list(["/Users/p/Desktop/Statistik"]))
    }

    @Test func replacesOnlyThatProperty() {
        let raw = "---\nordner:\n  - /alt\n  - /alt2\nthema: X\n---\nText"
        #expect(FrontmatterEditor.setting("ordner", list: ["/neu"], in: raw) == "---\nordner:\n  - /neu\nthema: X\n---\nText")
        #expect(FrontmatterEditor.setting("ordner", list: [], in: raw) == "---\nthema: X\n---\nText")
        let inline = "---\nordner: [/a, /b]\n---\n"
        #expect(FrontmatterEditor.setting("ordner", list: ["/c"], in: inline) == "---\nordner:\n  - /c\n---\n")
    }

    @Test func addsFrontmatterWhenMissingAndKeepsCRLF() {
        #expect(FrontmatterEditor.setting("ordner", list: ["/a b"], in: "# Titel\n") == "---\nordner:\n  - /a b\n---\n# Titel\n")
        #expect(FrontmatterEditor.setting("ordner", list: [], in: "# Titel\n") == "# Titel\n")
        let crlf = "---\r\nthema: X\r\n---\r\nText\r\n"
        #expect(FrontmatterEditor.setting("ordner", list: ["/a"], in: crlf) == "---\r\nthema: X\r\nordner:\r\n  - /a\r\n---\r\nText\r\n")
    }

    @Test func quotesValuesThatNeedIt() {
        let result = FrontmatterEditor.setting("ordner", list: ["/Users/p/Kurs: Statistik"], in: "---\n---\n")
        #expect(FrontmatterParser.parse(result).frontmatter?["ordner"] == .list(["/Users/p/Kurs: Statistik"]))
    }
}

@Suite("Notizen verschieben")
struct MoveTests {
    @Test func replacesExistingValueOnly() {
        let raw = "---\nbereich: Uni\nthema: Alt\n---\nthema: im Text\n"
        #expect(FrontmatterEditor.replacing("thema", with: "Neu: Thema", in: raw) == "---\nbereich: Uni\nthema: \"Neu: Thema\"\n---\nthema: im Text\n")
        #expect(FrontmatterEditor.replacing("fehlt", with: "x", in: raw) == raw)
    }

    @Test func movesWithoutOverwriting() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OrganizerMove-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = VaultWriter(root: root)
        try writer.createFile("Uni/A/Note.md", content: "x")
        try writer.createFile("Uni/B/Note2.md", content: "y")
        #expect(try writer.moveItem("Uni/A/Note.md", toFolder: "Uni/B") == "Uni/B/Note.md")
        #expect(try writer.read("Uni/B/Note.md") == "x")
        try writer.createFile("Uni/A/Note2.md", content: "z")
        #expect(throws: VaultWriter.WriteError.self) { try writer.moveItem("Uni/A/Note2.md", toFolder: "Uni/B") }
    }
}
