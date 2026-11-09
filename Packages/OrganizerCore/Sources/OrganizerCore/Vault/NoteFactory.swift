import Foundation

/// Baut aus dem Inhalt einer Datei ein `Note`-Modell.
public enum NoteFactory {
    /// Regel für Bereich und Thema: Der Speicherort gewinnt, weil er in Obsidian
    /// beim Verschieben aktuell bleibt. Das Frontmatter gilt nur für Notizen
    /// außerhalb der Bereichsordner.
    public static func makeNote(
        relativePath: String,
        url: URL,
        content: String,
        modified: Date,
        fileCreated: Date? = nil,
        layout: VaultLayout
    ) -> Note {
        let parsed = FrontmatterParser.parse(content)
        let frontmatter = parsed.frontmatter
        let location = layout.classify(relativePath: relativePath)

        let area: String?
        let topic: String?
        if let pathArea = location.area {
            area = pathArea
            topic = location.topic
        } else {
            area = frontmatter?.string(FrontmatterKey.area).flatMap { layout.area(forFolder: $0) ?? $0 }
            topic = frontmatter?.string(FrontmatterKey.topic)
        }

        let created = frontmatter?.string(FrontmatterKey.created).flatMap { OrganizerDateFormat.parse($0) } ?? fileCreated
        let fileName = (relativePath as NSString).lastPathComponent
        let title = (fileName as NSString).deletingPathExtension

        return Note(
            relativePath: relativePath,
            url: url,
            title: title,
            area: area,
            topic: topic,
            tags: TagExtractor.tags(frontmatter: frontmatter, body: parsed.body),
            created: created,
            modified: modified,
            frontmatter: frontmatter,
            body: parsed.body,
            excerpt: Excerpt.make(from: parsed.body, title: title),
            issues: parsed.issues
        )
    }
}

/// Kurzer Vorschautext für Listen, ähnlich wie in Apple Notizen.
public enum Excerpt {
    public static func make(from body: String, title: String, limit: Int = 160) -> String {
        var parts: [String] = []
        var length = 0
        var inFence = false
        var skippedTitle = false

        for rawLine in body.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence || line.isEmpty || line == "---" { continue }

            let isHeading = line.hasPrefix("#") && line.drop(while: { $0 == "#" }).first == " "
            line = stripMarkup(line)
            if line.isEmpty { continue }
            if isHeading, !skippedTitle, line.caseInsensitiveCompare(title) == .orderedSame {
                skippedTitle = true
                continue
            }
            parts.append(line)
            length += line.count + 1
            if length >= limit { break }
        }

        let text = parts.joined(separator: " ")
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func stripMarkup(_ line: String) -> String {
        var text = line
        // Präfixe von Überschriften, Zitaten, Listen und Checkboxen.
        if let match = text.prefixMatch(of: #/(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX/-]\]\s+)?|\d+[.)]\s+(?:\[[ xX/-]\]\s+)?)+/#) {
            text.removeSubrange(match.range)
        }
        // [[Ziel|Alias]] → Alias, [[Ziel]] → Ziel
        text = text.replacing(#/!?\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/#) { match in
            String(match.output.2 ?? match.output.1)
        }
        // [Text](url) → Text
        text = text.replacing(#/!?\[([^\]]*)\]\([^)]*\)/#) { String($0.output.1) }
        for marker in ["**", "__", "~~", "==", "`"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
