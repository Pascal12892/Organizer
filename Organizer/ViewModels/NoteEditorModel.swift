import Foundation
import OrganizerCore
import Observation

/// Bearbeitet eine Notiz und hält sie mit der Datei im Vault synchron.
///
/// - Speichert automatisch kurz nach dem Tippen, beim Wechsel der Notiz und wenn Organizer in den Hintergrund geht.
/// - Ändert sich die Datei von außen (Obsidian) und es gibt keine ungespeicherten Änderungen,
///   wird der neue Stand still übernommen. Sonst entsteht ein sichtbarer Konflikt – nichts wird überschrieben.
@Observable
final class NoteEditorModel {
    enum Status: Equatable {
        case loading
        case ready
        case conflict(diskContent: String)
        case failed(String)
    }

    let relativePath: String
    private(set) var status: Status = .loading
    private(set) var hasUnsavedChanges = false

    /// Der bearbeitete Text ohne Frontmatter.
    var body: String {
        get { document?.body ?? "" }
        set {
            guard document != nil, newValue != document?.body else { return }
            document?.body = newValue
            hasUnsavedChanges = true
            scheduleSave()
        }
    }

    private let writer: VaultWriter
    private var document: NoteDocument?
    /// Was zuletzt auf der Platte stand – Grundlage für die Konfliktprüfung.
    private var diskContent = ""
    private var saveTask: Task<Void, Never>?

    init(relativePath: String, writer: VaultWriter) {
        self.relativePath = relativePath
        self.writer = writer
    }

    func load() {
        do {
            let raw = try writer.read(relativePath)
            diskContent = raw
            document = NoteDocument(raw: raw)
            hasUnsavedChanges = false
            status = .ready
        } catch {
            status = .failed(L("Die Notiz konnte nicht geöffnet werden: \(localizedMessage(error))"))
        }
    }

    /// Speichert sofort, falls nötig.
    func saveNow() {
        saveTask?.cancel()
        guard hasUnsavedChanges, let document, status == .ready else { return }
        let newContent = document.raw
        do {
            try writer.save(relativePath, newContent: newContent, expected: diskContent)
            diskContent = newContent
            hasUnsavedChanges = false
        } catch VaultWriter.WriteError.changedOnDisk(let current) {
            status = .conflict(diskContent: current)
        } catch {
            status = .failed(localizedMessage(error))
        }
    }

    /// Der Vault meldet eine Änderung dieser Datei (auch durch Organizer selbst).
    func fileChangedOnDisk() {
        guard let current = try? writer.read(relativePath), current != diskContent else { return }
        if hasUnsavedChanges {
            saveTask?.cancel()
            status = .conflict(diskContent: current)
        } else {
            diskContent = current
            document = NoteDocument(raw: current)
            if case .ready = status {} else { status = .ready }
        }
    }

    /// Konflikt lösen: Stand aus Obsidian übernehmen, eigene Änderungen verwerfen.
    func takeDiskVersion() {
        guard case .conflict(let current) = status else { return }
        diskContent = current
        document = NoteDocument(raw: current)
        hasUnsavedChanges = false
        status = .ready
    }

    /// Konflikt lösen: eigene Version speichern (überschreibt bewusst den Stand aus Obsidian).
    func keepMyVersion() {
        guard case .conflict = status, let document else { return }
        do {
            try writer.forceSave(relativePath, newContent: document.raw)
            diskContent = document.raw
            hasUnsavedChanges = false
            status = .ready
        } catch {
            status = .failed(localizedMessage(error))
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }
}
