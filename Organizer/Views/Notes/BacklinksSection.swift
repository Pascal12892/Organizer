import OrganizerCore
import SwiftUI

/// „Verlinkt von“ unter einer Notiz: Notizen und Aufgaben, die per `[[…]]` auf sie verweisen.
/// Klick öffnet die Quelle. Aufgaben lassen sich hier auch abhaken.
struct BacklinksSection: View {
    @Environment(AppModel.self) private var model
    let note: Note
    @AppStorage("backlinksExpanded") private var isExpanded = true

    var body: some View {
        let backlinks = model.vault.index.backlinks[note.relativePath] ?? []
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            DisclosureGroup(isExpanded: $isExpanded) {
                if backlinks.isEmpty {
                    Text("Keine andere Notiz und keine Aufgabe verlinkt auf diese Notiz.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(backlinks) { backlink in
                            BacklinkRow(backlink: backlink)
                        }
                    }
                    .padding(.top, 4)
                }
            } label: {
                Label {
                    Text(L("Verlinkt von (\(backlinks.count))"))
                        .font(.headline)
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct BacklinkRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let backlink: Backlink

    /// Die Aufgabe hinter der Zeile, damit Abhaken genau diese Zeile ändert.
    private var task: TaskItem? {
        guard backlink.isTask else { return nil }
        return model.tasks.tasks.first { $0.relativePath == backlink.sourcePath && $0.lineNumber == backlink.lineNumber }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let task {
                Button {
                    model.tasks.setDone(task, task.isOpen, undoManager: undoManager)
                } label: {
                    Image(systemName: task.isOpen ? (task.status == .inProgress ? "circle.lefthalf.filled" : "circle")
                                                  : "checkmark.circle.fill")
                        .foregroundStyle(task.isOpen ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
                .buttonStyle(.plain)
                .help(task.isOpen ? L("Als erledigt markieren") : L("Wieder öffnen"))
                .accessibilityLabel(task.isOpen ? L("Erledigen") : L("Wieder öffnen"))
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Button {
                model.openNote(atPath: backlink.sourcePath)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(backlink.excerpt.isEmpty ? backlink.sourceTitle : backlink.excerpt)
                        .foregroundStyle(.primary)
                        .strikethrough(backlink.taskStatus == .done || backlink.taskStatus == .cancelled)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(backlink.sourceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("„\(backlink.sourceTitle)“ öffnen"))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
