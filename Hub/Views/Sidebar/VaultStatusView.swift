import HubCore
import SwiftUI

/// Dezente Statuszeile unten in der Seitenleiste (wie in Mail).
/// Zeigt Ladezustand und Lesefehler, bleibt aber leer, wenn alles in Ordnung ist.
struct VaultStatusView: View {
    @Environment(AppModel.self) private var model
    @State private var showsIssues = false

    var body: some View {
        let issues = model.vault.issues
        let settingsError = model.settings.lastError ?? model.writeError

        if model.vault.isScanning || !issues.isEmpty || settingsError != nil {
            HStack(spacing: 8) {
                if let writeError = model.writeError {
                    Label(writeError, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button {
                        model.writeError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Meldung schließen")
                    .accessibilityLabel("Meldung schließen")
                } else if model.vault.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Vault wird gelesen …")
                } else if let settingsError {
                    Label(settingsError, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .lineLimit(2)
                } else {
                    Button {
                        showsIssues = true
                    } label: {
                        Label(issues.count == 1 ? "1 Datei mit Problemen" : "\(issues.count) Dateien mit Problemen",
                              systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                    .buttonStyle(.plain)
                    .help("Probleme beim Lesen des Vaults anzeigen")
                    .popover(isPresented: $showsIssues, arrowEdge: .trailing) {
                        VaultIssuesList(issues: issues)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct VaultIssuesList: View {
    @Environment(AppModel.self) private var model
    let issues: [VaultIssue]

    var body: some View {
        List(issues) { issue in
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.relativePath.isEmpty ? "Vault" : issue.relativePath)
                    .font(.headline)
                Text(issue.message)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contextMenu {
                if let note = model.vault.notes.first(where: { $0.relativePath == issue.relativePath }) {
                    Button("Notiz anzeigen") { model.openWikiLink(note.relativePath) }
                    Button("Im Finder zeigen") { model.revealInFinder([note]) }
                }
            }
        }
        .frame(width: 380, height: 240)
    }
}

#Preview("Hell") {
    VaultStatusView()
        .environment(PreviewData.model())
        .frame(width: 240)
}

#Preview("Dunkel") {
    VaultStatusView()
        .environment(PreviewData.model())
        .frame(width: 240)
        .preferredColorScheme(.dark)
}
