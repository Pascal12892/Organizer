import OrganizerCore
import SwiftUI

/// Aufgaben als Board: Spalten Offen, In Arbeit und Erledigt (letzte 7 Tage).
/// Eine Aufgabe in eine andere Spalte ziehen ändert nur das Statuszeichen ihrer Zeile.
/// Ohne Maus geht dasselbe über das Kontextmenü „Status“.
struct TaskBoardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let board = model.tasks.board(area: model.taskAreaFilter)
        HStack(alignment: .top, spacing: 12) {
            ForEach(TaskBoardColumn.allCases) { column in
                BoardColumnView(column: column, tasks: board[column] ?? [])
            }
        }
        .padding(12)
        .animation(.smooth, value: board)
    }
}

private struct BoardColumnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let column: TaskBoardColumn
    let tasks: [TaskItem]

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { task in
                        TaskRow(task: task, showsArea: model.taskAreaFilter == nil)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            }
                    }
                }
                .padding(8)
            }
            .overlay {
                if tasks.isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.localizedTitle)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: column.symbol)
                .foregroundStyle(.secondary)
            Text(column.localizedTitle)
                .font(.headline)
            Spacer()
            Text(tasks.count, format: .number)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("\(tasks.count) Aufgaben"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyText: String {
        switch column {
        case .open: L("Keine offenen Aufgaben")
        case .inProgress: L("Aufgabe hierher ziehen, um sie zu beginnen")
        case .done: L("In den letzten 7 Tagen nichts erledigt")
        }
    }

    /// Abgelegte Aufgaben bekommen den Status der Spalte. Erledigt legt bei 🔁 die nächste Wiederholung an.
    private func drop(_ items: [String]) -> Bool {
        let ids = Set(items.compactMap(DragPayload.taskID(from:)))
        let dropped = model.tasks.tasks.filter { ids.contains($0.id) && $0.status != column.status }
        for task in dropped {
            model.tasks.setStatus(task, column.status, undoManager: undoManager)
        }
        return !dropped.isEmpty
    }
}

#Preview("Hell") {
    TaskBoardView()
        .environment(PreviewData.model())
        .frame(width: 900, height: 560)
}

#Preview("Dunkel") {
    TaskBoardView()
        .environment(PreviewData.model())
        .frame(width: 900, height: 560)
        .preferredColorScheme(.dark)
}
