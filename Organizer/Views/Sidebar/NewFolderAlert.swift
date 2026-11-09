import SwiftUI

/// Kleiner Dialog für einen neuen Ordner (im Bereich ist das ein neues Thema).
struct NewFolderAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(
                get: { model.newFolderParent != nil },
                set: { if !$0 { model.newFolderParent = nil } }
            )
        ) {
            TextField("Name", text: $name)
            Button("Anlegen") { create() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Abbrechen", role: .cancel) { name = "" }
        } message: {
            Text("Organizer legt den Ordner direkt im Vault an. Obsidian zeigt ihn sofort.")
        }
    }

    private var title: String {
        guard let parent = model.newFolderParent else { return "" }
        if parent.isEmpty { return "Neuer Ordner im Vault" }
        let name = parent.split(separator: "/").last.map(String.init) ?? parent
        return "Neuer Ordner in „\(name)“"
    }

    private func create() {
        guard let parent = model.newFolderParent else { return }
        let folderName = name
        name = ""
        Task {
            do {
                try await model.createFolder(named: folderName, in: parent, undoManager: undoManager)
            } catch {
                model.writeError = "Ordner konnte nicht angelegt werden: \(error.localizedDescription)"
            }
        }
    }
}
