import AppKit
import Observation
import OrganizerCore

/// Eine Datei in einem verknüpften Mac-Ordner.
struct LinkedFile: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let modified: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Ein Mac-Ordner, der mit einem Ordner im Vault (meist einem Thema) verknüpft ist.
struct LinkedFolder: Identifiable, Hashable {
    enum Status: Hashable {
        case available(files: [LinkedFile], total: Int)
        /// Steht im Frontmatter, aber Organizer hat (noch) keine Erlaubnis – z. B. nach Neuinstallation.
        case needsAccess
        case missing
        case failed(String)
    }

    let path: String
    var status: Status

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

/// Verknüpft Mac-Ordner mit Themen.
///
/// Quelle der Wahrheit ist die Eigenschaft `ordner` in `<Thema>/_index.md` – damit ist die
/// Verknüpfung auch in Obsidian sichtbar. Organizer speichert zusätzlich nur die Zugriffsrechte
/// (Security-Scoped Bookmarks) in seinen Einstellungen.
@Observable
final class FolderLinkService {
    static let propertyKey = "ordner"
    static let indexFileName = "_index.md"
    private static let maxListedFiles = 60

    private let vault: VaultService
    private let settings: SettingsStore
    /// Pfade, auf die gerade zugegriffen wird (Security Scope offen).
    @ObservationIgnored private var accessing: [String: URL] = [:]
    /// Zuletzt gelesener Inhalt pro Mac-Ordner.
    private(set) var cache: [String: LinkedFolder.Status] = [:]
    var lastError: String?

    init(vault: VaultService, settings: SettingsStore) {
        self.vault = vault
        self.settings = settings
    }

    // MARK: - Lesen

    static func indexPath(for folder: String) -> String {
        folder.isEmpty ? indexFileName : "\(folder)/\(indexFileName)"
    }

    /// Verknüpfte Pfade laut `_index.md`.
    func linkedPaths(for folder: String) -> [String] {
        let path = Self.indexPath(for: folder)
        let note = vault.notes.first { $0.relativePath == path }
        return note?.frontmatter?[Self.propertyKey]?.listValue ?? []
    }

    func linkedFolders(for folder: String) -> [LinkedFolder] {
        linkedPaths(for: folder).map { LinkedFolder(path: $0, status: cache[$0] ?? .needsAccess) }
    }

    /// Liest die Dateien der verknüpften Ordner neu ein.
    func refresh(folder: String) {
        for path in linkedPaths(for: folder) {
            cache[path] = load(path)
        }
    }

    private func load(_ path: String) -> LinkedFolder.Status {
        guard let url = accessibleURL(for: path) else {
            return settings.settings.folderBookmarks[path] == nil ? .needsAccess : .failed(L("Zugriff abgelaufen. Bitte erneut erlauben."))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        do {
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            let files = contents.map { item -> LinkedFile in
                let values = try? item.resourceValues(forKeys: Set(keys))
                return LinkedFile(url: item, isDirectory: values?.isDirectory ?? false, modified: values?.contentModificationDate)
            }
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            return .available(files: Array(files.prefix(Self.maxListedFiles)), total: files.count)
        } catch {
            return .failed(L("Ordner konnte nicht gelesen werden: \(localizedMessage(error))"))
        }
    }

    /// Löst das Bookmark auf und öffnet den Zugriff (einmal pro Sitzung).
    private func accessibleURL(for path: String) -> URL? {
        if let url = accessing[path] { return url }
        guard let bookmark = settings.settings.folderBookmarks[path],
              let (url, isStale) = try? SecurityScopedBookmark.resolve(bookmark) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if isStale, let fresh = try? SecurityScopedBookmark.make(for: url) {
            settings.update { $0.folderBookmarks[path] = fresh }
        }
        accessing[path] = url
        return url
    }

    // MARK: - Ändern

    /// Ordner per Dialog wählen und mit `folder` verknüpfen (mehrere möglich).
    func chooseAndLink(to folder: String, undoManager: UndoManager?) {
        let panel = NSOpenPanel()
        panel.title = L("Mac-Ordner verknüpfen")
        panel.message = L("Wähle einen oder mehrere Ordner, die zu „\(Self.displayName(folder))“ gehören.")
        panel.prompt = L("Verknüpfen")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL.desktopDirectory
        guard panel.runModal() == .OK else { return }
        link(panel.urls, to: folder, undoManager: undoManager)
    }

    /// Verknüpft bereits freigegebene URLs (Dialog oder Drag & Drop).
    func link(_ urls: [URL], to folder: String, undoManager: UndoManager?) {
        var paths = linkedPaths(for: folder)
        for url in urls {
            let path = url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
            do {
                let bookmark = try SecurityScopedBookmark.make(for: url)
                settings.update { $0.folderBookmarks[path] = bookmark }
            } catch {
                lastError = L("Zugriff auf „\(url.lastPathComponent)“ konnte nicht gespeichert werden: \(localizedMessage(error))")
                continue
            }
            if !paths.contains(path) { paths.append(path) }
        }
        writeLinks(paths, for: folder, actionName: L("Ordner verknüpfen"), undoManager: undoManager)
    }

    /// Zugriff für einen Pfad aus dem Frontmatter erneut erlauben.
    func grantAccess(to path: String) {
        let panel = NSOpenPanel()
        panel.title = L("Zugriff erlauben")
        panel.message = L("Wähle den Ordner „\((path as NSString).lastPathComponent)“, damit Organizer ihn anzeigen darf.")
        panel.prompt = L("Erlauben")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(filePath: path, directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let chosen = url.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        guard chosen == path else {
            lastError = L("Du hast „\(chosen)“ gewählt, verknüpft ist aber „\(path)“. Wähle genau diesen Ordner oder verknüpfe den neuen zusätzlich.")
            return
        }
        do {
            let bookmark = try SecurityScopedBookmark.make(for: url)
            settings.update { $0.folderBookmarks[path] = bookmark }
            accessing[path] = nil
            cache[path] = load(path)
        } catch {
            lastError = localizedMessage(error)
        }
    }

    func unlink(_ path: String, from folder: String, undoManager: UndoManager?) {
        let paths = linkedPaths(for: folder).filter { $0 != path }
        writeLinks(paths, for: folder, actionName: L("Verknüpfung entfernen"), undoManager: undoManager)
    }

    // MARK: - _index.md schreiben

    /// Schreibt nur die Eigenschaft `ordner` in `_index.md` (legt die Datei bei Bedarf an).
    private func writeLinks(_ paths: [String], for folder: String, actionName: String, undoManager: UndoManager?) {
        guard let root = vault.rootURL else { return }
        let writer = VaultWriter(root: root)
        let indexPath = Self.indexPath(for: folder)
        let exists = FileManager.default.fileExists(atPath: writer.url(for: indexPath).path(percentEncoded: false))
        do {
            if exists {
                let old = try writer.read(indexPath)
                let new = FrontmatterEditor.setting(Self.propertyKey, list: paths, in: old)
                guard new != old else { return }
                try writer.save(indexPath, newContent: new, expected: old)
                undoManager?.registerUndo(withTarget: self) { service in
                    service.restore(indexPath, to: old, from: new, actionName: actionName, undoManager: undoManager)
                }
            } else {
                guard !paths.isEmpty else { return }
                let (area, topic) = settings.layout.classify(folder: folder)
                let content = NoteTemplate.content(
                    area: area, topic: topic, created: .now,
                    extraProperties: [.init(key: Self.propertyKey, value: .list(paths))],
                    body: "# \(Self.displayName(folder))"
                )
                // Block-Liste wie Obsidian statt Inline-Liste:
                let formatted = FrontmatterEditor.setting(Self.propertyKey, list: paths, in: content)
                try writer.createFile(indexPath, content: formatted)
                undoManager?.registerUndo(withTarget: self) { service in
                    do { try writer.moveToTrash(indexPath) } catch { service.lastError = localizedMessage(error) }
                    Task { await service.vault.rescan() }
                }
            }
            undoManager?.setActionName(actionName)
            lastError = nil
        } catch {
            lastError = L("„\(indexPath)“ konnte nicht geschrieben werden: \(localizedMessage(error))")
        }
        Task {
            await vault.rescan()
            refresh(folder: folder)
        }
    }

    private func restore(_ indexPath: String, to content: String, from current: String, actionName: String, undoManager: UndoManager?) {
        guard let root = vault.rootURL else { return }
        let writer = VaultWriter(root: root)
        do {
            try writer.save(indexPath, newContent: content, expected: current)
            undoManager?.registerUndo(withTarget: self) { service in
                service.restore(indexPath, to: current, from: content, actionName: actionName, undoManager: undoManager)
            }
            undoManager?.setActionName(actionName)
        } catch {
            lastError = localizedMessage(error)
        }
        Task { await vault.rescan() }
    }

    static func displayName(_ folder: String) -> String {
        folder.split(separator: "/").last.map(String.init) ?? "Vault"
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        count > 1 && hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
