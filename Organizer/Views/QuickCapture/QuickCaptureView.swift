import OrganizerCore
import SwiftUI

/// Was die Schnellerfassung anlegt.
enum CaptureKind: String, CaseIterable {
    case task, event, note

    var title: String {
        switch self {
        case .task: L("Aufgabe")
        case .event: L("Termin")
        case .note: L("Notiz")
        }
    }

    var systemImage: String {
        switch self {
        case .task: "checklist"
        case .event: "calendar.badge.plus"
        case .note: "note.text"
        }
    }

    var placeholder: String {
        switch self {
        case .task: L("Aufgabe, z. B. „Hausarbeit Kapitel 2 bis Freitag #uni !!“")
        case .event: L("Termin, z. B. „Lerngruppe morgen 14 Uhr“")
        case .note: L("Titel der Notiz, z. B. „Idee für das Projekt #arbeit“")
        }
    }
}

/// Eingabe mit Live-Vorschau – im schwebenden Panel und im Dashboard.
struct QuickCaptureView: View {
    enum Style { case panel, inline }

    @Environment(AppModel.self) private var model
    var style: Style = .inline
    var undoManager: UndoManager?
    var onDone: (() -> Void)?

    /// Eingabe des schwebenden Panels. Im Dashboard liegt sie stattdessen in `model.dashboardDraft`,
    /// damit sie einen Wechsel des Bereichs übersteht (aber kein Beenden der App).
    @State private var panelDraft = EntryDraft()

    private var draft: Binding<EntryDraft> {
        style == .inline ? Bindable(model).dashboardDraft : $panelDraft
    }
    private var text: String { draft.wrappedValue.text }
    private var kind: CaptureKind { draft.wrappedValue.kind }
    @State private var message: (text: String, isError: Bool)?
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = NaturalDateParser.parse(text)

        VStack(alignment: .leading, spacing: style == .panel ? 12 : 8) {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(style == .panel ? .title2 : .title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .contentTransition(.symbolEffect(.replace))
                TextField(kind.placeholder, text: draft.text)
                    .textFieldStyle(.plain)
                    .font(style == .panel ? .title2 : .body)
                    .focused($focused)
                    .onSubmit(save)
                    .onKeyPress(.tab) {
                        cycleKind()
                        return .handled
                    }
                    .accessibilityLabel("Schnellerfassung: \(kind.title)")
                if kind == .task {
                    DueMenuButton(due: draft.due, detected: parsed.date)
                }
                Picker("Art", selection: draft.kind) {
                    ForEach(CaptureKind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Art wechseln (⇥)")
            }

            if let message {
                Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                preview(parsed)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if style == .panel {
                Text("⏎ speichert · ⇥ wechselt die Art · esc schließt")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.smooth, value: message?.text)
        .onAppear { focused = style == .panel }
        .onChange(of: text) { message = nil }
    }

    // MARK: Vorschau

    @ViewBuilder
    private func preview(_ parsed: ParsedCapture) -> some View {
        HStack(spacing: 12) {
            switch kind {
            case .task:
                if let date = parsed.date ?? draft.wrappedValue.due {
                    Label(TaskRow.relativeDay(date), systemImage: "calendar")
                    if parsed.hasTime {
                        Text("Uhrzeit wird bei Aufgaben nicht gespeichert")
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Label("Ohne Datum", systemImage: "calendar")
                }
                if parsed.priority > .none {
                    Label(parsed.priority.localizedTitle, systemImage: "exclamationmark")
                }
                if let area = area(for: parsed) { Label(area, systemImage: SidebarItem.areaSymbol(for: area)) }
            case .event:
                if let date = parsed.date {
                    Label(parsed.hasTime ? date.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
                                         : date.formatted(.dateTime.weekday(.abbreviated).day().month()) + L(", ganztägig"),
                          systemImage: "clock")
                } else {
                    Label("Wann? z. B. „Freitag 14 Uhr“", systemImage: "questionmark.circle")
                }
            case .note:
                Label(noteFolder(for: parsed).isEmpty ? "Oberste Ebene" : noteFolder(for: parsed), systemImage: "folder")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: Speichern

    private func save() {
        let parsed = NaturalDateParser.parse(text)
        let title = kind == .note ? text.trimmingCharacters(in: .whitespaces) : parsed.title
        guard !title.isEmpty else { return }
        let undo = undoManager ?? Self.mainWindowUndoManager

        switch kind {
        case .task:
            model.tasks.lastError = nil
            model.tasks.add(title: title, due: parsed.date.map { Calendar.current.startOfDay(for: $0) } ?? draft.wrappedValue.due,
                            priority: parsed.priority, area: area(for: parsed), topic: topic(for: parsed), undoManager: undo)
            if let error = model.tasks.lastError { return show(error, isError: true) }
            finish(L("Aufgabe „\(title)“ angelegt"))

        case .event:
            guard model.calendar.access == .fullAccess else {
                return show(L("Erlaube zuerst den Zugriff auf den Kalender (Kalenderansicht)."), isError: true)
            }
            guard let start = parsed.date else { return show(L("Wann? Zum Beispiel „Freitag 14 Uhr“."), isError: true) }
            guard let calendarID = model.calendar.defaultCalendarID else { return show(L("Kein beschreibbarer Kalender vorhanden."), isError: true) }
            do {
                try model.createEvent(title: title, start: start,
                                      end: parsed.hasTime ? start.addingTimeInterval(3600) : start,
                                      isAllDay: !parsed.hasTime, calendarID: calendarID, notes: nil, undoManager: undo)
                finish(L("Termin „\(title)“ angelegt"))
            } catch {
                show(localizedMessage(error), isError: true)
            }

        case .note:
            Task {
                do {
                    try await model.createNote(title: title, folder: noteFolder(for: parsed), openInEditor: style == .inline, undoManager: undo)
                    finish(L("Notiz „\(title)“ angelegt"))
                } catch {
                    show(localizedMessage(error), isError: true)
                }
            }
        }
    }

    private func finish(_ text: String) {
        draft.wrappedValue.text = ""
        draft.wrappedValue.due = nil
        show(text, isError: false)
        if let onDone {
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                onDone()
                message = nil
            }
        }
    }

    private func show(_ text: String, isError: Bool) {
        message = (text, isError)
    }

    private func cycleKind() {
        let all = CaptureKind.allCases
        draft.wrappedValue.kind = all[(all.firstIndex(of: kind)! + 1) % all.count]
    }

    /// `#uni` → Bereich „Uni“.
    private func area(for parsed: ParsedCapture) -> String? {
        model.areas.first { area in parsed.tags.contains { $0.caseInsensitiveCompare(NoteTemplate.tag(for: area)) == .orderedSame } }
    }

    private func topic(for parsed: ParsedCapture) -> String? {
        guard let area = area(for: parsed) else { return nil }
        return model.vault.snapshot.topics(in: area).first { topic in
            parsed.tags.contains { $0.caseInsensitiveCompare(NoteTemplate.tag(for: topic.name)) == .orderedSame }
        }?.name
    }

    private func noteFolder(for parsed: ParsedCapture) -> String {
        if let area = area(for: parsed) {
            return [area, topic(for: parsed)].compactMap { $0 }.joined(separator: "/")
        }
        return model.settings.settings.quickNoteFolder
    }

    /// Undo-Stapel des Hauptfensters, damit ⌘Z dort auch die Schnellerfassung rückgängig macht.
    static var mainWindowUndoManager: UndoManager? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.undoManager
    }
}
