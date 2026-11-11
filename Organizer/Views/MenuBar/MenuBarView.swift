import OrganizerCore
import SwiftUI

/// Inhalt des Menüleisten-Symbols: heutige Termine und Aufgaben, Schnellerfassung.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Date.now, format: .dateTime.weekday(.wide))
                        .font(.headline)
                    Text(Date.now, format: .dateTime.day().month(.wide))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openMainWindow()
                } label: {
                    Label("Organizer öffnen", systemImage: "macwindow")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Organizer öffnen")
            }

            QuickCaptureView(style: .inline, undoManager: QuickCaptureView.mainWindowUndoManager)

            Divider()

            section("Termine heute", systemImage: "calendar") {
                let events = todaysEvents
                if model.calendar.access != .fullAccess {
                    Text("Kein Zugriff auf den Kalender").foregroundStyle(.secondary)
                } else if events.isEmpty {
                    Text("Keine weiteren Termine").foregroundStyle(.secondary)
                } else {
                    ForEach(events.prefix(6)) { event in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(model.calendar.color(for: event.calendarID))
                                .frame(width: 3, height: 16)
                            Text(event.isAllDay ? L("ganztägig") : event.start.formatted(date: .omitted, time: .shortened))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 66, alignment: .leading)
                            Text(event.title).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            section("Aufgaben", systemImage: "checklist") {
                let tasks = model.tasks.sections(filter: .today, area: nil).flatMap(\.tasks)
                if model.vault.state != .ready {
                    Text("Kein Vault geöffnet").foregroundStyle(.secondary)
                } else if tasks.isEmpty {
                    Text("Heute ist nichts fällig").foregroundStyle(.secondary)
                } else {
                    ForEach(tasks.prefix(8)) { task in
                        MenuBarTaskRow(task: task)
                    }
                    if tasks.count > 8 {
                        Button("\(tasks.count - 8) weitere …") {
                            model.sidebarSelection = .tasks
                            openMainWindow()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Einstellungen …")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Organizer beenden") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var todaysEvents: [CalendarEventInfo] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let interval = DateInterval(start: today, end: calendar.date(byAdding: .day, value: 1, to: today)!)
        return CalendarMath.events(model.calendar.events(in: interval, hiddenCalendarIDs: model.settings.settings.hiddenCalendarIDs),
                                   on: today, calendar: calendar)
            .filter { $0.isAllDay || $0.end > .now }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// Kompakte Aufgabe mit Checkbox.
private struct MenuBarTaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.tasks.setDone(task, true, undoManager: QuickCaptureView.mainWindowUndoManager)
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(TaskGrouping.isOverdue(task) ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.plain)
            .help("Als erledigt markieren")
            .accessibilityLabel("\(task.title) erledigen")
            Text(task.title).lineLimit(1)
            Spacer(minLength: 4)
            if TaskGrouping.isOverdue(task), let date = task.relevantDate {
                Text(TaskRow.relativeDay(date))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

#Preview("Hell") {
    MenuBarView()
        .environment(PreviewData.model())
}

#Preview("Dunkel") {
    MenuBarView()
        .environment(PreviewData.model())
        .preferredColorScheme(.dark)
}
