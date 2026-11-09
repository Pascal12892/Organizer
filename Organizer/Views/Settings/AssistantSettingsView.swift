import OrganizerCore
import SwiftUI

/// Einstellungen für den Chat mit Claude: API-Schlüssel, Modell, Gründlichkeit, Bestätigung.
struct AssistantSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var hasKey = KeychainStore.apiKey?.isEmpty == false
    @State private var status: (text: String, isError: Bool)?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                if hasKey {
                    LabeledContent("API-Schlüssel") {
                        HStack {
                            Text("Im Schlüsselbund gespeichert")
                                .foregroundStyle(.secondary)
                            Button("Prüfen") { verify() }
                                .disabled(isChecking)
                            Button("Entfernen", role: .destructive) {
                                KeychainStore.delete()
                                hasKey = false
                                status = nil
                            }
                        }
                    }
                } else {
                    SecureField("API-Schlüssel", text: $keyDraft, prompt: Text("sk-ant-…"))
                        .onSubmit(save)
                    HStack {
                        Link("Schlüssel bei Anthropic erstellen", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        Spacer()
                        Button("Sichern") { save() }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if isChecking {
                    ProgressView().controlSize(.small)
                } else if let status {
                    Label(status.text, systemImage: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                }
            } header: {
                Text("Zugang")
            } footer: {
                Text("Der Schlüssel liegt nur im macOS-Schlüsselbund. Für den Chat werden deine Nachrichten und die Notizen, Aufgaben und Termine, die Claude dafür liest, an Anthropic gesendet. Alle anderen Funktionen von Organizer bleiben lokal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Verhalten") {
                Picker("Modell", selection: binding(\.assistantModel)) {
                    ForEach(AssistantModel.allCases, id: \.self) { model in
                        Text(model.title).tag(model.rawValue)
                    }
                }
                Picker("Gründlichkeit", selection: binding(\.assistantEffort)) {
                    Text("Schnell").tag("low")
                    Text("Ausgewogen").tag("medium")
                    Text("Gründlich").tag("high")
                }
                .help("Steuert, wie viel Claude nachdenkt – mehr Gründlichkeit kostet mehr Zeit und Tokens.")
                Toggle("Änderungen vor dem Ausführen bestätigen", isOn: binding(\.assistantConfirmsChanges))
                Text("Lesen und Suchen ist immer erlaubt. Ohne Bestätigung führt Claude Änderungen sofort aus; ⌘Z macht sie weiterhin rückgängig.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings.settings[keyPath: keyPath] },
            set: { value in model.settings.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func save() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainStore.save(key)
            keyDraft = ""
            hasKey = true
            verify()
        } catch {
            status = (error.localizedDescription, true)
        }
    }

    private func verify() {
        guard let key = KeychainStore.apiKey else { return }
        isChecking = true
        Task {
            do {
                try await AnthropicClient(apiKey: key).verifyKey(model: model.settings.settings.assistantModel)
                status = ("Verbindung funktioniert.", false)
            } catch {
                status = (error.localizedDescription, true)
            }
            isChecking = false
        }
    }
}

#Preview("Hell") {
    AssistantSettingsView()
        .environment(PreviewData.model())
        .frame(width: 520, height: 460)
}

#Preview("Dunkel") {
    AssistantSettingsView()
        .environment(PreviewData.model())
        .frame(width: 520, height: 460)
        .preferredColorScheme(.dark)
}
