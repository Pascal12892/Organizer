import Foundation

/// Eine Markdown-Datei im Vault. Die Datei bleibt die Quelle; dieses Modell ist nur eine Momentaufnahme.
public struct Note: Identifiable, Sendable, Hashable {
    /// Pfad relativ zum Vault, z. B. `Uni/Data Science/Vorlesung 1.md`. Dient als stabile ID.
    public let relativePath: String
    public let url: URL
    /// Dateiname ohne `.md` – so zeigt auch Obsidian den Titel an.
    public var title: String
    public var area: String?
    public var topic: String?
    public var tags: [String]
    public var created: Date?
    public var modified: Date
    public var frontmatter: Frontmatter?
    public var body: String
    public var excerpt: String
    public var issues: [String]
    /// 0-basierte Zeile, in der `body` in der Datei beginnt (nach dem Frontmatter).
    public var bodyStartLine: Int

    public var id: String { relativePath }

    /// Ordner der Notiz relativ zum Vault (leer für die oberste Ebene).
    public var folderPath: String {
        let components = relativePath.split(separator: "/")
        return components.dropLast().joined(separator: "/")
    }

    public init(
        relativePath: String,
        url: URL,
        title: String,
        area: String? = nil,
        topic: String? = nil,
        tags: [String] = [],
        created: Date? = nil,
        modified: Date,
        frontmatter: Frontmatter? = nil,
        body: String,
        excerpt: String,
        issues: [String] = [],
        bodyStartLine: Int = 0
    ) {
        self.relativePath = relativePath
        self.url = url
        self.title = title
        self.area = area
        self.topic = topic
        self.tags = tags
        self.created = created
        self.modified = modified
        self.frontmatter = frontmatter
        self.body = body
        self.excerpt = excerpt
        self.issues = issues
        self.bodyStartLine = bodyStartLine
    }
}

/// Ein Thema ist ein Unterordner eines Bereichs, z. B. `Uni/Data Science`.
public struct Topic: Identifiable, Sendable, Hashable {
    public let area: String
    public let name: String
    public let relativePath: String

    public var id: String { "\(area)/\(name)" }

    public init(area: String, name: String, relativePath: String) {
        self.area = area
        self.name = name
        self.relativePath = relativePath
    }
}

/// Ein Problem beim Lesen des Vaults, das in der Oberfläche angezeigt wird.
public struct VaultIssue: Identifiable, Sendable, Hashable {
    public let relativePath: String
    public let message: String

    public var id: String { relativePath + "|" + message }

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}
