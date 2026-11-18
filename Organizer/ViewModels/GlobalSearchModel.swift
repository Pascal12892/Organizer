import Foundation
import Observation
import OrganizerCore

/// Suchfeld für Termine, Aufgaben und Notizen. Gesucht wird mit kurzer Verzögerung,
/// damit Tippen flüssig bleibt.
@Observable
final class GlobalSearchModel {
    var text = "" {
        didSet { schedule() }
    }
    private(set) var query = GlobalSearch("")
    @ObservationIgnored private var task: Task<Void, Never>?

    func clear() {
        text = ""
    }

    private func schedule() {
        task?.cancel()
        let text = text
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            query = GlobalSearch("")
            return
        }
        task = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            query = GlobalSearch(text)
        }
    }
}
