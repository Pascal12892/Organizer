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
    /// Von der App selbst geschriebene Pfade – deren Dateiereignisse lösen keinen weiteren Scan aus.
    private var recentlyWritten: [String: Date] = [:]

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

    /// Liest nach einer eigenen Änderung nur die betroffenen Dateien neu – der neue Stand ist
    /// damit sofort sichtbar, auch in großen Vaults. `paths` sind relativ zum Vault.
    func refresh(paths: [String]) async {
        guard let rootURL, !paths.isEmpty else { return }
        let now = Date.now
        for path in paths { recentlyWritten[path] = now }
        await applyUpdate(paths: paths, root: rootURL)
    }

    /// Wendet ein gezieltes Update an. Ein laufender Vollscan wird verworfen (er kennt die
    /// Änderung womöglich noch nicht) und danach still im Hintergrund wiederholt.
    private func applyUpdate(paths: [String], root: URL) async {
        let interruptedScan = isScanning
        scanGeneration += 1
        let generation = scanGeneration
        let layout = layout
        let current = snapshot
        guard scannedLayout == layout else { await rescan(); return }
        let (snapshot, index) = await Task.detached(priority: .userInitiated) {
            let snapshot = VaultScanner.updating(current, root: root, changedPaths: paths, layout: layout)
            return (snapshot, VaultIndex(snapshot: snapshot))
        }.value
        guard generation == scanGeneration, root == rootURL else { return }
        self.snapshot = snapshot
        self.index = index
        version += 1
        isScanning = false
        isSlowScan = false
        saveCache()
        if interruptedScan { scheduleRescan(delay: .seconds(1)) }
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

        saveCache()
    }

    /// Stand für den nächsten Start sichern (im Hintergrund, Fehler sind hier unkritisch).
    private func saveCache() {
        guard let rootURL else { return }
        let cache = VaultCache(vaultPath: rootURL.standardizedFileURL.path(percentEncoded: false), layout: layout, snapshot: snapshot)
        Task.detached(priority: .utility) { try? cache.save(to: VaultService.cacheURL) }
    }

    /// Fasst schnell aufeinanderfolgende Änderungen (z. B. Tippen in Obsidian) zusammen.
    func scheduleRescan(delay: Duration = .milliseconds(300)) {
        rescanTask?.cancel()
        rescanTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await rescan()
        }
    }

    private func handleFileEvents(_ paths: [String]) {
        guard let rootURL else { return }
        let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        // Änderungen in .obsidian (Workspace, Plugins) betreffen die Notizen nicht.
        // Pfade außerhalb des erwarteten Präfixes (z. B. über Symlinks): sicherheitshalber alles neu.
        guard paths.allSatisfy({ $0.hasPrefix(prefix) || $0 == rootPath }) else { scheduleRescan(); return }
        let relevant = Set(paths.compactMap { path -> String? in
            guard path.hasPrefix(prefix) else { return nil }
            let relative = String(path.dropFirst(prefix.count))
            return relative.isEmpty || relative.split(separator: "/").contains(where: { VaultLayout.isHidden($0) }) ? nil : relative
        })
        // Eigene Änderungen sind bereits eingelesen.
        let cutoff = Date.now.addingTimeInterval(-3)
        recentlyWritten = recentlyWritten.filter { $0.value > cutoff }
        let foreign = relevant.filter { recentlyWritten[$0] == nil }
        guard !foreign.isEmpty else { return }

        // Einzelne Dateien (z. B. in Obsidian bearbeitet) gezielt neu lesen, sofort sichtbar.
        // Ordner-Änderungen oder viele Dateien auf einmal: alles neu einlesen.
        var isDirectory: ObjCBool = false
        let onlyFiles = foreign.count <= 50 && foreign.allSatisfy { path in
            !(FileManager.default.fileExists(atPath: rootURL.appending(path: path).path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue)
        }
        if onlyFiles, state == .ready {
            Task { await applyUpdate(paths: Array(foreign), root: rootURL) }
        } else {
            scheduleRescan()
        }
    }
}
