import AppKit
import Observation
import OrganizerCore

/// Wo neue Aufgaben gespeichert werden.
enum TaskStorage: String, Codable, CaseIterable {
    /// Alle in `_Organizer/Tasks.md`, Bereich und Thema als Tags.
    case central
    /// In `Aufgaben.md` im Ordner des Bereichs bzw. Themas.
    case perFolder

    var title: String {
        switch self {
        case .central: L("Zentral in _Organizer/Tasks.md")
        case .perFolder: L("In „Aufgaben.md“ im Bereich bzw. Thema")
        }
    }
}

/// Aufgaben lesen und ändern. Jede Änderung betrifft genau eine Zeile in einer Markdown-Datei
/// und lässt sich mit ⌘Z rückgängig machen und mit ⇧⌘Z wiederholen.
@Observable
final class TaskService {
    static let centralFile = VaultLayout.organizerFolderName + "/Tasks.md"

    private let vault: VaultService
    private let settings: SettingsStore
    var lastError: String?

    init(vault: VaultService, settings: SettingsStore) {
        self.vault = vault
        self.settings = settings
    }

    var tasks: [TaskItem] { vault.snapshot.tasks }

    /// Zwischengespeichert pro Vault-Stand und Tag (die Seitenleiste fragt bei jedem Neuzeichnen).
    var counts: (open: Int, dueToday: Int, overdue: Int) {
        let key = CountsKey(version: vault.version, day: Calendar.current.startOfDay(for: .now))
        let value = countsMemo(key) {
            let counts = TaskGrouping.counts(tasks)
            return [counts.open, counts.dueToday, counts.overdue]
        }
        return (value[0], value[1], value[2])
    }

    /// Gruppierte Liste, zwischengespeichert pro Stand, Ansicht, Bereich und Tag.
    func sections(filter: TaskFilter, area: String?) -> [TaskSection] {
        let key = SectionsKey(version: vault.version, filter: filter, area: area, day: Calendar.current.startOfDay(for: .now))
        return sectionsMemo(key) { TaskGrouping.sections(tasks, filter: filter, area: area) }
    }

    private struct SectionsKey: Equatable { let version: Int; let filter: TaskFilter; let area: String?; let day: Date }
    @ObservationIgnored private let sectionsMemo = Memo<SectionsKey, [TaskSection]>()

    private struct CountsKey: Equatable { let version: Int; let day: Date }
    @ObservationIgnored private let countsMemo = Memo<CountsKey, [Int]>()

    private var writer: VaultWriter? { vault.rootURL.map { VaultWriter(root: $0) } }

    // MARK: - Ändern

    func setDone(_ task: TaskItem, _ done: Bool, undoManager: UndoManager?) {
        if done { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        change(task, to: TaskLine.setting(task.rawLine, done: done), actionName: done ? L("Aufgabe erledigen") : L("Aufgabe öffnen"), undoManager: undoManager)
    }

    func setDue(_ task: TaskItem, _ due: Date?, undoManager: UndoManager?) {
        change(task, to: TaskLine.setting(task.rawLine, due: due), actionName: L("Fälligkeit ändern"), undoManager: undoManager)
    }

    func setPriority(_ task: TaskItem, _ priority: TaskPriority, undoManager: UndoManager?) {
        change(task, to: TaskLine.setting(task.rawLine, priority: priority), actionName: L("Priorität ändern"), undoManager: undoManager)
    }

    func rename(_ task: TaskItem, to title: String, undoManager: UndoManager?) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        change(task, to: TaskLine.setting(task.rawLine, title: trimmed), actionName: L("Aufgabe umbenennen"), undoManager: undoManager)
    }

    /// Mehrere Änderungen an einer Aufgabe in einem Schritt (eine Zeile, ein Rückgängig).
    func update(_ task: TaskItem, done: Bool? = nil, due: Date?? = nil, priority: TaskPriority? = nil, undoManager: UndoManager?) {
        var line = task.rawLine
        if let done { line = TaskLine.setting(line, done: done) }
        if let due { line = TaskLine.setting(line, due: due) }
        if let priority { line = TaskLine.setting(line, priority: priority) }
        change(task, to: line, actionName: L("Aufgabe ändern"), undoManager: undoManager)
    }

    /// Entfernt die Zeile. ⌘Z fügt sie an derselben Stelle wieder ein.
    func delete(_ task: TaskItem, undoManager: UndoManager?) {
        change(task, to: nil, actionName: L("Aufgabe löschen"), undoManager: undoManager)
    }

    /// Checkbox in der Notiz-Vorschau angeklickt.
    func toggleCheckbox(in relativePath: String, line: Int, undoManager: UndoManager?) {
        guard let task = tasks.first(where: { $0.relativePath == relativePath && $0.lineNumber == line }) else {
            lastError = L("Die Aufgabe wurde nicht gefunden. Die Datei hat sich vermutlich gerade geändert.")
            return
        }
        setDone(task, task.isOpen, undoManager: undoManager)
    }

    /// Neue Aufgabe anlegen – je nach Einstellung zentral oder im Ordner des Bereichs.
    func add(title: String, due: Date?, priority: TaskPriority = .none, area: String?, topic: String?, undoManager: UndoManager?) {
        guard let writer else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let storage = settings.settings.taskStorage
        let path: String
        let header: String
        var tags: [String] = []
        if storage == .perFolder, let area {
            let folder = [area, topic].compactMap { $0 }.joined(separator: "/")
            path = folder + "/Aufgaben.md"
            header = NoteTemplate.content(area: area, topic: topic, created: .now, body: "# Aufgaben") + "\n"
        } else {
            path = Self.centralFile
            header = "# Aufgaben\n\n"
            tags = [area, topic].compactMap { $0 }.map(NoteTemplate.tag(for:))
        }
        let line = TaskLine.make(title: trimmed, due: due, priority: priority, tags: tags)

        do {
            let index = try writer.appendLine(path, line: line, header: header)
            registerUndo(path: path, lineNumber: index, from: line, to: nil, actionName: L("Aufgabe hinzufügen"), undoManager: undoManager)
            refresh()
        } catch {
            lastError = L("Aufgabe konnte nicht gespeichert werden: \(localizedMessage(error))")
        }
    }

    // MARK: - Kern

    /// Sofort neu einlesen, damit die nächste Änderung auf dem aktuellen Stand der Datei arbeitet.
    private func refresh() {
        Task { await vault.rescan() }
    }

    private func change(_ task: TaskItem, to newLine: String?, actionName: String, undoManager: UndoManager?) {
        guard newLine != task.rawLine else { return }
        apply(path: task.relativePath, lineNumber: task.lineNumber, from: task.rawLine, to: newLine, actionName: actionName, undoManager: undoManager)
    }

    /// `from == nil`: Zeile einfügen; `to == nil`: Zeile entfernen; sonst ersetzen.
    private func apply(path: String, lineNumber: Int, from old: String?, to new: String?, actionName: String, undoManager: UndoManager?) {
        guard let writer else { return }
        do {
            let index: Int
            if let old {
                index = try writer.replaceLine(path, lineNumber: lineNumber, expected: old, with: new)
            } else if let new {
                try writer.insertLine(path, at: lineNumber, line: new)
                index = lineNumber
            } else {
                return
            }
            lastError = nil
            registerUndo(path: path, lineNumber: index, from: new, to: old, actionName: actionName, undoManager: undoManager)
            refresh()
        } catch {
            lastError = localizedMessage(error)
            refresh()
        }
    }

    /// Registriert die Gegenbewegung. Weil `apply` synchron läuft, landet sie beim Rückgängig
    /// automatisch auf dem Wiederholen-Stapel.
    private func registerUndo(path: String, lineNumber: Int, from: String?, to: String?, actionName: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { service in
            service.apply(path: path, lineNumber: lineNumber, from: from, to: to, actionName: actionName, undoManager: undoManager)
        }
        undoManager.setActionName(actionName)
    }
}
