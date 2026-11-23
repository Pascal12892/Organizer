import Foundation

/// Abgeleitete Daten eines Scans, einmal im Hintergrund berechnet statt bei jedem Neuzeichnen.
public struct VaultIndex: Sendable {
    /// Anzahl Notizen pro Ordner, Unterordner mitgezählt.
    public let folderNoteCounts: [String: Int]
    /// Projekte der Roadmap.
    public let projects: [RoadmapProject]
    /// Rückverweise: Pfad einer Notiz → Stellen, die auf sie verlinken.
    public let backlinks: [String: [Backlink]]

    public static let empty = VaultIndex(folderNoteCounts: [:], projects: [])

    public init(folderNoteCounts: [String: Int], projects: [RoadmapProject], backlinks: [String: [Backlink]] = [:]) {
        self.folderNoteCounts = folderNoteCounts
        self.projects = projects
        self.backlinks = backlinks
    }

    public init(snapshot: VaultSnapshot) {
        var counts: [String: Int] = [:]
        for note in snapshot.notes {
            let components = note.folderPath.split(separator: "/")
            for length in stride(from: components.count, through: 1, by: -1) {
                counts[components.prefix(length).joined(separator: "/"), default: 0] += 1
            }
        }
        folderNoteCounts = counts
        projects = snapshot.notes
            .filter(RoadmapParser.isRoadmapNote)
            .map { RoadmapParser.project(from: $0, tasks: snapshot.tasks) }
            .sorted { ($0.span?.start ?? .distantFuture, $0.title) < ($1.span?.start ?? .distantFuture, $1.title) }
        backlinks = BacklinkIndex.build(notes: snapshot.notes)
    }
}
