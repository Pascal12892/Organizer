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
            notes: event.notes.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
