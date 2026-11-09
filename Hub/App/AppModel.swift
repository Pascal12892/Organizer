import AppKit
import HubCore
import Observation

/// Zentraler Zustand der App: Einstellungen, Vault und Navigation.
@Observable
final class AppModel {
    let settings: SettingsStore
    let vault: VaultService
    let notes: NotesViewModel

    var sidebarSelection: SidebarItem? = .notes
    /// Ausgeklappte Bereiche in der Seitenleiste.
    var expandedAreas: Set<String> = []
    /// Wird erhöht, wenn das Suchfeld den Fokus bekommen soll (Cmd+F).
    private(set) var searchFocusRequest = 0

    init(settings: SettingsStore, vault: VaultService) {
        self.settings = settings
        self.vault = vault
        self.notes = NotesViewModel(vault: vault)
        expandedAreas = Set(settings.settings.areas)
        vault.updateLayout(settings.layout)
    }

    convenience init() {
        let settings = SettingsStore(fileURL: SettingsStore.defaultFileURL)
        self.init(settings: settings, vault: VaultService(layout: settings.layout))
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
                message: "Hub hat keinen Zugriff mehr auf den Vault. Wähle den Ordner bitte erneut aus."
            )
        }
    }

    /// Zeigt den Ordner-Dialog und öffnet den gewählten Vault.
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.title = "Obsidian-Vault auswählen"
        panel.message = "Wähle den Ordner deines Obsidian-Vaults. Hub liest und schreibt nur Markdown-Dateien darin."
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

    var areas: [String] { settings.layout.areas }

    func setAreas(_ areas: [String]) {
        settings.update { $0.areas = areas }
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

    func revealInFinder(_ notes: [Note]) {
        NSWorkspace.shared.activateFileViewerSelecting(notes.map(\.url))
    }

    // MARK: - Schreiben

    var writer: VaultWriter? { vault.rootURL.map { VaultWriter(root: $0) } }

    /// Letzter Fehler beim Schreiben; wird unten in der Seitenleiste angezeigt.
    var writeError: String?
    var isShowingNewNote = false
    /// Bereich, für den gerade ein neues Thema angelegt wird (zeigt den Dialog).
    var newTopicArea: String?

    /// Wo eine neue Notiz standardmäßig landet: im ausgewählten Bereich bzw. Thema.
    var defaultLocation: (area: String?, topic: String?) {
        switch sidebarSelection {
        case .area(let area): (area, nil)
        case .topic(let area, let name): (area, name)
        default:
            if let note = notes.selectedNote { (note.area, note.topic) } else { (areas.first, nil) }
        }
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
    func createNote(title: String, area: String?, topic: String?, undoManager: UndoManager?) async throws {
        guard let writer else { return }
        let folder = [area, topic].compactMap { $0 }.joined(separator: "/")
        let content = NoteTemplate.content(area: area, topic: topic, created: .now, body: "")
        let relativePath = try writer.createNote(folder: folder, title: title, content: content)
        await vault.rescan()

        if let area {
            expandedAreas.insert(area)
            sidebarSelection = topic.map { .topic(area: area, name: $0) } ?? .area(area)
        } else {
            sidebarSelection = .notes
        }
        notes.searchText = ""
        notes.tagFilter = nil
        notes.selectedNoteID = relativePath
        notes.isEditing = true

        undoManager?.registerUndo(withTarget: self) { model in
            model.undoCreation(of: relativePath, kind: "Notiz", undoManager: undoManager)
        }
        undoManager?.setActionName("Notiz anlegen")
    }

    func createTopic(named name: String, in area: String, undoManager: UndoManager?) async throws {
        guard let writer else { return }
        let relativePath = try writer.createTopic(area: area, name: name)
        await vault.rescan()
        expandedAreas.insert(area)
        if let topic = vault.snapshot.topics.first(where: { $0.relativePath == relativePath }) {
            sidebarSelection = .topic(area: area, name: topic.name)
        }
        undoManager?.registerUndo(withTarget: self) { model in
            model.undoCreation(of: relativePath, kind: "Thema", undoManager: undoManager)
        }
        undoManager?.setActionName("Thema anlegen")
    }

    /// Rückgängig für Anlegen: Datei bzw. Ordner wandern in den Papierkorb (wiederherstellbar).
    private func undoCreation(of relativePath: String, kind: String, undoManager: UndoManager?) {
        guard let writer else { return }
        do {
            if notes.selectedNoteID == relativePath {
                notes.isEditing = false
                notes.selectedNoteID = nil
            }
            if case .topic(let area, let name) = sidebarSelection, "\(area)/\(name)" == relativePath {
                sidebarSelection = .area(area)
            }
            try writer.moveToTrash(relativePath)
            reloadVault()
        } catch {
            writeError = "\(kind) konnte nicht in den Papierkorb gelegt werden: \(error.localizedDescription)"
        }
    }
}
