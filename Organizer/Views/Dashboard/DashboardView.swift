import OrganizerCore
import SwiftUI

/// Startansicht: Termine heute und morgen, fällige Aufgaben, zuletzt bearbeitete Notizen,
/// nächste Meilensteine und eine Schnellerfassung.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.largeTitle.weight(.bold))
                    Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                GroupBox {
                    QuickCaptureView(style: .inline, undoManager: undoManager)
                        .padding(4)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    EventsCard()
                    TasksCard()
                    RecentNotesCard()
                    MilestonesCard()
                }
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dashboard")
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: L("Guten Morgen")
        case 11..<17: L("Guten Tag")
        case 17..<23: L("Guten Abend")
        default: L("Hallo")
        }
    }
}

/// Einheitliche Karte mit Titel, Symbol und optionalem „Alle anzeigen“.
/// Mit `isExpanded` lässt sich der Inhalt über den Titel ein- und ausklappen.
private struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    var isExpanded: Binding<Bool>?
    var showAll: (() -> Void)?
    @ViewBuilder let content: Content

    private var showsContent: Bool { isExpanded?.wrappedValue ?? true }

    var body: some View {
        GroupBox {
            if showsContent {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding(6)
            }
        } label: {
            HStack {
                if let isExpanded {
                    Button {
                        withAnimation(.smooth) { isExpanded.wrappedValue.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            // „forward“ zeigt bei Arabisch automatisch nach links.
                            Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                                .contentTransition(.symbolEffect(.replace))
                            Label(title, systemImage: systemImage)
                                .font(.headline)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded.wrappedValue ? L("Einklappen") : L("Ausklappen"))
                    .accessibilityLabel(title)
                    .accessibilityValue(isExpanded.wrappedValue ? L("Ausgeklappt") : L("Eingeklappt"))
                    .accessibilityHint(isExpanded.wrappedValue ? L("Einklappen") : L("Ausklappen"))
                } else {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                }
                Spacer()
                if let showAll {
                    Button("Alle anzeigen", action: showAll)
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        }
    }
}

private struct EmptyCardText: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

// MARK: - Karten

private struct EventsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DashboardCard(title: "Heute und morgen", systemImage: "calendar", showAll: { model.sidebarSelection = .calendar }) {
            if model.calendar.access != .fullAccess {
                EmptyCardText(text: L("Kein Zugriff auf den Kalender."))
                Button("Zugriff erlauben …") { Task { await model.calendar.requestAccess() } }
            } else {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let interval = DateInterval(start: today, end: calendar.date(byAdding: .day, value: 2, to: today)!)
                let events = model.calendar.events(in: interval, hiddenCalendarIDs: model.settings.settings.hiddenCalendarIDs)
                ForEach([today, calendar.date(byAdding: .day, value: 1, to: today)!], id: \.self) { day in
                    let dayEvents = CalendarMath.events(events, on: day, calendar: calendar)
                    Text(calendar.isDateInToday(day) ? L("Heute") : L("Morgen"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if dayEvents.isEmpty {
                        Text("Keine Termine").foregroundStyle(.tertiary)
                    }
                    ForEach(dayEvents) { event in
                        DashboardEventRow(event: event)
                    }
                }
            }
        }
    }
}

private struct DashboardEventRow: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEventInfo
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(model.calendar.color(for: event.calendarID))
                    .frame(width: 3, height: 18)
                Text(event.isAllDay ? L("ganztägig") : event.start.formatted(date: .omitted, time: .shortened))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Text(event.title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            EventDetailView(event: event) {
                showsDetails = false
                model.createNote(for: event)
            }
        }
    }
}

private struct TasksCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sections = model.tasks.sections(filter: .today, area: nil)
        let tasks = sections.flatMap(\.tasks)
        DashboardCard(title: "Fällige Aufgaben", systemImage: "checklist", showAll: {
            model.settings.update { $0.taskFilter = .today }
            model.sidebarSelection = .tasks
        }) {
            if tasks.isEmpty {
                EmptyCardText(text: L("Heute ist nichts fällig. 🎉"))
            }
            ForEach(tasks.prefix(8)) { task in
                TaskRow(task: task)
            }
            if tasks.count > 8 {
                Text("und \(tasks.count - 8) weitere")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecentNotesCard: View {
    @Environment(AppModel.self) private var model
    /// Eingeklappt, bis man sie aufklappt; der Zustand bleibt erhalten.
    @AppStorage("dashboard.recentNotesExpanded") private var isExpanded = false

    var body: some View {
        DashboardCard(title: "Zuletzt bearbeitet", systemImage: "clock", isExpanded: $isExpanded,
                      showAll: { model.sidebarSelection = .notes }) {
            let notes = model.vault.notes.filter { !RoadmapParser.isRoadmapNote($0) }.prefix(6)
            if notes.isEmpty {
                EmptyCardText(text: model.vault.state == .ready ? L("Noch keine Notizen.") : L("Kein Vault geöffnet."))
            }
            ForEach(notes) { note in
                Button {
                    model.openNote(atPath: note.relativePath)
                } label: {
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.title).lineLimit(1)
                            Text(note.folderPath.isEmpty ? "Vault" : note.folderPath.replacingOccurrences(of: "/", with: " › "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(note.modified, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MilestonesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DashboardCard(title: "Nächste Meilensteine", systemImage: "map", showAll: { model.sidebarSelection = .roadmap }) {
            let upcoming = model.roadmap.projects
                .flatMap { project in project.upcomingMilestones().map { (project, $0) } }
                .sorted { ($0.1.end ?? .distantFuture) < ($1.1.end ?? .distantFuture) }
                .prefix(5)
            if upcoming.isEmpty {
                EmptyCardText(text: L("Keine offenen Meilensteine."))
            }
            ForEach(Array(upcoming), id: \.1.id) { project, milestone in
                HStack(spacing: 8) {
                    Circle().fill(RoadmapService.color(named: project.color)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.title).lineLimit(1)
                        Text(project.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let end = milestone.end {
                            Text(TaskRow.relativeDay(end))
                                .font(.callout)
                                .foregroundStyle(milestone.isOverdue ? .red : .secondary)
                        }
                        ProgressView(value: milestone.progress)
                            .frame(width: 70)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.sidebarSelection = .roadmap }
            }
        }
    }
}

#Preview("Hell") {
    NavigationStack { DashboardView() }
        .environment(PreviewData.model())
        .frame(width: 1000, height: 760)
}

#Preview("Dunkel") {
    NavigationStack { DashboardView() }
        .environment(PreviewData.model())
        .frame(width: 1000, height: 760)
        .preferredColorScheme(.dark)
}
