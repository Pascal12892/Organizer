import AppKit
import OrganizerCore
import Observation

/// Zentraler Zustand der App: Einstellungen, Vault und Navigation.
@Observable
final class AppModel {
    let settings: SettingsStore
    let vault: VaultService
    let notes: NotesViewModel
    let calendar: CalendarService
    let tasks: TaskService
    let folderLinks: FolderLinkService
    /// Chat mit Claude (braucht `self`, darum nach der Initialisierung gesetzt).
    @ObservationIgnored private(set) var chat: ChatViewModel!
    let calendarState = CalendarViewModel()

    var sidebarSelection: SidebarItem? = .notes
    /// Ausgeklappte Ordner in der Seitenleiste.
    var expandedFolders: Set<String> = []
    /// Wird erhöht, wenn das Suchfeld den Fokus bekommen soll (Cmd+F).
    private(set) var searchFocusRequest = 0
    /// Wird erhöht, wenn das Eingabefeld für neue Aufgaben den Fokus bekommen soll (⌘N in Aufgaben).
    var taskInputFocusRequest = 0
    /// Bereichsfilter in der Aufgabenliste (`nil` = alle).
    var taskAreaFilter: String?

    init(settings: SettingsStore, vault: VaultService, calendar: CalendarService) {
        self.settings = settings
        self.vault = vault
        self.calendar = calendar
        self.tasks = TaskService(vault: vault, settings: settings)
        self.folderLinks = FolderLinkService(vault: vault, settings: settings)
        defer { chat = ChatViewModel(model: self) }
        self.notes = NotesViewModel(vault: vault)
                vault.updateLayout(settings.layout)
    }

    convenience init() {
        let settings = SettingsStore(fileURL: SettingsStore.defaultFileURL)
        self.init(settings: settings, vault: VaultService(layout: settings.layout), calendar: CalendarService())
    }

    // MARK: - Vault

    /// Beim Start: gespeicherten Vault wieder öffnen.
    func restoreVault() async {
        guard vault.rootURL == nil, let bookmark = settings.settings.vaultBookmark else { return }
        do {
            let (url, isStale) = try SecurityScopedBookmark.resolve(bookmark)
            if isStale, let fresh = try? SecurityScopedBookmark.make(for: url) {
                settings.update { $0.vaultBookmark = fresh }
            }
            await vault.open(url)
        } catch {
            vault.markAccessLost(
                path: settings.settings.vaultPath,
                message: "Organizer hat keinen Zugriff mehr auf den Vault. Wähle den Ordner bitte erneut aus."
            )
        }
    }

    /// Zeigt den Ordner-Dialog und öffnet den gewählten Vault.
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.title = "Obsidian-Vault auswählen"
        panel.message = "Wähle den Ordner deines Obsidian-Vaults. Organizer liest und schreibt nur Markdown-Dateien darin."
        panel.prompt = "Auswählen"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let path = settings.settings.vaultPath {
            panel.directoryURL = URL(filePath: path).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await useVault(at: url) }
    }

    func useVault(at url: URL) async {
        do {
            let bookmark = try SecurityScopedBookmark.make(for: url)
            settings.update {
                $0.vaultBookmark = bookmark
                $0.vaultPath = url.path(percentEncoded: false)
            }
        } catch {
            // Ohne Bookmark funktioniert der Vault bis zum nächsten Start trotzdem.
            vault.markAccessLost(path: url.path(percentEncoded: false), message: "Der Zugriff konnte nicht dauerhaft gespeichert werden: \(error.localizedDescription)")
            return
        }
        notes.selectedNoteID = nil
        await vault.open(url)
    }

    func reloadVault() {
        Task { await vault.rescan() }
    }

    /// Prüft, ob der gewählte Ordner wie ein Obsidian-Vault aussieht.
    var vaultLooksLikeObsidian: Bool {
        guard let rootURL = vault.rootURL else { return false }
        return FileManager.default.fileExists(atPath: rootURL.appending(path: ".obsidian").path(percentEncoded: false))
    }

    // MARK: - Bereiche

    /// Die Bereiche: automatisch alle Ordner auf oberster Ebene, sonst die Liste aus den Einstellungen.
    var areas: [String] {
        let layout = settings.layout
        guard layout.automaticAreas else { return layout.areas }
        return folderTree.compactMap { layout.area(forFolder: $0.path) }
    }

    /// Ordnerbaum des Vaults; konfigurierte Bereiche stehen oben in ihrer Reihenfolge.
    var folderTree: [FolderNode] {
        FolderTree.build(vault.snapshot.folders, topLevelOrder: settings.settings.areas)
    }

    func setAreas(_ areas: [String]) {
        settings.update { $0.areas = areas }
        vault.updateLayout(settings.layout)
    }

    func setAutomaticAreas(_ automatic: Bool) {
        settings.update { $0.automaticAreas = automatic }
        vault.updateLayout(settings.layout)
    }

    func noteCount(for item: SidebarItem) -> Int {
        guard let scope = item.noteScope else { return 0 }
        return NoteQuery(scope: scope).apply(to: vault.notes).count
    }

    // MARK: - Navigation

    func focusSearch() {
        if sidebarSelection?.noteScope == nil { sidebarSelection = .notes }
        searchFocusRequest += 1
    }

    /// Öffnet die Notiz zu einem Wikilink. Gibt `false` zurück, wenn sie nicht existiert.
    @discardableResult
    func openWikiLink(_ target: String) -> Bool {
        guard let note = WikiLinks.resolve(target, in: vault.notes) else { return false }
        if let scope = sidebarSelection?.noteScope, NoteQuery(scope: scope).apply(to: [note]).isEmpty {
            sidebarSelection = .notes
        }
        notes.searchText = ""
        notes.tagFilter = nil
        notes.selectedNoteID = note.id
        return true
    }

    /// Öffnet die Notiz, in der eine Aufgabe steht.
    func openNote(atPath relativePath: String) {
        if let note = vault.notes.first(where: { $0.relativePath == relativePath }) {
            let folder = note.folderPath
            if folder.isEmpty {
                sidebarSelection = .notes
            } else {
                expand(toShow: folder)
                sidebarSelection = .folder(folder)
            }
            notes.searchText = ""
            notes.tagFilter = nil
            notes.selectedNoteID = note.id
        }
    }

    func revealInFinder(_ notes: [Note]) {
        NSWorkspace.shared.activateFileViewerSelecting(notes.map(\.url))
    }

    // MARK: - Schreiben

    var writer: VaultWriter? { vault.rootURL.map { VaultWriter(root: $0) } }

    /// Letzter Fehler beim Schreiben; wird unten in der Seitenleiste angezeigt.
    var writeError: String?
    var isShowingNewNote = false
    /// Vorbelegung für die nächste neue Notiz (z. B. Notiz zu einem Termin).
    var newNotePrefill: NewNotePrefill?
    /// Elternordner, in dem gerade ein neuer Ordner angelegt wird ("" = oberste Ebene). Zeigt den Dialog.
    var newFolderParent: String?

    /// Wo eine neue Notiz standardmäßig landet: im ausgewählten Ordner bzw. dem der offenen Notiz.
    var defaultFolder: String {
        if let path = sidebarSelection?.folderPath { return path }
        if let note = notes.selectedNote { return note.folderPath }
        return ""
    }

    /// Öffnet „Neue Notiz“ mit Titel und Verweis auf einen Termin im Frontmatter.
    func createNote(for event: CalendarEventInfo) {
        let date = OrganizerDateFormat.string(from: event.start, includingTime: !event.isAllDay)
        newNotePrefill = NewNotePrefill(
            title: event.title,
            extraProperties: [
                .init(key: "termin", value: .string(event.title)),
                .init(key: "termin-datum", value: .string(date)),
            ]
        )
        isShowingNewNote = true
    }

    func setCalendarHidden(_ id: String, hidden: Bool) {
        settings.update {
            if hidden { $0.hiddenCalendarIDs.insert(id) } else { $0.hiddenCalendarIDs.remove(id) }
        }
    }

    /// Legt einen Termin an; Rückgängig entfernt ihn wieder.
    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, notes: String?, undoManager: UndoManager?) throws {
        let id = try calendar.createEvent(title: title, start: start, end: end, isAllDay: isAllDay, calendarID: calendarID, notes: notes)
        settings.update { $0.hiddenCalendarIDs.remove(calendarID) }
        undoManager?.registerUndo(withTarget: self) { model in
            do {
                try model.calendar.removeEvent(withID: id)
            } catch {
                model.writeError = "Termin konnte nicht entfernt werden: \(error.localizedDescription)"
            }
        }
        undoManager?.setActionName("Termin anlegen")
    }

    func openInObsidian(_ note: Note) {
        guard let vaultName = vault.vaultName, let url = ObsidianURL.open(vaultName: vaultName, relativePath: note.relativePath) else { return }
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            writeError = "Obsidian ist nicht installiert oder nicht für obsidian://-Links registriert."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Legt eine Notiz an, öffnet sie im Bearbeiten-Modus und macht das Anlegen rückgängig-fähig.
    @discardableResult
    func createNote(title: String, folder: String, body: String = "", extraProperties: [Frontmatter.Entry] = [],
                    openInEditor: Bool = true, undoManager: UndoManager?) async throws -> String {
        guard let writer else { throw VaultWriter.WriteError.invalidName }
        let (area, topic) = settings.layout.classify(folder: folder)
        let content = NoteTemplate.content(area: area, topic: topic, created: .now, extraProperties: extraProperties, body: body)
        let relativePath = try writer.createNote(folder: folder, title: title, content: content)
        await vault.rescan()
        defer {
            undoManager?.registerUndo(withTarget: self) { model in
                model.undoCreation(of: relativePath, kind: "Notiz", undoManager: undoManager)
            }
            undoManager?.setActionName("Notiz anlegen")
        }
        guard openInEditor else { return relativePath }

        if folder.isEmpty {
            sidebarSelection = .notes
        } else {
            expand(toShow: folder)
            sidebarSelection = .folder(folder)
        }
        notes.searchText = ""
        notes.tagFilter = nil
        notes.selectedNoteID = relativePath
        notes.isEditing = true
        return relativePath
    }

    func createFolder(named name: String, in parent: String, undoManager: UndoManager?) async throws {
        guard let writer else { return }
        let relativePath = try writer.createFolder(parent: parent, name: name)
        await vault.rescan()
        expand(toShow: relativePath)
        sidebarSelection = .folder(relativePath)
        undoManager?.registerUndo(withTarget: self) { model in
            model.undoCreation(of: relativePath, kind: "Ordner", undoManager: undoManager)
        }
        undoManager?.setActionName("Ordner anlegen")
    }

    /// Klappt alle Elternordner auf, damit `path` in der Seitenleiste sichtbar ist.
    func expand(toShow path: String) {
        let components = path.split(separator: "/")
        for length in 1..<max(components.count, 1) {
            expandedFolders.insert(components.prefix(length).joined(separator: "/"))
        }
    }

    /// Rückgängig für Anlegen: Datei bzw. Ordner wandern in den Papierkorb (wiederherstellbar).
    private func undoCreation(of relativePath: String, kind: String, undoManager: UndoManager?) {
        guard let writer else { return }
        do {
            if notes.selectedNoteID == relativePath {
                notes.isEditing = false
                notes.selectedNoteID = nil
            }
            if let selected = sidebarSelection?.folderPath, selected == relativePath || selected.hasPrefix(relativePath + "/") {
                let parent = relativePath.split(separator: "/").dropLast().joined(separator: "/")
                sidebarSelection = parent.isEmpty ? .notes : .folder(parent)
            }
            try writer.moveToTrash(relativePath)
            reloadVault()
        } catch {
            writeError = "\(kind) konnte nicht in den Papierkorb gelegt werden: \(error.localizedDescription)"
        }
    }
}

/// Vorbelegung für das Blatt „Neue Notiz“.
struct NewNotePrefill: Equatable {
    var title: String
    var extraProperties: [Frontmatter.Entry]
}
