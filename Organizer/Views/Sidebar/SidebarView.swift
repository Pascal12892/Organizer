import OrganizerCore
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let counts = model.vault.index.folderNoteCounts

        List(selection: $model.sidebarSelection) {
            Section {
                ForEach(SidebarItem.sections, id: \.self) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .badge(badge(for: item))
                        .tag(item)
                }
            }

            if !model.folderTree.isEmpty {
                Section(model.settings.settings.automaticAreas ? "Ordner" : "Bereiche") {
                    ForEach(visibleTopLevel) { node in
                        FolderRow(node: node, counts: counts)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(model.vault.vaultName ?? "Organizer")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VaultStatusView()
        }
    }

    /// Notizen: Anzahl. Aufgaben: heute fällig plus überfällig, rot sobald etwas überfällig ist.
    private func badge(for item: SidebarItem) -> Text? {
        switch item {
        case .notes:
            return model.vault.notes.isEmpty ? nil : Text("\(model.vault.notes.count)")
        case .tasks:
            let counts = model.tasks.counts
            let due = counts.dueToday + counts.overdue
            guard due > 0 else { return nil }
            return Text("\(due)").foregroundStyle(counts.overdue > 0 ? .red : .secondary)
        default:
            return nil
        }
    }

    /// Im manuellen Modus nur die konfigurierten Bereiche, sonst der ganze Vault.
    private var visibleTopLevel: [FolderNode] {
        let layout = model.settings.layout
        guard !layout.automaticAreas else { return model.folderTree }
        return model.folderTree.filter { layout.area(forFolder: $0.path) != nil }
    }

}

/// Ein Ordner mit seinen Unterordnern, beliebig tief.
private struct FolderRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let node: FolderNode
    let counts: [String: Int]

    var body: some View {
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: expansion) {
                ForEach(node.children) { child in
                    FolderRow(node: child, counts: counts)
                }
            } label: {
                label
            }
        }
    }

    @State private var isDropTarget = false

    private var label: some View {
        let item = SidebarItem.folder(node.path)
        return Label(node.name, systemImage: item.systemImage)
            .badge(counts[node.path] ?? 0)
            .tag(item)
            .listRowBackground(isDropTarget ? RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.25)).padding(.horizontal, 6) : nil)
            .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $isDropTarget) { providers in
                handleDrop(providers)
            }
            .help("Notizen hierher ziehen zum Verschieben, Ordner aus dem Finder zum Verknüpfen")
            .contextMenu {
                Button("Neue Notiz in „\(node.name)“ …") {
                    model.sidebarSelection = item
                    model.isShowingNewNote = true
                }
                Button("Neuer Unterordner …") { model.newFolderParent = node.path }
                Button("Mac-Ordner verknüpfen …") {
                    model.sidebarSelection = item
                    model.folderLinks.chooseAndLink(to: node.path, undoManager: undoManager)
                }
                Divider()
                if let root = model.vault.rootURL {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([root.appending(path: node.path, directoryHint: .isDirectory)])
                    }
                }
            }
    }

    /// Notizen aus der Liste werden verschoben, Ordner aus dem Finder verknüpft.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        let target = node.path
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        if isDirectory {
                            model.folderLinks.link([url], to: target, undoManager: undoManager)
                        } else {
                            model.writeError = "„\(url.lastPathComponent)“ ist kein Ordner. Verknüpfen lassen sich nur Ordner."
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let path = string.flatMap(DragPayload.notePath(from:)) else { return }
                    Task { @MainActor in model.moveNote(path, toFolder: target, undoManager: undoManager) }
                }
            }
        }
        return handled
    }

    private var expansion: Binding<Bool> {
        Binding {
            model.expandedFolders.contains(node.path)
        } set: { expanded in
            if expanded {
                model.expandedFolders.insert(node.path)
            } else {
                model.expandedFolders.remove(node.path)
            }
        }
    }
}

#Preview("Hell") {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Detail")
    }
    .environment(PreviewData.model())
    .frame(width: 700, height: 520)
}

#Preview("Dunkel") {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Detail")
    }
    .environment(PreviewData.model())
    .frame(width: 700, height: 520)
    .preferredColorScheme(.dark)
}
