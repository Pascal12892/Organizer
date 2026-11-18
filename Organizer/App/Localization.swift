import Foundation
import OrganizerCore

/// Übersetzter Text für Stellen, an denen SwiftUI nicht von selbst übersetzt
/// (Bedingungen, Variablen, Meldungen). Der Schlüssel ist der deutsche Text.
nonisolated func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}

// MARK: - Anzeige für Typen aus OrganizerCore
// Der Kern bleibt sprachneutral bzw. deutsch, weil manche Werte ins Dateiformat gehören
// (z. B. „in Arbeit“ in Roadmap-Dateien). Übersetzt wird erst hier, für die Oberfläche.

extension TaskFilter {
    var localizedTitle: String {
        switch self {
        case .today: L("Heute")
        case .week: L("Diese Woche")
        case .all: L("Alle")
        case .done: L("Erledigt")
        }
    }
}

extension DonePeriod {
    var localizedTitle: String {
        switch self {
        case .today: L("Heute")
        case .yesterday: L("Gestern")
        case .thisWeek: L("Diese Woche")
        case .lastWeek: L("Letzte Woche")
        case .thisMonth: L("Dieser Monat")
        case .lastMonth: L("Letzter Monat")
        case .thisYear: L("Dieses Jahr")
        case .all: L("Alle")
        }
    }
}

extension CalendarScope {
    var localizedTitle: String {
        switch self {
        case .day: L("Tag")
        case .week: L("Woche")
        case .month: L("Monat")
        }
    }
}

extension TaskPriority {
    var localizedTitle: String {
        switch self {
        case .highest: L("Höchste")
        case .high: L("Hoch")
        case .medium: L("Mittel")
        case .low: L("Niedrig")
        case .lowest: L("Niedrigste")
        case .none: L("Keine")
        }
    }
}

extension MilestoneStatus {
    var localizedTitle: String {
        switch self {
        case .planned: L("Geplant")
        case .active: L("In Arbeit")
        case .done: L("Erledigt")
        case .paused: L("Pausiert")
        }
    }
}

extension TaskSection {
    var localizedTitle: String {
        switch id {
        case "overdue": L("Überfällig")
        case "today": L("Heute")
        case "done": L("Erledigt")
        case "area-none": L("Ohne Bereich")
        case "done-undated": L("Ohne Datum")
        default:
            switch title {
            case "Morgen": L("Morgen")
            case "Heute": L("Heute")
            case "Gestern": L("Gestern")
            default: title // Datumsangaben formatiert das System in der jeweiligen Sprache
            }
        }
    }
}

extension NoteSection {
    var localizedTitle: String {
        switch id {
        case "today": L("Heute")
        case "yesterday": L("Gestern")
        case "7days": L("Vorherige 7 Tage")
        case "30days": L("Vorherige 30 Tage")
        default: title // Monats- und Jahresnamen formatiert das System in der jeweiligen Sprache
        }
    }
}

extension VaultWriter.WriteError {
    nonisolated var localizedMessage: String {
        switch self {
        case .changedOnDisk: L("Die Notiz wurde in der Zwischenzeit außerhalb von Organizer geändert.")
        case .deletedOnDisk: L("Die Notiz existiert nicht mehr. Sie wurde verschoben oder gelöscht.")
        case .alreadyExists(let name): L("„\(name)“ gibt es bereits.")
        case .invalidName: L("Bitte gib einen Namen ein.")
        case .lineChanged: L("Die Aufgabe wurde in der Zwischenzeit in der Datei geändert. Bitte erneut versuchen.")
        }
    }
}

/// Fehlertext in der Sprache der App.
nonisolated func localizedMessage(_ error: Error) -> String {
    (error as? VaultWriter.WriteError)?.localizedMessage ?? error.localizedDescription
}
