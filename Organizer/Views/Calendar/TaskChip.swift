import OrganizerCore
import SwiftUI

/// Fällige Aufgabe im Kalender: runde Checkbox und Titel. Wird nicht in den Apple Kalender geschrieben.
struct TaskChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let task: TaskItem

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.tasks.setDone(task, task.isOpen, undoManager: undoManager)
            } label: {
                Image(systemName: task.isOpen ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(TaskGrouping.isOverdue(task) ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help("Als erledigt markieren")
            .accessibilityLabel("Aufgabe \(task.displayTitle) erledigen")

            Text(task.displayTitle)
                .lineLimit(1)
                .strikethrough(!task.isOpen)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .draggable(DragPayload.task(task.id)) {
            Label(task.displayTitle, systemImage: "checklist").padding(6)
        }
        .contextMenu { TaskMenuItems(task: task) }
        .onTapGesture(count: 2) { model.openNote(atPath: task.relativePath) }
        .help("\(task.displayTitle) – Doppelklick öffnet die Notiz")
    }
}
