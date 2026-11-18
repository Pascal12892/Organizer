import AppKit
import ServiceManagement

/// Startet Vault, Kalender und Tastenkürzel gleich beim App-Start – unabhängig davon, ob ein Fenster offen ist.
/// Wird Organizer beim Anmelden gestartet, bleibt das Fenster zu: Die App lädt still im Hintergrund
/// und ist in der Menüleiste erreichbar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        if launchedAsLoginItem {
            DispatchQueue.main.async {
                NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }.forEach { $0.close() }
            }
        }
    }
}

/// Beim Anmelden starten – über die Systemverwaltung für Anmeldeobjekte.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
