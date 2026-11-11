import OrganizerCore
import SwiftUI

/// Eine Aufgabe – angelehnt an Erinnerungen: runde Checkbox, Titel, darunter Datum und Herkunft.
struct TaskRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let task: TaskItem
    var showsArea = true

    @State private var isCompleting = false
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    private var isOverdue: Bool { TaskGrouping.isOverdue(task) }
    private var showsDone: Bool { !task.isOpen || isCompleting }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: toggle) {
                Image(systemName: showsDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(showsDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(task.isOpen ? L("Als erledigt markieren") : L("Wieder öffnen"))
            .accessibilityLabel(task.isOpen ? L("Erledigen") : L("Wieder öffnen"))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if task.priority > .none {
                        Text(String(repeating: "!", count: min(task.priority.rawValue, 3)))
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Priorität \(task.priority.localizedTitle)")
                    }
                    if isEditingTitle {
                        TextField("Titel", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .focused($titleFocused)
                            .onSubmit(commitTitle)
                            .onExitCommand { isEditingTitle = false }
                    } else {
                        Text(task.title.isEmpty ? L("Ohne Titel") : task.title)
                            .strikethrough(task.status == .cancelled)
                            .foregroundStyle(showsDone ? .secondary : .primary)
                            .onTapGesture(count: 2, perform: startEditing)
                    }
                }

                details
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .draggable(DragPayload.task(task.id)) {
            Label(task.title, systemImage: "checklist").padding(6)
        }
        .contextMenu { TaskMenuItems(task: task) }
        .swipeActions(edge: .leading) {
            Button(task.isOpen ? "Erledigt" : "Öffnen", systemImage: task.isOpen ? "checkmark" : "arrow.uturn.backward") {
                model.tasks.setDone(task, task.isOpen, undoManager: undoManager)
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash", role: .destructive) {
                model.tasks.delete(task, undoManager: undoManager)
            }
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused, isEditingTitle { commitTitle() }
        }
    }

    private var details: some View {
        HStack(spacing: 10) {
            if let date = task.relevantDate {
                Label {
                    Text(Self.relativeDay(date))
                } icon: {
                    Image(systemName: task.due == nil ? "clock" : "calendar")
                }
                .foregroundStyle(isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .help(task.due == nil ? L("Geplant") : L("Fällig"))
            }
            if task.recurrence != nil {
                Image(systemName: "repeat")
                    .help("Wiederholt sich: \(task.recurrence ?? "")")
                    .accessibilityLabel("Wiederholt sich")
            }
            Button {
                model.openNote(atPath: task.relativePath)
            } label: {
                Label(source, systemImage: "doc.text")
                    .lineLimit(1)
            }
            .buttonStyle(.link)
            .foregroundStyle(.secondary)
            .help("Notiz „\(task.noteTitle)“ öffnen")

            if !task.tags.isEmpty {
                Text(task.tags.map { "#" + $0 }.joined(separator: " "))
                    .lineLimit(1)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var source: String {
        if showsArea, let area = task.area {
            return [area, task.topic, task.relativePath == TaskService.centralFile ? nil : task.noteTitle]
                .compactMap { $0 }.joined(separator: " › ")
        }
        return task.noteTitle
    }

    /// Kurz abhaken mit Animation, dann in die Datei schreiben – wie in Erinnerungen.
    private func toggle() {
        guard task.isOpen else {
            model.tasks.setDone(task, false, undoManager: undoManager)
            return
        }
        withAnimation(.snappy) { isCompleting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            model.tasks.setDone(task, true, undoManager: undoManager)
        }
    }

    private func startEditing() {
        draftTitle = task.title
        isEditingTitle = true
        titleFocused = true
    }

    private func commitTitle() {
        isEditingTitle = false
        model.tasks.rename(task, to: draftTitle, undoManager: undoManager)
    }

    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("Heute") }
        if calendar.isDateInTomorrow(date) { return L("Morgen") }
        if calendar.isDateInYesterday(date) { return L("Gestern") }
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                       : .dateTime.day().month(.abbreviated).year())
    }
}

/// Kontextmenü einer Aufgabe – auch im Kalender verwendet.
struct TaskMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let task: TaskItem

    var body: some View {
        Button(task.isOpen ? L("Als erledigt markieren") : L("Wieder öffnen")) {
            model.tasks.setDone(task, task.isOpen, undoManager: undoManager)
        }

        Menu("Fällig") {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            Button("Heute") { setDue(today) }
            Button("Morgen") { setDue(calendar.date(byAdding: .day, value: 1, to: today)) }
            Button("Nächste Woche") {
                setDue(calendar.nextDate(after: today, matching: DateComponents(weekday: calendar.firstWeekday), matchingPolicy: .nextTime))
            }
            if task.due != nil {
                Divider()
                Button("Fälligkeit entfernen") { setDue(nil) }
            }
        }

        Picker("Priorität", selection: Binding(
            get: { task.priority },
            set: { model.tasks.setPriority(task, $0, undoManager: undoManager) }
        )) {
            ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                Text(priority.localizedTitle).tag(priority)
            }
        }

        Divider()
        Button("In Notiz zeigen") { model.openNote(atPath: task.relativePath) }
        if let note = model.vault.notes.first(where: { $0.relativePath == task.relativePath }) {
            Button("In Obsidian öffnen") { model.openInObsidian(note) }
        }
        Divider()
        Button("Löschen", role: .destructive) {
            model.tasks.delete(task, undoManager: undoManager)
        }
    }

    private func setDue(_ date: Date?) {
        model.tasks.setDue(task, date, undoManager: undoManager)
    }
}
