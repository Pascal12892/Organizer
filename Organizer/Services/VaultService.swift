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
    /// `true` während ein Scan läuft – auch wenn bereits Daten angezeigt werden.
    private(set) var isScanning = false
    private(set) var lastScan: Date?

    private var layout: VaultLayout
    private var watcher: VaultWatcher?
    private var isAccessingScope = false
    private var rescanTask: Task<Void, Never>?
    private var scanGeneration = 0

    init(layout: VaultLayout = VaultLayout()) {
        self.layout = layout
    }

    /// Für Previews: ein fertiger Vault ohne Dateizugriff.
    static func preview(_ snapshot: VaultSnapshot, name: String = "Vault") -> VaultService {
        let service = VaultService()
        service.snapshot = snapshot
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

        await rescan()
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
        let layout = layout
        let snapshot = await Task.detached(priority: .userInitiated) {
            VaultScanner.scan(root: rootURL, layout: layout)
        }.value

        // Ein neuerer Scan oder ein Vault-Wechsel hat dieses Ergebnis überholt.
        guard generation == scanGeneration, rootURL == self.rootURL else { return }
        self.snapshot = snapshot
        isScanning = false
        lastScan = .now
        state = .ready
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
