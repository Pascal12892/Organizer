import OrganizerCore
import SwiftUI

/// Neuer Termin im Apple Kalender.
struct NewEventSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay = false
    @State private var calendarID = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(start: Date) {
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(3600))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Titel", text: $title, prompt: Text("Neuer Termin"))
                    .focused($titleFocused)

                Toggle("Ganztägig", isOn: $isAllDay)
                DatePicker("Beginn", selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ende", selection: $end, in: start..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])

                Picker("Kalender", selection: $calendarID) {
                    ForEach(model.calendar.writableCalendars) { calendar in
                        Label {
                            Text(calendar.title)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(calendar.color)
                        }
                        .tag(calendar.id)
                    }
                }

                TextField("Notizen", text: $notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(2...5)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Hinzufügen") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || calendarID.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .onAppear {
            calendarID = model.calendar.defaultCalendarID ?? ""
            titleFocused = true
        }
        .onChange(of: start) { oldValue, newValue in
            // Dauer beibehalten, wie in Apple Kalender.
            end = newValue.addingTimeInterval(max(end.timeIntervalSince(oldValue), 0))
        }
    }

    private func create() {
        let calendar = Calendar.current
        let eventStart = isAllDay ? calendar.startOfDay(for: start) : start
        let eventEnd = isAllDay ? max(calendar.startOfDay(for: end), eventStart) : max(end, start)
        do {
            try model.createEvent(
                title: title.trimmingCharacters(in: .whitespaces),
                start: eventStart,
                end: eventEnd,
                isAllDay: isAllDay,
                calendarID: calendarID,
                notes: notes,
                undoManager: undoManager
            )
            model.calendarState.selectedDay = calendar.startOfDay(for: eventStart)
            dismiss()
        } catch {
            errorMessage = "Termin konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}

#Preview("Hell") {
    NewEventSheet(start: .now)
        .environment(PreviewData.model())
}

#Preview("Dunkel") {
    NewEventSheet(start: .now)
        .environment(PreviewData.model())
        .preferredColorScheme(.dark)
}
