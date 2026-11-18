import OrganizerCore
import SwiftUI

/// Dezente Statuszeile unten in der Seitenleiste (wie in Mail).
/// Zeigt Ladezustand und Lesefehler, bleibt aber leer, wenn alles in Ordnung ist.
struct VaultStatusView: View {
    @Environment(AppModel.self) private var model
    @State private var showsIssues = false

    var body: some View {
        let issues = model.vault.issues
        let settingsError = model.settings.lastError ?? model.writeError ?? model.tasks.lastError ?? model.folderLinks.lastError ?? model.roadmap.lastError

        let isHuge = model.vault.snapshot.entryCount > VaultScanner.largeFolderThreshold

        if model.vault.isSlowScan || !issues.isEmpty || settingsError != nil || isHuge {
            HStack(spacing: 8) {
                if let writeError = model.writeError ?? model.tasks.lastError ?? model.folderLinks.lastError ?? model.roadmap.lastError {
                    Label(writeError, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button {
                        model.writeError = nil
                        model.tasks.lastError = nil
                        model.folderLinks.lastError = nil
                        model.roadmap.lastError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Meldung schließen")
                    .accessibilityLabel("Meldung schließen")
                } else if model.vault.isSlowScan {
                    ProgressView()
                        .controlSize(.small)
                    // Mit Zwischenspeicher sind die Notizen schon da – dann wird nur abgeglichen.
                    Text(model.vault.notes.isEmpty ? L("Vault wird gelesen …") : L("Wird aktualisiert …"))
                } else if isHuge {
                    LargeFolderHint(entryCount: model.vault.snapshot.entryCount)
                } else if let settingsError {
                    Label(settingsError, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .lineLimit(2)
                } else {
                    Button {
                        showsIssues = true
                    } label: {
                        Label(issues.count == 1 ? L("1 Datei mit Problemen") : L("\(issues.count) Dateien mit Problemen"),
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

/// Nur die Schildkröte; der Hinweis erscheint beim Darüberfahren (oder per Klick).
private struct LargeFolderHint: View {
    let entryCount: Int
    @State private var showsText = false
    @State private var hoverTask: Task<Void, Never>?

    private var text: String {
        L("Dieser Ordner enthält \(entryCount) Dateien. Ist das wirklich dein Vault? Ein kleinerer Ordner lädt viel schneller.")
    }

    var body: some View {
        Button {
            showsText.toggle()
        } label: {
            Image(systemName: "tortoise")
                .font(.body)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoverTask?.cancel()
            // Kurz verzögert öffnen, sofort beim Verlassen schließen – flackert nicht beim Vorbeifahren.
            hoverTask = Task {
                if inside { try? await Task.sleep(for: .milliseconds(250)) }
                guard !Task.isCancelled else { return }
                showsText = inside
            }
        }
        .popover(isPresented: $showsText, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Anderen Ordner wählen: Ablage › Vault öffnen … (⇧⌘O)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 260, alignment: .leading)
        }
        .accessibilityLabel(text)
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
