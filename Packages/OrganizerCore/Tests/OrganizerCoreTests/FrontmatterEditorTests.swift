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
