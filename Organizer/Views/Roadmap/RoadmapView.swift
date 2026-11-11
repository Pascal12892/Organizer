import OrganizerCore
import SwiftUI

/// Auswahl in der Roadmap.
enum RoadmapSelection: Hashable {
    case project(String)
    case milestone(String)
}

/// Maßstab der Zeitleiste.
enum RoadmapZoom: String, CaseIterable {
    case weeks, months, quarters

    var title: String {
        switch self {
        case .weeks: L("Wochen")
        case .months: L("Monate")
        case .quarters: L("Quartale")
        }
    }

    var pointsPerDay: CGFloat {
        switch self {
        case .weeks: 26
        case .months: 7
        case .quarters: 2.6
        }
    }
}

/// Roadmap: Projekte und Meilensteine als horizontale Zeitleiste (Gantt-ähnlich).
struct RoadmapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var zoom: RoadmapZoom = .months
    @State private var selection: RoadmapSelection?
    @State private var showsNewProject = false
    @State private var newMilestoneProject: RoadmapProject?
    @State private var scrollToTodayRequest = 0

    var body: some View {
        let projects = model.roadmap.projects

        Group {
            if model.vault.state != .ready {
                ContentUnavailableView("Kein Vault geöffnet", systemImage: "folder.badge.questionmark",
                                       description: Text("Projekte liegen als Markdown-Dateien in _Organizer/Roadmap."))
            } else if projects.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Projekte", systemImage: "map")
                } description: {
                    Text("Jedes Projekt ist eine Notiz in _Organizer/Roadmap. Meilensteine sind Überschriften, ihre Aufgaben stehen darunter.")
                } actions: {
                    Button("Neues Projekt …") { showsNewProject = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                GanttChart(projects: projects, zoom: zoom, selection: $selection, scrollToTodayRequest: scrollToTodayRequest)
            }
        }
        .navigationTitle("Roadmap")
        .navigationSubtitle(projects.isEmpty ? "" : (projects.count == 1 ? L("1 Projekt") : L("\(projects.count) Projekte")))
        .inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
            inspector(projects: projects)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Maßstab", selection: $zoom) {
                    ForEach(RoadmapZoom.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Maßstab der Zeitleiste")
            }
            ToolbarItem {
                Button("Heute") { scrollToTodayRequest += 1 }
                    .help("Zu heute scrollen")
                    .disabled(projects.isEmpty)
            }
            ToolbarItem {
                Menu {
                    Button("Neues Projekt …") { showsNewProject = true }
                    if let project = selectedProject(in: projects) {
                        Button("Neuer Meilenstein in „\(project.title)“ …") { newMilestoneProject = project }
                    }
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                } primaryAction: {
                    if let project = selectedProject(in: projects) {
                        newMilestoneProject = project
                    } else {
                        showsNewProject = true
                    }
                }
                .help("Neuer Meilenstein im ausgewählten Projekt, sonst neues Projekt")
                .disabled(model.vault.state != .ready)
            }
        }
        .sheet(isPresented: $showsNewProject) {
            NewProjectSheet { path in selection = .project(path) }
        }
        .sheet(item: $newMilestoneProject) { project in
            NewMilestoneSheet(project: project)
        }
    }

    private func selectedProject(in projects: [RoadmapProject]) -> RoadmapProject? {
        switch selection {
        case .project(let id): projects.first { $0.id == id }
        case .milestone(let id): projects.first { $0.milestones.contains { $0.id == id } }
        case nil: nil
        }
    }

    @ViewBuilder
    private func inspector(projects: [RoadmapProject]) -> some View {
        switch selection {
        case .milestone(let id):
            if let project = projects.first(where: { $0.milestones.contains { $0.id == id } }),
               let milestone = project.milestones.first(where: { $0.id == id }) {
                MilestoneInspector(milestone: milestone, project: project)
            } else {
                ContentUnavailableView("Meilenstein nicht gefunden", systemImage: "questionmark")
            }
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                ProjectInspector(project: project) { newMilestoneProject = project }
            } else {
                ContentUnavailableView("Projekt nicht gefunden", systemImage: "questionmark")
            }
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Zeitleiste

private struct GanttChart: View {
    @Environment(AppModel.self) private var model
    let projects: [RoadmapProject]
    let zoom: RoadmapZoom
    @Binding var selection: RoadmapSelection?
    let scrollToTodayRequest: Int

    static let labelWidth: CGFloat = 230
    static let headerHeight: CGFloat = 34
    static let projectRowHeight: CGFloat = 38
    static let milestoneRowHeight: CGFloat = 30

    private let calendar = Calendar.current

    /// Zeitraum der Leiste: alle Projekte plus etwas Luft, mindestens heute.
    private var range: DateInterval {
        let today = calendar.startOfDay(for: .now)
        let starts = projects.compactMap(\.span?.start) + [today]
        let ends = projects.compactMap(\.span?.end) + [today]
        let start = calendar.date(byAdding: .day, value: -14, to: starts.min()!)!
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        let end = calendar.date(byAdding: .day, value: 45, to: ends.max()!)!
        return DateInterval(start: monthStart, end: end)
    }

    var body: some View {
        let range = range
        let width = x(range.end, in: range)
        let rows = self.rows

        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // Linke Spalte mit Namen
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: Self.headerHeight)
                    ForEach(rows) { row in
                        RowLabel(row: row, isSelected: selection == row.selection)
                            .frame(height: row.height)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = row.selection }
                    }
                }
                .frame(width: Self.labelWidth)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            TimeGrid(range: range, zoom: zoom, height: rows.reduce(Self.headerHeight) { $0 + $1.height })

                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear.frame(height: Self.headerHeight)
                                ForEach(rows) { row in
                                    TimelineRow(row: row, range: range, zoom: zoom, selection: $selection)
                                        .frame(width: width, height: row.height, alignment: .topLeading)
                                }
                            }

                            // Heute-Linie mit Anker zum Hinscrollen
                            let todayX = x(calendar.startOfDay(for: .now), in: range)
                            Rectangle()
                                .fill(.red)
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                                .offset(x: todayX)
                                .accessibilityHidden(true)
                            Color.clear
                                .frame(width: 1, height: 1)
                                .offset(x: max(todayX - 120, 0))
                                .id("today")
                        }
                        .frame(width: width, alignment: .topLeading)
                    }
                    .onAppear { proxy.scrollTo("today", anchor: .leading) }
                    .onChange(of: scrollToTodayRequest) {
                        withAnimation(.smooth) { proxy.scrollTo("today", anchor: .leading) }
                    }
                    .onChange(of: zoom) {
                        proxy.scrollTo("today", anchor: .leading)
                    }
                }
            }
        }
    }

    func x(_ date: Date, in range: DateInterval) -> CGFloat {
        CGFloat(date.timeIntervalSince(range.start) / 86_400) * zoom.pointsPerDay
    }

    struct Row: Identifiable {
        enum Kind { case project(RoadmapProject), milestone(Milestone, RoadmapProject) }
        let kind: Kind
        var id: String {
            switch kind {
            case .project(let project): "p-" + project.id
            case .milestone(let milestone, _): "m-" + milestone.id
            }
        }
        var height: CGFloat {
            if case .project = kind { return GanttChart.projectRowHeight }
            return GanttChart.milestoneRowHeight
        }
        var selection: RoadmapSelection {
            switch kind {
            case .project(let project): .project(project.id)
            case .milestone(let milestone, _): .milestone(milestone.id)
            }
        }
    }

    private var rows: [Row] {
        projects.flatMap { project in
            [Row(kind: .project(project))] + project.milestones.map { Row(kind: .milestone($0, project)) }
        }
    }
}

/// Monats- bzw. Wochenraster mit Beschriftung oben.
private struct TimeGrid: View {
    let range: DateInterval
    let zoom: RoadmapZoom
    let height: CGFloat
    private let calendar = Calendar.current

    var body: some View {
        let marks = self.marks
        ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.date) { mark in
                let x = CGFloat(mark.date.timeIntervalSince(range.start) / 86_400) * zoom.pointsPerDay
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 0.5, height: height)
                    .offset(x: x)
                Text(mark.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: x + 6, y: 10)
            }
        }
        .frame(height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var marks: [(date: Date, label: String)] {
        var result: [(Date, String)] = []
        var date = range.start
        let step: DateComponents
        switch zoom {
        case .weeks:
            date = CalendarMath.weekDays(containing: range.start, calendar: calendar)[0]
            step = DateComponents(day: 7)
        case .months: step = DateComponents(month: 1)
        case .quarters: step = DateComponents(month: 3)
        }
        while date < range.end {
            let label: String = switch zoom {
            case .weeks: L("KW \(calendar.component(.weekOfYear, from: date)) · ") + date.formatted(.dateTime.day().month(.abbreviated))
            case .months: date.formatted(.dateTime.month(.wide).year())
            case .quarters: L("Q\((calendar.component(.month, from: date) - 1) / 3 + 1) ") + date.formatted(.dateTime.year())
            }
            result.append((date, label))
            date = calendar.date(byAdding: step, to: date)!
        }
        return result
    }
}

/// Beschriftung links: Projekt fett mit Farbe und Fortschritt, Meilensteine eingerückt mit Status.
private struct RowLabel: View {
    let row: GanttChart.Row
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch row.kind {
            case .project(let project):
                Circle()
                    .fill(RoadmapService.color(named: project.color))
                    .frame(width: 10, height: 10)
                Text(project.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(project.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .milestone(let milestone, _):
                StatusIcon(status: milestone.status, isOverdue: milestone.isOverdue)
                Text(milestone.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if milestone.start == nil && milestone.end == nil {
                    Text("ohne Datum")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.leading, isMilestone ? 30 : 12)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.tint.opacity(0.15))
                    .padding(.horizontal, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var isMilestone: Bool {
        if case .milestone = row.kind { return true }
        return false
    }
}

struct StatusIcon: View {
    let status: MilestoneStatus
    var isOverdue = false

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .help(isOverdue ? L("Überfällig") : status.localizedTitle)
            .accessibilityLabel(isOverdue ? L("Überfällig") : status.localizedTitle)
    }

    private var symbol: String { StatusSymbol.name(for: status) }

    private var color: Color {
        if isOverdue { return .red }
        return switch status {
        case .planned, .paused: .secondary
        case .active: .accentColor
        case .done: .green
        }
    }
}

/// Eine Zeile der Zeitleiste: Balken für Projekt bzw. Meilenstein, verschiebbar per Ziehen.
private struct TimelineRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let row: GanttChart.Row
    let range: DateInterval
    let zoom: RoadmapZoom
    @Binding var selection: RoadmapSelection?
    @State private var dragDays = 0

    private let calendar = Calendar.current

    var body: some View {
        switch row.kind {
        case .project(let project):
            if let span = project.span {
                let color = RoadmapService.color(named: project.color)
                Capsule()
                    .fill(color.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.7))
                            .frame(width: max(width(span) * project.progress, 0))
                    }
                    .frame(width: max(width(span), 8), height: 8)
                    .offset(x: x(span.start), y: GanttChart.projectRowHeight / 2 - 4)
                    .onTapGesture { selection = .project(project.id) }
                    .help("\(project.title): \(dateText(span.start)) – \(dateText(span.end))")
            }
        case .milestone(let milestone, let project):
            milestoneBar(milestone, color: RoadmapService.color(named: project.color))
        }
    }

    @ViewBuilder
    private func milestoneBar(_ milestone: Milestone, color: Color) -> some View {
        if let start = milestone.start ?? milestone.end {
            let end = milestone.end ?? start
            let shift = TimeInterval(dragDays * 86_400)
            let interval = DateInterval(start: start.addingTimeInterval(shift),
                                        end: calendar.date(byAdding: .day, value: 1, to: end)!.addingTimeInterval(shift))
            let isSelected = selection == .milestone(milestone.id)
            let barWidth = max(width(interval), 10)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(milestone.status == .done ? 0.55 : 0.22))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.6))
                    .frame(width: barWidth * milestone.progress)
                if barWidth > 60 {
                    Text(milestone.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
            .frame(width: barWidth, height: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : (milestone.isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.clear)),
                                  lineWidth: 1.5)
            }
            .offset(x: x(interval.start), y: (GanttChart.milestoneRowHeight - 20) / 2)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in dragDays = Int((value.translation.width / zoom.pointsPerDay).rounded()) }
                    .onEnded { _ in
                        let days = dragDays
                        dragDays = 0
                        guard days != 0 else { return }
                        model.roadmap.setDates(
                            of: milestone,
                            start: milestone.start.flatMap { calendar.date(byAdding: .day, value: days, to: $0) },
                            end: milestone.end.flatMap { calendar.date(byAdding: .day, value: days, to: $0) },
                            undoManager: undoManager
                        )
                    }
            )
            .onTapGesture { selection = .milestone(milestone.id) }
            .help("\(milestone.title): \(dateText(interval.start)) – \(dateText(end.addingTimeInterval(shift))) · ziehen zum Verschieben")
            .contextMenu { MilestoneMenu(milestone: milestone) }
            .accessibilityElement()
            .accessibilityLabel("\(milestone.title), \(dateText(interval.start)) bis \(dateText(end)), \(Int(milestone.progress * 100)) Prozent")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func x(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(range.start) / 86_400) * zoom.pointsPerDay
    }

    private func width(_ interval: DateInterval) -> CGFloat {
        CGFloat(interval.duration / 86_400) * zoom.pointsPerDay
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// Kontextmenü eines Meilensteins.
struct MilestoneMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let milestone: Milestone

    var body: some View {
        Picker("Status", selection: Binding(
            get: { milestone.status },
            set: { model.roadmap.setStatus(of: milestone, $0, undoManager: undoManager) }
        )) {
            ForEach(MilestoneStatus.allCases, id: \.self) { status in
                Text(status.localizedTitle).tag(status)
            }
        }
        Divider()
        Button("In Notiz zeigen") { model.openNote(atPath: milestone.relativePath) }
        if let note = model.vault.notes.first(where: { $0.relativePath == milestone.relativePath }) {
            Button("In Obsidian öffnen") { model.openInObsidian(note) }
        }
    }
}

#Preview("Hell") {
    NavigationStack {
        RoadmapView()
    }
    .environment(PreviewData.model())
    .frame(width: 1000, height: 560)
}

#Preview("Dunkel") {
    NavigationStack {
        RoadmapView()
    }
    .environment(PreviewData.model())
    .frame(width: 1000, height: 560)
    .preferredColorScheme(.dark)
}
