import Foundation

/// Eine Erinnerung aus Apple Erinnerungen, unabhängig von EventKit (testbar).
public struct ReminderState: Sendable, Hashable {
    public let id: String
    public let title: String
    /// Fälligkeitstag (ohne Uhrzeit).
    public let due: Date?
    public let isCompleted: Bool
    /// Bereich laut Liste („Organizer – Uni“ → „Uni“), `nil` für die allgemeine Liste.
    public let area: String?

    public init(id: String, title: String, due: Date?, isCompleted: Bool, area: String?) {
        self.id = id
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
        self.area = area
    }

    public var signature: String { ReminderSync.signature(title: title, due: due, completed: isCompleted) }
}

/// Verknüpfung zwischen einer Aufgaben-Zeile und einer Erinnerung, mit dem zuletzt abgeglichenen Stand beider Seiten.
public struct ReminderLink: Codable, Sendable, Hashable {
    public var reminderID: String
    public var path: String
    public var title: String
    /// Die Zeile, wie sie beim letzten Abgleich in der Datei stand.
    public var lastLine: String
    /// Titel, Tag und Status der Erinnerung beim letzten Abgleich.
    public var lastSignature: String

    public init(reminderID: String, path: String, title: String, lastLine: String, lastSignature: String) {
        self.reminderID = reminderID
        self.path = path
        self.title = title
        self.lastLine = lastLine
        self.lastSignature = lastSignature
    }
}

/// Was beim Abgleich zu tun ist.
public enum ReminderSyncAction: Sendable, Hashable {
    /// Neue Erinnerung für eine Aufgabe anlegen.
    case createReminder(TaskItem)
    /// Erinnerung an den Stand der Aufgabe anpassen.
    case updateReminder(id: String, from: TaskItem)
    /// Spiegel-Erinnerung entfernen, weil die Aufgabe im Vault nicht mehr existiert.
    case deleteReminder(id: String)
    /// Aufgaben-Zeile an den Stand der Erinnerung anpassen.
    case updateTask(TaskItem, newLine: String, reminder: ReminderState)
    /// Neue Erinnerung (z. B. vom iPhone) als Aufgabe übernehmen.
    case importReminder(ReminderState, line: String)
}

/// Entscheidet, was beim Abgleich zwischen Markdown-Aufgaben und Erinnerungen passiert.
/// Regeln: Markdown ist die Quelle – hat sich die Zeile geändert, gewinnt sie.
/// Nur wenn ausschließlich die Erinnerung geändert wurde, wird die Zeile angepasst.
public enum ReminderSync {
    public static func signature(title: String, due: Date?, completed: Bool, timeZone: TimeZone = .current) -> String {
        let day = due.map { OrganizerDateFormat.string(from: $0, includingTime: false, timeZone: timeZone) } ?? "-"
        return "\(title.trimmingCharacters(in: .whitespaces))|\(day)|\(completed ? 1 : 0)"
    }

    /// Signatur, die eine aus `task` erzeugte Erinnerung hätte.
    public static func signature(for task: TaskItem, timeZone: TimeZone = .current) -> String {
        signature(title: task.title, due: task.relevantDate, completed: !task.isOpen, timeZone: timeZone)
    }

    /// Wird abgeglichen? Offene Aufgaben mit Datum.
    public static func isSyncable(_ task: TaskItem) -> Bool {
        task.isOpen && task.relevantDate != nil
    }

    public struct Plan: Sendable {
        public var actions: [ReminderSyncAction]
        /// Verknüpfungen, die erhalten bleiben (mit aktualisiertem Stand). Neue entstehen erst beim Ausführen.
        public var links: [ReminderLink]
        /// Aufgaben, deren Erinnerung du gelöscht hast (Schlüssel aus `dismissKey`). Sie bekommen erst wieder
        /// eine Erinnerung, wenn sich die Zeile ändert.
        public var dismissed: Set<String>
    }

    /// Schlüssel für „Erinnerung absichtlich gelöscht“: Datei und genaue Zeile.
    public static func dismissKey(path: String, line: String) -> String { path + "\n" + line }

    public static func plan(tasks: [TaskItem], reminders: [ReminderState], links: [ReminderLink],
                            dismissed: Set<String> = [], timeZone: TimeZone = .current) -> Plan {
        var dismissed = dismissed
        let remindersByID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var actions: [ReminderSyncAction] = []
        var keptLinks: [ReminderLink] = []
        var linkedTaskIDs = Set<String>()
        var linkedReminderIDs = Set<String>()

        for var link in links {
            // In Erinnerungen gelöscht → Verknüpfung lösen, Aufgabe bleibt unangetastet und
            // bekommt keine neue Erinnerung, solange die Zeile gleich bleibt.
            guard let reminder = remindersByID[link.reminderID] else {
                dismissed.insert(dismissKey(path: link.path, line: link.lastLine))
                if let task = find(link, in: tasks, excluding: linkedTaskIDs) { linkedTaskIDs.insert(task.id) }
                continue
            }
            linkedReminderIDs.insert(reminder.id)

            guard let task = find(link, in: tasks, excluding: linkedTaskIDs) else {
                // Aufgabe im Vault entfernt → Spiegel entfernen (die Erinnerung hat Organizer selbst angelegt).
                actions.append(.deleteReminder(id: reminder.id))
                continue
            }
            linkedTaskIDs.insert(task.id)

            if task.rawLine != link.lastLine {
                // Zeile geändert (Obsidian oder Organizer) → Markdown gewinnt.
                let expected = signature(for: task, timeZone: timeZone)
                if reminder.signature != expected { actions.append(.updateReminder(id: reminder.id, from: task)) }
                link.lastLine = task.rawLine
                link.title = task.title
                link.lastSignature = expected
            } else if reminder.signature != link.lastSignature {
                // Nur die Erinnerung wurde geändert → in die Zeile übernehmen.
                var line = task.rawLine
                if reminder.isCompleted == task.isOpen {
                    line = TaskLine.setting(line, done: reminder.isCompleted)
                }
                let reminderDay = reminder.due.map { OrganizerDateFormat.string(from: $0, includingTime: false, timeZone: timeZone) }
                let taskDay = task.relevantDate.map { OrganizerDateFormat.string(from: $0, includingTime: false, timeZone: timeZone) }
                if reminderDay != taskDay {
                    line = TaskLine.setting(line, due: reminder.due, timeZone: timeZone)
                }
                let title = reminder.title.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty, title != task.title {
                    line = TaskLine.setting(line, title: title)
                }
                if line != task.rawLine { actions.append(.updateTask(task, newLine: line, reminder: reminder)) }
                link.lastLine = line
                link.title = title.isEmpty ? task.title : title
                link.lastSignature = reminder.signature
            }
            keptLinks.append(link)
        }

        // Unverknüpfte Paare mit gleichem Titel und Tag wieder zusammenführen statt doppelt anzulegen
        // (Erinnerungen können beim ersten iCloud-Abgleich ihre Kennung wechseln).
        for reminder in reminders where !linkedReminderIDs.contains(reminder.id) {
            guard let task = tasks.first(where: { task in
                isSyncable(task) && !linkedTaskIDs.contains(task.id)
                    && signature(for: task, timeZone: timeZone) == reminder.signature
            }) else { continue }
            linkedTaskIDs.insert(task.id)
            linkedReminderIDs.insert(reminder.id)
            keptLinks.append(ReminderLink(reminderID: reminder.id, path: task.relativePath, title: task.title,
                                          lastLine: task.rawLine, lastSignature: reminder.signature))
        }

        // Neue Aufgaben mit Datum → neue Erinnerungen
        for task in tasks where isSyncable(task) && !linkedTaskIDs.contains(task.id)
            && !dismissed.contains(dismissKey(path: task.relativePath, line: task.rawLine)) {
            actions.append(.createReminder(task))
        }
        // Nur Einträge behalten, deren Zeile es noch gibt.
        let currentKeys = Set(tasks.map { dismissKey(path: $0.relativePath, line: $0.rawLine) })
        dismissed.formIntersection(currentKeys)

        // Neue offene Erinnerungen in den Organizer-Listen → Aufgaben in Tasks.md
        for reminder in reminders where !linkedReminderIDs.contains(reminder.id) && !reminder.isCompleted {
            let title = reminder.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            let tags = reminder.area.map { [NoteTemplate.tag(for: $0)] } ?? []
            actions.append(.importReminder(reminder, line: TaskLine.make(title: title, due: reminder.due, tags: tags, timeZone: timeZone)))
        }

        return Plan(actions: actions, links: keptLinks, dismissed: dismissed)
    }

    /// Findet die Aufgabe zu einer Verknüpfung: zuerst exakt dieselbe Zeile, sonst derselbe Titel in derselben Datei.
    static func find(_ link: ReminderLink, in tasks: [TaskItem], excluding used: Set<String>) -> TaskItem? {
        let candidates = tasks.filter { $0.relativePath == link.path && !used.contains($0.id) }
        if let exact = candidates.first(where: { $0.rawLine == link.lastLine }) { return exact }
        let sameTitle = candidates.filter { $0.title == link.title }
        return sameTitle.count == 1 ? sameTitle[0] : nil
    }
}
