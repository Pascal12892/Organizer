import Foundation

/// Alle Schreibzugriffe auf den Vault an einer Stelle.
/// Regeln: nie ungefragt überschreiben, nie löschen (nur in den Papierkorb, und nur per Rückgängig),
/// und vor dem Speichern prüfen, ob die Datei inzwischen woanders geändert wurde.
public struct VaultWriter: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public enum WriteError: LocalizedError {
        /// Die Datei wurde seit dem Laden geändert (z. B. in Obsidian).
        case changedOnDisk(current: String)
        case deletedOnDisk
        case alreadyExists(String)
        case invalidName

        public var errorDescription: String? {
            switch self {
            case .changedOnDisk: "Die Notiz wurde in der Zwischenzeit außerhalb von Hub geändert."
            case .deletedOnDisk: "Die Notiz existiert nicht mehr. Sie wurde verschoben oder gelöscht."
            case .alreadyExists(let name): "„\(name)“ gibt es bereits."
            case .invalidName: "Bitte gib einen Namen ein."
            }
        }
    }

    public func url(for relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    public func read(_ relativePath: String) throws -> String {
        var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url(for: relativePath), options: [], error: &coordinationError) { url in
            result = Result { try String(contentsOf: url, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Speichert `newContent` nur, wenn auf der Platte noch `expected` steht.
    public func save(_ relativePath: String, newContent: String, expected: String) throws {
        let fileURL = url(for: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            throw WriteError.deletedOnDisk
        }
        let current = try read(relativePath)
        guard current == expected else { throw WriteError.changedOnDisk(current: current) }
        guard current != newContent else { return }
        try coordinatedWrite(newContent, to: fileURL, overwrite: true)
    }

    /// Überschreibt ausdrücklich – nur nach Bestätigung im Konfliktfall.
    public func forceSave(_ relativePath: String, newContent: String) throws {
        try coordinatedWrite(newContent, to: url(for: relativePath), overwrite: true)
    }

    /// Legt eine neue Notiz an. Gibt es den Namen schon, wird „Titel 2“, „Titel 3“ … verwendet.
    public func createNote(folder: String, title: String, content: String) throws -> String {
        let folderURL = folder.isEmpty ? root : root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let baseName = NoteTemplate.fileName(for: title)
        for counter in 1...999 {
            let name = counter == 1 ? baseName : "\(baseName) \(counter)"
            let fileURL = folderURL.appending(path: name + ".md")
            guard !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { continue }
            try coordinatedWrite(content, to: fileURL, overwrite: false)
            return folder.isEmpty ? name + ".md" : "\(folder)/\(name).md"
        }
        throw WriteError.alreadyExists(baseName)
    }

    /// Legt einen Themen-Ordner an.
    public func createTopic(area: String, name: String) throws -> String {
        try createFolder(parent: area, name: name)
    }

    /// Legt einen Ordner in `parent` an (leer = oberste Ebene des Vaults).
    public func createFolder(parent: String, name: String) throws -> String {
        let clean = NoteTemplate.fileName(for: name)
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw WriteError.invalidName }
        let relativePath = parent.isEmpty ? clean : "\(parent)/\(clean)"
        let folderURL = root.appending(path: relativePath, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: folderURL.path(percentEncoded: false)) {
            throw WriteError.alreadyExists(clean)
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return relativePath
    }

    /// Verschiebt eine Datei in den Papierkorb (wiederherstellbar). Nur für Rückgängig.
    public func moveToTrash(_ relativePath: String) throws {
        try FileManager.default.trashItem(at: url(for: relativePath), resultingItemURL: nil)
    }

    private func coordinatedWrite(_ content: String, to fileURL: URL, overwrite: Bool) throws {
        var writeError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: overwrite ? .forReplacing : [], error: &coordinationError) { url in
            do {
                let data = Data(content.utf8)
                try data.write(to: url, options: overwrite ? .atomic : .withoutOverwriting)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
