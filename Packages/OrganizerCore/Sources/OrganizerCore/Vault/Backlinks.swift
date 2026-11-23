import Foundation

/// Eine Stelle im Vault, die per Wikilink auf eine Notiz verweist.
public struct Backlink: Identifiable, Sendable, Hashable {
    /// Notiz, in der der Link steht.
    public let sourcePath: String
    public let sourceTitle: String
    /// 0-basierte Zeile in der Datei (inklusive Frontmatter), wie bei Aufgaben.
    public let lineNumber: Int
    /// Die Zeile lesbar gemacht: Listenzeichen und Wikilink-Klammern entfernt, gekürzt.
    public let excerpt: String
    /// Status, wenn die Zeile eine Aufgabe ist; sonst `nil`.
    public let taskStatus: TaskStatus?

    public var id: String { "\(sourcePath)#\(lineNumber)" }
    public var isTask: Bool { taskStatus != nil }

    public init(sourcePath: String, sourceTitle: String, lineNumber: Int, excerpt: String, taskStatus: TaskStatus?) {
        self.sourcePath = sourcePath
        self.sourceTitle = sourceTitle
        self.lineNumber = lineNumber
        self.excerpt = excerpt
        self.taskStatus = taskStatus
    }
}

/// Rückverweise für alle Notizen, einmal pro Scan im Hintergrund berechnet.
/// Links werden wie in Obsidian aufgelöst: zuerst über den Pfad, dann über den Dateinamen.
public enum BacklinkIndex {
    static let excerptLength = 160

    /// Pfad der Zielnotiz → Stellen, die auf sie verweisen (nach Quelle und Zeile sortiert).
    public static func build(notes: [Note]) -> [String: [Backlink]] {
        // Nachschlagetabellen statt WikiLinks.resolve pro Link: bei großen Vaults sonst quadratisch.
        var byPath: [String: String] = [:]
        var byName: [String: String] = [:]
        for note in notes {
            let path = note.relativePath.lowercased()
            byPath[path.hasSuffix(".md") ? String(path.dropLast(3)) : path] = note.relativePath
            let name = note.title.lowercased()
            if byName[name] == nil { byName[name] = note.relativePath }
        }
        func resolve(_ target: String) -> String? {
            let name = WikiLinks.noteName(fromTarget: target).lowercased()
            guard !name.isEmpty else { return nil }
            if name.contains("/"), let path = byPath[name] { return path }
            return byName[(name as NSString).lastPathComponent]
        }

        var result: [String: [Backlink]] = [:]
        for note in notes where note.body.contains("[[") {
            var inFence = false
            for (index, line) in note.body.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
                guard !inFence, line.contains("[[") else { continue }
                let text = String(line)
                // Jede Zielnotiz nur einmal pro Zeile, und keine Verweise einer Notiz auf sich selbst.
                let targets = Set(TaskLine.links(in: text).compactMap(resolve)).subtracting([note.relativePath])
                guard !targets.isEmpty else { continue }
                let backlink = Backlink(
                    sourcePath: note.relativePath,
                    sourceTitle: note.title,
                    lineNumber: note.bodyStartLine + index,
                    excerpt: excerpt(of: text),
                    taskStatus: TaskLine.parts(of: text)?.status
                )
                for target in targets { result[target, default: []].append(backlink) }
            }
        }
        return result.mapValues { links in
            links.sorted { ($0.sourceTitle.lowercased(), $0.lineNumber) < ($1.sourceTitle.lowercased(), $1.lineNumber) }
        }
    }

    /// Lesbare Kurzfassung einer Zeile: bei Aufgaben der Titel, sonst die Zeile ohne Listen- und Überschriftszeichen.
    static func excerpt(of line: String) -> String {
        let text: String
        if let parts = TaskLine.parts(of: line) {
            text = TaskLine.title(of: parts.description)
        } else {
            var rest = Substring(line.trimmingCharacters(in: .whitespaces))
            while let first = rest.first, "#>-*+".contains(first) { rest = rest.dropFirst() }
            text = rest.trimmingCharacters(in: .whitespaces)
        }
        let readable = TaskLine.displayTitle(text)
        guard readable.count > excerptLength else { return readable }
        return String(readable.prefix(excerptLength - 1)) + "…"
    }
}
