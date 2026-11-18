import SwiftUI

@main
struct OrganizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Organizer", id: "main") {
            RootView()
                .environment(model)
                // Erinnerungen neu planen, sobald sich Aufgaben oder Meilensteine ändern.
                .onChange(of: model.vault.version) {
                    model.notifications.scheduleUpdate()
                    model.publishWidgetSnapshot()
                    model.reminders.scheduleSync()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.reminders.scheduleSync()
                }
                .onChange(of: model.calendar.revision) { model.publishWidgetSnapshot() }
                .onOpenURL { model.handle($0) }

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

        MenuBarExtra(isInserted: Binding(
            get: { model.settings.settings.showsMenuBarIcon },
            set: { shown in model.settings.update { $0.showsMenuBarIcon = shown } }
        )) {
            MenuBarView()
                .environment(model)
        } label: {
            Image(L("MenuBarIcon"))
                .accessibilityLabel("Organizer")
        }
        .menuBarExtraStyle(.window)
    }
}
