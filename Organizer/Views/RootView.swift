import OrganizerCore
import SwiftUI

/// Hauptfenster: eine feste Seitenleiste und rechts der gewählte Bereich.
///
/// Bewusst nur *ein* NavigationSplitView: Würde je nach Bereich zwischen zwei- und dreispaltig
/// gewechselt, baut SwiftUI das ganze Fenster samt Seitenleiste neu auf – das ruckelt.
/// Notizen teilen ihren Bereich darum selbst in Liste und Notiz auf (wie Apple Notizen).
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 320)
        } detail: {
            detail
        }
        .sheet(isPresented: Bindable(model).isShowingNewNote) {
            NewNoteSheet()
        }
        .modifier(NewFolderAlert())
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebarSelection {
        case .dashboard: DashboardView()
        case .calendar: CalendarView()
        case .tasks: TasksView()
        case .roadmap: RoadmapView()
        case .notes, .folder:
            if let scope = model.sidebarSelection?.noteScope {
                NotesSplitView(scope: scope)
            }
        case nil:
            ContentUnavailableView("Nichts ausgewählt", systemImage: "sidebar.left")
        }
    }
}

/// Notizliste und Notiz nebeneinander, Breite der Liste veränderbar.
private struct NotesSplitView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool
    let scope: NoteScope

    var body: some View {
        @Bindable var notes = model.notes

        HSplitView {
            listColumn
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)
            noteDetail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .searchable(text: $notes.searchText, placement: .toolbar, prompt: "Suchen")
        .searchFocused($searchFocused)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }

    @ViewBuilder
    private var listColumn: some View {
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
