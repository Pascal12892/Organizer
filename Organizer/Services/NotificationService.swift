import AppKit
import OrganizerCore
@preconcurrency import UserNotifications

/// Erinnerungen an fällige Aufgaben und Meilensteine über die Mitteilungszentrale.
///
/// Geplant wird lokal für die nächsten Tage (macOS erlaubt höchstens 64 ausstehende Mitteilungen).
/// Bei jeder Änderung im Vault wird neu geplant, damit erledigte Aufgaben keine Erinnerung mehr auslösen.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private static let prefix = "organizer."
    private static let category = "organizer.due"
    private static let doneAction = "organizer.done"
    private static let maximum = 50

    private unowned let model: AppModel
    private var rescheduleTask: Task<Void, Never>?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    init(model: AppModel) {
        self.model = model
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: L("Erledigt"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [done], intentIdentifiers: []),
        ])
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Fragt einmalig nach der Erlaubnis. Gibt zurück, ob Mitteilungen erlaubt sind.
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Nach Änderungen gebündelt neu planen.
    func scheduleUpdate() {
        rescheduleTask?.cancel()
        rescheduleTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    private func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let settings = model.settings.settings
        guard settings.notifiesDueItems, authorization == .authorized || authorization == .provisional else { return }

        let calendar = Calendar.current
        let now = Date.now
        func fireDate(for day: Date) -> Date? {
            calendar.date(byAdding: .minute, value: settings.notificationMinutes, to: calendar.startOfDay(for: day))
        }

        var requests: [(Date, UNNotificationRequest)] = []
        for task in model.tasks.tasks where task.isOpen {
            guard let due = task.relevantDate, let fire = fireDate(for: due), fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.due == nil ? L("Heute geplant") : L("Heute fällig")
            content.body = task.title
            content.subtitle = [task.area, task.topic].compactMap { $0 }.joined(separator: " › ")
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.threadIdentifier = "tasks"
            content.userInfo = ["path": task.relativePath, "line": task.rawLine]
            let id = Self.prefix + "task." + String(task.relativePath.hashValue ^ task.rawLine.hashValue)
            requests.append((fire, request(id, content, fire)))
        }
        for project in model.roadmap.projects {
            for milestone in project.milestones where milestone.status != .done {
                guard let end = milestone.end, let fire = fireDate(for: end), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = L("Meilenstein endet heute")
                content.body = milestone.title
                content.subtitle = project.title
                content.sound = .default
                content.threadIdentifier = "roadmap"
                content.userInfo = ["roadmap": milestone.id]
                requests.append((fire, request(Self.prefix + "milestone." + String(milestone.id.hashValue), content, fire)))
            }
        }

        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(Self.maximum) {
            try? await center.add(request)
        }
    }

    private func request(_ id: String, _ content: UNNotificationContent, _ date: Date) -> UNNotificationRequest {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let path = info["path"] as? String
        let line = info["line"] as? String
        let isRoadmap = info["roadmap"] != nil
        await MainActor.run {
            if action == Self.doneAction, let path, let line,
               let task = model.tasks.tasks.first(where: { $0.relativePath == path && $0.rawLine == line }) {
                model.tasks.setDone(task, true, undoManager: QuickCaptureView.mainWindowUndoManager)
                return
            }
            model.sidebarSelection = isRoadmap ? .roadmap : .tasks
            NSApp.activate()
        }
    }
}
