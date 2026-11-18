import SwiftUI
import UserNotifications

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
                ClaudeSettingsView()
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
                    Button(model.vault.rootURL == nil ? L("Vault auswählen …") : L("Anderen Vault wählen …")) {
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

            Section {
                Picker("Tastenkürzel", selection: Binding(
                    get: { HotKeyPreset(rawValue: model.settings.settings.quickCaptureHotKey) ?? .controlOptionSpace },
                    set: { preset in
                        model.settings.update { $0.quickCaptureHotKey = preset.rawValue }
                        model.registerQuickCaptureHotKey()
                    }
                )) {
                    ForEach(HotKeyPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if let warning = (HotKeyPreset(rawValue: model.settings.settings.quickCaptureHotKey) ?? .controlOptionSpace).warning {
                    Text(warning).font(.callout).foregroundStyle(.secondary)
                }
                TextField("Ordner für schnelle Notizen", text: Binding(
                    get: { model.settings.settings.quickNoteFolder },
                    set: { value in model.settings.update { $0.quickNoteFolder = value.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) } }
                ), prompt: Text("Inbox"))
            } header: {
                Text("Schnellerfassung")
            } footer: {
                Text("Das Kürzel funktioniert in jeder App. Notizen mit einem Bereichs-Tag wie #uni landen im Bereich, alle anderen im angegebenen Ordner.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LanguageSection()

            NotificationSettingsSection()

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

/// Sprache der Oberfläche.
private struct LanguageSection: View {
    @State private var selection = AppLanguage.current
    @State private var needsRestart = false

    var body: some View {
        Section {
            Picker("Sprache", selection: $selection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .onChange(of: selection) { _, language in
                language.apply()
                needsRestart = true
            }
            if needsRestart {
                HStack {
                    Label("Die neue Sprache gilt nach einem Neustart von Organizer.", systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Jetzt neu starten") { AppLanguage.relaunch() }
                        .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text("Sprache")
        } footer: {
            Text("Betrifft nur die Oberfläche. Dateien im Vault (z. B. „bereich:“, „Tasks.md“) bleiben unverändert, damit sie in jeder Sprache lesbar bleiben.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Menüleisten-Symbol und Erinnerungen.
private struct NotificationSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
    @State private var loginError: String?

    var body: some View {
        Section {
            Toggle("Beim Anmelden im Hintergrund starten", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    do {
                        try LaunchAtLogin.set(enabled)
                        loginError = nil
                    } catch {
                        loginError = localizedMessage(error)
                    }
                    launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
                }
            ))
            .help("Organizer lädt Vault und Kalender schon beim Hochfahren des Macs und ist dann sofort da.")
            if LaunchAtLogin.needsApproval {
                Text("Bitte unter Systemeinstellungen › Allgemein › Anmeldeobjekte erlauben.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let loginError {
                Label(loginError, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
            }
            Toggle("Symbol in der Menüleiste", isOn: Binding(
                get: { model.settings.settings.showsMenuBarIcon },
                set: { shown in model.settings.update { $0.showsMenuBarIcon = shown } }
            ))
            Toggle("An fällige Aufgaben und Meilensteine erinnern", isOn: Binding(
                get: { model.settings.settings.notifiesDueItems },
                set: { enabled in
                    model.settings.update { $0.notifiesDueItems = enabled }
                    Task {
                        if enabled { _ = await model.notifications.requestAuthorization() }
                        authorization = model.notifications.authorization
                        model.notifications.scheduleUpdate()
                    }
                }
            ))
            if model.settings.settings.notifiesDueItems {
                DatePicker("Uhrzeit", selection: Binding(
                    get: { Calendar.current.date(byAdding: .minute, value: model.settings.settings.notificationMinutes,
                                                 to: Calendar.current.startOfDay(for: .now))! },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        model.settings.update { $0.notificationMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0) }
                        model.notifications.scheduleUpdate()
                    }
                ), displayedComponents: .hourAndMinute)
                if authorization == .denied {
                    HStack {
                        Label("Mitteilungen sind für Organizer ausgeschaltet.", systemImage: "bell.slash")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Systemeinstellungen öffnen") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
            }
        } header: {
            Text("Menüleiste und Mitteilungen")
        } footer: {
            Text("Erinnert am Fälligkeitstag zur gewählten Uhrzeit. In der Mitteilung kannst du die Aufgabe direkt abhaken.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .task {
            await model.notifications.refreshAuthorization()
            authorization = model.notifications.authorization
        }
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
