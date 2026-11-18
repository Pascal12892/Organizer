import EventKit
import OrganizerCore
import Observation
import SwiftUI

/// Ein Kalender aus der Apple-Kalender-App.
struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
    let sourceTitle: String
    let allowsModifications: Bool
    /// Farbe als „#RRGGBB“ (für die Widgets).
    var hex: String = "#007AFF"
}

/// Zugriff auf den Apple Kalender über EventKit.
/// Liest Termine und legt neue an. Aufgaben werden hier nie hineingeschrieben.
@Observable
final class CalendarService {
    enum Access: Hashable {
        case notDetermined
        case denied
        case restricted
        case writeOnly
        case fullAccess
    }

    private(set) var access: Access
    private(set) var calendars: [CalendarInfo] = []
    /// Wird bei jeder Änderung im Kalender erhöht – Views laden dann neu.
    private(set) var revision = 0
    private(set) var lastError: String?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    private let isPreview: Bool
    private var previewEvents: [CalendarEventInfo] = []

    init() {
        isPreview = false
        access = Self.currentAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.storeChanged() }
        }
        if access == .fullAccess { reloadCalendars() }
    }

    /// Für Previews: feste Kalender und Termine, ohne Systemzugriff.
    init(previewCalendars: [CalendarInfo], events: [CalendarEventInfo]) {
        isPreview = true
        access = .fullAccess
        calendars = previewCalendars
        previewEvents = events
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied
        }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            lastError = L("Zugriff auf den Kalender fehlgeschlagen: \(localizedMessage(error))")
        }
        access = Self.currentAccess()
        if access == .fullAccess { reloadCalendars() }
    }

    func reloadCalendars() {
        guard !isPreview else { return }
        calendars = store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    color: Color(cgColor: calendar.cgColor),
                    sourceTitle: calendar.source?.title ?? L("Andere"),
                    allowsModifications: calendar.allowsContentModifications,
                    hex: Self.hex(calendar.cgColor)
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    /// Termine im Zeitraum aus allen Kalendern, die nicht ausgeblendet sind.
    func events(in interval: DateInterval, hiddenCalendarIDs: Set<String>) -> [CalendarEventInfo] {
        // Zwischenspeichern: Monats-, Wochen- und Dashboard-Ansicht fragen bei jedem Neuzeichnen.
        let key = EventsKey(interval: interval, hidden: hiddenCalendarIDs, revision: revision, access: access)
        if let cached = eventCache[key] { return cached }
        let events = fetchEvents(in: interval, hiddenCalendarIDs: hiddenCalendarIDs)
        if eventCache.count > 24 { eventCache.removeAll() }
        eventCache[key] = events
        return events
    }

    private struct EventsKey: Hashable { let interval: DateInterval; let hidden: Set<String>; let revision: Int; let access: Access }
    @ObservationIgnored private var eventCache: [EventsKey: [CalendarEventInfo]] = [:]

    private func fetchEvents(in interval: DateInterval, hiddenCalendarIDs: Set<String>) -> [CalendarEventInfo] {
        if isPreview {
            return previewEvents.filter { $0.start < interval.end && $0.end > interval.start && !hiddenCalendarIDs.contains($0.calendarID) }
        }
        guard access == .fullAccess else { return [] }
        let visible = store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: visible)
        return store.events(matching: predicate).map(Self.info)
    }

    func color(for calendarID: String) -> Color {
        calendars.first { $0.id == calendarID }?.color ?? .accentColor
    }

    func calendar(withID id: String) -> CalendarInfo? {
        calendars.first { $0.id == id }
    }

    var writableCalendars: [CalendarInfo] { calendars.filter(\.allowsModifications) }

    var defaultCalendarID: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier ?? writableCalendars.first?.id
    }

    /// Legt einen Termin an und gibt seine ID zurück (für Rückgängig).
    @discardableResult
    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, notes: String?) throws -> String {
        guard let calendar = store.calendar(withIdentifier: calendarID) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: L("Der Kalender existiert nicht mehr.")])
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.calendar = calendar
        if let notes, !notes.isEmpty { event.notes = notes }
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    /// Alles, was nötig ist, um einen gelöschten Einzeltermin per Rückgängig wiederherzustellen.
    struct DeletedEvent {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendarID: String
        let location: String?
        let notes: String?
        let url: URL?
        let alarms: [EKAlarm]
    }

    /// Löscht einen Termin – wie in Apple Kalender. Bei Serien entscheidet `futureEvents`,
    /// ob nur dieses Vorkommen oder auch alle folgenden entfernt werden.
    /// Gibt bei Einzelterminen den alten Stand zurück (für Rückgängig).
    @discardableResult
    func deleteEvent(_ info: CalendarEventInfo, futureEvents: Bool = false) throws -> DeletedEvent? {
        guard let event = ekEvent(for: info) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: L("Der Termin existiert nicht mehr.")])
        }
        guard event.calendar.allowsContentModifications else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: L("Der Kalender „\(event.calendar.title)“ ist schreibgeschützt.")])
        }
        let snapshot = event.hasRecurrenceRules ? nil : DeletedEvent(
            title: event.title ?? "", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier, location: event.location, notes: event.notes,
            url: event.url, alarms: event.alarms ?? []
        )
        try store.remove(event, span: futureEvents ? .futureEvents : .thisEvent, commit: true)
        return snapshot
    }

    /// Stellt einen gelöschten Einzeltermin wieder her und gibt die neue ID zurück.
    func restore(_ deleted: DeletedEvent) throws -> String {
        guard let calendar = store.calendar(withIdentifier: deleted.calendarID) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: L("Der Kalender existiert nicht mehr.")])
        }
        let event = EKEvent(eventStore: store)
        event.title = deleted.title
        event.startDate = deleted.start
        event.endDate = deleted.end
        event.isAllDay = deleted.isAllDay
        event.calendar = calendar
        event.location = deleted.location
        event.notes = deleted.notes
        event.url = deleted.url
        for alarm in deleted.alarms { event.addAlarm(alarm.copy() as! EKAlarm) }
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    /// Darf der Termin geändert bzw. gelöscht werden?
    func canModify(_ info: CalendarEventInfo) -> Bool {
        calendar(withID: info.calendarID)?.allowsModifications ?? false
    }

    /// Das konkrete Vorkommen eines Termins (bei Serien das am angezeigten Tag).
    private func ekEvent(for info: CalendarEventInfo) -> EKEvent? {
        let itemID = String(info.id.split(separator: "|").first ?? "")
        guard let calendar = store.calendar(withIdentifier: info.calendarID) else { return nil }
        let predicate = store.predicateForEvents(withStart: info.start.addingTimeInterval(-1), end: max(info.end, info.start).addingTimeInterval(1), calendars: [calendar])
        return store.events(matching: predicate).first { $0.calendarItemIdentifier == itemID && $0.startDate == info.start }
            ?? store.calendarItem(withIdentifier: itemID) as? EKEvent
    }

    /// Entfernt einen Termin, den Organizer selbst angelegt hat – nur für Rückgängig.
    func removeEvent(withID id: String) throws {
        guard let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private static func hex(_ color: CGColor?) -> String {
        guard let color, let rgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return "#007AFF" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }

    private func storeChanged() {
        reloadCalendars()
        revision += 1
    }

    private static func info(_ event: EKEvent) -> CalendarEventInfo {
        CalendarEventInfo(
            id: event.calendarItemIdentifier + "|" + String(event.startDate.timeIntervalSinceReferenceDate),
            title: event.title ?? L("Ohne Titel"),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier,
            location: event.location.flatMap { $0.isEmpty ? nil : $0 },
            notes: event.notes.flatMap { $0.isEmpty ? nil : $0 },
            isRecurring: event.hasRecurrenceRules
        )
    }
}
