import OrganizerCore
import SwiftUI
import WidgetKit

@main
struct OrganizerWidgets: WidgetBundle {
    var body: some Widget {
        TasksWidget()
        EventsWidget()
    }
}

// MARK: - Daten

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .preview : (WidgetSnapshot.load() ?? .preview)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // Die App lädt die Widgets bei jeder Änderung neu; zusätzlich um Mitternacht und alle 30 Minuten.
        let now = Date.now
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let next = min(midnight, now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: WidgetSnapshot.load())], policy: .after(next)))
    }
}

// MARK: - Aufgaben

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.pascallupo.Organizer.tasks", provider: SnapshotProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "organizer://tasks"))
        }
        .configurationDisplayName("Heutige Aufgaben")
        .description("Fällige und überfällige Aufgaben aus deinem Vault.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Heute", systemImage: "checklist")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Spacer()
                if let snapshot = entry.snapshot {
                    Text("\(snapshot.tasks.count)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
            }

            if let snapshot = entry.snapshot {
                if snapshot.tasks.isEmpty {
                    Spacer()
                    Label("Alles erledigt", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(snapshot.tasks.prefix(limit), id: \.self) { task in
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .foregroundStyle(task.isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                                .imageScale(.small)
                            Text(task.title)
                                .lineLimit(1)
                                .font(family == .systemSmall ? .caption : .callout)
                            Spacer(minLength: 0)
                            if family != .systemSmall, let area = task.area {
                                Text(area).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if snapshot.tasks.count > limit {
                        Text("und \(snapshot.tasks.count - limit) weitere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Spacer()
                Text("Öffne Organizer, um deine Aufgaben hier zu sehen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var limit: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        default: 11
        }
    }
}

// MARK: - Termine

struct EventsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.pascallupo.Organizer.events", provider: SnapshotProvider()) { entry in
            EventsWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "organizer://calendar"))
        }
        .configurationDisplayName("Nächste Termine")
        .description("Deine nächsten Termine aus dem Apple Kalender.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct EventsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Termine", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.tint)

            let upcoming = (entry.snapshot?.events ?? []).filter { $0.isAllDay ? $0.end > entry.date : $0.end > entry.date }
            if entry.snapshot == nil {
                Spacer()
                Text("Öffne Organizer, um deine Termine hier zu sehen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if upcoming.isEmpty {
                Spacer()
                Label("Keine Termine in den nächsten Tagen", systemImage: "calendar.badge.checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(upcoming.prefix(limit), id: \.self) { event in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: event.color))
                            .frame(width: 3, height: family == .systemSmall ? 24 : 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(event.title)
                                .font(family == .systemSmall ? .caption.weight(.medium) : .callout.weight(.medium))
                                .lineLimit(1)
                            Text(timeText(event))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 3
        default: 8
        }
    }

    private func timeText(_ event: WidgetSnapshot.EventEntry) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(event.start) ? "Heute"
            : calendar.isDateInTomorrow(event.start) ? "Morgen"
            : event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return event.isAllDay ? "\(day), ganztägig" : "\(day), \(event.start.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Hilfen

extension Color {
    /// „#RRGGBB“ → Farbe; unbekannt → Akzentfarbe.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
        guard let value else {
            self = .accentColor
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

extension WidgetSnapshot {
    static let preview: WidgetSnapshot = {
        let now = Date.now
        return WidgetSnapshot(
            generated: now,
            tasks: [
                .init(title: "Exposé abgeben", due: now.addingTimeInterval(-86_400), isOverdue: true, area: "Uni", priority: 2),
                .init(title: "Folien Kapitel 3 lesen", due: now, isOverdue: false, area: "Uni", priority: 0),
                .init(title: "Sprint-Review vorbereiten", due: now, isOverdue: false, area: "Arbeit", priority: 1),
            ],
            openTaskCount: 12,
            events: [
                .init(title: "Vorlesung Data Science", start: now.addingTimeInterval(3_600), end: now.addingTimeInterval(9_000),
                      isAllDay: false, color: "#3B82F6", calendar: "Uni"),
                .init(title: "Lerngruppe", start: now.addingTimeInterval(90_000), end: now.addingTimeInterval(93_600),
                      isAllDay: false, color: "#F59E0B", calendar: "Privat"),
            ]
        )
    }()
}

#Preview("Aufgaben", as: .systemMedium) {
    TasksWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview("Termine", as: .systemSmall) {
    EventsWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
