import AppKit

/// Sprache der App: folgt dem System oder ist fest eingestellt.
/// Gespeichert wird die Wahl wie bei jeder Mac-App über „AppleLanguages“ – nur für Organizer.
/// Arabisch dreht die Oberfläche automatisch auf rechts-nach-links.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case german = "de"
    case english = "en"
    case arabic = "ar"

    var id: String { rawValue }

    /// Name in der jeweiligen Sprache selbst, damit man ihn immer findet.
    var displayName: String {
        switch self {
        case .system: L("Systemsprache")
        case .german: "Deutsch"
        case .english: "English"
        case .arabic: "العربية"
        }
    }

    static var current: AppLanguage {
        guard let codes = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = codes.first else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// Startet Organizer neu, damit die neue Sprache überall greift.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
