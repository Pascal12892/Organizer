import SwiftUI

@main
struct OrganizerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Organizer", id: "main") {
            RootView()
                .environment(model)
                .task { await model.restoreVault() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            SidebarCommands()
            OrganizerCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
