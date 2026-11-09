import OrganizerCore
import SwiftUI

/// Rechte Spalte: gerenderte Notiz mit ihren Eigenschaften.
struct NoteDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let note: Note
    @State private var content: MarkdownContent?
    @State private var missingLink: String?
    @State private var editor: NoteEditorModel?

    var body: some View {
        Group {
            if model.notes.isEditing, let editor {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    NoteEditorView(editor: editor)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let content {
                            MarkdownView(content: content)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: model.notes.isEditing, initial: true) { _, isEditing in
            if isEditing {
                startEditing()
            } else {
                editor?.saveNow()
                editor = nil
            }
        }
        .onChange(of: note.modified) {
            editor?.fileChangedOnDisk()
        }
        .task(id: note.body) {
            let body = note.body
            let firstLine = note.bodyStartLine
            content = await Task.detached(priority: .userInitiated) { MarkdownContent(markdown: body, firstLine: firstLine) }.value
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let target = WikiLinks.target(from: url) else { return .systemAction }
            if !model.openWikiLink(target) {
                missingLink = WikiLinks.noteName(fromTarget: target)
            }
            return .handled
        })
        .environment(\.toggleCheckbox, CheckboxAction(id: note.relativePath) { line in
            model.tasks.toggleCheckbox(in: note.relativePath, line: line, undoManager: undoManager)
        })
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.notes.isEditing.toggle()
                } label: {
                    Label(model.notes.isEditing ? "Vorschau" : "Bearbeiten",
                          systemImage: model.notes.isEditing ? "eye" : "pencil")
                }
                .help(model.notes.isEditing ? "Vorschau zeigen (⌘E)" : "Notiz bearbeiten (⌘E)")

                Button {
                    model.openInObsidian(note)
                } label: {
                    Label("In Obsidian öffnen", systemImage: "arrow.up.forward.app")
                }
                .help("In Obsidian öffnen (⌥⌘O)")
            }
        }
    }

    private func startEditing() {
        guard editor == nil, let writer = model.writer else { return }
        let editor = NoteEditorModel(relativePath: note.relativePath, writer: writer)
        editor.load()
        self.editor = editor
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.title)
                .font(.largeTitle.weight(.bold))
                .textSelection(.enabled)

            PropertiesView(note: note)

            if let missingLink {
                Label("„\(missingLink)“ gibt es im Vault noch nicht.", systemImage: "link.badge.plus")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            ForEach(note.issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.smooth, value: missingLink)
    }
}

/// Bereich, Thema, Tags und Datum – zurückhaltend unter dem Titel.
private struct PropertiesView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                if let area = note.area {
                    Label(note.topic.map { "\(area) › \($0)" } ?? area,
                          systemImage: SidebarItem.areaSymbol(for: area))
                }
                if let created = note.created {
                    Label {
                        Text(created, format: .dateTime.day().month(.wide).year().hour().minute())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .help("Erstellt")
                }
                Label {
                    Text(note.modified, format: .relative(presentation: .named))
                } icon: {
                    Image(systemName: "clock")
                }
                .help("Zuletzt geändert: \(note.modified.formatted(date: .long, time: .shortened))")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            if !note.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(note.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.callout)
                            .foregroundStyle(.tint)
                    }
                }
                .accessibilityLabel("Tags: \(note.tags.joined(separator: ", "))")
            }
        }
    }
}

#Preview("Hell") {
    NavigationStack {
        NoteDetailView(note: PreviewData.snapshot.notes[0])
    }
    .environment(PreviewData.model())
    .frame(width: 640, height: 720)
}

#Preview("Dunkel") {
    NavigationStack {
        NoteDetailView(note: PreviewData.snapshot.notes[0])
    }
    .environment(PreviewData.model())
    .frame(width: 640, height: 720)
    .preferredColorScheme(.dark)
}
