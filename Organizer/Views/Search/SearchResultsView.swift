import OrganizerCore
import SwiftUI

/// Ergebnisse der Suche über Termine, Aufgaben und Notizen – gruppiert wie in Spotlight.
struct SearchResultsView: View {
    @Environment(AppModel.self) private var model
    let query: GlobalSearch

    @State private var memo = Memo<Key, Results>()
    @State private var expanded: Set<Kind> = []

    /// So viele Treffer pro Gruppe, bis man „Alle zeigen“ wählt.
    private static let previewLimit = 8

    enum Kind: Hashable { case events, tasks, notes }

    private struct Key: Equatable {
        let query: GlobalSearch
        let vaultVersion: Int
        let calendarRevision: Int
        let hidden: Set<String>
    }

    struct Results {
        var events: [CalendarEventInfo] = []
        var tasks: [TaskItem] = []
        var notes: [Note] = []
        var isEmpty: Bool { events.isEmpty && tasks.isEmpty && notes.isEmpty }
    }

    var body: some View {
        let results = currentResults

        List {
            if !results.events.isEmpty {
                Section {
                    ForEach(limited(results.events, .events)) { event in
                        SearchEventRow(event: event)
                    }
                } header: {
                    header(L("Termine"), count: results.events.count, kind: .events)
                }
            }
            if !results.tasks.isEmpty {
                Section {
                    ForEach(limited(results.tasks, .tasks)) { task in
                        TaskRow(task: task)
                    }
                } header: {
                    header(L("Aufgaben"), count: results.tasks.count, kind: .tasks)
                }
            }
            if !results.notes.isEmpty {
                Section {
                    ForEach(limited(results.notes, .notes)) { note in
                        Button {
                            model.openNote(atPath: note.relativePath)
                        } label: {
                            NoteRow(note: note)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    header(L("Notizen"), count: results.notes.count, kind: .notes)
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query.terms.joined(separator: " "))
            }
        }
        .navigationTitle("Suche")
        .navigationSubtitle(subtitle(results))
        .onChange(of: query) { expanded = [] }
    }

    private var currentResults: Results {
        let hidden = model.settings.settings.hiddenCalendarIDs
        let key = Key(query: query, vaultVersion: model.vault.version, calendarRevision: model.calendar.revision, hidden: hidden)
        return memo(key) {
            var results = Results()
            if model.calendar.access == .fullAccess {
                results.events = query.events(in: model.calendar.searchableEvents(hiddenCalendarIDs: hidden))
            }
            results.tasks = query.tasks(in: model.tasks.tasks)
            results.notes = query.notes(in: model.vault.notes.filter { !RoadmapParser.isRoadmapNote($0) })
            return results
        }
    }

    private func limited<T>(_ items: [T], _ kind: Kind) -> ArraySlice<T> {
        expanded.contains(kind) ? items[...] : items.prefix(Self.previewLimit)
    }

    private func header(_ title: String, count: Int, kind: Kind) -> some View {
        HStack {
            Text(title)
            Text("\(count)")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer()
            if count > Self.previewLimit {
                Button(expanded.contains(kind) ? L("Weniger zeigen") : L("Alle zeigen")) {
                    withAnimation(.smooth) {
                        if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
    }

    private func subtitle(_ results: Results) -> String {
        let total = results.events.count + results.tasks.count + results.notes.count
        return L("\(total) Treffer")
    }
}

/// Ein Termin in den Suchergebnissen. Klick zeigt ihn im Kalender.
private struct SearchEventRow: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEventInfo

    var body: some View {
        Button {
            model.showInCalendar(event)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(model.calendar.color(for: event.calendarID))
                    .frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(dateText)
                            .monospacedDigit()
                        if let location = event.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if event.isRecurring {
                    Image(systemName: "repeat")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Wiederholt sich")
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Im Kalender zeigen")
        .contextMenu {
            Button("Im Kalender zeigen") { model.showInCalendar(event) }
            Button("Notiz zum Termin anlegen …") { model.createNote(for: event) }
                .disabled(model.vault.state != .ready)
        }
    }

    private var dateText: String {
        let sameYear = Calendar.current.isDate(event.start, equalTo: .now, toGranularity: .year)
        let day = event.start.formatted(sameYear ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                                 : .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        if event.isAllDay { return day + L(", ganztägig") }
        return day + ", " + event.start.formatted(date: .omitted, time: .shortened)
    }
}
