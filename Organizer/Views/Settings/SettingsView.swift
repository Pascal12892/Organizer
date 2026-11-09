import SwiftUI

/// Einstellungsfenster (Cmd+,).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Allgemein", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Bereiche", systemImage: "square.stack") {
                AreasSettingsView()
            }
            Tab("Aufgaben", systemImage: "checklist") {
                TaskSettingsView()
            }
            Tab("Claude", systemImage: "sparkles") {
                AssistantSettingsView()
            }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Ordner") {
                    if let url = model.vault.rootURL {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(url.lastPathComponent)
                            Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .truncationMode(.middle)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Nicht ausgewählt")
                            .foregroundStyle(.secondary)
                    }
                }

                if model.vault.state == .ready {
                    LabeledContent("Inhalt") {
                        Text("\(model.vault.notes.count) Notizen, \(model.vault.snapshot.topics.count) Themen")
                    }
                    if !model.vaultLooksLikeObsidian {
                        Label("In diesem Ordner fehlt „.obsidian“. Ist es wirklich ein Obsidian-Vault?",
                              systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.callout)
                    }
                }
                if case .accessLost(_, let message) = model.vault.state {
                    Label(message, systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.callout)
                }

                HStack {
                    if let url = model.vault.rootURL {
                        Button("Im Finder zeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    Spacer()
                    Button(model.vault.rootURL == nil ? "Vault auswählen …" : "Anderen Vault wählen …") {
                        model.chooseVault()
                    }
                }
            } header: {
                Text("Obsidian-Vault")
            } footer: {
                Text("Organizer liest Markdown-Dateien direkt aus diesem Ordner. Änderungen aus Obsidian erscheinen automatisch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = model.settings.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Hell") {
    SettingsView()
        .environment(PreviewData.model())
}

#Preview("Dunkel") {
    SettingsView()
        .environment(PreviewData.model())
        .preferredColorScheme(.dark)
}
