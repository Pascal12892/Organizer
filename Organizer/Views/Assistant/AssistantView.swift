import OrganizerCore
import SwiftUI

/// Chat mit Claude. Claude kann Notizen, Aufgaben und Termine lesen und – nach Bestätigung – anlegen.
struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings
    @FocusState private var inputFocused: Bool

    var body: some View {
        let chat = model.chat!

        VStack(spacing: 0) {
            if !chat.hasAPIKey {
                ContentUnavailableView {
                    Label("Claude verbinden", systemImage: "sparkles")
                } description: {
                    Text("Für den Chat brauchst du einen eigenen API-Schlüssel von Anthropic (console.anthropic.com). Die Nutzung wird nach Verbrauch abgerechnet.")
                } actions: {
                    Button("Einstellungen öffnen …") { openSettings() }
                        .buttonStyle(.borderedProminent)
                }
            } else if chat.isEmpty {
                ContentUnavailableView {
                    Label("Was soll ich erledigen?", systemImage: "sparkles")
                } description: {
                    Text("Zum Beispiel: „Leg für Freitag 14 Uhr einen Termin ‚Lerngruppe‘ an und eine Aufgabe, Kapitel 3 bis Mittwoch zu lesen.“\n\nWas du schreibst und was Claude dafür aus deinen Notizen liest, wird an Anthropic gesendet. Änderungen musst du bestätigen.")
                }
            } else {
                messages(chat)
            }

            if chat.hasAPIKey {
                Divider()
                inputBar(chat)
            }
        }
        .navigationTitle("Claude")
        .navigationSubtitle(AssistantModel(rawValue: model.settings.settings.assistantModel)?.title ?? "")
        .toolbar {
            ToolbarItem {
                Button {
                    chat.reset()
                    inputFocused = true
                } label: {
                    Label("Neuer Chat", systemImage: "square.and.pencil")
                }
                .help("Neuer Chat – der bisherige Verlauf wird verworfen")
                .disabled(chat.isEmpty)
            }
        }
        .onAppear {
            chat.undoManager = undoManager
            inputFocused = true
        }
        .onChange(of: undoManager) { _, manager in chat.undoManager = manager }
    }

    private func messages(_ chat: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chat.entries) { entry in
                        ChatEntryView(entry: entry, chat: chat)
                            .id(entry.id)
                    }
                    if chat.isRunning, chat.waitingActions.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Claude arbeitet …").foregroundStyle(.secondary)
                        }
                        .id("progress")
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: chat.entries.count) {
                withAnimation(.smooth) { proxy.scrollTo(chat.entries.last?.id, anchor: .bottom) }
            }
            .onChange(of: lastText(chat)) {
                proxy.scrollTo(chat.entries.last?.id, anchor: .bottom)
            }
        }
    }

    private func lastText(_ chat: ChatViewModel) -> Int {
        if case .assistant(let text) = chat.entries.last?.kind { return text.count }
        return 0
    }

    private func inputBar(_ chat: ChatViewModel) -> some View {
        @Bindable var chat = chat
        return HStack(alignment: .bottom, spacing: 10) {
            TextField("Nachricht an Claude", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($inputFocused)
                .onKeyPress(.return, phases: .down) { press in
                    // ⏎ sendet, ⇧⏎ fügt eine neue Zeile ein.
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    chat.send()
                    return .handled
                }
                .accessibilityLabel("Nachricht an Claude")

            if chat.isRunning {
                Button {
                    chat.stop()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Anhalten")
                .accessibilityLabel("Anhalten")
            } else {
                Button {
                    chat.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Senden (⏎)")
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct ChatEntryView: View {
    let entry: ChatViewModel.Entry
    let chat: ChatViewModel

    var body: some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant(let text):
            MarkdownView(content: MarkdownContent(markdown: text))
        case .activity(let title, let systemImage, let isError):
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        case .action(let action):
            ActionCard(action: action, chat: chat)
        case .notice(let text, let isError):
            Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "info.circle")
                .symbolRenderingMode(isError ? .multicolor : .monochrome)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Vorgeschlagene Änderung mit „Ausführen“ und „Ablehnen“.
private struct ActionCard: View {
    let action: PendingAction
    let chat: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(action.title, systemImage: action.systemImage)
                .font(.headline)
            ForEach(action.details, id: \.self) { detail in
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
            HStack {
                status
                Spacer()
                if action.state == .waiting {
                    Button("Ablehnen") { chat.reject(action) }
                    Button("Ausführen") { chat.approve(action) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(chat.waitingActions.count == 1 ? .defaultAction : nil)
                }
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.smooth, value: action.state)
    }

    @ViewBuilder
    private var status: some View {
        switch action.state {
        case .waiting:
            if chat.waitingActions.count > 1, chat.waitingActions.first === action {
                Button("Alle ausführen") { chat.approveAll() }
                    .buttonStyle(.link)
            }
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Label("Ausgeführt – ⌘Z macht es rückgängig", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .rejected:
            Label("Abgelehnt", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.callout)
        }
    }
}

#Preview("Hell") {
    NavigationStack {
        AssistantView()
    }
    .environment(PreviewData.model())
    .frame(width: 700, height: 560)
}

#Preview("Dunkel") {
    NavigationStack {
        AssistantView()
    }
    .environment(PreviewData.model())
    .frame(width: 700, height: 560)
    .preferredColorScheme(.dark)
}
