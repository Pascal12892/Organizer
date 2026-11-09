import CoreServices
import Foundation

/// Beobachtet einen Ordner rekursiv mit FSEvents und meldet geänderte Pfade.
/// Erkennt auch Änderungen, die in Obsidian oder im Finder gemacht werden.
nonisolated final class VaultWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "de.pascallupo.Hub.VaultWatcher")
    // Nur auf `queue` bzw. in start/stop verwendet.
    private var stream: FSEventStreamRef?

    init(url: URL, onChange: @escaping @Sendable ([String]) -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self)
            let changed = (0..<count).compactMap { array[$0] as? String }
            watcher.onChange(changed)
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
