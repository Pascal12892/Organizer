import Foundation

public struct FrontmatterParseResult: Sendable, Hashable {
    /// `nil`, wenn die Datei kein (gültig abgeschlossenes) Frontmatter hat.
    public var frontmatter: Frontmatter?
    /// Der Inhalt nach dem Frontmatter, mit `\n` als Zeilenende.
    public var body: String
    /// 0-basierte Zeilennummer, in der `body` in der Originaldatei beginnt.
    public var bodyStartLine: Int
    /// Lesbare Hinweise auf Zeilen, die nicht verstanden wurden.
    public var issues: [String]
}

/// Liest YAML-Frontmatter im Umfang, den Obsidian-Eigenschaften nutzen:
/// `key: wert`, `key: [a, b]`, Blocklisten mit `- a` und Anführungszeichen.
/// Verschachtelte Strukturen werden übersprungen, nicht falsch interpretiert.
public enum FrontmatterParser {
    public static func parse(_ text: String) -> FrontmatterParseResult {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        // "\r\n" ist in Swift ein einzelnes Zeichen, darum vorher vereinheitlichen.
        source = source.replacingOccurrences(of: "\r\n", with: "\n")

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, trimTrailing(first) == "---" else {
            return FrontmatterParseResult(frontmatter: nil, body: source, bodyStartLine: 0, issues: [])
        }

        let closing = lines.indices.dropFirst().first { index in
            let line = trimTrailing(lines[index])
            return line == "---" || line == "..."
        }
        guard let closing else {
            return FrontmatterParseResult(
                frontmatter: nil,
                body: source,
                bodyStartLine: 0,
                issues: ["Das Frontmatter wird nicht mit „---“ abgeschlossen."]
            )
        }

        var issues: [String] = []
        let frontmatter = parseProperties(lines[1..<closing], issues: &issues)
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return FrontmatterParseResult(frontmatter: frontmatter, body: body, bodyStartLine: closing + 1, issues: issues)
    }

    static func parseProperties(_ lines: ArraySlice<Substring>, issues: inout [String]) -> Frontmatter {
        var entries: [Frontmatter.Entry] = []
        // Index des Eintrags, unter dem gerade eine Blockliste (`- a`) stehen darf.
        var openListIndex: Int?

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if let index = openListIndex, trimmed == "-" || trimmed.hasPrefix("- ") {
                let item = unquote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                var values = entries[index].value.listValue
                if !item.isEmpty { values.append(item) }
                entries[index].value = .list(values)
                continue
            }

            // Eingerückte Zeilen gehören zu verschachtelten Strukturen, die Hub nicht nutzt.
            if line.first == " " || line.first == "\t" { continue }

            guard let colon = trimmed.firstIndex(of: ":") else {
                issues.append("Zeile im Frontmatter nicht lesbar: „\(trimmed)“")
                openListIndex = nil
                continue
            }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                issues.append("Eigenschaft ohne Namen im Frontmatter: „\(trimmed)“")
                openListIndex = nil
                continue
            }

            if rawValue.isEmpty {
                entries.append(.init(key: key, value: .string("")))
                openListIndex = entries.count - 1
            } else if rawValue.hasPrefix("["), rawValue.hasSuffix("]") {
                entries.append(.init(key: key, value: .list(parseInlineList(rawValue))))
                openListIndex = nil
            } else {
                entries.append(.init(key: key, value: .string(unquote(rawValue))))
                openListIndex = nil
            }
        }
        return Frontmatter(entries: entries)
    }

    /// `[a, "b, c", 'd']` → `["a", "b, c", "d"]`
    static func parseInlineList(_ value: String) -> [String] {
        let inner = value.dropFirst().dropLast()
        var items: [String] = []
        var current = ""
        var quote: Character?
        for character in inner {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current)
        return items
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        return first == "\""
            ? inner.replacingOccurrences(of: "\\\"", with: "\"")
            : inner.replacingOccurrences(of: "''", with: "'")
    }

    private static func trimTrailing(_ line: Substring) -> Substring {
        var line = line
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return line
    }
}
