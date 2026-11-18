import Foundation

/// Die Ordnerkonvention im Vault: `<Bereich>/<Thema>/…`.
///
/// Mit `automaticAreas` ist jeder sichtbare Ordner auf oberster Ebene ein Bereich –
/// die Struktur aus Obsidian wird also unverändert übernommen.
public struct VaultLayout: Sendable, Hashable, Codable {
    public static let organizerFolderName = "_Organizer"
    public static let defaultAreas = ["Uni", "Arbeit", "Freizeit"]

    public let areas: [String]
    public let automaticAreas: Bool

    public init(areas: [String] = VaultLayout.defaultAreas, automaticAreas: Bool = false) {
        self.areas = areas
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.automaticAreas = automaticAreas
    }

    /// Der Bereichsname für einen Ordner auf oberster Ebene, oder `nil`, wenn er kein Bereich ist.
    public func area(forFolder folder: some StringProtocol) -> String? {
        if automaticAreas {
            guard !Self.isHidden(folder), folder.caseInsensitiveCompare(Self.organizerFolderName) != .orderedSame else { return nil }
            return String(folder)
        }
        return areas.first { $0.compare(folder, options: .caseInsensitive) == .orderedSame }
    }

    /// Bereich und Thema allein aus dem Speicherort einer Datei.
    public func classify(relativePath: String) -> (area: String?, topic: String?) {
        let components = relativePath.split(separator: "/")
        guard components.count >= 2, let area = area(forFolder: components[0]) else {
            return (nil, nil)
        }
        let topic = components.count >= 3 ? String(components[1]) : nil
        return (area, topic)
    }

    /// Bereich und Thema für eine Notiz, die direkt in `folder` liegt.
    public func classify(folder: String) -> (area: String?, topic: String?) {
        classify(relativePath: folder.isEmpty ? "x.md" : folder + "/x.md")
    }

    /// Ordner und Dateien, die mit `.` beginnen (`.obsidian`, `.trash`), gehören nicht zum Inhalt.
    public static func isHidden(_ component: some StringProtocol) -> Bool {
        component.hasPrefix(".")
    }
}
