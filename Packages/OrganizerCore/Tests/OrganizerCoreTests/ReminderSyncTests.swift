import Foundation
import Testing
@testable import OrganizerCore

@Suite("Abgleich mit Erinnerungen")
struct ReminderSyncTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    func day(_ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: d))!
    }
    func task(_ line: String, path: String = "Uni/A.md", number: Int = 3, area: String? = "Uni") -> TaskItem {
        var task = TaskLine.parse(line, relativePath: path, lineNumber: number, timeZone: berlin)!
        task.area = area
        return task
    }
    func link(for task: TaskItem, id: String = "r1") -> ReminderLink {
        ReminderLink(reminderID: id, path: task.relativePath, title: task.title, lastLine: task.rawLine,
                     lastSignature: ReminderSync.signature(for: task, timeZone: berlin))
    }
    func reminder(_ title: String, id: String = "r1", due: Date?, done: Bool = false, area: String? = "Uni") -> ReminderState {
        ReminderState(id: id, title: title, due: due, isCompleted: done, area: area)
    }

    @Test func createsRemindersOnlyForOpenDatedTasks() {
        let tasks = [task("- [ ] Lesen 📅 2026-11-20"), task("- [ ] Ohne Datum", number: 4), task("- [x] Fertig 📅 2026-11-01", number: 5)]
        let plan = ReminderSync.plan(tasks: tasks, reminders: [], links: [], timeZone: berlin)
        #expect(plan.actions == [.createReminder(tasks[0])])
    }

    @Test func nothingHappensWhenBothSidesUnchanged() {
        let item = task("- [ ] Lesen 📅 2026-11-20")
        let plan = ReminderSync.plan(tasks: [item], reminders: [reminder("Lesen", due: day(20))], links: [link(for: item)], timeZone: berlin)
        #expect(plan.actions.isEmpty)
        #expect(plan.links.count == 1)
    }

    @Test func completingInRemindersChecksOffTheLine() throws {
        let item = task("- [ ] Lesen 📅 2026-11-20 #uni")
        let plan = ReminderSync.plan(tasks: [item], reminders: [reminder("Lesen", due: day(20), done: true)],
                                     links: [link(for: item)], timeZone: berlin)
        guard case .updateTask(_, let line, _) = try #require(plan.actions.first) else { Issue.record("keine Änderung"); return }
        #expect(line.hasPrefix("- [x] Lesen 📅 2026-11-20 #uni ✅ "))
        #expect(plan.links.first?.lastLine == line)
    }

    @Test func movingDateAndRenamingInRemindersUpdatesLine() throws {
        let item = task("- [ ] Lesen ⏫ 📅 2026-11-20")
        let plan = ReminderSync.plan(tasks: [item], reminders: [reminder("Kapitel 3 lesen", due: day(22))],
                                     links: [link(for: item)], timeZone: berlin)
        guard case .updateTask(_, let line, _) = try #require(plan.actions.first) else { Issue.record("keine Änderung"); return }
        #expect(line == "- [ ] Kapitel 3 lesen ⏫ 📅 2026-11-22")
    }

    @Test func markdownWinsOnConflict() {
        let old = task("- [ ] Lesen 📅 2026-11-20")
        let changed = task("- [ ] Lesen 📅 2026-11-25")
        // Beide Seiten geändert: Erinnerung erledigt, Zeile verschoben → Zeile gewinnt.
        let plan = ReminderSync.plan(tasks: [changed], reminders: [reminder("Lesen", due: day(20), done: true)],
                                     links: [link(for: old)], timeZone: berlin)
        #expect(plan.actions == [.updateReminder(id: "r1", from: changed)])
        #expect(plan.links.first?.lastLine == changed.rawLine)
    }

    @Test func completedTaskCompletesReminder() {
        let old = task("- [ ] Lesen 📅 2026-11-20")
        let done = task("- [x] Lesen 📅 2026-11-20 ✅ 2026-11-11")
        let plan = ReminderSync.plan(tasks: [done], reminders: [reminder("Lesen", due: day(20))], links: [link(for: old)], timeZone: berlin)
        #expect(plan.actions == [.updateReminder(id: "r1", from: done)])
    }

    @Test func deletedOnEitherSide() {
        let item = task("- [ ] Lesen 📅 2026-11-20")
        // In Erinnerungen gelöscht → Verknüpfung weg, keine neue Erinnerung, solange die Zeile gleich bleibt.
        let gone = ReminderSync.plan(tasks: [item], reminders: [], links: [link(for: item)], timeZone: berlin)
        #expect(gone.links.isEmpty)
        #expect(gone.actions.isEmpty)
        let again = ReminderSync.plan(tasks: [item], reminders: [], links: [], dismissed: gone.dismissed, timeZone: berlin)
        #expect(again.actions.isEmpty)
        // Neues Datum in Obsidian → wieder eine Erinnerung
        let rescheduled = task("- [ ] Lesen 📅 2026-11-27")
        let back = ReminderSync.plan(tasks: [rescheduled], reminders: [], links: [], dismissed: again.dismissed, timeZone: berlin)
        #expect(back.actions == [.createReminder(rescheduled)])
        #expect(back.dismissed.isEmpty)
        // Im Vault gelöscht → Spiegel-Erinnerung entfernen
        let removed = ReminderSync.plan(tasks: [], reminders: [reminder("Lesen", due: day(20))], links: [link(for: item)], timeZone: berlin)
        #expect(removed.actions == [.deleteReminder(id: "r1")])
    }

    @Test func findsTaskAfterLineMovedInFile() {
        let original = task("- [ ] Lesen 📅 2026-11-20", number: 3)
        let moved = task("- [ ] Lesen 📅 2026-11-20", number: 9)
        let plan = ReminderSync.plan(tasks: [moved], reminders: [reminder("Lesen", due: day(20))], links: [link(for: original)], timeZone: berlin)
        #expect(plan.actions.isEmpty)
    }

    @Test func importsNewRemindersWithAreaTag() throws {
        let plan = ReminderSync.plan(tasks: [], reminders: [reminder("Vom iPhone", id: "r9", due: day(15)), reminder("Schon erledigt", id: "r8", due: nil, done: true)],
                                     links: [], timeZone: berlin)
        #expect(plan.actions.count == 1)
        guard case .importReminder(let state, let line) = try #require(plan.actions.first) else { Issue.record("kein Import"); return }
        #expect(state.id == "r9")
        #expect(line == "- [ ] Vom iPhone 📅 2026-11-15 #uni")
    }

    @Test func relinksMatchingPairsInsteadOfDuplicating() {
        let item = task("- [ ] Lesen 📅 2026-11-20")
        let plan = ReminderSync.plan(tasks: [item], reminders: [reminder("Lesen", id: "neu", due: day(20))], links: [], timeZone: berlin)
        #expect(plan.actions.isEmpty)
        #expect(plan.links.map(\.reminderID) == ["neu"])
    }
}
