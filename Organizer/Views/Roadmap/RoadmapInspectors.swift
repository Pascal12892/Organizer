import OrganizerCore
import SwiftUI

/// Details eines Meilensteins im Inspector: Zeitraum, Status, Fortschritt und Aufgaben.
struct MilestoneInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let milestone: Milestone
    let project: RoadmapProject
    @State private var newTask = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(milestone.title)
                        .font(.title3.weight(.semibold))
                    Label(project.title, systemImage: "map")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Zeitraum") {
                optionalDate("Beginn", date: milestone.start) { date in
                    model.roadmap.setDates(of: milestone, start: date, end: milestone.end, undoManager: undoManager)
                }
                optionalDate("Ende", date: milestone.end) { date in
                    model.roadmap.setDates(of: milestone, start: milestone.start, end: date, undoManager: undoManager)
                }
                Picker("Status", selection: Binding(
                    get: { milestone.status },
                    set: { model.roadmap.setStatus(of: milestone, $0, undoManager: undoManager) }
                )) {
                    ForEach(MilestoneStatus.allCases, id: \.self) { status in
                        Label(status.rawValue.capitalized, systemImage: StatusSymbol.name(for: status)).tag(status)
                    }
                }
            }

            Section("Fortschritt") {
                let relevant = milestone.tasks.filter { $0.status != .cancelled }
                ProgressView(value: milestone.progress) {
                    Text(relevant.isEmpty
                         ? (milestone.status == .done ? "Erledigt" : "Noch keine Aufgaben")
                         : "\(relevant.filter { $0.status == .done }.count) von \(relevant.count) Aufgaben erledigt")
                }
                if milestone.isOverdue {
                    Label("Das Ende ist überschritten.", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section("Aufgaben") {
                ForEach(milestone.tasks) { task in
                    TaskRow(task: task, showsArea: false)
                }
                TextField("Neue Aufgabe", text: $newTask)
                    .onSubmit {
                        model.roadmap.addTask(newTask, due: milestone.end, to: milestone, undoManager: undoManager)
                        newTask = ""
                    }
                    .help("Neue Aufgaben bekommen das Ende des Meilensteins als Fälligkeit.")
            }

            Section {
                Button("In Notiz zeigen") { model.openNote(atPath: milestone.relativePath) }
                if let note = model.vault.notes.first(where: { $0.relativePath == milestone.relativePath }) {
                    Button("In Obsidian öffnen") { model.openInObsidian(note) }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Datum mit Schalter: ausgeschaltet entfernt das Feld aus der Datei.
    private func optionalDate(_ title: String, date: Date?, set: @escaping (Date?) -> Void) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { $0 ? set(milestone.start ?? milestone.end ?? Calendar.current.startOfDay(for: .now)) : set(nil) }
            ))
            if let date {
                Spacer()
                DatePicker(title, selection: Binding(get: { date }, set: { set($0) }), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

enum StatusSymbol {
    static func name(for status: MilestoneStatus) -> String {
        switch status {
        case .planned: "circle.dashed"
        case .active: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        case .paused: "pause.circle"
        }
    }
}

/// Übersicht eines Projekts im Inspector.
struct ProjectInspector: View {
    @Environment(AppModel.self) private var model
    let project: RoadmapProject
    let addMilestone: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(RoadmapService.color(named: project.color)).frame(width: 12, height: 12)
                        Text(project.title).font(.title3.weight(.semibold))
                    }
                    if let area = project.area {
                        Label(area, systemImage: SidebarItem.areaSymbol(for: area)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Überblick") {
                if let span = project.span {
                    LabeledContent("Zeitraum") {
                        Text(span.start.formatted(date: .abbreviated, time: .omitted) + " – " + span.end.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                LabeledContent("Status") { Text(project.status.rawValue.capitalized) }
                ProgressView(value: project.progress) {
                    Text("\(project.milestones.filter { $0.status == .done }.count) von \(project.milestones.count) Meilensteinen erledigt")
                }
            }
            Section("Meilensteine") {
                ForEach(project.milestones) { milestone in
                    HStack {
                        StatusIcon(status: milestone.status, isOverdue: milestone.isOverdue)
                        Text(milestone.title)
                        Spacer()
                        if let end = milestone.end {
                            Text(end, format: .dateTime.day().month(.abbreviated))
                                .foregroundStyle(milestone.isOverdue ? .red : .secondary)
                                .monospacedDigit()
                        }
                    }
                    .contextMenu { MilestoneMenu(milestone: milestone) }
                }
                Button("Neuer Meilenstein …", action: addMilestone)
            }
            Section {
                Text("Projektdaten wie Zeitraum, Status und Farbe stehen im Frontmatter der Datei und lassen sich in der Notiz oder in Obsidian ändern.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("In Notiz zeigen") { model.openNote(atPath: project.relativePath) }
                if let note = model.vault.notes.first(where: { $0.relativePath == project.relativePath }) {
                    Button("In Obsidian öffnen") { model.openInObsidian(note) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Neues Projekt in _Organizer/Roadmap.
struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    let onCreate: (String) -> Void

    @State private var title = ""
    @State private var area: String?
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.date(byAdding: .month, value: 3, to: Calendar.current.startOfDay(for: .now))!
    @State private var color = "blue"
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $title, prompt: Text("z. B. Bachelorarbeit"))
                    .focused($titleFocused)
                Picker("Bereich", selection: $area) {
                    Text("Kein Bereich").tag(String?.none)
                    ForEach(model.areas, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                DatePicker("Beginn", selection: $start, displayedComponents: .date)
                DatePicker("Ende", selection: $end, in: start..., displayedComponents: .date)
                Picker("Farbe", selection: $color) {
                    ForEach(RoadmapService.colorNames, id: \.self) { name in
                        Label {
                            Text(RoadmapService.colorTitle(name))
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(RoadmapService.color(named: name))
                        }
                        .tag(name)
                    }
                }
                Text("Organizer legt die Datei _Organizer/Roadmap/\(NoteTemplate.fileName(for: title.isEmpty ? "Name" : title)).md an.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Anlegen") {
                    if let path = model.roadmap.createProject(title: title.trimmingCharacters(in: .whitespaces), area: area,
                                                               start: start, end: end, color: color, undoManager: undoManager) {
                        onCreate(path)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .onAppear { titleFocused = true }
    }
}

/// Neuer Meilenstein am Ende der Projektdatei.
struct NewMilestoneSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    let project: RoadmapProject

    @State private var title = ""
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.date(byAdding: .day, value: 14, to: Calendar.current.startOfDay(for: .now))!
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent("Projekt", value: project.title)
                TextField("Name", text: $title, prompt: Text("z. B. Literaturrecherche"))
                    .focused($titleFocused)
                DatePicker("Beginn", selection: $start, displayedComponents: .date)
                DatePicker("Ende", selection: $end, in: start..., displayedComponents: .date)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Anlegen") {
                    model.roadmap.addMilestone(title.trimmingCharacters(in: .whitespaces), start: start, end: end,
                                               to: project, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 400)
        .onAppear {
            // Neuer Meilenstein beginnt nach dem letzten.
            if let last = project.milestones.compactMap(\.end).max(), last >= start {
                start = Calendar.current.date(byAdding: .day, value: 1, to: last)!
                end = Calendar.current.date(byAdding: .day, value: 14, to: start)!
            }
            titleFocused = true
        }
    }
}
