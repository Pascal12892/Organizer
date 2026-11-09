import Foundation

/// Status eines Meilensteins oder Projekts. Gespeichert wird der deutsche Begriff.
public enum MilestoneStatus: String, CaseIterable, Sendable, Hashable {
    case planned = "geplant"
    case active = "in Arbeit"
    case done = "erledigt"
    case paused = "pausiert"

    /// Tolerant gegenüber Schreibweisen aus Obsidian (auch Englisch).
    public init(text: String?) {
        switch text?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "in arbeit", "aktiv", "active", "in progress", "doing", "läuft": self = .active
        case "erledigt", "fertig", "done", "abgeschlossen", "completed": self = .done
        case "pausiert", "paused", "on hold", "wartet": self = .paused
        default: self = .planned
        }
    }
}

public struct Milestone: Identifiable, Sendable, Hashable {
    public let relativePath: String
    public var title: String
    public var start: Date?
    public var end: Date?
    public var status: MilestoneStatus
    public var tasks: [TaskItem]
    /// 0-basierte Zeile der Überschrift in der Datei.
    public var headingLine: Int

    public var id: String { "\(relativePath)#\(headingLine)" }

    /// Anteil erledigter Aufgaben; ohne Aufgaben zählt der Status.
    public var progress: Double {
        let relevant = tasks.filter { $0.status != .cancelled }
        guard !relevant.isEmpty else { return status == .done ? 1 : 0 }
        return Double(relevant.filter { $0.status == .done }.count) / Double(relevant.count)
    }

    public var isOverdue: Bool {
        guard status != .done, let end else { return false }
        return end < Calendar.current.startOfDay(for: .now)
    }
}

public struct RoadmapProject: Identifiable, Sendable, Hashable {
    public let relativePath: String
    public var title: String
    public var area: String?
    public var color: String?
    public var start: Date?
    public var end: Date?
    public var status: MilestoneStatus
    public var milestones: [Milestone]

    public var id: String { relativePath }

    /// Zeitraum aus den Projektdaten, sonst aus den Meilensteinen.
    public var span: DateInterval? {
        let starts = ([start] + milestones.map(\.start)).compactMap { $0 }
        let ends = ([end] + milestones.map(\.end)).compactMap { $0 }
        guard let first = start ?? starts.min(), let last = end ?? ends.max() ?? starts.max() else { return nil }
        return DateInterval(start: min(first, last), end: max(first, last))
    }

    public var progress: Double {
        let tasks = milestones.flatMap(\.tasks).filter { $0.status != .cancelled }
        if !tasks.isEmpty { return Double(tasks.filter { $0.status == .done }.count) / Double(tasks.count) }
        guard !milestones.isEmpty else { return status == .done ? 1 : 0 }
        return milestones.map(\.progress).reduce(0, +) / Double(milestones.count)
    }

    /// Nächste noch offene Meilensteine (für das Dashboard).
    public func upcomingMilestones(after date: Date = .now) -> [Milestone] {
        milestones.filter { $0.status != .done && ($0.end ?? .distantFuture) >= Calendar.current.startOfDay(for: date) }
            .sorted { ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture) }
    }
}

/// Liest ein Projekt aus einer Roadmap-Notiz:
///
///     ---
///     bereich: Uni
///     start: 2026-11-01
///     ende: 2027-03-31
///     status: in Arbeit
///     farbe: blue
///     ---
///     # Bachelorarbeit
///
///     ## Literaturrecherche
///     start:: 2026-11-01
///     ende:: 2026-11-30
///     status:: in Arbeit
///
///     - [ ] Quellen sammeln
public enum RoadmapParser {
    public static let folder = VaultLayout.organizerFolderName + "/Roadmap"

    public static func isRoadmapNote(_ note: Note) -> Bool {
        note.relativePath.hasPrefix(folder + "/") && note.relativePath.lowercased().hasSuffix(".md")
    }

    public static func project(from note: Note, tasks: [TaskItem], timeZone: TimeZone = .current) -> RoadmapProject {
        let frontmatter = note.frontmatter
        func date(_ key: String) -> Date? { frontmatter?.string(key).flatMap { OrganizerDateFormat.parse($0, timeZone: timeZone) } }

        var milestones: [Milestone] = []
        var inFence = false
        let lines = note.body.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            if trimmed.hasPrefix("## ") {
                milestones.append(Milestone(
                    relativePath: note.relativePath,
                    title: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces),
                    status: .planned,
                    tasks: [],
                    headingLine: note.bodyStartLine + index
                ))
            } else if trimmed.hasPrefix("# ") {
                continue
            } else if var milestone = milestones.popLast() {
                if let (key, value) = field(in: trimmed) {
                    switch key {
                    case "start", "beginn": milestone.start = OrganizerDateFormat.parse(value, timeZone: timeZone)
                    case "ende", "end", "fällig", "deadline": milestone.end = OrganizerDateFormat.parse(value, timeZone: timeZone)
                    case "status": milestone.status = MilestoneStatus(text: value)
                    default: break
                    }
                }
                milestones.append(milestone)
            }
        }

        // Aufgaben gehören zum Meilenstein, unter dessen Überschrift sie stehen.
        let fileTasks = tasks.filter { $0.relativePath == note.relativePath }
        for index in milestones.indices {
            let from = milestones[index].headingLine
            let to = index + 1 < milestones.count ? milestones[index + 1].headingLine : Int.max
            milestones[index].tasks = fileTasks.filter { $0.lineNumber > from && $0.lineNumber < to }
        }

        return RoadmapProject(
            relativePath: note.relativePath,
            title: frontmatter?.string("projekt") ?? note.title,
            area: note.area ?? frontmatter?.string(FrontmatterKey.area),
            color: frontmatter?.string("farbe"),
            start: date("start"),
            end: date("ende") ?? date("end"),
            status: MilestoneStatus(text: frontmatter?.string("status")),
            milestones: milestones
        )
    }

    /// `key:: wert` (Dataview-Inline-Feld).
    static func field(in line: String) -> (String, String)? {
        guard let range = line.range(of: "::") else { return nil }
        let key = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, key.wholeMatch(of: #/[\p{L}\p{N}_-]+/#) != nil else { return nil }
        return (key, line[range.upperBound...].trimmingCharacters(in: .whitespaces))
    }
}

/// Ändert Roadmap-Dateien zeilengenau.
public enum RoadmapEditor {
    /// Setzt Felder eines Meilensteins (`nil` entfernt das Feld). Andere Zeilen bleiben unverändert.
    public static func setting(_ fields: [(key: String, value: String?)], milestoneAt headingLine: Int, in raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        guard lines.indices.contains(headingLine) else { return raw }
        let cr = raw.contains("\r\n") ? "\r" : ""

        // Feldzeilen direkt unter der Überschrift
        var end = headingLine + 1
        while end < lines.count, RoadmapParser.field(in: lines[end].trimmingCharacters(in: .whitespacesAndNewlines)) != nil { end += 1 }

        for (key, value) in fields {
            let index = (headingLine + 1..<end).first {
                RoadmapParser.field(in: lines[$0].trimmingCharacters(in: .whitespacesAndNewlines))?.0 == key.lowercased()
            }
            switch (index, value) {
            case let (index?, value?): lines[index] = "\(key):: \(value)" + cr
            case let (index?, nil):
                lines.remove(at: index)
                end -= 1
            case let (nil, value?):
                lines.insert("\(key):: \(value)" + cr, at: end)
                end += 1
            case (nil, nil): break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Hängt einen neuen Meilenstein ans Dateiende an.
    public static func appendingMilestone(title: String, start: Date?, end: Date?, status: MilestoneStatus = .planned,
                                          to raw: String, timeZone: TimeZone = .current) -> String {
        let ending = raw.contains("\r\n") ? "\r\n" : "\n"
        var lines = ["## \(title.trimmingCharacters(in: .whitespaces))"]
        if let start { lines.append("start:: " + OrganizerDateFormat.string(from: start, includingTime: false, timeZone: timeZone)) }
        if let end { lines.append("ende:: " + OrganizerDateFormat.string(from: end, includingTime: false, timeZone: timeZone)) }
        lines.append("status:: \(status.rawValue)")
        var result = raw
        if !result.isEmpty {
            if !result.hasSuffix(ending) { result += ending }
            if !result.hasSuffix(ending + ending) { result += ending }
        }
        return result + lines.joined(separator: ending) + ending
    }

    /// Fügt eine Aufgabe am Ende des Meilensteins ein (nach der letzten Aufgabe bzw. den Feldern).
    public static func insertingTask(_ taskLine: String, milestoneAt headingLine: Int, in raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        guard lines.indices.contains(headingLine) else { return raw }
        let cr = raw.contains("\r\n") ? "\r" : ""
        func clean(_ index: Int) -> String { lines[index].trimmingCharacters(in: .whitespacesAndNewlines) }

        var sectionEnd = headingLine + 1
        while sectionEnd < lines.count, !clean(sectionEnd).hasPrefix("## "), !clean(sectionEnd).hasPrefix("# ") { sectionEnd += 1 }
        // Leere Zeilen am Ende des Abschnitts bleiben hinter der neuen Aufgabe.
        var insertAt = sectionEnd
        while insertAt > headingLine + 1, clean(insertAt - 1).isEmpty { insertAt -= 1 }

        var newLines = [taskLine + cr]
        let previous = clean(insertAt - 1)
        if insertAt - 1 == headingLine || RoadmapParser.field(in: previous) != nil {
            newLines.insert(cr, at: 0) // Leerzeile zwischen Feldern und Liste
        }
        if insertAt == lines.count, lines.last == "" {
            insertAt -= 1 // vor dem abschließenden Zeilenumbruch
        }
        lines.insert(contentsOf: newLines, at: insertAt)
        return lines.joined(separator: "\n")
    }

    public static func newProject(title: String, area: String?, start: Date?, end: Date?, color: String?,
                                  timeZone: TimeZone = .current) -> String {
        var properties: [Frontmatter.Entry] = []
        if let start { properties.append(.init(key: "start", value: .string(OrganizerDateFormat.string(from: start, includingTime: false, timeZone: timeZone)))) }
        if let end { properties.append(.init(key: "ende", value: .string(OrganizerDateFormat.string(from: end, includingTime: false, timeZone: timeZone)))) }
        properties.append(.init(key: "status", value: .string(MilestoneStatus.planned.rawValue)))
        if let color { properties.append(.init(key: "farbe", value: .string(color))) }
        return NoteTemplate.content(area: area, topic: nil, created: .now, extraTags: ["roadmap"], extraProperties: properties,
                                    body: "# \(title)\n\nZiel des Projekts in ein, zwei Sätzen.", timeZone: timeZone)
    }
}
