import Foundation

/// Ergebnis eines Durchlaufs durch den Vault.
public struct VaultSnapshot: Sendable, Hashable {
    public var notes: [Note]
    public var topics: [Topic]
    public var issues: [VaultIssue]

    public static let empty = VaultSnapshot(notes: [], topics: [], issues: [])

    public init(notes: [Note], topics: [Topic], issues: [VaultIssue]) {
        self.notes = notes
        self.topics = topics
        self.issues = issues
    }

    public func topics(in area: String) -> [Topic] {
        topics.filter { $0.area == area }
    }
}

/// Liest alle Markdown-Dateien eines Vaults. Rein lesend, ändert nie etwas.
/// Läuft synchron und ist für den Aufruf außerhalb des Main Actors gedacht.
public enum VaultScanner {
    /// Größere Dateien sind fast sicher keine Notizen und werden übersprungen.
    public static let maxFileSize = 5 * 1024 * 1024

    public static func scan(root: URL, layout: VaultLayout) -> VaultSnapshot {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        let enumerationErrors = IssueCollector()

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                enumerationErrors.add(VaultIssue(
                    relativePath: url.lastPathComponent,
                    message: "Ordner konnte nicht gelesen werden: \(error.localizedDescription)"
                ))
                return true
            }
        ) else {
            return VaultSnapshot(notes: [], topics: [], issues: [
                VaultIssue(relativePath: "", message: "Der Vault-Ordner konnte nicht geöffnet werden."),
            ])
        }

        var notes: [Note] = []
        var topics: [Topic] = []
        var issues: [VaultIssue] = []

        for case let url as URL in enumerator {
            var components = url.standardizedFileURL.pathComponents
            if !components.starts(with: rootComponents) {
                components = url.resolvingSymlinksInPath().pathComponents
            }
            let relative = Array(components.dropFirst(rootComponents.count))
            guard !relative.isEmpty, !relative.contains(where: VaultLayout.isHidden) else { continue }
            let relativePath = relative.joined(separator: "/")
            let values = try? url.resourceValues(forKeys: Set(keys))

            if values?.isDirectory == true {
                if relative.count == 2, let area = layout.area(forFolder: relative[0]) {
                    topics.append(Topic(area: area, name: relative[1], relativePath: relativePath))
                }
                continue
            }

            guard url.pathExtension.lowercased() == "md" else { continue }
            if let size = values?.fileSize, size > maxFileSize {
                issues.append(VaultIssue(relativePath: relativePath, message: "Datei ist größer als 5 MB und wurde übersprungen."))
                continue
            }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let note = NoteFactory.makeNote(
                    relativePath: relativePath,
                    url: url,
                    content: content,
                    modified: values?.contentModificationDate ?? .distantPast,
                    fileCreated: values?.creationDate,
                    layout: layout
                )
                notes.append(note)
                issues += note.issues.map { VaultIssue(relativePath: relativePath, message: $0) }
            } catch {
                issues.append(VaultIssue(
                    relativePath: relativePath,
                    message: "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
                ))
            }
        }

        notes.sort { $0.modified > $1.modified }
        topics.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return VaultSnapshot(notes: notes, topics: topics, issues: enumerationErrors.issues + issues)
    }
}

/// Sammelt Fehler aus dem `errorHandler` des Enumerators (wird synchron aufgerufen).
private final class IssueCollector: @unchecked Sendable {
    private(set) var issues: [VaultIssue] = []
    func add(_ issue: VaultIssue) { issues.append(issue) }
}
