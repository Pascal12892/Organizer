import OrganizerCore
import SwiftUI

/// Hauptfenster: eine feste Seitenleiste und rechts der gewählte Bereich.
///
/// Bewusst nur *ein* NavigationSplitView: Würde je nach Bereich zwischen zwei- und dreispaltig
/// gewechselt, baut SwiftUI das ganze Fenster samt Seitenleiste neu auf – das ruckelt.
/// Notizen teilen ihren Bereich darum selbst in Liste und Notiz auf (wie Apple Notizen).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var globalSearchFocused: Bool

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
        if let scope = model.sidebarSelection?.noteScope {
            NotesSplitView(scope: scope)
        } else {
            @Bindable var search = model.search
            Group {
                if !search.query.isEmpty {
                    SearchResultsView(query: search.query)
                } else {
                    section
                }
            }
            .searchable(text: $search.text, placement: .toolbar, prompt: L("Termine, Aufgaben, Notizen"))
            .searchFocused($globalSearchFocused)
            .onChange(of: model.searchFocusRequest) { globalSearchFocused = true }
        }
    }

    @ViewBuilder
    private var section: some View {
        switch model.sidebarSelection {
        case .dashboard: DashboardView()
        case .calendar: CalendarView()
        case .tasks: TasksView()
        case .roadmap: RoadmapView()
        case .notes, .folder, nil:
            ContentUnavailableView("Nichts ausgewählt", systemImage: "sidebar.left")
        }
    }
}

/// Notizliste und Notiz nebeneinander. Die Breite der Liste lässt sich ziehen und wird gespeichert.
private struct NotesSplitView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool
    @AppStorage("noteListWidth") private var listWidth: Double = 320
    @State private var dragStartWidth: Double?
    let scope: NoteScope

    var body: some View {
        @Bindable var notes = model.notes

        HStack(spacing: 0) {
            listColumn
                .frame(width: listWidth)
            divider
            noteDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $notes.searchText, placement: .toolbar, prompt: L("Notizen durchsuchen"))
        .searchFocused($searchFocused)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }

    /// Schmale Trennlinie mit breiter Griff-Fläche, wie bei NSSplitView.
    private var divider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let start = dragStartWidth ?? listWidth
                                dragStartWidth = start
                                listWidth = min(max(start + value.translation.width, 240), 520)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
            .accessibilityHidden(true)
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
