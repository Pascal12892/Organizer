import SwiftUI

@main
struct HubApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Hub", id: "main") {
            RootView()
                .environment(model)
                .task { await model.restoreVault() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            SidebarCommands()
            HubCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
