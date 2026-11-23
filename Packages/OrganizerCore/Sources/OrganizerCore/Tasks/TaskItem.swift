import Foundation

/// Status einer Checkbox, wie das Obsidian-Plugin „Tasks“ sie kennt.
public enum TaskStatus: Sendable, Hashable {
    case open        // [ ]
    case inProgress  // [/]
    case done        // [x]
    case cancelled   // [-]
    case other(Character)

    init(_ character: Character) {
        switch character {
        case " ": self = .open
        case "/": self = .inProgress
        case "x", "X": self = .done
        case "-": self = .cancelled
        default: self = .other(character)
        }
    }

    public var character: Character {
        switch self {
        case .open: " "
        case .inProgress: "/"
        case .done: "x"
        case .cancelled: "-"
        case .other(let character): character
        }
    }

    public var isOpen: Bool { self == .open || self == .inProgress }
}

/// Priorität im Format des Tasks-Plugins.
public enum TaskPriority: Int, Sendable, Hashable, Comparable, CaseIterable {
    case lowest = -2, low = -1, none = 0, medium = 1, high = 2, highest = 3

    public var emoji: String? {
        switch self {
        case .highest: "🔺"
        case .high: "⏫"
        case .medium: "🔼"
        case .low: "🔽"
        case .lowest: "⏬"
        case .none: nil
        }
    }

    public var title: String {
        switch self {
        case .highest: "Höchste"
        case .high: "Hoch"
        case .medium: "Mittel"
        case .low: "Niedrig"
        case .lowest: "Niedrigste"
        case .none: "Keine"
        }
    }

    init?(emoji: Character) {
        guard let match = Self.allCases.first(where: { $0.emoji.map(Character.init) == emoji }) else { return nil }
        self = match
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Eine Aufgabe = eine Checkbox-Zeile in einer Markdown-Datei.
public struct TaskItem: Identifiable, Sendable, Hashable {
    public let relativePath: String
    /// 0-basierte Zeile in der Datei (inklusive Frontmatter).
    public let lineNumber: Int
    /// Die Zeile genau so, wie sie in der Datei steht (ohne Zeilenende). Grundlage für sichere Änderungen.
    public let rawLine: String
    public var title: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var due: Date?
    public var scheduled: Date?
    public var start: Date?
    public var doneDate: Date?
    public var created: Date?
    public var recurrence: String?
    public var tags: [String]
    /// Verlinkte Notizen als Wikilink-Ziele (`[[Gliederung]]` → `Gliederung`), in der Reihenfolge der Zeile.
    public var links: [String]
    public var area: String?
    public var topic: String?
    public var noteTitle: String

    public var id: String { "\(relativePath)#\(lineNumber)" }
    public var isOpen: Bool { status.isOpen }

    /// Das Datum, das für „fällig“ zählt: Deadline, sonst geplant.
    public var relevantDate: Date? { due ?? scheduled }

    /// Titel zum Anzeigen: Wikilinks als lesbarer Text (`[[Ordner/Gliederung|Plan]]` → `Plan`).
    public var displayTitle: String { TaskLine.displayTitle(title) }

    public init(relativePath: String, lineNumber: Int, rawLine: String, title: String, status: TaskStatus,
                priority: TaskPriority = .none, due: Date? = nil, scheduled: Date? = nil, start: Date? = nil,
                doneDate: Date? = nil, created: Date? = nil, recurrence: String? = nil, tags: [String] = [],
                links: [String] = [], area: String? = nil, topic: String? = nil, noteTitle: String = "") {
        self.relativePath = relativePath
        self.lineNumber = lineNumber
        self.rawLine = rawLine
        self.title = title
        self.status = status
        self.priority = priority
        self.due = due
        self.scheduled = scheduled
        self.start = start
        self.doneDate = doneDate
        self.created = created
        self.recurrence = recurrence
        self.tags = tags
        self.links = links
        self.area = area
        self.topic = topic
        self.noteTitle = noteTitle
    }
}
