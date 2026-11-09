import OrganizerCore
import SwiftUI

struct TaskSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Neue Aufgaben speichern", selection: Binding(
                    get: { model.settings.settings.taskStorage },
                    set: { storage in model.settings.update { $0.taskStorage = storage } }
                )) {
                    ForEach(TaskStorage.allCases, id: \.self) { storage in
                        Text(storage.title).tag(storage)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Speicherort")
            } footer: {
                Text("Gilt für Aufgaben, die du in Organizer anlegst. Aufgaben, die schon in Notizen stehen, bleiben dort – Organizer sammelt alle Zeilen „- [ ] …“ aus dem ganzen Vault ein. Ohne Bereich landen neue Aufgaben immer in Tasks.md.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Format") {
                LabeledContent("Beispiel") {
                    Text("- [ ] Kapitel 2 schreiben ⏫ 📅 2026-11-20 #uni")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                Text("Kompatibel mit dem Obsidian-Plugin „Tasks“. Beim Abhaken ergänzt Organizer „✅ Datum“. Wiederholungen (🔁) werden angezeigt, aber nicht automatisch neu angelegt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Hell") {
    TaskSettingsView()
        .environment(PreviewData.model())
        .frame(width: 520, height: 400)
}

#Preview("Dunkel") {
    TaskSettingsView()
        .environment(PreviewData.model())
        .frame(width: 520, height: 400)
        .preferredColorScheme(.dark)
}
