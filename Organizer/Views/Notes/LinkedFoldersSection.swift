import AppKit
import OrganizerCore
import QuickLook
import SwiftUI

/// Abschnitt „Auf dem Mac“ über den Notizen eines Themas: verknüpfte Ordner mit ihren Dateien.
struct LinkedFoldersSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let folder: String
    @State private var collapsed: Set<String> = []

    var body: some View {
        let folders = model.folderLinks.linkedFolders(for: folder)
        if !folders.isEmpty {
            Section("Auf dem Mac") {
                ForEach(folders) { linked in
                    DisclosureGroup(isExpanded: expansion(for: linked.path)) {
                        content(for: linked)
                    } label: {
                        header(for: linked)
                    }
                }
            }
            .task(id: folders.map(\.path)) { model.folderLinks.refresh(folder: folder) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.folderLinks.refresh(folder: folder)
            }
        }
    }

    private func header(for linked: LinkedFolder) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(linked.name)
                Text(linked.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if case .available = linked.status {
                Button {
                    reveal(URL(filePath: linked.path, directoryHint: .isDirectory))
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Im Finder öffnen")
                .accessibilityLabel("\(linked.name) im Finder öffnen")
            }
        }
        .contextMenu {
            Button("Im Finder zeigen") { reveal(URL(filePath: linked.path, directoryHint: .isDirectory)) }
            Button("Pfad kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(linked.path, forType: .string)
            }
            Divider()
            Button("Verknüpfung entfernen") {
                model.folderLinks.unlink(linked.path, from: folder, undoManager: undoManager)
            }
        }
    }

    @ViewBuilder
    private func content(for linked: LinkedFolder) -> some View {
        switch linked.status {
        case .available(let files, let total):
            if files.isEmpty {
                Text("Der Ordner ist leer.")
                    .foregroundStyle(.secondary)
            }
            ForEach(files) { file in
                FileRow(file: file)
            }
            if total > files.count {
                Button("\(total - files.count) weitere im Finder zeigen …") {
                    reveal(URL(filePath: linked.path, directoryHint: .isDirectory))
                }
                .buttonStyle(.link)
            }
        case .needsAccess:
            HStack {
                Text("Organizer braucht einmal deine Erlaubnis, diesen Ordner zu lesen.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Zugriff erlauben …") { model.folderLinks.grantAccess(to: linked.path) }
            }
        case .missing:
            HStack {
                Label("Ordner nicht gefunden – verschoben oder gelöscht?", systemImage: "questionmark.folder")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Verknüpfung entfernen") { model.folderLinks.unlink(linked.path, from: folder, undoManager: undoManager) }
            }
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Zugriff erlauben …") { model.folderLinks.grantAccess(to: linked.path) }
            }
        }
    }

    private func expansion(for path: String) -> Binding<Bool> {
        Binding {
            !collapsed.contains(path)
        } set: { expanded in
            if expanded { collapsed.remove(path) } else { collapsed.insert(path) }
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Eine Datei: Symbol aus dem Finder, Name, Änderungsdatum. Doppelklick öffnet sie.
private struct FileRow: View {
    let file: LinkedFile
    @State private var quickLookURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(file.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let modified = file.modified {
                Text(modified, format: NoteRow.dateStyle(for: modified))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
        .quickLookPreview($quickLookURL)
        .contextMenu {
            Button("Öffnen") { NSWorkspace.shared.open(file.url) }
            Button("Übersicht") { quickLookURL = file.url }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
        .help(file.isDirectory ? "Doppelklick öffnet den Ordner im Finder" : "Doppelklick öffnet die Datei")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { NSWorkspace.shared.open(file.url) }
    }
}
