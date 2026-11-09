import Foundation

/// Was die Widgets anzeigen. Die App schreibt diese Datei in den gemeinsamen App-Group-Container;
/// die Widget-Erweiterung liest sie nur (sie hat keinen Zugriff auf Vault oder Kalender).
public struct WidgetSnapshot: Codable, Sendable {
    public struct TaskEntry: Codable, Sendable, Hashable {
        public let title: String
        public let due: Date?
        public let isOverdue: Bool
        public let area: String?
        public let priority: Int

        public init(title: String, due: Date?, isOverdue: Bool, area: String?, priority: Int) {
            self.title = title
            self.due = due
            self.isOverdue = isOverdue
            self.area = area
            self.priority = priority
        }
    }

    public struct EventEntry: Codable, Sendable, Hashable {
        public let title: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool
        /// Farbe des Kalenders als „#RRGGBB“.
        public let color: String
        public let calendar: String

        public init(title: String, start: Date, end: Date, isAllDay: Bool, color: String, calendar: String) {
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.color = color
            self.calendar = calendar
        }
    }

    public let generated: Date
    public let tasks: [TaskEntry]
    public let openTaskCount: Int
    public let events: [EventEntry]

    public init(generated: Date, tasks: [TaskEntry], openTaskCount: Int, events: [EventEntry]) {
        self.generated = generated
        self.tasks = tasks
        self.openTaskCount = openTaskCount
        self.events = events
    }

    public static let fileName = "widget-snapshot.json"

    /// Name der App Group aus der Info.plist (Schlüssel `OrganizerAppGroup`).
    public static var appGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "OrganizerAppGroup") as? String
    }

    public static var fileURL: URL? {
        guard let group = appGroup,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return container.appending(path: fileName)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save() throws {
        guard let url = Self.fileURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Kein gemeinsamer Container für die Widgets (App Group fehlt)."])
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
