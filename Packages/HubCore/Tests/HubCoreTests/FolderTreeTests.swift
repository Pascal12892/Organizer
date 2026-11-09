import Foundation
import Testing
@testable import HubCore

@Suite("Ordnerstruktur")
struct FolderTreeTests {
    @Test func buildsNestedTreeWithOrder() {
        let tree = FolderTree.build(
            ["Projekte/Atlas/Notizen", "Uni", "Uni/Statistik", "Arbeit", "Archiv"],
            topLevelOrder: ["Uni", "Arbeit"]
        )
        #expect(tree.map(\.path) == ["Uni", "Arbeit", "Archiv", "Projekte"])
        let projects = tree[3]
        #expect(projects.children.map(\.path) == ["Projekte/Atlas"])
        #expect(projects.children[0].children.map(\.name) == ["Notizen"])
        #expect(projects.children[0].children[0].depth == 2)
        #expect(FolderTree.flatten(tree).map(\.path) == [
            "Uni", "Uni/Statistik", "Arbeit", "Archiv", "Projekte", "Projekte/Atlas", "Projekte/Atlas/Notizen",
        ])
    }

    @Test func automaticAreasUseTopLevelFolders() {
        let layout = VaultLayout(areas: [], automaticAreas: true)
        #expect(layout.classify(relativePath: "Projekte/Atlas/Tief/x.md") == ("Projekte", "Atlas"))
        #expect(layout.classify(relativePath: "_Hub/Tasks.md") == (nil, nil))
        #expect(layout.classify(folder: "Projekte") == ("Projekte", nil))
        #expect(layout.classify(folder: "") == (nil, nil))
    }

    @Test func folderScopeIncludesSubfolders() {
        let notes = ["A/x.md", "A/B/y.md", "AB/z.md"].map {
            Note(relativePath: $0, url: URL(filePath: "/v/" + $0), title: $0, modified: .now, body: "", excerpt: "")
        }
        #expect(NoteQuery(scope: .folder("A")).apply(to: notes).map(\.relativePath) == ["A/x.md", "A/B/y.md"])
    }

    @Test func scannerReportsFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "HubFolders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Projekte/Atlas/Tief", ".obsidian/plugins", "Leer"] {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        let snapshot = VaultScanner.scan(root: root, layout: VaultLayout(automaticAreas: true))
        #expect(snapshot.folders == ["Leer", "Projekte", "Projekte/Atlas", "Projekte/Atlas/Tief"])
        #expect(snapshot.topics.map(\.id) == ["Projekte/Atlas"])
    }
}
