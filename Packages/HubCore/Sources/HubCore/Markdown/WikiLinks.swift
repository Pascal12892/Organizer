import Foundation

/// Obsidian-Wikilinks (`[[Ziel]]`, `[[Ziel|Alias]]`). Standard-Markdown kennt sie nicht,
/// darum werden sie vor dem Parsen in normale Links mit eigenem Schema umgeschrieben.
public enum WikiLinks {
    public static let scheme = "hub-note"

    public static func url(forTarget target: String) -> URL? {
        let encoded = target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? target
        return URL(string: "\(scheme)://open?target=\(encoded)")
    }

    public static func target(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "target" }?
            .value
    }

    /// `[[Ziel|Alias]]` → `[Alias](hub-note://open?target=Ziel)`, außerhalb von Code.
    public static func rewrite(_ markdown: String) -> String {
        guard markdown.contains("[[") else { return markdown }
        return MarkdownText.transformOutsideCode(markdown) { text in
            text.replacing(#/!?\[\[([^\[\]|]+?)(?:\|([^\[\]]+?))?\]\]/#) { match in
                let target = String(match.output.1).trimmingCharacters(in: .whitespaces)
                let label = String(match.output.2 ?? match.output.1)
                    .replacingOccurrences(of: "[", with: "\\[")
                    .replacingOccurrences(of: "]", with: "\\]")
                guard let url = url(forTarget: target) else { return String(match.output.0) }
                return "[\(label)](\(url.absoluteString))"
            }
        }
    }

    /// Entfernt Überschriften- und Blockverweise: `Notiz#Abschnitt` → `Notiz`.
    public static func noteName(fromTarget target: String) -> String {
        let name = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.lowercased().hasSuffix(".md") ? String(trimmed.dropLast(3)) : trimmed
    }

    /// Findet die Notiz zu einem Link-Ziel wie Obsidian: zuerst Pfad, dann Dateiname.
    public static func resolve(_ target: String, in notes: [Note]) -> Note? {
        let name = noteName(fromTarget: target)
        guard !name.isEmpty else { return nil }
        if name.contains("/") {
            let path = name + ".md"
            if let note = notes.first(where: { $0.relativePath.caseInsensitiveCompare(path) == .orderedSame }) {
                return note
            }
        }
        let fileName = (name as NSString).lastPathComponent
        return notes.first { $0.title.caseInsensitiveCompare(fileName) == .orderedSame }
    }
}
