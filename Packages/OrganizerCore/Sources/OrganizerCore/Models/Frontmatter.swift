import Foundation

/// Ein Wert im YAML-Frontmatter. Unterstützt wird die Teilmenge, die Obsidian
/// in seinen „Eigenschaften“ selbst schreibt: Text und Listen.
public enum FrontmatterValue: Sendable, Hashable, Codable {
    case string(String)
    case list([String])

    /// Der Wert als Text; bei Listen das erste Element.
    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .list(let values): values.first
        }
    }

    /// Der Wert als Liste; ein einzelner Text wird zu einer Liste mit einem Element.
    public var listValue: [String] {
        switch self {
        case .string(let value): value.isEmpty ? [] : [value]
        case .list(let values): values
        }
    }
}

/// Geordnetes Frontmatter einer Notiz. Die Reihenfolge bleibt erhalten,
/// damit spätere Schreibvorgänge die Datei nicht umsortieren.
public struct Frontmatter: Sendable, Hashable, Codable {
    public struct Entry: Sendable, Hashable, Codable {
        public var key: String
        public var value: FrontmatterValue

        public init(key: String, value: FrontmatterValue) {
            self.key = key
            self.value = value
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Zugriff ohne Beachtung der Groß- und Kleinschreibung (Obsidian ist hier tolerant).
    public subscript(key: String) -> FrontmatterValue? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// Nicht-leerer Text-Wert für `key`, sonst `nil`.
    public func string(_ key: String) -> String? {
        guard let value = self[key]?.stringValue?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        return value
    }
}

/// Die Schlüssel, die Organizer im Frontmatter verwendet.
public enum FrontmatterKey {
    public static let area = "bereich"
    public static let topic = "thema"
    public static let created = "erstellt"
    public static let tags = "tags"
}
