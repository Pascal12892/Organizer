import Foundation
import Testing
@testable import HubCore

@Suite("Schreiben in den Vault")
struct VaultWriterTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "HubWrite-\(UUID().uuidString)")
    var writer: VaultWriter { VaultWriter(root: root) }

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func createsUniqueNamesWithoutOverwriting() throws {
        let first = try writer.createNote(folder: "Uni/Statistik", title: "Kapitel: 1", content: "A")
        let second = try writer.createNote(folder: "Uni/Statistik", title: "Kapitel: 1", content: "B")
        #expect(first == "Uni/Statistik/Kapitel- 1.md")
        #expect(second == "Uni/Statistik/Kapitel- 1 2.md")
        #expect(try writer.read(first) == "A")
        #expect(try writer.read(second) == "B")
        #expect(try writer.createNote(folder: "", title: "Oben", content: "") == "Oben.md")
    }

    @Test func savesOnlyWhenDiskMatchesExpectation() throws {
        let path = try writer.createNote(folder: "", title: "N", content: "alt")
        try writer.save(path, newContent: "neu", expected: "alt")
        #expect(try writer.read(path) == "neu")

        // Obsidian ändert die Datei – Hub darf mit veraltetem Stand nicht überschreiben.
        try "aus Obsidian".write(to: root.appending(path: path), atomically: true, encoding: .utf8)
        #expect(throws: VaultWriter.WriteError.self) {
            try writer.save(path, newContent: "hub", expected: "neu")
        }
        #expect(try writer.read(path) == "aus Obsidian")
    }

    @Test func refusesExistingTopic() throws {
        #expect(try writer.createTopic(area: "Uni", name: "Data Science") == "Uni/Data Science")
        #expect(throws: VaultWriter.WriteError.self) {
            try writer.createTopic(area: "Uni", name: "Data Science")
        }
    }
}
