import Foundation
import Testing
@testable import OrganizerCore

@Suite("Aufgaben-Zeilen")
struct TaskLineTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        calendar.firstWeekday = 2
        return calendar
    }
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func parsesTasksPluginLine() throws {
        let task = try #require(TaskLine.parse("- [ ] Hausarbeit Kapitel 2 schreiben ⏫ 📅 2026-11-20 #uni", timeZone: berlin))
        #expect(task.title == "Hausarbeit Kapitel 2 schreiben")
        #expect(task.status == .open)
        #expect(task.priority == .high)
        #expect(task.due == day(2026, 11, 20))
        #expect(task.tags == ["uni"])
    }

    @Test func parsesAllFields() throws {
        let line = "  * [x] Lesen #lernen im Park 🔁 every week ➕ 2026-11-01 🛫 2026-11-02 ⏳ 2026-11-03 📅 2026-11-04 ✅ 2026-11-05 ^abc1"
        let task = try #require(TaskLine.parse(line, timeZone: berlin))
        #expect(task.title == "Lesen #lernen im Park")
        #expect(task.status == .done)
        #expect(task.recurrence == "every week")
        #expect(task.created == day(2026, 11, 1))
        #expect(task.start == day(2026, 11, 2))
        #expect(task.scheduled == day(2026, 11, 3))
        #expect(task.due == day(2026, 11, 4))
        #expect(task.doneDate == day(2026, 11, 5))
        #expect(task.tags == ["lernen"])
    }

    @Test func recognisesStatusAndRejectsNonTasks() {
        #expect(TaskLine.parse("- [/] Läuft")?.status == .inProgress)
        #expect(TaskLine.parse("- [-] Abgesagt")?.status == .cancelled)
        #expect(TaskLine.parse("1. [ ] Nummeriert")?.title == "Nummeriert")
        #expect(TaskLine.parse("- Normale Liste") == nil)
        #expect(TaskLine.parse("[ ] ohne Aufzählung") == nil)
    }

    @Test func togglingAddsAndRemovesDoneDate() {
        let line = "- [ ] Aufgabe 📅 2026-11-20 #uni ^id1"
        let done = TaskLine.setting(line, done: true, on: day(2026, 11, 9), timeZone: berlin)
        #expect(done == "- [x] Aufgabe 📅 2026-11-20 #uni ✅ 2026-11-09 ^id1")
        #expect(TaskLine.setting(done, done: false) == "- [ ] Aufgabe 📅 2026-11-20 #uni ^id1")
    }

    @Test func settingDueReplacesOrInserts() {
        #expect(TaskLine.setting("- [ ] A #uni", due: day(2026, 11, 20), timeZone: berlin) == "- [ ] A 📅 2026-11-20 #uni")
        #expect(TaskLine.setting("- [ ] A 📅 2026-11-01 #uni", due: day(2026, 11, 20), timeZone: berlin) == "- [ ] A 📅 2026-11-20 #uni")
        #expect(TaskLine.setting("- [ ] A 📅 2026-11-01 #uni", due: nil) == "- [ ] A #uni")
        #expect(TaskLine.setting("\t- [ ] Eingerückt", due: day(2026, 11, 20), timeZone: berlin) == "\t- [ ] Eingerückt 📅 2026-11-20")
    }

    @Test func settingPriorityAndTitleKeepsMetadata() {
        let line = "- [ ] Alt 🔼 📅 2026-11-20 #uni"
        #expect(TaskLine.setting(line, priority: .highest) == "- [ ] Alt 🔺 📅 2026-11-20 #uni")
        #expect(TaskLine.setting(line, priority: .none) == "- [ ] Alt 📅 2026-11-20 #uni")
        #expect(TaskLine.setting(line, title: "Neu") == "- [ ] Neu 🔼 📅 2026-11-20 #uni")
    }

    @Test func makesNewLine() {
        let line = TaskLine.make(title: "Folien #lesen", due: day(2026, 11, 20), priority: .high, tags: ["uni", "lesen"], timeZone: berlin)
        #expect(line == "- [ ] Folien #lesen ⏫ 📅 2026-11-20 #uni")
        #expect(TaskLine.parse(line, timeZone: berlin)?.tags == ["lesen", "uni"])
    }
}

@Suite("Aufgaben sammeln")
struct TaskCollectionTests {
    let layout = VaultLayout()

    @Test func extractsWithFileLineNumbers() {
        let content = "---\ntags: [uni]\n---\n# Titel\n- [ ] Eins\n```\n- [ ] im Code\n```\n- [x] Zwei"
        let note = NoteFactory.makeNote(relativePath: "Uni/Statistik/A.md", url: URL(filePath: "/v/A"), content: content, modified: .now, layout: layout)
        let tasks = TaskExtractor.tasks(in: note)
        #expect(tasks.map(\.title) == ["Eins", "Zwei"])
        #expect(tasks.map(\.lineNumber) == [4, 8])
        #expect(tasks.first?.area == "Uni" && tasks.first?.topic == "Statistik")
        #expect(tasks.first?.noteTitle == "A")
    }

    @Test func assignsCentralTasksByTag() {
        let tasks = [TaskLine.parse("- [ ] X #uni #data-science")!, TaskLine.parse("- [ ] Y #sonstwas")!]
        let topics = [Topic(area: "Uni", name: "Data Science", relativePath: "Uni/Data Science")]
        let assigned = TaskExtractor.assignAreasByTags(tasks, topics: topics, areas: ["Uni", "Arbeit"])
        #expect(assigned[0].area == "Uni" && assigned[0].topic == "Data Science")
        #expect(assigned[1].area == nil)
    }

    @Test func groupsByFilter() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))) // Mittwoch
        func line(_ text: String) -> TaskItem { TaskLine.parse(text, timeZone: calendar.timeZone)! }
        let tasks = [
            line("- [ ] Alt 📅 2026-11-02"),
            line("- [ ] Heute ⏫ 📅 2026-11-11"),
            line("- [ ] Heute geplant ⏳ 2026-11-11"),
            line("- [ ] Freitag 📅 2026-11-13"),
            line("- [ ] Nächste Woche 📅 2026-11-17"),
            line("- [ ] Ohne Datum"),
            line("- [x] Fertig ✅ 2026-11-10"),
        ]
        let today = TaskGrouping.sections(tasks, filter: .today, now: now, calendar: calendar)
        #expect(today.map(\.id) == ["overdue", "today"])
        #expect(today[1].tasks.map(\.title) == ["Heute", "Heute geplant"])

        let week = TaskGrouping.sections(tasks, filter: .week, now: now, calendar: calendar)
        #expect(week.map(\.title).first == "Überfällig")
        #expect(week.flatMap(\.tasks).map(\.title).contains("Freitag"))
        #expect(!week.flatMap(\.tasks).map(\.title).contains("Nächste Woche"))

        #expect(TaskGrouping.sections(tasks, filter: .all, now: now, calendar: calendar).flatMap(\.tasks).count == 6)
        #expect(TaskGrouping.sections(tasks, filter: .done, now: now, calendar: calendar).first?.tasks.map(\.title) == ["Fertig"])

        let lastWeekTasks = [
            line("- [x] Montag letzte Woche ✅ 2026-11-02"),
            line("- [x] Sonntag letzte Woche ✅ 2026-11-08"),
            line("- [x] Diese Woche ✅ 2026-11-09"),
            line("- [x] Heute erledigt ✅ 2026-11-11"),
            line("- [x] Oktober ✅ 2026-10-20"),
            line("- [x] Ohne Datum erledigt"),
        ]
        func done(_ period: DonePeriod) -> [String] {
            TaskGrouping.sections(lastWeekTasks, filter: .done, donePeriod: period, now: now, calendar: calendar).flatMap(\.tasks).map(\.title)
        }
        #expect(done(.today) == ["Heute erledigt"])
        #expect(done(.thisWeek) == ["Heute erledigt", "Diese Woche"])
        #expect(done(.lastWeek) == ["Sonntag letzte Woche", "Montag letzte Woche"])
        #expect(done(.lastMonth) == ["Oktober"])
        #expect(done(.thisMonth).count == 4)
        #expect(done(.all).last == "Ohne Datum erledigt")
        let allSections = TaskGrouping.sections(lastWeekTasks, filter: .done, now: now, calendar: calendar)
        #expect(allSections.first?.title == "Heute")
        #expect(allSections.count == 6)

        let counts = TaskGrouping.counts(tasks, now: now, calendar: calendar)
        #expect(counts.open == 6 && counts.dueToday == 2 && counts.overdue == 1)
    }

    @Test func markdownCheckboxesKnowTheirFileLine() {
        let content = MarkdownContent(markdown: "Text\n\n- [ ] A\n- [x] B", firstLine: 3)
        guard case .list(let list) = content.blocks[1] else { Issue.record("Liste fehlt"); return }
        #expect(list.items.map(\.sourceLine) == [5, 6])
    }
}

@Suite("Zeilen schreiben")
struct LineWriterTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "OrganizerLines-\(UUID().uuidString)")
    var writer: VaultWriter { VaultWriter(root: root) }

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func replacesOnlyTheLineAndKeepsCRLF() throws {
        try "Kopf\r\n- [ ] A\r\nEnde\r\n".write(to: root.appending(path: "n.md"), atomically: true, encoding: .utf8)
        try writer.replaceLine("n.md", lineNumber: 1, expected: "- [ ] A", with: "- [x] A")
        #expect(try writer.read("n.md") == "Kopf\r\n- [x] A\r\nEnde\r\n")
    }

    @Test func findsMovedLineOrRefuses() throws {
        try "Neu oben\n- [ ] A\n- [ ] B\n- [ ] B\n".write(to: root.appending(path: "n.md"), atomically: true, encoding: .utf8)
        #expect(try writer.replaceLine("n.md", lineNumber: 0, expected: "- [ ] A", with: "- [x] A") == 1)
        #expect(throws: VaultWriter.WriteError.self) {
            try writer.replaceLine("n.md", lineNumber: 0, expected: "- [ ] B", with: nil)
        }
        #expect(throws: VaultWriter.WriteError.self) {
            try writer.replaceLine("n.md", lineNumber: 0, expected: "- [ ] Weg", with: nil)
        }
    }

    @Test func deletesAndRestoresLine() throws {
        try "a\n- [ ] X\nb\n".write(to: root.appending(path: "n.md"), atomically: true, encoding: .utf8)
        try writer.replaceLine("n.md", lineNumber: 1, expected: "- [ ] X", with: nil)
        #expect(try writer.read("n.md") == "a\nb\n")
        try writer.insertLine("n.md", at: 1, line: "- [ ] X")
        #expect(try writer.read("n.md") == "a\n- [ ] X\nb\n")
    }

    @Test func appendsAndCreatesCentralFile() throws {
        #expect(try writer.appendLine("_Organizer/Tasks.md", line: "- [ ] Eins", header: "# Aufgaben\n\n") == 2)
        #expect(try writer.appendLine("_Organizer/Tasks.md", line: "- [ ] Zwei") == 3)
        #expect(try writer.read("_Organizer/Tasks.md") == "# Aufgaben\n\n- [ ] Eins\n- [ ] Zwei\n")
        try "ohne Ende".write(to: root.appending(path: "x.md"), atomically: true, encoding: .utf8)
        #expect(try writer.appendLine("x.md", line: "- [ ] Y") == 1)
        #expect(try writer.read("x.md") == "ohne Ende\n- [ ] Y\n")
    }
}
