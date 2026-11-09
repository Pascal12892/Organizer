import Foundation

/// Rohinhalt einer Notiz, aufgeteilt in Frontmatter-Block und Text.
/// Beim Zusammensetzen bleibt der Frontmatter-Block Byte für Byte erhalten,
/// ebenso das Zeilenende (`\n` oder `\r\n`). So ändert Organizer nur, was du bearbeitet hast.
public struct NoteDocument: Sendable, Hashable {
    /// Alles bis einschließlich der Zeile nach dem schließenden `---` (kann leer sein).
    public let frontmatterBlock: String
    /// Der Text, immer mit `\n` als Zeilenende.
    public var body: String
    public let lineEnding: String

    public init(raw: String) {
        lineEnding = raw.contains("\r\n") ? "\r\n" : "\n"
        let (block, rest) = Self.split(raw)
        frontmatterBlock = block
        body = rest.replacingOccurrences(of: "\r\n", with: "\n")
    }

    public var raw: String {
        let restored = lineEnding == "\n" ? body : body.replacingOccurrences(of: "\n", with: lineEnding)
        return frontmatterBlock + restored
    }

    /// Trennt am schließenden `---`, ohne den Text davor anzufassen.
    static func split(_ raw: String) -> (String, String) {
        guard FrontmatterParser.parse(raw).frontmatter != nil else { return ("", raw) }
        // Zeilen inkl. Zeilenende durchgehen und die Position nach dem zweiten Trenner finden.
        var index = raw.startIndex
        var lineNumber = 0
        while index < raw.endIndex {
            let lineEnd = raw[index...].firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) ?? raw.endIndex
            let line = raw[index..<lineEnd].trimmingCharacters(in: .whitespaces)
            let next = lineEnd < raw.endIndex ? raw.index(after: lineEnd) : raw.endIndex
            if lineNumber > 0, line == "---" || line == "..." {
                return (String(raw[..<next]), String(raw[next...]))
            }
            lineNumber += 1
            index = next
        }
        return ("", raw)
    }
}

/// Erzeugt neue Notizen im Organizer-Format.
public enum NoteTemplate {
    /// Dateiname ohne Zeichen, die macOS, Obsidian oder Links stören (`/ \ : * ? " < > | # ^ [ ]`).
    public static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return trimmed.isEmpty ? "Unbenannt" : String(trimmed.prefix(120))
    }

    /// Tag aus einem Namen: `Data Science` → `data-science`.
    public static func tag(for name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-/")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    public static func content(
        area: String?,
        topic: String?,
        created: Date,
        extraTags: [String] = [],
        extraProperties: [Frontmatter.Entry] = [],
        body: String,
        timeZone: TimeZone = .current
    ) -> String {
        var lines = ["---"]
        if let area { lines.append("bereich: \(yamlValue(area))") }
        if let topic { lines.append("thema: \(yamlValue(topic))") }
        lines.append("erstellt: \(OrganizerDateFormat.string(from: created, timeZone: timeZone))")
        let tags = TagExtractor.deduplicated(([area, topic].compactMap { $0 }.map(tag(for:)) + extraTags).filter { !$0.isEmpty })
        lines.append("tags: [\(tags.map(yamlValue).joined(separator: ", "))]")
        for entry in extraProperties {
            switch entry.value {
            case .string(let value): lines.append("\(entry.key): \(yamlValue(value))")
            case .list(let values): lines.append("\(entry.key): [\(values.map(yamlValue).joined(separator: ", "))]")
            }
        }
        lines.append("---")
        let text = body.trimmingCharacters(in: .newlines)
        return lines.joined(separator: "\n") + "\n" + (text.isEmpty ? "" : text + "\n")
    }

    /// Setzt Anführungszeichen nur, wenn YAML sie braucht.
    static func yamlValue(_ value: String) -> String {
        let needsQuotes = value.isEmpty
            || value.contains(where: { ":#,[]{}&*!|>'\"%@`".contains($0) })
            || value.first == " " || value.last == " "
            || ["true", "false", "yes", "no", "null", "~"].contains(value.lowercased())
            || Double(value) != nil
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Links in die Obsidian-App.
public enum ObsidianURL {
    /// `obsidian://open?vault=<Name>&file=<Pfad ohne .md>`
    public static func open(vaultName: String, relativePath: String) -> URL? {
        var path = relativePath
        if path.lowercased().hasSuffix(".md") { path.removeLast(3) }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let vault = vaultName.addingPercentEncoding(withAllowedCharacters: allowed),
              let file = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "obsidian://open?vault=\(vault)&file=\(file)")
    }
}
