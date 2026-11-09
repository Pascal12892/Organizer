import Foundation

/// Die Ordnerkonvention im Vault: `<Bereich>/<Thema>/…`.
public struct VaultLayout: Sendable, Hashable {
    public static let hubFolderName = "_Hub"
    public static let defaultAreas = ["Uni", "Arbeit", "Freizeit"]

    public let areas: [String]

    public init(areas: [String] = VaultLayout.defaultAreas) {
        self.areas = areas
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Der konfigurierte Bereichsname für einen Ordnernamen (Groß-/Kleinschreibung egal).
    public func area(forFolder folder: some StringProtocol) -> String? {
        areas.first { $0.compare(folder, options: .caseInsensitive) == .orderedSame }
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

    /// Ordner und Dateien, die mit `.` beginnen (`.obsidian`, `.trash`), gehören nicht zum Inhalt.
    public static func isHidden(_ component: some StringProtocol) -> Bool {
        component.hasPrefix(".")
    }
}
