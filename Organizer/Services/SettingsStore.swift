import Foundation
import OrganizerCore
import Observation

/// Darstellung der Aufgaben.
enum TaskLayout: String, Codable, CaseIterable {
    case list, board
}

/// Alle App-Einstellungen. Wird als JSON in Application Support gespeichert.
struct AppSettings: Codable, Equatable {
    /// Security-Scoped Bookmark auf den Vault-Ordner.
    var vaultBookmark: Data?
    /// Letzter bekannter Pfad, nur zur Anzeige, falls das Bookmark nicht mehr auflösbar ist.
    var vaultPath: String?
    var areas: [String] = VaultLayout.defaultAreas
    /// Ordner auf oberster Ebene automatisch als Bereiche verwenden (Struktur aus Obsidian übernehmen).
    var automaticAreas = true
    /// Ausgeblendete Kalender. Neue Kalender sind damit automatisch sichtbar.
    var hiddenCalendarIDs: Set<String> = []
    var calendarScope: CalendarScope = .week
    var taskStorage: TaskStorage = .central
    var taskFilter: TaskFilter = .today
    /// Aufgaben als Liste oder als Board mit Spalten nach Status.
    var taskLayout: TaskLayout = .list
    /// Zeitraum in der Ansicht „Erledigt“.
    var donePeriod: DonePeriod = .thisWeek
    /// Zugriffsrechte auf verknüpfte Mac-Ordner (Pfad → Security-Scoped Bookmark).
    var folderBookmarks: [String: Data] = [:]
    var quickCaptureHotKey = HotKeyPreset.controlOptionSpace.rawValue
    /// Ordner für schnelle Notizen ohne Bereichs-Tag.
    var quickNoteFolder = "Inbox"
    var showsMenuBarIcon = true
    /// Erinnerungen für fällige Aufgaben und Meilensteine.
    var notifiesDueItems = false
    /// Uhrzeit der Erinnerung in Minuten nach Mitternacht (Standard 8:30).
    var notificationMinutes = 8 * 60 + 30
    /// Aufgaben mit Apple Erinnerungen abgleichen.
    var syncsReminders = false

    init() {}

    /// Fehlende Schlüssel (aus älteren Versionen) bekommen Standardwerte.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vaultBookmark = try container.decodeIfPresent(Data.self, forKey: .vaultBookmark)
        vaultPath = try container.decodeIfPresent(String.self, forKey: .vaultPath)
        areas = try container.decodeIfPresent([String].self, forKey: .areas) ?? VaultLayout.defaultAreas
        automaticAreas = try container.decodeIfPresent(Bool.self, forKey: .automaticAreas) ?? true
        hiddenCalendarIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenCalendarIDs) ?? []
        calendarScope = try container.decodeIfPresent(CalendarScope.self, forKey: .calendarScope) ?? .week
        taskStorage = try container.decodeIfPresent(TaskStorage.self, forKey: .taskStorage) ?? .central
        taskFilter = try container.decodeIfPresent(TaskFilter.self, forKey: .taskFilter) ?? .today
        taskLayout = try container.decodeIfPresent(TaskLayout.self, forKey: .taskLayout) ?? .list
        donePeriod = try container.decodeIfPresent(DonePeriod.self, forKey: .donePeriod) ?? .thisWeek
        folderBookmarks = try container.decodeIfPresent([String: Data].self, forKey: .folderBookmarks) ?? [:]
        quickCaptureHotKey = try container.decodeIfPresent(String.self, forKey: .quickCaptureHotKey) ?? HotKeyPreset.controlOptionSpace.rawValue
        quickNoteFolder = try container.decodeIfPresent(String.self, forKey: .quickNoteFolder) ?? "Inbox"
        showsMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarIcon) ?? true
        notifiesDueItems = try container.decodeIfPresent(Bool.self, forKey: .notifiesDueItems) ?? false
        notificationMinutes = try container.decodeIfPresent(Int.self, forKey: .notificationMinutes) ?? 8 * 60 + 30
        syncsReminders = try container.decodeIfPresent(Bool.self, forKey: .syncsReminders) ?? false
    }
}

/// Lädt und speichert `AppSettings`. Fehler werden sichtbar gemacht, nicht verschluckt.
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings
    /// Letzter Fehler beim Lesen oder Schreiben der Einstellungsdatei.
    private(set) var lastError: String?

    private let fileURL: URL?

    /// - Parameter fileURL: `nil` hält die Einstellungen nur im Speicher (Previews).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL else {
            settings = AppSettings()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            settings = try JSONDecoder().decode(AppSettings.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            settings = AppSettings()
        } catch {
            settings = AppSettings()
            lastError = L("Einstellungen konnten nicht gelesen werden: \(localizedMessage(error))")
        }
    }

    static func inMemory(_ settings: AppSettings = AppSettings()) -> SettingsStore {
        let store = SettingsStore(fileURL: nil)
        store.settings = settings
        return store
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Organizer", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }

    var layout: VaultLayout { VaultLayout(areas: settings.areas, automaticAreas: settings.automaticAreas) }

    func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = L("Einstellungen konnten nicht gespeichert werden: \(localizedMessage(error))")
        }
    }
}
