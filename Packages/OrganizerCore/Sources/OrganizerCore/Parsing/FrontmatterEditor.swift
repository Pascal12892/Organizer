import Foundation

/// Ändert eine einzelne Eigenschaft im Frontmatter, ohne andere Zeilen anzufassen.
public enum FrontmatterEditor {
    /// Setzt `key` auf eine Liste (Block-Format, wie Obsidian es schreibt). Eine leere Liste entfernt die Eigenschaft.
    /// Fehlt das Frontmatter, wird es oben eingefügt; der übrige Inhalt bleibt Byte für Byte erhalten.
    public static func setting(_ key: String, list values: [String], in raw: String) -> String {
        let ending = raw.contains("\r\n") ? "\r\n" : "\n"
        let newLines = values.isEmpty ? [] : ["\(key):"] + values.map { "  - " + NoteTemplate.yamlValue($0) }

        var lines = raw.components(separatedBy: "\n")
        let hasCR = ending == "\r\n"
        func clean(_ line: String) -> String { hasCR && line.hasSuffix("\r") ? String(line.dropLast()) : line }

        guard FrontmatterParser.parse(raw).frontmatter != nil,
              let closing = lines.indices.dropFirst().first(where: { ["---", "..."].contains(clean(lines[$0]).trimmingCharacters(in: .whitespaces)) })
        else {
            guard !newLines.isEmpty else { return raw }
            let block = (["---"] + newLines + ["---"]).joined(separator: ending) + ending
            return block + raw
        }

        // Zeilen der Eigenschaft finden: „key:“ plus eingerückte bzw. „- “-Folgezeilen.
        let keyIndex = (1..<closing).first { index in
            let line = clean(lines[index])
            guard let colon = line.firstIndex(of: ":"), line.first != " ", line.first != "\t" else { return false }
            return line[..<colon].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) == .orderedSame
        }
        let suffix = hasCR ? "\r" : ""
        let replacement = newLines.map { $0 + suffix }

        if let keyIndex {
            var end = keyIndex + 1
            while end < closing {
                let line = clean(lines[end])
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard line.first == " " || line.first == "\t" || trimmed.hasPrefix("- ") || trimmed == "-" else { break }
                end += 1
            }
            lines.replaceSubrange(keyIndex..<end, with: replacement)
        } else {
            lines.insert(contentsOf: replacement, at: closing)
        }
        return lines.joined(separator: "\n")
    }
}
