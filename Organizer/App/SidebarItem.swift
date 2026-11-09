import OrganizerCore

/// Ein Eintrag in der Seitenleiste.
enum SidebarItem: Hashable {
    case dashboard
    case notes
    case calendar
    case tasks
    case roadmap
    /// Ein Ordner im Vault (relativer Pfad), beliebig tief verschachtelt.
    case folder(String)

    static let sections: [SidebarItem] = [.dashboard, .notes, .calendar, .tasks, .roadmap]

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .notes: "Notizen"
        case .calendar: "Kalender"
        case .tasks: "Aufgaben"
        case .roadmap: "Roadmap"
        case .folder(let path): path.split(separator: "/").last.map(String.init) ?? path
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .notes: "note.text"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .roadmap: "map"
        case .folder(let path): path.contains("/") ? "folder" : Self.areaSymbol(for: path)
        }
    }

    /// Zeigt dieser Eintrag eine Notizliste (dreispaltiges Layout)?
    var noteScope: NoteScope? {
        switch self {
        case .notes: .all
        case .folder(let path): .folder(path)
        default: nil
        }
    }

    var folderPath: String? {
        if case .folder(let path) = self { return path }
        return nil
    }

    /// In welcher Phase der Bereich fertig wird (für Platzhalter).
    var plannedPhase: Int? {
        switch self {
        case .dashboard: 7
        case .tasks: 4
        case .roadmap: 6
        default: nil
        }
    }

    static func areaSymbol(for name: String) -> String {
        switch name.lowercased() {
        case "uni", "studium", "schule": "graduationcap"
        case "arbeit", "job", "beruf": "briefcase"
        case "freizeit", "privat": "sun.max"
        case "sport": "figure.run"
        case "finanzen": "eurosign.circle"
        case "familie": "person.2"
        case "projekte": "hammer"
        case "archiv": "archivebox"
        case "inbox", "eingang": "tray"
        case "_hub": "square.grid.2x2"
        default: "folder"
        }
    }
}
