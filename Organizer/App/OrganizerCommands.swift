import SwiftUI

/// Einträge in der Menüleiste mit Tastenkürzeln.
struct OrganizerCommands: Commands {
    let model: AppModel

    private var vaultReady: Bool { model.vault.state == .ready }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if model.sidebarSelection == .calendar {
                Button("Neuer Termin …") {
                    model.calendarState.newEventStart = model.calendarState.suggestedStart()
                }
                .keyboardShortcut("n")
                .disabled(model.calendar.access != .fullAccess || model.calendar.writableCalendars.isEmpty)
                Button("Neue Notiz …") { model.isShowingNewNote = true }
                    .disabled(!vaultReady)
            } else {
                Button("Neue Notiz …") { model.isShowingNewNote = true }
                    .keyboardShortcut("n")
                    .disabled(!vaultReady)
            }
            Button("Neuer Ordner …") {
                model.newFolderParent = model.sidebarSelection?.folderPath ?? ""
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!vaultReady)
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

        CommandMenu("Notiz") {
            Button(model.notes.isEditing ? "Vorschau zeigen" : "Bearbeiten") {
                model.notes.isEditing.toggle()
            }
            .keyboardShortcut("e")
            .disabled(model.notes.selectedNote == nil)

            Button("In Obsidian öffnen") {
                if let note = model.notes.selectedNote { model.openInObsidian(note) }
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(model.notes.selectedNote == nil)

            Button("Im Finder zeigen") {
                if let note = model.notes.selectedNote { model.revealInFinder([note]) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.notes.selectedNote == nil)
        }
    }
}
