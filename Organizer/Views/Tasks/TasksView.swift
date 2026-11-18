import OrganizerCore
import SwiftUI

/// Aufgabenliste mit den Ansichten Heute, Diese Woche, Alle und Erledigt.
struct TasksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var selection: TaskItem.ID?

    var body: some View {
        let filter = model.settings.settings.taskFilter
        let donePeriod = model.settings.settings.donePeriod
        let sections = model.tasks.sections(filter: filter, area: model.taskAreaFilter, donePeriod: donePeriod)

        List(selection: $selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.tasks) { task in
                        TaskRow(task: task, showsArea: model.taskAreaFilter == nil)
                            .tag(task.id)
                    }
                } header: {
                    Text(section.localizedTitle)
                        .foregroundStyle(section.isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
        }
        .animation(.smooth, value: sections)
        .overlay {
            if sections.isEmpty { emptyState(filter) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if filter != .done, model.vault.state == .ready {
                NewTaskField(defaultDue: filter == .all ? nil : Calendar.current.startOfDay(for: .now))
            }
        }
        .onKeyPress(.space) {
            guard let task = selectedTask else { return .ignored }
            model.tasks.setDone(task, task.isOpen, undoManager: undoManager)
            return .handled
        }
        .onDeleteCommand {
            if let task = selectedTask { model.tasks.delete(task, undoManager: undoManager) }
        }
        .navigationTitle("Aufgaben")
        .navigationSubtitle(filter == .done ? doneSubtitle(sections, period: donePeriod) : subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Ansicht", selection: Binding(
                    get: { filter },
                    set: { newFilter in model.settings.update { $0.taskFilter = newFilter } }
                )) {
                    ForEach(TaskFilter.allCases, id: \.self) { filter in
                        Text(filter.localizedTitle).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            if filter == .done {
                ToolbarItem {
                    Picker("Zeitraum", selection: Binding(
                        get: { donePeriod },
                        set: { period in model.settings.update { $0.donePeriod = period } }
                    )) {
                        ForEach(DonePeriod.allCases, id: \.self) { period in
                            if period == .all { Divider() }
                            Text(period.localizedTitle).tag(period)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .help("Erledigte Aufgaben nach Zeitraum filtern")
                }
            }
            ToolbarItem {
                Menu {
                    Picker("Bereich", selection: Bindable(model).taskAreaFilter) {
                        Text("Alle Bereiche").tag(String?.none)
                        Divider()
                        ForEach(model.areas, id: \.self) { area in
                            Label(area, systemImage: SidebarItem.areaSymbol(for: area)).tag(String?.some(area))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Nach Bereich filtern", systemImage: model.taskAreaFilter == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .help(model.taskAreaFilter.map { L("Nur \($0)") } ?? L("Nach Bereich filtern"))
            }
        }
    }

    private var selectedTask: TaskItem? {
        model.tasks.tasks.first { $0.id == selection }
    }

    private var subtitle: String {
        let counts = model.tasks.counts
        var parts = [L("\(counts.open) offen")]
        if counts.overdue > 0 { parts.append(L("\(counts.overdue) überfällig")) }
        return parts.joined(separator: ", ")
    }

    private func doneSubtitle(_ sections: [TaskSection], period: DonePeriod) -> String {
        let count = sections.reduce(0) { $0 + $1.tasks.count }
        let text = L("\(count) erledigt")
        return count >= TaskGrouping.doneLimit ? L("Die neuesten \(count)") : text
    }

    @ViewBuilder
    private func emptyState(_ filter: TaskFilter) -> some View {
        if model.vault.state != .ready {
            ContentUnavailableView("Kein Vault geöffnet", systemImage: "folder.badge.questionmark",
                                   description: Text("Aufgaben werden aus den Notizen deines Vaults gelesen."))
        } else {
            switch filter {
            case .today:
                ContentUnavailableView("Alles erledigt für heute", systemImage: "checkmark.circle",
                                       description: Text("Neue Aufgaben kannst du unten eingeben."))
            case .week:
                ContentUnavailableView("Diese Woche ist nichts fällig", systemImage: "calendar",
                                       description: Text("Aufgaben mit 📅-Datum erscheinen hier."))
            case .all:
                ContentUnavailableView("Keine offenen Aufgaben", systemImage: "checklist",
                                       description: Text("Jede Zeile „- [ ] …“ in einer Notiz ist eine Aufgabe."))
            case .done:
                if model.settings.settings.donePeriod == .all {
                    ContentUnavailableView("Noch nichts erledigt", systemImage: "checkmark.circle")
                } else {
                    ContentUnavailableView("In diesem Zeitraum nichts erledigt", systemImage: "checkmark.circle",
                                           description: Text("Wähle in der Symbolleiste einen anderen Zeitraum."))
                }
            }
        }
    }
}

/// Eingabezeile für neue Aufgaben am unteren Rand – wie in Erinnerungen.
private struct NewTaskField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let defaultDue: Date?

    @State private var title = ""
    @State private var due: Date?
    @FocusState private var focused: Bool

    var body: some View {
        // Ein Datum im Text („bis Freitag“, „25.11.“) hat Vorrang vor der Auswahl rechts.
        let parsed = NaturalDateParser.parse(title)

        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            TextField("Neue Aufgabe", text: $title)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(add)

            DueMenuButton(due: $due, detected: parsed.date)

            if let area = model.taskAreaFilter {
                Text(area)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Wird dem Bereich \(area) zugeordnet")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .onAppear { due = defaultDue }
        .onChange(of: defaultDue) { _, newValue in due = newValue }
        .onChange(of: model.taskInputFocusRequest) { focused = true }
    }

    private func add() {
        let parsed = NaturalDateParser.parse(title)
        let dueDate = parsed.date.map { Calendar.current.startOfDay(for: $0) } ?? due
        model.tasks.add(title: parsed.title.isEmpty ? title : parsed.title, due: dueDate, priority: parsed.priority,
                        area: model.taskAreaFilter, topic: nil, undoManager: undoManager)
        title = ""
        focused = true
    }
}

#Preview("Hell") {
    NavigationStack {
        TasksView()
    }
    .environment(PreviewData.model())
    .frame(width: 720, height: 560)
}

#Preview("Dunkel") {
    NavigationStack {
        TasksView()
    }
    .environment(PreviewData.model())
    .frame(width: 720, height: 560)
    .preferredColorScheme(.dark)
}
