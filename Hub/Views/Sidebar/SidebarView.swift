import HubCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let counts = noteCounts()

        List(selection: $model.sidebarSelection) {
            Section {
                ForEach(SidebarItem.sections, id: \.self) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .badge(item == .notes ? counts[item] ?? 0 : 0)
                        .tag(item)
                }
            }

            Section("Bereiche") {
                ForEach(model.areas, id: \.self) { area in
                    DisclosureGroup(isExpanded: expansion(for: area)) {
                        ForEach(model.vault.snapshot.topics(in: area)) { topic in
                            let item = SidebarItem.topic(area: area, name: topic.name)
                            Label(topic.name, systemImage: item.systemImage)
                                .badge(counts[item] ?? 0)
                                .tag(item)
                        }
                    } label: {
                        let item = SidebarItem.area(area)
                        Label(area, systemImage: item.systemImage)
                            .badge(counts[item] ?? 0)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(model.vault.vaultName ?? "Hub")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VaultStatusView()
        }
    }

    private func expansion(for area: String) -> Binding<Bool> {
        Binding {
            model.expandedAreas.contains(area)
        } set: { expanded in
            if expanded {
                model.expandedAreas.insert(area)
            } else {
                model.expandedAreas.remove(area)
            }
        }
    }

    /// Zählt alle Notizen in einem Durchlauf statt pro Eintrag.
    private func noteCounts() -> [SidebarItem: Int] {
        var counts: [SidebarItem: Int] = [.notes: model.vault.notes.count]
        for note in model.vault.notes {
            guard let area = note.area else { continue }
            counts[.area(area), default: 0] += 1
            if let topic = note.topic {
                counts[.topic(area: area, name: topic), default: 0] += 1
            }
        }
        return counts
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
