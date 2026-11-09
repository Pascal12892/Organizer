import AppKit
import OrganizerCore
import SwiftUI

/// Anleitung, wie Claude (über dein Abo) per MCP auf Organizer zugreift.
struct ClaudeSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var copied: String?

    var body: some View {
        Form {
            Section {
                Text("Claude nutzt Organizer über MCP: Du chattest in der Claude-App oder in Claude Code – über dein Claude-Abo, ohne API-Schlüssel – und Claude kann Notizen suchen und anlegen, Aufgaben anlegen und abhaken sowie Termine ansehen und anlegen. Organizer zeigt Änderungen sofort an.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Claude fragt vor jeder Aktion um Erlaubnis. Organizer selbst bleibt dabei offline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("1. Programm installieren") {
                Text("Einmalig im Terminal, im Projektordner von Organizer:")
                    .font(.callout)
                CommandRow(command: "Scripts/install-mcp.sh", copied: $copied)
                Text("Legt das Programm unter \(binaryPath) ab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let vault = vaultPath {
                Section("2. Mit Claude verbinden") {
                    LabeledContent("Claude Code") {
                        Text("im Terminal ausführen").foregroundStyle(.secondary)
                    }
                    CommandRow(command: claudeCodeCommand(vault: vault), copied: $copied)

                    LabeledContent("Claude Desktop") {
                        Text("Einstellungen › Entwickler › Konfiguration bearbeiten").foregroundStyle(.secondary)
                    }
                    CommandRow(command: desktopConfig(vault: vault), copied: $copied)
                    Text("Den Eintrag „organizer“ in „mcpServers“ der Datei claude_desktop_config.json einfügen und Claude neu starten.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("2. Mit Claude verbinden") {
                    Label("Wähle zuerst einen Vault aus – die Befehle enthalten seinen Pfad.", systemImage: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Gut zu wissen") {
                Label("Für Termine braucht die App, in der Claude läuft, Zugriff auf deinen Kalender. macOS fragt beim ersten Mal nach.", systemImage: "calendar")
                Label("Änderungen von Claude lassen sich nicht mit ⌘Z in Organizer zurücknehmen – sie stehen aber zeilengenau in den Markdown-Dateien und lassen sich dort oder über den Dateiverlauf von Obsidian rückgängig machen.", systemImage: "arrow.uturn.backward")
                Label("Die Einstellungen „Bereiche“ und „Aufgaben“ von Organizer werden als Optionen übergeben. Nach einer Änderung dort den Befehl bitte neu ausführen.", systemImage: "gearshape")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: - Pfade und Befehle

    /// Echtes Benutzerverzeichnis (in der Sandbox zeigt `NSHomeDirectory()` auf den Container).
    private var realHome: String {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: dir)
    }

    private var binaryPath: String { realHome + "/.local/bin/organizer-mcp" }

    private var vaultPath: String? {
        guard let url = model.vault.rootURL else { return nil }
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private var extraArguments: [String] {
        var arguments: [String] = []
        let settings = model.settings.settings
        if !settings.automaticAreas { arguments += ["--areas", settings.areas.joined(separator: ",")] }
        if settings.taskStorage == .perFolder { arguments += ["--tasks", "folder"] }
        return arguments
    }

    private func claudeCodeCommand(vault: String) -> String {
        let arguments = (["--vault", vault] + extraArguments).map(shellQuoted).joined(separator: " ")
        return "claude mcp add --scope user organizer -- \(shellQuoted(binaryPath)) \(arguments)"
    }

    private func desktopConfig(vault: String) -> String {
        let arguments = (["--vault", vault] + extraArguments).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return """
        "organizer": {
          "command": "\(binaryPath)",
          "args": [\(arguments.joined(separator: ", "))]
        }
        """
    }

    private func shellQuoted(_ value: String) -> String {
        value.allSatisfy { $0.isLetter || $0.isNumber || "/._-,~".contains($0) } ? value : "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Befehl in Monospace mit Kopieren-Knopf.
private struct CommandRow: View {
    let command: String
    @Binding var copied: String?

    var body: some View {
        HStack(alignment: .top) {
            Text(command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = command
            } label: {
                Image(systemName: copied == command ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Kopieren")
            .accessibilityLabel("Befehl kopieren")
        }
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#Preview("Hell") {
    ClaudeSettingsView()
        .environment(PreviewData.model())
        .frame(width: 560, height: 640)
}

#Preview("Dunkel") {
    ClaudeSettingsView()
        .environment(PreviewData.model())
        .frame(width: 560, height: 640)
        .preferredColorScheme(.dark)
}
