import SwiftUI

/// Kleiner Dialog für ein neues Thema (legt einen Ordner im Bereich an).
struct NewTopicAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert(
            "Neues Thema in „\(model.newTopicArea ?? "")“",
            isPresented: Binding(
                get: { model.newTopicArea != nil },
                set: { if !$0 { model.newTopicArea = nil } }
            )
        ) {
            TextField("Name", text: $name)
            Button("Anlegen") { create() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Abbrechen", role: .cancel) { name = "" }
        } message: {
            Text("Hub legt dafür einen Ordner im Vault an.")
        }
    }

    private func create() {
        guard let area = model.newTopicArea else { return }
        let topicName = name
        name = ""
        Task {
            do {
                try await model.createTopic(named: topicName, in: area, undoManager: undoManager)
            } catch {
                model.writeError = "Thema konnte nicht angelegt werden: \(error.localizedDescription)"
            }
        }
    }
}
