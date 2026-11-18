import AppKit
import OrganizerCore
import Observation
import WidgetKit

/// Zentraler Zustand der App: Einstellungen, Vault und Navigation.
@Observable
final class AppModel {
    let settings: SettingsStore
    let vault: VaultService
    let notes: NotesViewModel
    let calendar: CalendarService
    let tasks: TaskService
    let folderLinks: FolderLinkService
    let roadmap: RoadmapService
    let reminders: RemindersSyncService
    @ObservationIgnored private(set) var quickCapture: QuickCaptureController!
    @ObservationIgnored private(set) var notifications: NotificationService!
    @ObservationIgnored private let hotKey = HotKeyService()
    let calendarState = CalendarViewModel()

    var sidebarSelection: SidebarItem? = .dashboard
    /// Ausgeklappte Ordner in der Seitenleiste.
    var expandedFolders: Set<String> = []
    /// Wird erhöht, wenn das Suchfeld den Fokus bekommen soll (Cmd+F).
    private(set) var searchFocusRequest = 0
    /// Suche über Termine, Aufgaben und Notizen (Suchfeld außerhalb der Notizen).
    let search = GlobalSearchModel()
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
        self.roadmap = RoadmapService(vault: vault)
        self.reminders = RemindersSyncService(vault: vault, settings: settings)
        defer {
            quickCapture = QuickCaptureController(model: self)
            notifications = NotificationService(model: self)
        }
        self.notes = NotesViewModel(vault: vault)
                vault.updateLayout(settings.layout)
    }

    /// Die eine Instanz der App (Previews legen eigene an).
    static let shared = AppModel()
    @ObservationIgnored private var started = false

    /// Einmal beim App-Start: Tastenkürzel registrieren und den Vault laden – auch ohne offenes Fenster.
    func start() {
        guard !started else { return }
        started = true
        registerQuickCaptureHotKey()
        Task { await restoreVault() }
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
                message: L("Organizer hat keinen Zugriff mehr auf den Vault. Wähle den Ordner bitte erneut aus.")
            )
        }
    }

    /// Zeigt den Ordner-Dialog und öffnet den gewählten Vault.
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.title = L("Obsidian-Vault auswählen")
        panel.message = L("Wähle den Ordner deines Obsidian-Vaults. Organizer liest und schreibt nur Markdown-Dateien darin.")
        panel.prompt = L("Auswählen")
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
            vault.markAccessLost(path: url.path(percentEncoded: false), message: L("Der Zugriff konnte nicht dauerhaft gespeichert werden: \(localizedMessage(error))"))
            return
        }
        notes.selectedNoteID = nil
        await vault.open(url)
    }

    /// Globales Kürzel für die Schnellerfassung (neu) registrieren.
    func registerQuickCaptureHotKey() {
        hotKey.action = { [weak self] in self?.quickCapture.toggle() }
        hotKey.register(HotKeyPreset(rawValue: settings.settings.quickCaptureHotKey) ?? .controlOptionSpace)
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
        let areas = settings.settings.areas
        return folderTreeMemo(FolderTreeKey(version: vault.version, areas: areas)) {
            FolderTree.build(vault.snapshot.folders, topLevelOrder: areas)
        }
    }

    private struct FolderTreeKey: Equatable { let version: Int; let areas: [String] }
    @ObservationIgnored private let folderTreeMemo = Memo<FolderTreeKey, [FolderNode]>()

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

    /// ⌘F: In den Notizen deren Suchfeld, sonst die Suche über alles.
    func focusSearch() {
        searchFocusRequest += 1
    }

    /// ⇧⌘F: Suche über Termine, Aufgaben und Notizen – auch aus den Notizen heraus.
    func focusGlobalSearch() {
        if sidebarSelection?.noteScope != nil { sidebarSelection = .dashboard }
        searchFocusRequest += 1
    }

    /// Termin aus den Suchergebnissen im Kalender zeigen.
    func showInCalendar(_ event: CalendarEventInfo) {
        search.clear()
        calendarState.date = event.start
        calendarState.select(event.start)
        calendarState.selectedEventID = event.id
        sidebarSelection = .calendar
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
        search.clear()
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

    // MARK: - Drag and Drop

    /// Aufgaben auf einen Kalendertag gezogen: Fälligkeit setzen.
    @discardableResult
    func dropTasks(_ items: [String], on day: Date, undoManager: UndoManager?) -> Bool {
        let ids = items.compactMap(DragPayload.taskID(from:))
        let dropped = tasks.tasks.filter { ids.contains($0.id) }
        for task in dropped {
            tasks.setDue(task, Calendar.current.startOfDay(for: day), undoManager: undoManager)
        }
        return !dropped.isEmpty
    }

    /// Notiz in einen anderen Ordner verschieben. Bereich und Thema im Frontmatter werden angepasst,
    /// sofern sie dort stehen. Links in anderen Notizen bleiben gültig, solange der Dateiname eindeutig ist.
    func moveNote(_ relativePath: String, toFolder folder: String, undoManager: UndoManager?) {
        guard let writer, let note = vault.notes.first(where: { $0.relativePath == relativePath }),
              note.folderPath != folder else { return }
        do {
            let newPath = try writer.moveItem(relativePath, toFolder: folder)
            let original = try writer.read(newPath)
            let (area, topic) = settings.layout.classify(folder: folder)
            var updated = original
            if let area { updated = FrontmatterEditor.replacing(FrontmatterKey.area, with: area, in: updated) }
            if let topic { updated = FrontmatterEditor.replacing(FrontmatterKey.topic, with: topic, in: updated) }
            if updated != original { try writer.save(newPath, newContent: updated, expected: original) }

            if notes.selectedNoteID == relativePath { notes.selectedNoteID = newPath }
            undoManager?.registerUndo(withTarget: self) { model in
                do {
                    if updated != original { try writer.save(newPath, newContent: original, expected: updated) }
                    try writer.moveItem(newPath, toFolder: note.folderPath)
                    if model.notes.selectedNoteID == newPath { model.notes.selectedNoteID = relativePath }
                } catch {
                    model.writeError = L("Verschieben konnte nicht rückgängig gemacht werden: \(localizedMessage(error))")
                }
                model.reloadVault()
            }
            undoManager?.setActionName(L("Notiz verschieben"))
        } catch {
            writeError = L("Notiz konnte nicht verschoben werden: \(localizedMessage(error))")
        }
        reloadVault()
    }

    // MARK: - Widgets und Links

    /// Schreibt den Stand für die Widgets und lädt sie neu. Ohne App Group (z. B. ohne Team in Xcode)
    /// passiert nichts – die Widgets zeigen dann einen Hinweis.
    func publishWidgetSnapshot() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let due = tasks.sections(filter: .today, area: nil).flatMap(\.tasks)
        let interval = DateInterval(start: today, end: calendar.date(byAdding: .day, value: 7, to: today)!)
        let events = self.calendar.access == .fullAccess
            ? self.calendar.events(in: interval, hiddenCalendarIDs: settings.settings.hiddenCalendarIDs)
                .filter { $0.end > .now }
                .sorted { $0.start < $1.start }
            : []
        let snapshot = WidgetSnapshot(
            generated: .now,
            tasks: due.prefix(20).map {
                .init(title: $0.title, due: $0.relevantDate, isOverdue: TaskGrouping.isOverdue($0), area: $0.area, priority: $0.priority.rawValue)
            },
            openTaskCount: tasks.counts.open,
            events: events.prefix(20).map { event in
                let info = self.calendar.calendar(withID: event.calendarID)
                return .init(title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                             color: info?.hex ?? "#007AFF", calendar: info?.title ?? "")
            }
        )
        do {
            try snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Bewusst still: Ohne Team/App Group gibt es keinen gemeinsamen Container. Die App funktioniert trotzdem.
        }
    }

    /// Links aus Widgets und Mitteilungen: organizer://tasks, organizer://calendar, organizer://roadmap
    func handle(_ url: URL) {
        guard url.scheme == "organizer" else { return }
        switch url.host() {
        case "tasks": sidebarSelection = .tasks
        case "calendar": sidebarSelection = .calendar
        case "roadmap": sidebarSelection = .roadmap
        case "notes": sidebarSelection = .notes
        default: sidebarSelection = .dashboard
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
                model.writeError = L("Termin konnte nicht entfernt werden: \(localizedMessage(error))")
            }
        }
        undoManager?.setActionName(L("Termin anlegen"))
    }

    /// Termin löschen; Einzeltermine lassen sich mit ⌘Z wiederherstellen.
    func deleteEvent(_ event: CalendarEventInfo, futureEvents: Bool = false, undoManager: UndoManager?) {
        do {
            if let deleted = try calendar.deleteEvent(event, futureEvents: futureEvents) {
                registerEventRestore(deleted, undoManager: undoManager)
            }
        } catch {
            writeError = L("Termin konnte nicht gelöscht werden: \(localizedMessage(error))")
        }
    }

    private func registerEventRestore(_ deleted: CalendarService.DeletedEvent, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            do {
                let id = try model.calendar.restore(deleted)
                // Wiederholen löscht den wiederhergestellten Termin erneut.
                undoManager.registerUndo(withTarget: model) { model in
                    do {
                        try model.calendar.removeEvent(withID: id)
                        model.registerEventRestore(deleted, undoManager: undoManager)
                    } catch {
                        model.writeError = L("Termin konnte nicht gelöscht werden: \(localizedMessage(error))")
                    }
                }
                undoManager.setActionName(L("Termin löschen"))
            } catch {
                model.writeError = L("Termin konnte nicht wiederhergestellt werden: \(localizedMessage(error))")
            }
        }
        undoManager.setActionName(L("Termin löschen"))
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
        await vault.refresh(paths: [relativePath])
        defer {
            undoManager?.registerUndo(withTarget: self) { model in
                model.undoCreation(of: relativePath, kind: L("Notiz"), undoManager: undoManager)
            }
            undoManager?.setActionName(L("Notiz anlegen"))
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
        await vault.refresh(paths: [relativePath])
        expand(toShow: relativePath)
        sidebarSelection = .folder(relativePath)
        undoManager?.registerUndo(withTarget: self) { model in
            model.undoCreation(of: relativePath, kind: L("Ordner"), undoManager: undoManager)
        }
        undoManager?.setActionName(L("Ordner anlegen"))
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
            Task { await vault.refresh(paths: [relativePath]) }
        } catch {
            writeError = L("\(kind) konnte nicht in den Papierkorb gelegt werden: \(localizedMessage(error))")
        }
    }
}

/// Vorbelegung für das Blatt „Neue Notiz“.
struct NewNotePrefill: Equatable {
    var title: String
    var extraProperties: [Frontmatter.Entry]
}
