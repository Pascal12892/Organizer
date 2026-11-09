import Foundation

/// Merkt sich das letzte Ergebnis einer teuren Berechnung, solange der Schlüssel gleich bleibt.
/// Damit rechnen Views beim Neuzeichnen nicht jedes Mal alles neu (z. B. Filter über alle Notizen).
final class Memo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func callAsFunction(_ key: Key, compute: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let fresh = compute()
        self.key = key
        value = fresh
        return fresh
    }
}
