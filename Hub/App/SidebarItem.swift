import HubCore

/// Ein Eintrag in der Seitenleiste.
enum SidebarItem: Hashable {
    case dashboard
    case notes
    case calendar
    case tasks
    case roadmap
    case area(String)
    case topic(area: String, name: String)

    static let sections: [SidebarItem] = [.dashboard, .notes, .calendar, .tasks, .roadmap]

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .notes: "Notizen"
        case .calendar: "Kalender"
        case .tasks: "Aufgaben"
        case .roadmap: "Roadmap"
        case .area(let name): name
        case .topic(_, let name): name
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .notes: "note.text"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .roadmap: "map"
        case .area(let name): Self.areaSymbol(for: name)
        case .topic: "folder"
        }
    }

    /// Zeigt dieser Eintrag eine Notizliste (dreispaltiges Layout)?
    var noteScope: NoteScope? {
        switch self {
        case .notes: .all
        case .area(let name): .area(name)
        case .topic(let area, let name): .topic(area: area, name: name)
        default: nil
        }
    }

    /// In welcher Phase der Bereich fertig wird (für Platzhalter).
    var plannedPhase: Int? {
        switch self {
        case .dashboard: 7
        case .calendar: 3
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
        default: "square.stack"
        }
    }
}
