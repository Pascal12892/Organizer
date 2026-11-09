import SwiftUI

/// Einträge in der Menüleiste mit Tastenkürzeln.
struct HubCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Vault öffnen …") { model.chooseVault() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Notizen durchsuchen") { model.focusSearch() }
                .keyboardShortcut("f")
        }

        CommandGroup(before: .sidebar) {
            ForEach(Array(SidebarItem.sections.enumerated()), id: \.offset) { index, item in
                Button(item.title) { model.sidebarSelection = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Button("Vault neu laden") { model.reloadVault() }
                .keyboardShortcut("r")
                .disabled(model.vault.rootURL == nil)
            Divider()
        }
    }
}
