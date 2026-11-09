import HubCore
import SwiftUI

/// Kalender mit Tag-, Wochen- und Monatsansicht – angelehnt an Apple Kalender.
struct CalendarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.calendar.access {
        case .fullAccess:
            CalendarContent()
        case .notDetermined:
            ContentUnavailableView {
                Label("Kalender verbinden", systemImage: "calendar")
            } description: {
                Text("Hub zeigt deine Termine aus dem Apple Kalender neben Notizen und Aufgaben. Die Daten bleiben auf deinem Mac.")
            } actions: {
                Button("Zugriff erlauben …") {
                    Task { await model.calendar.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Kalender")
        case .denied, .restricted, .writeOnly:
            ContentUnavailableView {
                Label("Kein Zugriff auf den Kalender", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Erlaube Hub in den Systemeinstellungen unter Datenschutz & Sicherheit › Kalender den vollen Zugriff.")
            } actions: {
                Button("Systemeinstellungen öffnen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .navigationTitle("Kalender")
        }
    }
}

private struct CalendarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.calendarState
        let scope = model.settings.settings.calendarScope
        let calendar = Calendar.current
        let interval = CalendarMath.interval(for: scope, containing: state.date, calendar: calendar)
        let events = model.calendar.events(in: interval, hiddenCalendarIDs: model.settings.settings.hiddenCalendarIDs)

        Group {
            switch scope {
            case .month:
                MonthView(
                    days: CalendarMath.monthGrid(containing: state.date, calendar: calendar),
                    month: state.date,
                    events: events
                )
            case .week:
                CalendarTimeline(days: CalendarMath.weekDays(containing: state.date, calendar: calendar), events: events)
            case .day:
                CalendarTimeline(days: [calendar.startOfDay(for: state.date)], events: events)
            }
        }
        .navigationTitle(CalendarMath.title(for: scope, date: state.date, calendar: calendar))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button {
                        withAnimation(.snappy) { state.step(-1, scope: scope) }
                    } label: {
                        Label("Zurück", systemImage: "chevron.left")
                    }
                    .help("Zurück (⌘←)")
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    Button("Heute") {
                        withAnimation(.snappy) { state.goToToday() }
                    }
                    .help("Zu heute springen (⌘T)")
                    .keyboardShortcut("t")

                    Button {
                        withAnimation(.snappy) { state.step(1, scope: scope) }
                    } label: {
                        Label("Weiter", systemImage: "chevron.right")
                    }
                    .help("Weiter (⌘→)")
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                }
            }

            ToolbarItem(placement: .principal) {
                Picker("Ansicht", selection: Binding(
                    get: { scope },
                    set: { newScope in model.settings.update { $0.calendarScope = newScope } }
                )) {
                    ForEach(CalendarScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .help("Tag, Woche oder Monat")
            }

            ToolbarItem {
                CalendarsMenu()
            }

            ToolbarItem {
                Button {
                    state.newEventStart = state.suggestedStart()
                } label: {
                    Label("Neuer Termin", systemImage: "plus")
                }
                .help("Neuer Termin (⌘N)")
                .disabled(model.calendar.writableCalendars.isEmpty)
            }
        }
        .sheet(isPresented: Binding(
            get: { state.newEventStart != nil },
            set: { if !$0 { state.newEventStart = nil } }
        )) {
            NewEventSheet(start: state.newEventStart ?? .now)
        }
    }
}

/// Auswahl der angezeigten Kalender, gruppiert nach Konto.
private struct CalendarsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let hidden = model.settings.settings.hiddenCalendarIDs
        let sources = Dictionary(grouping: model.calendar.calendars, by: \.sourceTitle)

        Menu {
            ForEach(sources.keys.sorted(), id: \.self) { source in
                Section(source) {
                    ForEach(sources[source] ?? []) { calendar in
                        Toggle(isOn: Binding(
                            get: { !hidden.contains(calendar.id) },
                            set: { model.setCalendarHidden(calendar.id, hidden: !$0) }
                        )) {
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(calendar.color)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Kalender", systemImage: hidden.isEmpty ? "calendar" : "calendar.badge.minus")
        }
        .help(hidden.isEmpty ? "Angezeigte Kalender wählen" : "\(hidden.count) Kalender ausgeblendet")
    }
}

#Preview("Hell – Woche") {
    NavigationStack {
        CalendarView()
    }
    .environment(PreviewData.model())
    .frame(width: 960, height: 680)
}

#Preview("Dunkel – Woche") {
    NavigationStack {
        CalendarView()
    }
    .environment(PreviewData.model())
    .frame(width: 960, height: 680)
    .preferredColorScheme(.dark)
}
