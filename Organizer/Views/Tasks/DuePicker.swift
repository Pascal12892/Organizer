import SwiftUI

/// Fälligkeit wählen: Schnellauswahl und ein Kalender für ein genaues Datum.
struct DuePicker: View {
    let initial: Date?
    let onChoose: (Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(initial: Date?, onChoose: @escaping (Date?) -> Void) {
        self.initial = initial
        self.onChoose = onChoose
        _date = State(initialValue: initial ?? Calendar.current.startOfDay(for: .now))
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                quick(L("Heute"), today)
                quick(L("Morgen"), calendar.date(byAdding: .day, value: 1, to: today)!)
                quick(L("Nächste Woche"), calendar.nextDate(after: today, matching: DateComponents(weekday: calendar.firstWeekday),
                                                             matchingPolicy: .nextTime)!)
            }
            DatePicker("Datum", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                if initial != nil {
                    Button("Fälligkeit entfernen", role: .destructive) { choose(nil) }
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Übernehmen") { choose(calendar.startOfDay(for: date)) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func quick(_ title: String, _ value: Date) -> some View {
        Button(title) { choose(value) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func choose(_ value: Date?) {
        onChoose(value)
        dismiss()
    }
}

/// Datumsknopf für Eingabezeilen neuer Aufgaben (Aufgabenliste, Dashboard, Schnellerfassung).
/// Ein im Text erkanntes Datum („bis Freitag“) hat Vorrang und wird angezeigt.
struct DueMenuButton: View {
    @Binding var due: Date?
    /// Aus dem eingegebenen Text erkanntes Datum.
    var detected: Date?
    @State private var showsPicker = false

    var body: some View {
        let effective = detected.map { Calendar.current.startOfDay(for: $0) } ?? due
        Menu {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            Button("Heute") { due = today }
            Button("Morgen") { due = calendar.date(byAdding: .day, value: 1, to: today) }
            Button("Nächste Woche") {
                due = calendar.nextDate(after: today, matching: DateComponents(weekday: calendar.firstWeekday), matchingPolicy: .nextTime)
            }
            Button("Datum wählen …") { showsPicker = true }
            Divider()
            Button("Ohne Datum") { due = nil }
        } label: {
            Label(effective.map(TaskRow.relativeDay) ?? L("Ohne Datum"), systemImage: "calendar")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(detected != nil ? L("Datum aus dem Text erkannt") : L("Fälligkeit"))
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            DuePicker(initial: due) { due = $0 }
        }
    }
}

#Preview("Hell") {
    DuePicker(initial: .now) { _ in }
}

#Preview("Dunkel") {
    DuePicker(initial: nil) { _ in }
        .preferredColorScheme(.dark)
}
