import OrganizerCore
import SwiftUI

/// Neue Notiz: Titel und Ordner. Bereich und Thema ergeben sich aus dem Ordner
/// und landen im Frontmatter. Der Inhalt wird danach direkt im Editor geschrieben.
struct NewNoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var title = ""
    @State private var folder = ""
    @State private var extraProperties: [Frontmatter.Entry] = []
    @State private var linkedTask: TaskItem?
    @State private var errorMessage: String?
    @State private var isCreating = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Titel", text: $title, prompt: Text("Titel der Notiz"))
                    .focused($titleFocused)

                Picker("Ordner", selection: $folder) {
                    Label("Vault (oberste Ebene)", systemImage: "externaldrive").tag("")
                    Divider()
                    ForEach(FolderTree.flatten(model.folderTree)) { node in
                        Text(String(repeating: "    ", count: node.depth) + node.name)
                            .tag(node.path)
                    }
                }

                LabeledContent("Eigenschaften") {
                    Text(propertiesPreview)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Anlegen") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .navigationTitle("Neue Notiz")
        .onAppear {
            folder = model.defaultFolder
            if let prefill = model.newNotePrefill {
                title = prefill.title
                extraProperties = prefill.extraProperties
                if let prefillFolder = prefill.folder { folder = prefillFolder }
                linkedTask = prefill.linkedTask
                model.newNotePrefill = nil
            }
            titleFocused = true
        }
    }

    /// Zeigt, was ins Frontmatter geschrieben wird.
    private var propertiesPreview: String {
        let (area, topic) = model.settings.layout.classify(folder: folder)
        var parts: [String] = switch (area, topic) {
        case let (area?, topic?): [L("Bereich \(area)"), L("Thema \(topic)")]
        case let (area?, nil): [L("Bereich \(area)")]
        default: [L("Kein Bereich")]
        }
        if let event = extraProperties.first(where: { $0.key == "termin" })?.value.stringValue {
            parts.append(L("Termin „\(event)“"))
        }
        if let linkedTask {
            parts.append(L("Verlinkt mit „\(linkedTask.displayTitle)“"))
        }
        return parts.joined(separator: " · ")
    }

    private func create() {
        isCreating = true
        Task {
            do {
                let path = try await model.createNote(
                    title: title.trimmingCharacters(in: .whitespaces),
                    folder: folder,
                    extraProperties: extraProperties,
                    undoManager: undoManager
                )
                // Erst nach dem Anlegen verlinken, damit der Link den tatsächlichen Dateinamen trägt („Titel 2“).
                if let linkedTask, let note = model.vault.notes.first(where: { $0.relativePath == path }) {
                    model.tasks.addLink(linkedTask, target: WikiLinks.linkTarget(for: note, in: model.vault.notes),
                                        undoManager: undoManager)
                }
                dismiss()
            } catch {
                errorMessage = localizedMessage(error)
                isCreating = false
            }
        }
    }
}

#Preview("Hell") {
    NewNoteSheet()
        .environment(PreviewData.model())
}

#Preview("Dunkel") {
    NewNoteSheet()
        .environment(PreviewData.model())
        .preferredColorScheme(.dark)
}
