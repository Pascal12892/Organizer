import Foundation
import OrganizerCore
import Observation

/// Zugriff auf den Obsidian-Vault: Öffnen, Einlesen, Beobachten.
/// In Phase 1 ausschließlich lesend.
@Observable
final class VaultService {
    enum State: Equatable {
        /// Noch kein Vault gewählt.
        case noVault
        /// Ein Vault ist gespeichert, aber der Zugriff ging verloren.
        case accessLost(path: String?, message: String)
        case loading
        case ready
    }

    private(set) var state: State = .noVault
    private(set) var rootURL: URL?
    private(set) var snapshot: VaultSnapshot = .empty
    /// Abgeleitete Daten zum aktuellen Stand (Zähler, Roadmap).
    private(set) var index: VaultIndex = .empty
    /// Wird mit jedem neuen Stand erhöht – Schlüssel für Zwischenspeicher in den Views.
    private(set) var version = 0
    /// `true` während ein Scan läuft – auch wenn bereits Daten angezeigt werden.
    private(set) var isScanning = false
    /// `true`, wenn ein Scan länger als eine halbe Sekunde dauert. Nur dann zeigt die
    /// Seitenleiste einen Hinweis – sonst würde sie bei jeder kleinen Änderung kurz springen.
    private(set) var isSlowScan = false
    private(set) var lastScan: Date?

    private var layout: VaultLayout
    private var watcher: VaultWatcher?
    private var isAccessingScope = false
    private var rescanTask: Task<Void, Never>?
    private var scanGeneration = 0
    /// Layout, mit dem `snapshot` erstellt wurde (nur dann dürfen Notizen wiederverwendet werden).
    private var scannedLayout: VaultLayout?

    init(layout: VaultLayout = VaultLayout()) {
        self.layout = layout
    }

    /// Für Previews: ein fertiger Vault ohne Dateizugriff.
    static func preview(_ snapshot: VaultSnapshot, name: String = "Vault") -> VaultService {
        let service = VaultService()
        service.snapshot = snapshot
        service.index = VaultIndex(snapshot: snapshot)
        service.rootURL = URL(filePath: "/Users/vorschau/\(name)", directoryHint: .isDirectory)
        service.state = .ready
        return service
    }

    var vaultName: String? { rootURL?.lastPathComponent }
    var notes: [Note] { snapshot.notes }
    var issues: [VaultIssue] { snapshot.issues }

    /// Öffnet einen Vault. `url` muss bereits per Bookmark oder NSOpenPanel freigegeben sein.
    func open(_ url: URL) async {
        close()
        isAccessingScope = url.startAccessingSecurityScopedResource()
        rootURL = url
        state = .loading

        let watcher = VaultWatcher(url: url) { [weak self] paths in
            Task { @MainActor in self?.handleFileEvents(paths) }
        }
        watcher.start()
        self.watcher = watcher

        // Letzten Stand sofort zeigen – das eigentliche Einlesen läuft danach im Hintergrund
        // und liest nur Dateien neu, die sich seitdem geändert haben.
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let layout = layout
        let cached = await Task.detached(priority: .userInitiated) { () -> (VaultSnapshot, VaultIndex)? in
            guard let cache = VaultCache.load(from: VaultService.cacheURL), cache.matches(vaultPath: path, layout: layout) else { return nil }
            let snapshot = cache.snapshot
            return (snapshot, VaultIndex(snapshot: snapshot))
        }.value
        if let (snapshot, index) = cached, rootURL == url {
            self.snapshot = snapshot
            self.index = index
            scannedLayout = layout
            version += 1
            state = .ready
        }

        await rescan()
    }

    /// Ort des Zwischenspeichers (im Container der App).
    nonisolated static var cacheURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Organizer", directoryHint: .isDirectory)
            .appending(path: "vault-cache.plist")
    }

    func markAccessLost(path: String?, message: String) {
        close()
        state = .accessLost(path: path, message: message)
    }

    func close() {
        watcher?.stop()
        watcher = nil
        rescanTask?.cancel()
        if isAccessingScope, let rootURL {
            rootURL.stopAccessingSecurityScopedResource()
        }
        isAccessingScope = false
        isScanning = false
        rootURL = nil
        snapshot = .empty
        index = .empty
        scannedLayout = nil
        version += 1
        state = .noVault
    }

    func updateLayout(_ layout: VaultLayout) {
        guard layout != self.layout else { return }
        self.layout = layout
        scheduleRescan()
    }

    /// Liest den gesamten Vault neu ein (im Hintergrund).
    func rescan() async {
        guard let rootURL else { return }
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if isScanning, generation == scanGeneration { isSlowScan = true }
        }
        let layout = layout
        // Unveränderte Dateien aus dem letzten Stand übernehmen, statt alles neu zu lesen.
        let previous = scannedLayout == layout
            ? Dictionary(snapshot.notes.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
            : [:]
        let (snapshot, index) = await Task.detached(priority: .userInitiated) {
            let snapshot = VaultScanner.scan(root: rootURL, layout: layout, previous: previous)
            return (snapshot, VaultIndex(snapshot: snapshot))
        }.value

        // Ein neuerer Scan oder ein Vault-Wechsel hat dieses Ergebnis überholt.
        guard generation == scanGeneration, rootURL == self.rootURL else { return }
        self.snapshot = snapshot
        self.index = index
        scannedLayout = layout
        version += 1
        isScanning = false
        isSlowScan = false
        lastScan = .now
        state = .ready

        // Stand für den nächsten Start sichern (im Hintergrund, Fehler sind hier unkritisch).
        let cache = VaultCache(vaultPath: rootURL.standardizedFileURL.path(percentEncoded: false), layout: layout, snapshot: snapshot)
        Task.detached(priority: .utility) { try? cache.save(to: VaultService.cacheURL) }
    }

    /// Fasst schnell aufeinanderfolgende Änderungen (z. B. Tippen in Obsidian) zusammen.
    func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await rescan()
        }
    }

    private func handleFileEvents(_ paths: [String]) {
        guard let rootURL else { return }
        let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let relevant = paths.contains { path in
            let relative = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
            // Änderungen in .obsidian (Workspace, Plugins) betreffen die Notizen nicht.
            return !relative.split(separator: "/").contains { VaultLayout.isHidden($0) }
        }
        if relevant { scheduleRescan() }
    }
}
