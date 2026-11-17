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

#Preview("Hell") {
    DuePicker(initial: .now) { _ in }
}

#Preview("Dunkel") {
    DuePicker(initial: nil) { _ in }
        .preferredColorScheme(.dark)
}
