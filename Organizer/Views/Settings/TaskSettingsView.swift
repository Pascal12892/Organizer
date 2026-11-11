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

            RemindersSection()

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

/// Abgleich mit Apple Erinnerungen.
private struct RemindersSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sync = model.reminders
        Section {
            Toggle("Mit Apple Erinnerungen abgleichen", isOn: Binding(
                get: { sync.isEnabled },
                set: { enabled in
                    if enabled { Task { await sync.enable() } } else { sync.disable() }
                }
            ))
            if sync.isEnabled {
                HStack {
                    status(sync.status)
                    Spacer()
                    Button("Jetzt abgleichen") { Task { await sync.syncNow() } }
                        .disabled(sync.status == .syncing || sync.status == .denied)
                }
                if sync.status == .denied {
                    Button("Systemeinstellungen öffnen") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                    }
                }
            }
        } header: {
            Text("Apple Erinnerungen")
        } footer: {
            Text("Offene Aufgaben mit Datum erscheinen in Listen „Organizer – Bereich“ – über iCloud auch auf dem iPhone. Abhaken, Titel oder Datum ändern in Erinnerungen wird in die Markdown-Zeile übernommen, neue Erinnerungen in diesen Listen landen in _Organizer/Tasks.md. Bei gleichzeitigen Änderungen gewinnt Markdown. Ausschalten lässt alles, wie es ist.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func status(_ status: RemindersSyncService.Status) -> some View {
        switch status {
        case .off:
            EmptyView()
        case .needsAccess:
            Label("Wartet auf Erlaubnis", systemImage: "hourglass").foregroundStyle(.secondary)
        case .denied:
            Label("Kein Zugriff auf Erinnerungen", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Gleiche ab …").foregroundStyle(.secondary)
            }
        case .synced(let date):
            if date == .distantPast {
                Text("Noch nicht abgeglichen").foregroundStyle(.secondary)
            } else {
                Label("\(model.reminders.linkCount) verknüpft · zuletzt \(date.formatted(date: .omitted, time: .shortened))",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .lineLimit(3)
        }
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
