import Foundation

/// Sammelt Aufgaben aus Notizen ein.
public enum TaskExtractor {
    /// Alle Checkbox-Zeilen außerhalb von Codeblöcken.
    public static func tasks(in note: Note) -> [TaskItem] {
        var result: [TaskItem] = []
        var inFence = false
        for (index, line) in note.body.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
            guard !inFence, trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("+") || trimmed.first?.isNumber == true,
                  var task = TaskLine.parse(String(line), relativePath: note.relativePath, lineNumber: note.bodyStartLine + index)
            else { continue }
            task.area = note.area
            task.topic = note.topic
            task.noteTitle = note.title
            result.append(task)
        }
        return result
    }

    /// Ordnet Aufgaben ohne Bereich (z. B. aus der zentralen Tasks.md) über ihre Tags zu:
    /// `#uni` → Bereich „Uni“, `#data-science` → Thema „Data Science“.
    public static func assignAreasByTags(_ tasks: [TaskItem], topics: [Topic], areas: [String]) -> [TaskItem] {
        let areaByTag = Dictionary(areas.map { (NoteTemplate.tag(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        return tasks.map { task in
            guard task.area == nil else { return task }
            var task = task
            let tags = task.tags.map { $0.lowercased() }
            task.area = tags.lazy.compactMap { areaByTag[$0] }.first
            if let area = task.area {
                task.topic = topics.first { $0.area == area && tags.contains(NoteTemplate.tag(for: $0.name)) }?.name
            }
            return task
        }
    }
}

/// Ansichten der Aufgabenliste.
public enum TaskFilter: String, CaseIterable, Sendable, Hashable, Codable {
    case today, week, all, done

    public var title: String {
        switch self {
        case .today: "Heute"
        case .week: "Diese Woche"
        case .all: "Alle"
        case .done: "Erledigt"
        }
    }
}

public struct TaskSection: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let tasks: [TaskItem]
    public let isOverdue: Bool
}

public enum TaskGrouping {
    /// Reihenfolge innerhalb einer Gruppe: Datum, dann Priorität, dann Titel.
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            let l = lhs.relevantDate ?? .distantFuture, r = rhs.relevantDate ?? .distantFuture
            if l != r { return l < r }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public static func isOverdue(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard task.isOpen, let date = task.relevantDate else { return false }
        return date < calendar.startOfDay(for: now)
    }

    public static func isDueToday(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard task.isOpen, let date = task.relevantDate else { return false }
        return calendar.isDate(date, inSameDayAs: now)
    }

    public static func sections(_ tasks: [TaskItem], filter: TaskFilter, area: String? = nil,
                                now: Date = .now, calendar: Calendar = .current) -> [TaskSection] {
        let scoped = area.map { area in tasks.filter { $0.area == area } } ?? tasks
        let open = scoped.filter(\.isOpen)
        let overdue = sorted(open.filter { isOverdue($0, now: now, calendar: calendar) })
        let overdueSection = overdue.isEmpty ? [] : [TaskSection(id: "overdue", title: "Überfällig", tasks: overdue, isOverdue: true)]

        switch filter {
        case .today:
            let today = sorted(open.filter { isDueToday($0, now: now, calendar: calendar) })
            return overdueSection + (today.isEmpty ? [] : [TaskSection(id: "today", title: "Heute", tasks: today, isOverdue: false)])

        case .week:
            let days = CalendarMath.weekDays(containing: now, calendar: calendar).filter { $0 >= calendar.startOfDay(for: now) }
            let daySections = days.compactMap { day -> TaskSection? in
                let due = sorted(open.filter { $0.relevantDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false })
                guard !due.isEmpty else { return nil }
                let title = calendar.isDateInToday(day) ? "Heute"
                    : calendar.isDateInTomorrow(day) ? "Morgen"
                    : day.formatted(.dateTime.weekday(.wide).day().month(.wide))
                return TaskSection(id: "day-\(Int(day.timeIntervalSinceReferenceDate))", title: title, tasks: due, isOverdue: false)
            }
            return overdueSection + daySections

        case .all:
            let byArea = Dictionary(grouping: open) { $0.area ?? "" }
            let areaNames = byArea.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            var sections = areaNames.map { TaskSection(id: "area-\($0)", title: $0, tasks: sorted(byArea[$0]!), isOverdue: false) }
            if let rest = byArea[""], !rest.isEmpty {
                sections.append(TaskSection(id: "area-none", title: "Ohne Bereich", tasks: sorted(rest), isOverdue: false))
            }
            return sections

        case .done:
            let done = scoped.filter { $0.status == .done || $0.status == .cancelled }
                .sorted { ($0.doneDate ?? .distantPast) > ($1.doneDate ?? .distantPast) }
            return done.isEmpty ? [] : [TaskSection(id: "done", title: "Erledigt", tasks: Array(done.prefix(300)), isOverdue: false)]
        }
    }

    /// Zahlen für die Seitenleiste.
    public static func counts(_ tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> (open: Int, dueToday: Int, overdue: Int) {
        let open = tasks.filter(\.isOpen)
        return (
            open.count,
            open.filter { isDueToday($0, now: now, calendar: calendar) }.count,
            open.filter { isOverdue($0, now: now, calendar: calendar) }.count
        )
    }
}
