import Foundation
import OrganizerCore

/// Die Werkzeuge, die Claude im Chat nutzen darf. Lesende Werkzeuge laufen sofort,
/// schreibende werden (je nach Einstellung) erst nach Bestätigung ausgeführt.
struct AssistantTool {
    let name: String
    let description: String
    let schema: JSONValue
    let isWrite: Bool

    var definition: JSONValue {
        [
            "name": .string(name),
            "description": .string(description),
            "input_schema": schema,
            // Eingaben werden gestreamt; Organizer prüft sie selbst (ToolInputValidator).
            "eager_input_streaming": true,
        ]
    }

    static let all: [AssistantTool] = [
        AssistantTool(
            name: "search_notes",
            description: "Volltextsuche in den Notizen des Obsidian-Vaults. Liefert bis zu 20 Treffer mit Pfad, Titel, Ordner, Tags und Vorschau.",
            schema: object(["query": string("Suchbegriffe, alle müssen vorkommen"), "folder": string("Optional: nur in diesem Ordner (relativer Pfad) suchen")], required: ["query"]),
            isWrite: false
        ),
        AssistantTool(
            name: "read_note",
            description: "Liest den vollständigen Markdown-Inhalt einer Notiz.",
            schema: object(["path": string("Relativer Pfad der Notiz, z. B. „Uni/Statistik/Formelsammlung.md“")], required: ["path"]),
            isWrite: false
        ),
        AssistantTool(
            name: "list_folders",
            description: "Listet alle Ordner im Vault. Ordner auf oberster Ebene sind Bereiche, ihre Unterordner Themen.",
            schema: object([:], required: []),
            isWrite: false
        ),
        AssistantTool(
            name: "list_tasks",
            description: "Listet Aufgaben aus dem Vault mit ID, Titel, Fälligkeit, Priorität, Bereich und Notiz.",
            schema: object([
                "filter": enumString(["today", "week", "all", "done"], "today: heute fällig und überfällig; week: diese Woche; all: alle offenen; done: erledigte"),
                "area": string("Optional: nur dieser Bereich"),
            ], required: ["filter"]),
            isWrite: false
        ),
        AssistantTool(
            name: "list_events",
            description: "Listet Termine aus dem Apple Kalender in einem Zeitraum.",
            schema: object([
                "start": string("Erster Tag, Format YYYY-MM-DD"),
                "end": string("Letzter Tag (inklusive), Format YYYY-MM-DD"),
            ], required: ["start", "end"]),
            isWrite: false
        ),
        AssistantTool(
            name: "create_note",
            description: "Legt eine neue Notiz im Vault an. Frontmatter (Bereich, Thema, Datum, Tags) ergänzt Organizer automatisch.",
            schema: object([
                "title": string("Titel, wird zum Dateinamen"),
                "folder": string("Relativer Ordnerpfad, z. B. „Uni/Statistik“; leer für die oberste Ebene"),
                "content": string("Inhalt in Markdown, ohne Frontmatter"),
            ], required: ["title", "folder"]),
            isWrite: true
        ),
        AssistantTool(
            name: "append_to_note",
            description: "Hängt Text an das Ende einer bestehenden Notiz an. Der vorhandene Inhalt bleibt unverändert.",
            schema: object(["path": string("Relativer Pfad der Notiz"), "text": string("Anzuhängender Markdown-Text")], required: ["path", "text"]),
            isWrite: true
        ),
        AssistantTool(
            name: "create_task",
            description: "Legt eine Aufgabe als Markdown-Checkbox im Format des Obsidian-Plugins „Tasks“ an.",
            schema: object([
                "title": string("Was zu tun ist"),
                "due": string("Optional: Fälligkeit, Format YYYY-MM-DD"),
                "priority": enumString(["highest", "high", "medium", "low", "lowest", "none"], "Optional: Priorität"),
                "area": string("Optional: Bereich (Ordner auf oberster Ebene)"),
                "topic": string("Optional: Thema (Unterordner des Bereichs)"),
            ], required: ["title"]),
            isWrite: true
        ),
        AssistantTool(
            name: "update_task",
            description: "Ändert eine bestehende Aufgabe: abhaken bzw. wieder öffnen, Fälligkeit oder Priorität. Die ID kommt aus list_tasks.",
            schema: object([
                "task_id": string("ID aus list_tasks"),
                "done": boolean("Optional: true = erledigt, false = wieder offen"),
                "due": string("Optional: neue Fälligkeit YYYY-MM-DD, leerer Text entfernt sie"),
                "priority": enumString(["highest", "high", "medium", "low", "lowest", "none"], "Optional: neue Priorität"),
            ], required: ["task_id"]),
            isWrite: true
        ),
        AssistantTool(
            name: "create_event",
            description: "Legt einen Termin im Apple Kalender an.",
            schema: object([
                "title": string("Titel des Termins"),
                "start": string("Beginn, Format YYYY-MM-DDTHH:MM (lokale Zeit) oder YYYY-MM-DD bei ganztägig"),
                "end": string("Optional: Ende im selben Format; ohne Angabe 1 Stunde"),
                "all_day": boolean("Optional: ganztägig"),
                "calendar": string("Optional: Name des Kalenders; sonst der Standardkalender"),
                "notes": string("Optional: Notizen zum Termin"),
            ], required: ["title", "start"]),
            isWrite: true
        ),
    ]

    static func named(_ name: String) -> AssistantTool? { all.first { $0.name == name } }

    // MARK: Schema-Bausteine

    private static func object(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })]
    }
    private static func string(_ description: String) -> JSONValue { ["type": "string", "description": .string(description)] }
    private static func boolean(_ description: String) -> JSONValue { ["type": "boolean", "description": .string(description)] }
    private static func enumString(_ values: [String], _ description: String) -> JSONValue {
        ["type": "string", "enum": .array(values.map { .string($0) }), "description": .string(description)]
    }
}

/// Führt Werkzeugaufrufe gegen die App aus.
struct AssistantToolExecutor {
    let model: AppModel

    struct ToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Kurze Beschreibung für Bestätigungskarte bzw. Verlauf.
    func summary(name: String, input: JSONValue) -> (title: String, details: [String], systemImage: String) {
        func s(_ key: String) -> String? { input[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
        switch name {
        case "search_notes": return ("Notizen durchsuchen: „\(s("query") ?? "")“", [], "magnifyingglass")
        case "read_note": return ("Notiz lesen: \(s("path") ?? "")", [], "doc.text")
        case "list_folders": return ("Ordner ansehen", [], "folder")
        case "list_tasks": return ("Aufgaben ansehen", [], "checklist")
        case "list_events": return ("Termine ansehen: \(s("start") ?? "") – \(s("end") ?? "")", [], "calendar")
        case "create_note":
            let folder = s("folder") ?? ""
            var details = ["Ordner: \(folder.isEmpty ? "oberste Ebene" : folder)"]
            if let content = s("content") { details.append(String(content.prefix(240)) + (content.count > 240 ? " …" : "")) }
            return ("Notiz anlegen: „\(s("title") ?? "")“", details, "note.text.badge.plus")
        case "append_to_note":
            let text = s("text") ?? ""
            return ("An Notiz anhängen: \(s("path") ?? "")", [String(text.prefix(240)) + (text.count > 240 ? " …" : "")], "text.append")
        case "create_task":
            var details: [String] = []
            if let due = s("due").flatMap({ OrganizerDateFormat.parse($0) }) { details.append("Fällig: \(TaskRow.relativeDay(due))") }
            if let priority = s("priority"), priority != "none" { details.append("Priorität: \(Self.priority(priority).title)") }
            if let area = s("area") { details.append("Bereich: \([area, s("topic")].compactMap { $0 }.joined(separator: " › "))") }
            return ("Aufgabe anlegen: „\(s("title") ?? "")“", details, "checklist")
        case "update_task":
            let task = model.tasks.tasks.first { $0.id == s("task_id") }
            var details: [String] = []
            if let done = input["done"]?.boolValue { details.append(done ? "Als erledigt markieren" : "Wieder öffnen") }
            if let due = input["due"]?.stringValue {
                details.append(due.isEmpty ? "Fälligkeit entfernen" : "Fällig: \(OrganizerDateFormat.parse(due).map(TaskRow.relativeDay) ?? due)")
            }
            if let priority = s("priority") { details.append("Priorität: \(Self.priority(priority).title)") }
            return ("Aufgabe ändern: „\(task?.title ?? s("task_id") ?? "")“", details, "checkmark.circle")
        case "create_event":
            var details: [String] = []
            if let start = s("start").flatMap({ OrganizerDateFormat.parse($0) }) {
                details.append(input["all_day"]?.boolValue == true
                    ? start.formatted(date: .complete, time: .omitted) + ", ganztägig"
                    : start.formatted(date: .complete, time: .shortened))
            }
            if let calendar = s("calendar") { details.append("Kalender: \(calendar)") }
            return ("Termin anlegen: „\(s("title") ?? "")“", details, "calendar.badge.plus")
        default:
            return (name, [], "wrench")
        }
    }

    /// Führt das Werkzeug aus und liefert das Ergebnis für Claude.
    func execute(name: String, input: JSONValue, undoManager: UndoManager?) async throws -> JSONValue {
        func s(_ key: String) -> String? { input[key]?.stringValue.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        guard model.vault.state == .ready || ["list_events", "create_event"].contains(name) else {
            throw ToolError(message: "In Organizer ist kein Vault geöffnet.")
        }

        switch name {
        case "search_notes":
            let scope: NoteScope = try s("folder").map { .folder(try safePath($0)) } ?? .all
            let notes = NoteQuery(scope: scope, searchText: s("query") ?? "").apply(to: model.vault.notes)
            return ["count": .number(Double(notes.count)), "notes": .array(notes.prefix(20).map(noteSummary))]

        case "read_note":
            let path = try safePath(s("path") ?? "")
            guard let writer = model.writer, model.vault.notes.contains(where: { $0.relativePath == path }) else {
                throw ToolError(message: "Die Notiz „\(path)“ gibt es nicht.")
            }
            let content = try writer.read(path)
            let limit = 60_000
            if content.count > limit {
                return ["path": .string(path), "content": .string(String(content.prefix(limit))),
                        "truncated": true, "note": "Die Notiz ist länger; nur die ersten 60.000 Zeichen wurden geliefert."]
            }
            return ["path": .string(path), "content": .string(content)]

        case "list_folders":
            return ["areas": .array(model.areas.map { .string($0) }),
                    "folders": .array(model.vault.snapshot.folders.map { .string($0) })]

        case "list_tasks":
            let filter = TaskFilter(rawValue: s("filter") ?? "today") ?? .today
            let sections = TaskGrouping.sections(model.tasks.tasks, filter: filter, area: s("area"))
            return ["sections": .array(sections.map { section in
                ["title": .string(section.title), "tasks": .array(section.tasks.prefix(100).map(taskSummary))]
            })]

        case "list_events":
            guard model.calendar.access == .fullAccess else {
                throw ToolError(message: "Organizer hat keinen Zugriff auf den Kalender. Der Nutzer kann ihn in der Kalenderansicht erlauben.")
            }
            guard let start = s("start").flatMap({ OrganizerDateFormat.parse($0) }),
                  let end = s("end").flatMap({ OrganizerDateFormat.parse($0) }) else {
                throw ToolError(message: "Ungültiges Datum. Format: YYYY-MM-DD.")
            }
            let calendar = Calendar.current
            let interval = DateInterval(start: calendar.startOfDay(for: start),
                                        end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(end, start)))!)
            let events = model.calendar.events(in: interval, hiddenCalendarIDs: model.settings.settings.hiddenCalendarIDs)
                .sorted { $0.start < $1.start }
            return ["events": .array(events.prefix(200).map { event in
                var item: [String: JSONValue] = [
                    "title": .string(event.title),
                    "start": .string(OrganizerDateFormat.string(from: event.start, includingTime: !event.isAllDay)),
                    "end": .string(OrganizerDateFormat.string(from: event.end, includingTime: !event.isAllDay)),
                    "all_day": .bool(event.isAllDay),
                    "calendar": .string(model.calendar.calendar(withID: event.calendarID)?.title ?? ""),
                ]
                if let location = event.location { item["location"] = .string(location) }
                return .object(item)
            })]

        case "create_note":
            let folder = try s("folder").map(safePath) ?? ""
            let path = try await model.createNote(title: s("title") ?? "", folder: folder, body: input["content"]?.stringValue ?? "",
                                                  openInEditor: false, undoManager: undoManager)
            return ["created": .string(path)]

        case "append_to_note":
            let path = try safePath(s("path") ?? "")
            guard let writer = model.writer, model.vault.notes.contains(where: { $0.relativePath == path }) else {
                throw ToolError(message: "Die Notiz „\(path)“ gibt es nicht.")
            }
            let old = try writer.read(path)
            let separator = old.isEmpty || old.hasSuffix("\n\n") ? "" : (old.hasSuffix("\n") ? "\n" : "\n\n")
            let new = old + separator + (input["text"]?.stringValue ?? "").trimmingCharacters(in: .newlines) + "\n"
            try writer.save(path, newContent: new, expected: old)
            undoManager?.registerUndo(withTarget: model) { model in
                do { try model.writer?.save(path, newContent: old, expected: new) }
                catch { model.writeError = "Rückgängig nicht möglich: \(error.localizedDescription)" }
                model.reloadVault()
            }
            undoManager?.setActionName("An Notiz anhängen")
            await model.vault.rescan()
            return ["appended_to": .string(path)]

        case "create_task":
            let due = try s("due").map(parseDate)
            let area = s("area").map { name in model.areas.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name }
            model.tasks.lastError = nil
            model.tasks.add(title: s("title") ?? "", due: due, priority: Self.priority(s("priority") ?? "none"),
                            area: area, topic: s("topic"), undoManager: undoManager)
            if let error = model.tasks.lastError { throw ToolError(message: error) }
            await model.vault.rescan()
            return ["created": true, "storage": .string(model.settings.settings.taskStorage == .central ? TaskService.centralFile : "Aufgaben.md im Ordner des Bereichs")]

        case "update_task":
            guard let task = model.tasks.tasks.first(where: { $0.id == s("task_id") }) else {
                throw ToolError(message: "Aufgabe nicht gefunden. Rufe list_tasks erneut auf, die IDs ändern sich, wenn Zeilen verschoben werden.")
            }
            // nil = unverändert, .some(nil) = Fälligkeit entfernen
            var due: Date?? = nil
            if let text = input["due"]?.stringValue {
                due = text.isEmpty ? .some(nil) : .some(try parseDate(text))
            }
            model.tasks.lastError = nil
            model.tasks.update(task, done: input["done"]?.boolValue, due: due,
                               priority: s("priority").map(Self.priority), undoManager: undoManager)
            if let error = model.tasks.lastError { throw ToolError(message: error) }
            await model.vault.rescan()
            return ["updated": .string(task.title)]

        case "create_event":
            guard model.calendar.access == .fullAccess else {
                throw ToolError(message: "Organizer hat keinen Zugriff auf den Kalender.")
            }
            let calendar = Calendar.current
            let isAllDay = input["all_day"]?.boolValue ?? false
            var start = try parseDate(s("start") ?? "")
            var end = try s("end").map(parseDate) ?? start.addingTimeInterval(3600)
            if isAllDay {
                start = calendar.startOfDay(for: start)
                end = max(calendar.startOfDay(for: end), start)
            }
            guard end >= start else { throw ToolError(message: "Das Ende liegt vor dem Beginn.") }
            let calendarID = s("calendar").flatMap { name in
                model.calendar.writableCalendars.first { $0.title.caseInsensitiveCompare(name) == .orderedSame }?.id
            } ?? model.calendar.defaultCalendarID
            guard let calendarID else { throw ToolError(message: "Kein beschreibbarer Kalender vorhanden.") }
            try model.createEvent(title: s("title") ?? "", start: start, end: end, isAllDay: isAllDay,
                                  calendarID: calendarID, notes: s("notes"), undoManager: undoManager)
            return ["created": true, "calendar": .string(model.calendar.calendar(withID: calendarID)?.title ?? "")]

        default:
            throw ToolError(message: "Unbekanntes Werkzeug „\(name)“.")
        }
    }

    // MARK: Hilfen

    /// Nur Pfade innerhalb des Vaults, keine versteckten Ordner.
    private func safePath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let components = trimmed.split(separator: "/")
        guard !components.contains(where: { $0 == ".." || $0 == "." || $0.hasPrefix(".") }) else {
            throw ToolError(message: "Ungültiger Pfad „\(path)“.")
        }
        return components.joined(separator: "/")
    }

    private func parseDate(_ string: String) throws -> Date {
        guard let date = OrganizerDateFormat.parse(string) else {
            throw ToolError(message: "Ungültiges Datum „\(string)“. Format: YYYY-MM-DD oder YYYY-MM-DDTHH:MM.")
        }
        return date
    }

    private func noteSummary(_ note: Note) -> JSONValue {
        [
            "path": .string(note.relativePath),
            "title": .string(note.title),
            "folder": .string(note.folderPath),
            "modified": .string(OrganizerDateFormat.string(from: note.modified)),
            "tags": .array(note.tags.map { .string($0) }),
            "excerpt": .string(note.excerpt),
        ]
    }

    private func taskSummary(_ task: TaskItem) -> JSONValue {
        var item: [String: JSONValue] = [
            "id": .string(task.id),
            "title": .string(task.title),
            "done": .bool(!task.isOpen),
            "note": .string(task.relativePath),
        ]
        if let due = task.due { item["due"] = .string(OrganizerDateFormat.string(from: due, includingTime: false)) }
        if let scheduled = task.scheduled { item["scheduled"] = .string(OrganizerDateFormat.string(from: scheduled, includingTime: false)) }
        if task.priority != .none { item["priority"] = .string(Self.priorityName(task.priority)) }
        if let area = task.area { item["area"] = .string(area) }
        if let topic = task.topic { item["topic"] = .string(topic) }
        return .object(item)
    }

    static func priority(_ name: String) -> TaskPriority {
        switch name {
        case "highest": .highest
        case "high": .high
        case "medium": .medium
        case "low": .low
        case "lowest": .lowest
        default: .none
        }
    }

    static func priorityName(_ priority: TaskPriority) -> String {
        switch priority {
        case .highest: "highest"
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case .lowest: "lowest"
        case .none: "none"
        }
    }
}
