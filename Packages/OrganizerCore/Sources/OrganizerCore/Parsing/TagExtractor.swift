import Foundation

/// Sammelt Tags aus dem Frontmatter und aus dem Text (`#uni`), so wie Obsidian sie erkennt.
public enum TagExtractor {
    /// Alle Tags einer Notiz, ohne `#`, ohne Duplikate (Groß-/Kleinschreibung egal).
    public static func tags(frontmatter: Frontmatter?, body: String) -> [String] {
        deduplicated(frontmatterTags(frontmatter) + inlineTags(in: body))
    }

    public static func frontmatterTags(_ frontmatter: Frontmatter?) -> [String] {
        guard let value = frontmatter?[FrontmatterKey.tags] ?? frontmatter?["tag"] else { return [] }
        let raw: [String] = switch value {
        case .list(let values): values
        case .string(let value): value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        }
        return raw.compactMap(normalize)
    }

    public static func inlineTags(in body: String) -> [String] {
        var result: [String] = []
        var inFence = false
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            let text = MarkdownText.removingInlineCode(String(line))
            for match in text.matches(of: #/(?:^|\s)#([\p{L}\p{N}_\/-]+)/#) {
                if let tag = normalize(String(match.output.1)) { result.append(tag) }
            }
        }
        return result
    }

    /// Entfernt führende `#`; reine Zahlen sind in Obsidian keine Tags.
    public static func normalize(_ raw: String) -> String? {
        var tag = raw.trimmingCharacters(in: .whitespaces)
        while tag.hasPrefix("#") { tag.removeFirst() }
        guard !tag.isEmpty, tag.contains(where: { !$0.isNumber }) else { return nil }
        return tag
    }

    static func deduplicated(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }
    }
}

enum MarkdownText {
    /// Ersetzt `code`-Abschnitte durch Leerzeichen, damit darin nichts erkannt wird.
    static func removingInlineCode(_ line: String) -> String {
        guard line.contains("`") else { return line }
        return line.split(separator: "`", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset.isMultiple(of: 2) ? String($0.element) : " " }
            .joined()
    }

    /// Wendet `transform` nur auf Text außerhalb von Codeblöcken und Inline-Code an.
    static func transformOutsideCode(_ markdown: String, _ transform: (String) -> String) -> String {
        var inFence = false
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return String(line)
            }
            if inFence { return String(line) }
            guard line.contains("`") else { return transform(String(line)) }
            return line.split(separator: "`", omittingEmptySubsequences: false)
                .enumerated()
                .map { $0.offset.isMultiple(of: 2) ? transform(String($0.element)) : String($0.element) }
                .joined(separator: "`")
        }
        return lines.joined(separator: "\n")
    }
}
