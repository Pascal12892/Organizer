import HubCore
import SwiftUI

/// Neue Notiz: Titel, Bereich und Thema. Der Inhalt wird danach direkt im Editor geschrieben.
struct NewNoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var title = ""
    @State private var area: String?
    @State private var topic: String?
    @State private var newTopicName = ""
    @State private var errorMessage: String?
    @State private var isCreating = false
    @FocusState private var titleFocused: Bool

    /// Platzhalter-Tag für „Neues Thema …“ im Picker.
    private static let newTopicTag = "\u{0}neu"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Titel", text: $title, prompt: Text("Titel der Notiz"))
                    .focused($titleFocused)

                Picker("Bereich", selection: $area) {
                    Text("Kein Bereich").tag(String?.none)
                    Divider()
                    ForEach(model.areas, id: \.self) { area in
                        Label(area, systemImage: SidebarItem.areaSymbol(for: area)).tag(String?.some(area))
                    }
                }

                if let area {
                    Picker("Thema", selection: $topic) {
                        Text("Kein Thema").tag(String?.none)
                        let topics = model.vault.snapshot.topics(in: area)
                        if !topics.isEmpty { Divider() }
                        ForEach(topics) { topic in
                            Text(topic.name).tag(String?.some(topic.name))
                        }
                        Divider()
                        Text("Neues Thema …").tag(String?.some(Self.newTopicTag))
                    }
                    if topic == Self.newTopicTag {
                        TextField("Neues Thema", text: $newTopicName, prompt: Text("Name des Themas"))
                    }
                }

                LabeledContent("Speicherort") {
                    Text(locationPreview)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
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
                    .disabled(!canCreate || isCreating)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .navigationTitle("Neue Notiz")
        .onAppear {
            let location = model.defaultLocation
            area = location.area
            topic = location.topic
            titleFocused = true
        }
        .onChange(of: area) { oldValue, _ in
            if oldValue != nil { topic = nil }
        }
    }

    private var resolvedTopic: String? {
        guard topic == Self.newTopicTag else { return topic }
        let name = newTopicName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : NoteTemplate.fileName(for: name)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (topic != Self.newTopicTag || resolvedTopic != nil)
    }

    private var locationPreview: String {
        let folder = [area, area == nil ? nil : resolvedTopic].compactMap { $0 }.joined(separator: "/")
        let file = NoteTemplate.fileName(for: title.isEmpty ? "Titel" : title) + ".md"
        return folder.isEmpty ? file : "\(folder)/\(file)"
    }

    private func create() {
        guard canCreate else { return }
        isCreating = true
        Task {
            do {
                try await model.createNote(
                    title: title.trimmingCharacters(in: .whitespaces),
                    area: area,
                    topic: area == nil ? nil : resolvedTopic,
                    undoManager: undoManager
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
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
