import HubCore
import SwiftUI

/// Bereiche verwalten. Ein Bereich entspricht einem Ordner auf oberster Ebene im Vault.
struct AreasSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Int?
    @FocusState private var focusedRow: Int?

    var body: some View {
        Form {
            Section {
                Toggle("Ordnerstruktur aus Obsidian übernehmen", isOn: Binding(
                    get: { model.settings.settings.automaticAreas },
                    set: { model.setAutomaticAreas($0) }
                ))
            } footer: {
                Text(model.settings.settings.automaticAreas
                     ? "Jeder Ordner auf oberster Ebene ist ein Bereich, seine Unterordner sind die Themen. Die Seitenleiste zeigt alle Ordner wie in Obsidian."
                     : "Nur die unten aufgeführten Ordner sind Bereiche und erscheinen in der Seitenleiste.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !model.settings.settings.automaticAreas {
            Section {
                List(selection: $selection) {
                    ForEach(Array(model.settings.settings.areas.enumerated()), id: \.offset) { index, _ in
                        AreaRow(name: binding(for: index), folderExists: folderExists(at: index))
                            .focused($focusedRow, equals: index)
                            .tag(index)
                    }
                    .onMove { source, destination in
                        var areas = model.settings.settings.areas
                        areas.move(fromOffsets: source, toOffset: destination)
                        model.setAreas(areas)
                    }
                }
                .frame(minHeight: 180)

                HStack(spacing: 0) {
                    Button {
                        addArea()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 20)
                    }
                    .help("Bereich hinzufügen")
                    .accessibilityLabel("Bereich hinzufügen")

                    Button {
                        removeSelected()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 20)
                    }
                    .help("Ausgewählten Bereich entfernen")
                    .accessibilityLabel("Bereich entfernen")
                    .disabled(selection == nil)

                    Spacer()

                    Button("Standard wiederherstellen") {
                        model.setAreas(VaultLayout.defaultAreas)
                    }
                    .disabled(model.settings.settings.areas == VaultLayout.defaultAreas)
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Bereiche")
            } footer: {
                Text("Entfernen ändert nichts im Vault, Hub blendet den Ordner nur aus. Die Reihenfolge bestimmt auch die Sortierung in der Seitenleiste.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding {
            let areas = model.settings.settings.areas
            return areas.indices.contains(index) ? areas[index] : ""
        } set: { newValue in
            var areas = model.settings.settings.areas
            guard areas.indices.contains(index) else { return }
            areas[index] = newValue
            model.setAreas(areas)
        }
    }

    private func folderExists(at index: Int) -> Bool? {
        guard let root = model.vault.rootURL else { return nil }
        let areas = model.settings.settings.areas
        guard areas.indices.contains(index), !areas[index].isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        let path = root.appending(path: areas[index]).path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func addArea() {
        var areas = model.settings.settings.areas
        var name = "Neuer Bereich"
        var counter = 2
        while areas.contains(name) {
            name = "Neuer Bereich \(counter)"
            counter += 1
        }
        areas.append(name)
        model.setAreas(areas)
        selection = areas.count - 1
        focusedRow = areas.count - 1
    }

    private func removeSelected() {
        guard let selection else { return }
        var areas = model.settings.settings.areas
        guard areas.indices.contains(selection) else { return }
        areas.remove(at: selection)
        model.setAreas(areas)
        self.selection = nil
    }
}

private struct AreaRow: View {
    @Binding var name: String
    let folderExists: Bool?

    var body: some View {
        HStack {
            Image(systemName: SidebarItem.areaSymbol(for: name))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
            if folderExists == false {
                Text("Ordner fehlt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Im Vault gibt es noch keinen Ordner mit diesem Namen.")
            }
        }
    }
}

#Preview("Hell") {
    AreasSettingsView()
        .environment(PreviewData.model())
        .frame(width: 520, height: 420)
}

#Preview("Dunkel") {
    AreasSettingsView()
        .environment(PreviewData.model())
        .frame(width: 520, height: 420)
        .preferredColorScheme(.dark)
}
