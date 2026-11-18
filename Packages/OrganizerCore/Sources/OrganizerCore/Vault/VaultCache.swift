import Foundation

/// Zuletzt gelesener Stand eines Vaults, auf der Platte gespeichert.
/// Beim Start zeigt die App diesen Stand sofort an und gleicht im Hintergrund ab –
/// unveränderte Dateien werden dabei nicht neu gelesen.
public struct VaultCache: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var vaultPath: String
    public var layout: VaultLayout
    public var notes: [Note]
    public var folders: [String]
    public var issues: [VaultIssue]

    public init(vaultPath: String, layout: VaultLayout, snapshot: VaultSnapshot) {
        version = Self.currentVersion
        self.vaultPath = vaultPath
        self.layout = layout
        notes = snapshot.notes
        folders = snapshot.folders
        issues = snapshot.issues
    }

    /// Passt der Zwischenspeicher zu diesem Vault und diesen Einstellungen?
    public func matches(vaultPath: String, layout: VaultLayout) -> Bool {
        version == Self.currentVersion && self.vaultPath == vaultPath && self.layout == layout
    }

    public var snapshot: VaultSnapshot {
        VaultScanner.assemble(notes: notes, folders: folders, issues: issues, layout: layout)
    }

    public static func load(from url: URL) -> VaultCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = PropertyListDecoder()
        return try? decoder.decode(VaultCache.self, from: data)
    }

    public func save(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
