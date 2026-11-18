import Foundation
import Testing
@testable import OrganizerCore

@Suite("Tags")
struct TagTests {
    @Test func combinesFrontmatterAndInlineTags() {
        let frontmatter = FrontmatterParser.parse("---\ntags: [uni, '#Data-Science']\n---").frontmatter
        let body = """
        # Überschrift ist kein Tag
        Text mit #lernen und #Uni sowie #2026 und `#code`.
        ```
        #auch-kein-tag
        ```
        Pfad #projekt/hub
        """
        #expect(TagExtractor.tags(frontmatter: frontmatter, body: body) == ["uni", "Data-Science", "lernen", "projekt/hub"])
    }

    @Test func splitsTagString() {
        let frontmatter = FrontmatterParser.parse("---\ntags: uni, arbeit freizeit\n---").frontmatter
        #expect(TagExtractor.frontmatterTags(frontmatter) == ["uni", "arbeit", "freizeit"])
    }
}

@Suite("Vault-Struktur")
struct VaultLayoutTests {
    let layout = VaultLayout()

    @Test func classifiesByPath() {
        #expect(layout.classify(relativePath: "Uni/Data Science/Vorlesung.md") == ("Uni", "Data Science"))
        #expect(layout.classify(relativePath: "uni/Statistik/Sub/Note.md") == ("Uni", "Statistik"))
        #expect(layout.classify(relativePath: "Arbeit/Notiz.md") == ("Arbeit", nil))
        #expect(layout.classify(relativePath: "Inbox/Notiz.md") == (nil, nil))
        #expect(layout.classify(relativePath: "Notiz.md") == (nil, nil))
    }

    @Test func pathWinsOverFrontmatter() {
        let content = "---\nbereich: Arbeit\nthema: Falsch\n---\nText"
        let note = NoteFactory.makeNote(relativePath: "Uni/Statistik/A.md", url: URL(filePath: "/v/Uni/Statistik/A.md"), content: content, modified: .now, layout: layout)
        #expect(note.area == "Uni")
        #expect(note.topic == "Statistik")
        #expect(note.title == "A")
    }

    @Test func frontmatterUsedOutsideAreas() {
        let content = "---\nbereich: arbeit\nthema: Projekt X\nerstellt: 2026-01-02\n---\nText"
        let note = NoteFactory.makeNote(relativePath: "Inbox/B.md", url: URL(filePath: "/v/Inbox/B.md"), content: content, modified: .now, layout: layout)
        #expect(note.area == "Arbeit")
        #expect(note.topic == "Projekt X")
        #expect(note.created != nil)
    }

    @Test func excerptSkipsTitleAndMarkup() {
        let body = "# Vorlesung\n\n- [ ] **Wichtig**: [[Ziel|Alias]] lesen\n> Zitat mit [Link](https://x.de)"
        #expect(Excerpt.make(from: body, title: "Vorlesung") == "Wichtig: Alias lesen Zitat mit Link")
    }
}

@Suite("Vault-Scan")
struct VaultScannerTests {
    @Test func scansNotesTopicsAndSkipsHidden() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OrganizerScan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String, _ content: String) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("Uni/Data Science/Vorlesung 1.md", "---\ntags: [uni]\n---\n# Vorlesung 1\nText")
        try write("Arbeit/Meeting.md", "Notiz")
        try write("Freizeit/Reisen/.versteckt.md", "x")
        try write(".obsidian/workspace.md", "x")
        try write("Inbox/Bild.png", "x")
        try write("Kaputt.md", "---\nbereich: Uni\nText ohne Ende")
        try FileManager.default.createDirectory(at: root.appending(path: "Freizeit/Reisen"), withIntermediateDirectories: true)

        let snapshot = VaultScanner.scan(root: root, layout: VaultLayout())
        #expect(Set(snapshot.notes.map(\.relativePath)) == ["Uni/Data Science/Vorlesung 1.md", "Arbeit/Meeting.md", "Kaputt.md"])
        #expect(snapshot.topics.map(\.id) == ["Uni/Data Science", "Freizeit/Reisen"])
        #expect(snapshot.issues.map(\.relativePath) == ["Kaputt.md"])

        let lecture = try #require(snapshot.notes.first { $0.title == "Vorlesung 1" })
        #expect(lecture.area == "Uni")
        #expect(lecture.topic == "Data Science")
        #expect(lecture.tags == ["uni"])
    }
}

@Suite("Filter und Gruppierung")
struct NoteQueryTests {
    func note(_ path: String, body: String = "", tags: [String] = [], modified: Date = .now) -> Note {
        let layout = VaultLayout().classify(relativePath: path)
        return Note(relativePath: path, url: URL(filePath: "/v/" + path), title: (path as NSString).lastPathComponent,
                    area: layout.area, topic: layout.topic, tags: tags, modified: modified, body: body, excerpt: "")
    }

    @Test func filtersByScopeTagAndText() {
        let notes = [
            note("Uni/Statistik/A.md", body: "Regression und Varianz", tags: ["uni"]),
            note("Uni/Mathe/B.md", body: "Analysis"),
            note("Arbeit/C.md", body: "Regression im Projekt", tags: ["arbeit"]),
        ]
        #expect(NoteQuery(scope: .area("Uni")).apply(to: notes).count == 2)
        #expect(NoteQuery(scope: .topic(area: "Uni", name: "Mathe")).apply(to: notes).map(\.title) == ["B.md"])
        #expect(NoteQuery(tag: "UNI").apply(to: notes).map(\.title) == ["A.md"])
        #expect(NoteQuery(searchText: "regression").apply(to: notes).count == 2)
        #expect(NoteQuery(searchText: "regression projekt").apply(to: notes).map(\.title) == ["C.md"])
        #expect(NoteQuery(searchText: "varianz", ).apply(to: notes).count == 1)
    }

    @Test func groupsByRecency() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let day: TimeInterval = 86_400
        let notes = [
            note("a.md", modified: now),
            note("b.md", modified: now - day),
            note("c.md", modified: now - 3 * day),
            note("d.md", modified: now - 20 * day),
            note("e.md", modified: now - 100 * day),
            note("f.md", modified: now - 400 * day),
        ]
        let sections = NoteGrouping.byRecency(notes, now: now, calendar: calendar)
        #expect(sections.map(\.id) == ["today", "yesterday", "7days", "30days", "m2026-8", "y2025"])
    }
}

@Suite("Markdown")
struct MarkdownTests {
    @Test func rewritesWikiLinksOutsideCode() throws {
        let rewritten = WikiLinks.rewrite("Siehe [[Data Science/Vorlesung 1|Vorlesung]] und `[[kein Link]]`")
        #expect(rewritten.hasPrefix("Siehe [Vorlesung](organizer-note://open?target=Data%20Science%2FVorlesung%201)"))
        #expect(rewritten.hasSuffix("`[[kein Link]]`"))
        let url = try #require(WikiLinks.url(forTarget: "A (b)#Abschnitt"))
        #expect(WikiLinks.target(from: url) == "A (b)#Abschnitt")
    }

    @Test func resolvesTargets() {
        let layout = VaultLayout()
        let notes = ["Uni/X/Vorlesung.md", "Arbeit/Vorlesung.md", "Inbox/Idee.md"].map {
            NoteFactory.makeNote(relativePath: $0, url: URL(filePath: "/v/" + $0), content: "", modified: .now, layout: layout)
        }
        #expect(WikiLinks.resolve("Idee#Teil", in: notes)?.relativePath == "Inbox/Idee.md")
        #expect(WikiLinks.resolve("Arbeit/Vorlesung", in: notes)?.relativePath == "Arbeit/Vorlesung.md")
        #expect(WikiLinks.resolve("Fehlt", in: notes) == nil)
    }

    @Test func convertsBlocks() throws {
        let content = MarkdownContent(markdown: """
        # Titel
        Text mit **fett** und [[Link]].

        - [ ] offen
        - [x] erledigt

        | A | B |
        |---|---|
        | 1 | 2 |

        ```swift
        let x = 1
        ```
        """)
        #expect(content.blocks.count == 5)
        guard case .heading(1, let title) = content.blocks[0] else { Issue.record("Überschrift fehlt"); return }
        #expect(String(title.characters) == "Titel")
        guard case .paragraph(let paragraph) = content.blocks[1] else { Issue.record("Absatz fehlt"); return }
        #expect(String(paragraph.characters) == "Text mit fett und Link.")
        #expect(paragraph.runs.contains { $0.link.flatMap(WikiLinks.target(from:)) == "Link" })
        guard case .list(let list) = content.blocks[2] else { Issue.record("Liste fehlt"); return }
        #expect(list.items.map(\.checkbox) == [false, true])
        guard case .table(let header, let rows) = content.blocks[3] else { Issue.record("Tabelle fehlt"); return }
        #expect(header.count == 2 && rows.count == 1)
        #expect(content.blocks[4] == .code(language: "swift", code: "let x = 1"))
    }
}

@Suite("Inkrementeller Scan")
struct IncrementalScanTests {
    @Test func reusesUnchangedNotesAndRereadsChangedOnes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OrganizerIncremental-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = VaultWriter(root: root)
        try writer.createFile("Uni/A.md", content: "- [ ] Alt")
        try writer.createFile("Uni/B.md", content: "B")
        let first = VaultScanner.scan(root: root, layout: VaultLayout())

        // Vorherigen Stand absichtlich verfälschen: nur wiederverwendete Notizen behalten den falschen Titel.
        var previous = Dictionary(uniqueKeysWithValues: first.notes.map { ($0.relativePath, $0) })
        previous["Uni/B.md"]?.title = "aus dem Cache"
        try writer.save("Uni/A.md", newContent: "- [x] Neu", expected: "- [ ] Alt")
        // Änderungsdatum sicher verschieben (Dateisysteme mit grober Auflösung)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(5)], ofItemAtPath: writer.url(for: "Uni/A.md").path(percentEncoded: false))

        let second = VaultScanner.scan(root: root, layout: VaultLayout(), previous: previous)
        #expect(second.notes.first { $0.relativePath == "Uni/B.md" }?.title == "aus dem Cache")
        #expect(second.tasks.map(\.title) == ["Neu"])
        #expect(second.tasks.first?.status == .done)
    }

    @Test func updatesOnlyChangedPaths() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OrganizerUpdate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = VaultWriter(root: root)
        try writer.createFile("Uni/A.md", content: "- [ ] Alt")
        try writer.createFile("Uni/B.md", content: "B")
        var first = VaultScanner.scan(root: root, layout: VaultLayout())
        // Unveränderte Notizen müssen unverändert übernommen werden (nicht neu gelesen).
        if let index = first.notes.firstIndex(where: { $0.relativePath == "Uni/B.md" }) { first.notes[index].title = "behalten" }

        _ = try writer.appendLine("Uni/A.md", line: "- [ ] Neu")
        try writer.createFile("Privat/Neu.md", content: "- [ ] Einkaufen")
        try writer.moveToTrash("Uni/B.md")
        let updated = VaultScanner.updating(first, root: root, changedPaths: ["Uni/A.md", "Privat/Neu.md"], layout: VaultLayout())
        #expect(Set(updated.tasks.map(\.title)) == ["Alt", "Neu", "Einkaufen"])
        #expect(updated.folders.contains("Privat"))
        #expect(updated.notes.first { $0.relativePath == "Uni/B.md" }?.title == "behalten")

        let removed = VaultScanner.updating(updated, root: root, changedPaths: ["Uni/B.md"], layout: VaultLayout())
        #expect(!removed.notes.contains { $0.relativePath == "Uni/B.md" })
    }
}

@Suite("Zwischenspeicher")
struct VaultCacheTests {
    @Test func roundTripRestoresSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OrganizerCache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = VaultWriter(root: root)
        try writer.createFile("Uni/Statistik/A.md", content: "---\ntags: [uni]\n---\n- [ ] Lesen 📅 2026-11-20\n")
        try writer.createFile("_Organizer/Tasks.md", content: "- [ ] Zentral #uni\n")
        let layout = VaultLayout(areas: [], automaticAreas: true)
        let snapshot = VaultScanner.scan(root: root, layout: layout)

        let file = root.appending(path: "cache.plist")
        try VaultCache(vaultPath: root.path, layout: layout, snapshot: snapshot).save(to: file)
        let cache = try #require(VaultCache.load(from: file))
        #expect(cache.matches(vaultPath: root.path, layout: layout))
        #expect(!cache.matches(vaultPath: "/anders", layout: layout))

        let restored = cache.snapshot
        #expect(restored.notes == snapshot.notes)
        #expect(restored.topics == snapshot.topics)
        #expect(restored.tasks == snapshot.tasks)
        #expect(restored.tasks.first { $0.title == "Zentral" }?.area == "Uni")
    }

    @Test func skipsProgramFoldersAndCountsEntries() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OrganizerSkip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = VaultWriter(root: root)
        try writer.createFile("Projekt/node_modules/paket/README.md", content: "x")
        try writer.createFile("Projekt/Notiz.md", content: "y")
        let snapshot = VaultScanner.scan(root: root, layout: VaultLayout())
        #expect(snapshot.notes.map(\.relativePath) == ["Projekt/Notiz.md"])
        #expect(snapshot.entryCount >= 3)
    }
}
