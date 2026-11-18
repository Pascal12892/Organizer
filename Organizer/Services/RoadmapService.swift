import Foundation
import Observation
import OrganizerCore
import SwiftUI

/// Projekte und Meilensteine aus `_Organizer/Roadmap/`. Jede Änderung schreibt die Datei
/// nur, wenn sie seit dem Lesen unverändert ist, und lässt sich rückgängig machen.
@Observable
final class RoadmapService {
    private let vault: VaultService
    var lastError: String?

    init(vault: VaultService) {
        self.vault = vault
    }

    /// Im Hintergrund beim Scan berechnet (VaultIndex).
    var projects: [RoadmapProject] { vault.index.projects }

    private var writer: VaultWriter? { vault.rootURL.map { VaultWriter(root: $0) } }

    // MARK: - Ändern

    func setDates(of milestone: Milestone, start: Date?, end: Date?, undoManager: UndoManager?) {
        edit(milestone.relativePath, actionName: L("Meilenstein verschieben"), undoManager: undoManager) { raw in
            RoadmapEditor.setting([
                ("start", start.map { OrganizerDateFormat.string(from: $0, includingTime: false) }),
                ("ende", end.map { OrganizerDateFormat.string(from: $0, includingTime: false) }),
            ], milestoneAt: milestone.headingLine, in: raw)
        }
    }

    func setStatus(of milestone: Milestone, _ status: MilestoneStatus, undoManager: UndoManager?) {
        edit(milestone.relativePath, actionName: L("Status ändern"), undoManager: undoManager) { raw in
            RoadmapEditor.setting([("status", status.rawValue)], milestoneAt: milestone.headingLine, in: raw)
        }
    }

    func addTask(_ title: String, due: Date?, to milestone: Milestone, undoManager: UndoManager?) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        edit(milestone.relativePath, actionName: L("Aufgabe hinzufügen"), undoManager: undoManager) { raw in
            RoadmapEditor.insertingTask(TaskLine.make(title: trimmed, due: due), milestoneAt: milestone.headingLine, in: raw)
        }
    }

    func addMilestone(_ title: String, start: Date?, end: Date?, to project: RoadmapProject, undoManager: UndoManager?) {
        edit(project.relativePath, actionName: L("Meilenstein anlegen"), undoManager: undoManager) { raw in
            RoadmapEditor.appendingMilestone(title: title, start: start, end: end, to: raw)
        }
    }

    /// Legt ein neues Projekt an und gibt seinen Pfad zurück.
    @discardableResult
    func createProject(title: String, area: String?, start: Date?, end: Date?, color: String?, undoManager: UndoManager?) -> String? {
        guard let writer else { return nil }
        do {
            let content = RoadmapEditor.newProject(title: title, area: area, start: start, end: end, color: color)
            let path = try writer.createNote(folder: RoadmapParser.folder, title: title, content: content)
            undoManager?.registerUndo(withTarget: self) { service in
                do { try service.writer?.moveToTrash(path) } catch { service.lastError = localizedMessage(error) }
                Task { await service.vault.refresh(paths: [path]) }
            }
            undoManager?.setActionName(L("Projekt anlegen"))
            lastError = nil
            Task { await vault.refresh(paths: [path]) }
            return path
        } catch {
            lastError = L("Projekt konnte nicht angelegt werden: \(localizedMessage(error))")
            return nil
        }
    }

    // MARK: - Kern

    private func edit(_ path: String, actionName: String, undoManager: UndoManager?, transform: (String) -> String) {
        guard let writer else { return }
        do {
            let old = try writer.read(path)
            let new = transform(old)
            guard new != old else { return }
            try writer.save(path, newContent: new, expected: old)
            registerUndo(path: path, from: new, to: old, actionName: actionName, undoManager: undoManager)
            lastError = nil
        } catch {
            lastError = localizedMessage(error)
        }
        Task { await vault.refresh(paths: [path]) }
    }

    private func registerUndo(path: String, from current: String, to previous: String, actionName: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { service in
            guard let writer = service.writer else { return }
            do {
                try writer.save(path, newContent: previous, expected: current)
                service.registerUndo(path: path, from: previous, to: current, actionName: actionName, undoManager: undoManager)
            } catch {
                service.lastError = L("Rückgängig nicht möglich: \(localizedMessage(error))")
            }
            Task { await service.vault.refresh(paths: [path]) }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Farben

    static let colorNames = ["blue", "green", "orange", "red", "purple", "pink", "teal", "yellow", "gray"]

    static func color(named name: String?) -> Color {
        switch name?.lowercased() {
        case "green", "grün": .green
        case "orange": .orange
        case "red", "rot": .red
        case "purple", "lila", "violett": .purple
        case "pink": .pink
        case "teal", "türkis": .teal
        case "yellow", "gelb": .yellow
        case "gray", "grau": .gray
        default: .blue
        }
    }

    static func colorTitle(_ name: String) -> String {
        switch name {
        case "green": L("Grün")
        case "orange": L("Orange")
        case "red": L("Rot")
        case "purple": L("Lila")
        case "pink": L("Pink")
        case "teal": L("Türkis")
        case "yellow": L("Gelb")
        case "gray": L("Grau")
        default: L("Blau")
        }
    }
}
