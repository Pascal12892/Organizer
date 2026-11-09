import HubCore
import SwiftUI

/// Hauptfenster. Notizbereiche nutzen drei Spalten (Seitenleiste, Liste, Detail),
/// alle anderen Bereiche zwei – so wie Kalender oder Erinnerungen.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var notes = model.notes

        Group {
            if let scope = model.sidebarSelection?.noteScope {
                NavigationSplitView {
                    sidebar
                } content: {
                    contentColumn(scope: scope)
                        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
                } detail: {
                    noteDetail
                }
                .searchable(text: $notes.searchText, placement: .toolbar, prompt: "Suchen")
                .searchFocused($searchFocused)
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    sectionPlaceholder
                }
            }
        }
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
        }
        .sheet(isPresented: Bindable(model).isShowingNewNote) {
            NewNoteSheet()
        }
        .modifier(NewTopicAlert())
    }

    private var sidebar: some View {
        SidebarView()
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 320)
    }

    @ViewBuilder
    private func contentColumn(scope: NoteScope) -> some View {
        switch model.vault.state {
        case .noVault:
            ChooseVaultView()
        case .accessLost(let path, let message):
            ChooseVaultView(lostPath: path, message: message)
        case .loading:
            ProgressView("Vault wird gelesen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            NoteListView(scope: scope)
        }
    }

    @ViewBuilder
    private var noteDetail: some View {
        if let note = model.notes.selectedNote {
            NoteDetailView(note: note)
                .id(note.id)
        } else if model.vault.state == .ready {
            ContentUnavailableView("Keine Notiz ausgewählt", systemImage: "note.text")
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var sectionPlaceholder: some View {
        if let item = model.sidebarSelection, let phase = item.plannedPhase {
            ContentUnavailableView {
                Label(item.title, systemImage: item.systemImage)
            } description: {
                Text("Dieser Bereich folgt in Phase \(phase).")
            }
            .navigationTitle(item.title)
        } else {
            ContentUnavailableView("Nichts ausgewählt", systemImage: "sidebar.left")
        }
    }
}

#Preview("Hell") {
    RootView()
        .environment(PreviewData.model())
        .frame(width: 1100, height: 680)
}

#Preview("Dunkel") {
    RootView()
        .environment(PreviewData.model())
        .frame(width: 1100, height: 680)
        .preferredColorScheme(.dark)
}

#Preview("Ohne Vault") {
    RootView()
        .environment(PreviewData.model(withVault: false))
        .frame(width: 1100, height: 680)
}
