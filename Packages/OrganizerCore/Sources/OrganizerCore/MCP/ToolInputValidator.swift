import Foundation

/// Prüft Werkzeug-Eingaben gegen ein (einfaches) JSON-Schema, bevor ein Werkzeug läuft.
public enum ToolInputValidator {
    public static func validate(_ input: JSONValue, schema: JSONValue) -> String? {
        guard case .object(let object) = input else { return "Eingabe ist kein Objekt." }
        let properties = schema["properties"]?.objectValue ?? [:]
        for key in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
            guard let value = object[key], value != .null else { return "Pflichtfeld „\(key)“ fehlt." }
            if case .string(let text) = value, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Pflichtfeld „\(key)“ ist leer."
            }
        }
        for (key, value) in object {
            guard let property = properties[key] else { return "Unbekanntes Feld „\(key)“." }
            if value == .null { continue }
            switch property["type"]?.stringValue {
            case "string":
                guard case .string(let text) = value else { return "„\(key)“ muss Text sein." }
                if let allowed = property["enum"]?.arrayValue?.compactMap(\.stringValue), !allowed.contains(text) {
                    return "„\(key)“ muss einer dieser Werte sein: \(allowed.joined(separator: ", "))."
                }
            case "boolean":
                guard case .bool = value else { return "„\(key)“ muss true oder false sein." }
            case "integer", "number":
                guard case .number = value else { return "„\(key)“ muss eine Zahl sein." }
            default:
                break
            }
        }
        return nil
    }
}
