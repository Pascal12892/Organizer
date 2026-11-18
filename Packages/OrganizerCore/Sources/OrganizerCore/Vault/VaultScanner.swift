import Foundation

/// Ergebnis eines Durchlaufs durch den Vault.
public struct VaultSnapshot: Sendable, Hashable {
    public var notes: [Note]
    public var topics: [Topic]
    public var issues: [VaultIssue]
    /// Alle sichtbaren Ordner, relativ zum Vault.
    public var folders: [String]
    /// Alle Aufgaben aus allen Notizen.
    public var tasks: [TaskItem]
    /// Wie viele Dateien und Ordner der Scan durchgehen musste (für den Hinweis bei riesigen Ordnern).
    public var entryCount = 0

    public static let empty = VaultSnapshot(notes: [], topics: [], issues: [])

    public init(notes: [Note], topics: [Topic], issues: [VaultIssue], folders: [String] = [], tasks: [TaskItem]? = nil) {
        self.notes = notes
        self.topics = topics
        self.issues = issues
        self.folders = folders
        self.tasks = tasks ?? notes.flatMap(TaskExtractor.tasks(in:))
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
    /// Ab so vielen Einträgen ist der Ordner vermutlich kein Vault (z. B. der ganze Schreibtisch).
    public static let largeFolderThreshold = 20_000
    /// Ordner, die Programme anlegen und die nie Notizen enthalten – werden gar nicht erst durchsucht.
    static let skippedFolders: Set<String> = ["node_modules", "__pycache__", "site-packages", "Pods", "DerivedData", "venv"]

    /// - Parameter previous: Notizen des letzten Scans (gleiches Layout). Unveränderte Dateien
    ///   (gleiches Änderungsdatum) werden übernommen statt neu gelesen – nach einer Änderung
    ///   muss so meist nur eine einzige Datei gelesen werden.
    public static func scan(root: URL, layout: VaultLayout, previous: [String: Note] = [:]) -> VaultSnapshot {
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
        var issues: [VaultIssue] = []
        var folders: [String] = []
        var entryCount = 0

        for case let url as URL in enumerator {
            entryCount += 1
            var components = url.standardizedFileURL.pathComponents
            if !components.starts(with: rootComponents) {
                components = url.resolvingSymlinksInPath().pathComponents
            }
            let relative = Array(components.dropFirst(rootComponents.count))
            guard !relative.isEmpty, !relative.contains(where: VaultLayout.isHidden) else { continue }
            let relativePath = relative.joined(separator: "/")
            let values = try? url.resourceValues(forKeys: Set(keys))

            if values?.isDirectory == true {
                if skippedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                folders.append(relativePath)
                continue
            }

            guard url.pathExtension.lowercased() == "md" else { continue }
            if let size = values?.fileSize, size > maxFileSize {
                issues.append(VaultIssue(relativePath: relativePath, message: "Datei ist größer als 5 MB und wurde übersprungen."))
                continue
            }

            if let modified = values?.contentModificationDate, let cached = previous[relativePath], cached.modified == modified {
                notes.append(cached)
                issues += cached.issues.map { VaultIssue(relativePath: relativePath, message: $0) }
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

        var snapshot = assemble(notes: notes, folders: folders, issues: enumerationErrors.issues + issues, layout: layout)
        snapshot.entryCount = entryCount
        return snapshot
    }

    /// Baut aus Notizen und Ordnern den vollständigen Stand: Themen, Aufgaben (mit Bereich), Sortierung.
    /// Wird nach jedem Scan und beim Laden aus dem Zwischenspeicher verwendet.
    public static func assemble(notes: [Note], folders: [String], issues: [VaultIssue], layout: VaultLayout) -> VaultSnapshot {
        let notes = notes.sorted { $0.modified > $1.modified }
        let folders = folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let topics = folders.compactMap { path -> Topic? in
            let parts = path.split(separator: "/")
            guard parts.count == 2, let area = layout.area(forFolder: parts[0]) else { return nil }
            return Topic(area: area, name: String(parts[1]), relativePath: path)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let areas = layout.automaticAreas
            ? folders.filter { !$0.contains("/") }.compactMap { layout.area(forFolder: $0) }
            : layout.areas
        let tasks = TaskExtractor.assignAreasByTags(notes.flatMap(TaskExtractor.tasks(in:)), topics: topics, areas: areas)
        return VaultSnapshot(notes: notes, topics: topics, issues: issues, folders: folders, tasks: tasks)
    }
}

/// Sammelt Fehler aus dem `errorHandler` des Enumerators (wird synchron aufgerufen).
private final class IssueCollector: @unchecked Sendable {
    private(set) var issues: [VaultIssue] = []
    func add(_ issue: VaultIssue) { issues.append(issue) }
}
