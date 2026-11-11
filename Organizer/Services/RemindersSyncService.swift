import EventKit
import Foundation
import Observation
import OrganizerCore

/// Gleicht Aufgaben mit Apple Erinnerungen ab – Markdown bleibt die Quelle.
///
/// - Offene Aufgaben mit Datum erscheinen in Listen „Organizer – <Bereich>“ (über iCloud auch auf dem iPhone).
/// - Abhaken, Titel oder Datum ändern in Erinnerungen wird in die Markdown-Zeile zurückgeschrieben.
/// - Neue Erinnerungen in diesen Listen landen als Aufgabe in `_Organizer/Tasks.md`.
/// - Welche Erinnerung zu welcher Zeile gehört, steht nur in Organizers eigener Datei, nicht in den Notizen.
@Observable
final class RemindersSyncService {
    enum Status: Equatable {
        case off
        case needsAccess
        case denied
        case syncing
        case synced(Date)
        case failed(String)
    }

    static let listPrefix = "Organizer"

    private(set) var status: Status = .off
    private(set) var linkCount = 0

    private let vault: VaultService
    private let settings: SettingsStore
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var state = SyncState()

    /// Gespeicherter Abgleich-Stand.
    private struct SyncState: Codable {
        var links: [ReminderLink] = []
        var dismissed: [String] = []
    }

    init(vault: VaultService, settings: SettingsStore) {
        self.vault = vault
        self.settings = settings
        state = Self.loadState()
        linkCount = state.links.count
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        }
        refreshStatus()
    }

    var isEnabled: Bool { settings.settings.syncsReminders }

    private var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    private func refreshStatus() {
        guard isEnabled else { status = .off; return }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: if case .off = status { status = .synced(.distantPast) }
        case .notDetermined: status = .needsAccess
        default: status = .denied
        }
    }

    // MARK: - Ein- und Ausschalten

    func enable() async {
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        settings.update { $0.syncsReminders = true }
        refreshStatus()
        await syncNow()
    }

    /// Ausschalten lässt alle Erinnerungen und Aufgaben, wie sie sind.
    func disable() {
        settings.update { $0.syncsReminders = false }
        pending?.cancel()
        status = .off
    }

    /// Mehrere Änderungen kurz hintereinander zu einem Abgleich bündeln.
    func scheduleSync() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    // MARK: - Abgleich

    func syncNow() async {
        guard isEnabled, !isRunning else { return }
        guard hasAccess else { refreshStatus(); return }
        guard vault.state == .ready, let root = vault.rootURL else { return }
        isRunning = true
        status = .syncing
        defer { isRunning = false }

        do {
            let writer = VaultWriter(root: root)
            let tasks = vault.snapshot.tasks
            let (states, reminders) = try await loadReminders()
            let plan = ReminderSync.plan(tasks: tasks, reminders: states, links: state.links, dismissed: Set(state.dismissed))

            var links = plan.links
            var changedFiles = false

            for action in plan.actions {
                switch action {
                case .createReminder(let task):
                    let reminder = EKReminder(eventStore: store)
                    reminder.calendar = try list(for: task.area)
                    apply(task, to: reminder)
                    try store.save(reminder, commit: false)
                    links.append(ReminderLink(reminderID: reminder.calendarItemIdentifier, path: task.relativePath, title: task.title,
                                              lastLine: task.rawLine, lastSignature: ReminderSync.signature(for: task)))

                case .updateReminder(let id, let task):
                    guard let reminder = reminders[id] else { continue }
                    apply(task, to: reminder)
                    try store.save(reminder, commit: false)

                case .deleteReminder(let id):
                    if let reminder = reminders[id] { try store.remove(reminder, commit: false) }

                case .updateTask(let task, let newLine, _):
                    do {
                        try writer.replaceLine(task.relativePath, lineNumber: task.lineNumber, expected: task.rawLine, with: newLine)
                        changedFiles = true
                    } catch {
                        // Zeile hat sich gerade geändert: Verknüpfung auf altem Stand lassen, nächster Abgleich holt es nach.
                        if let index = links.firstIndex(where: { $0.path == task.relativePath && $0.lastLine == newLine }) {
                            links[index].lastLine = task.rawLine
                        }
                    }

                case .importReminder(let reminder, let line):
                    let path = TaskService.centralFile
                    try writer.appendLine(path, line: line, header: "# Aufgaben\n\n")
                    changedFiles = true
                    links.append(ReminderLink(reminderID: reminder.id, path: path,
                                              title: TaskLine.parse(line)?.title ?? reminder.title,
                                              lastLine: line, lastSignature: reminder.signature))
                }
            }
            try store.commit()

            state = SyncState(links: links, dismissed: Array(plan.dismissed.prefix(1000)))
            saveState()
            linkCount = links.count
            status = .synced(.now)
            if changedFiles { await vault.rescan() }
        } catch {
            store.reset()
            status = .failed(localizedMessage(error))
        }
    }

    // MARK: - EventKit

    private func organizerLists() -> [EKCalendar] {
        store.calendars(for: .reminder).filter { $0.title == Self.listPrefix || $0.title.hasPrefix(Self.listPrefix + " – ") }
    }

    private static func listTitle(for area: String?) -> String {
        area.map { "\(listPrefix) – \($0)" } ?? listPrefix
    }

    private static func area(fromListTitle title: String) -> String? {
        title.hasPrefix(listPrefix + " – ") ? String(title.dropFirst(listPrefix.count + 3)) : nil
    }

    /// Liste für einen Bereich, wird bei Bedarf angelegt (im Standard-Konto für Erinnerungen, meist iCloud).
    private func list(for area: String?) throws -> EKCalendar {
        let title = Self.listTitle(for: area)
        if let existing = organizerLists().first(where: { $0.title == title }) { return existing }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = title
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: L("Kein Konto für Erinnerungen gefunden.")])
        }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    private func loadReminders() async throws -> ([ReminderState], [String: EKReminder]) {
        let lists = organizerLists()
        guard !lists.isEmpty else { return ([], [:]) }
        let predicate = store.predicateForReminders(in: lists)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                nonisolated(unsafe) let result = reminders ?? []
                continuation.resume(returning: result)
            }
        }
        var byID: [String: EKReminder] = [:]
        let states = fetched.map { reminder -> ReminderState in
            byID[reminder.calendarItemIdentifier] = reminder
            let due = reminder.dueDateComponents.flatMap { components -> Date? in
                var day = DateComponents()
                day.year = components.year
                day.month = components.month
                day.day = components.day
                return Calendar.current.date(from: day)
            }
            return ReminderState(id: reminder.calendarItemIdentifier, title: reminder.title ?? "", due: due,
                                 isCompleted: reminder.isCompleted, area: Self.area(fromListTitle: reminder.calendar.title))
        }
        return (states, byID)
    }

    /// Überträgt Titel, Tag, Status und Priorität einer Aufgabe auf die Erinnerung.
    private func apply(_ task: TaskItem, to reminder: EKReminder) {
        reminder.title = task.title
        if let date = task.relevantDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        } else {
            reminder.dueDateComponents = nil
        }
        reminder.isCompleted = !task.isOpen
        reminder.priority = switch task.priority {
        case .highest, .high: 1
        case .medium: 5
        case .low, .lowest: 9
        case .none: 0
        }
        if reminder.notes == nil || reminder.notes?.hasPrefix("Aus Organizer:") == true {
            reminder.notes = "Aus Organizer: \(task.relativePath)"
        }
        if let vaultName = vault.vaultName {
            reminder.url = ObsidianURL.open(vaultName: vaultName, relativePath: task.relativePath)
        }
    }

    // MARK: - Speichern

    private static var stateURL: URL {
        URL.applicationSupportDirectory.appending(path: "Organizer", directoryHint: .isDirectory).appending(path: "reminders-sync.json")
    }

    private static func loadState() -> SyncState {
        guard let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(SyncState.self, from: data) else {
            return SyncState()
        }
        return state
    }

    private func saveState() {
        do {
            try FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
        } catch {
            status = .failed(L("Abgleich-Stand konnte nicht gespeichert werden: \(localizedMessage(error))"))
        }
    }
}
