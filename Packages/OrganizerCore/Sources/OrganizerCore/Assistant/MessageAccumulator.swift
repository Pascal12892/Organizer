import Foundation

/// Setzt eine gestreamte Claude-Antwort (Server-Sent Events) zu Inhaltsblöcken zusammen.
///
/// Jeder Block wird als JSON gehalten und genau so zurückgegeben, wie die API ihn geliefert hat –
/// auch Denk-Blöcke mit Signatur und unbekannte Blocktypen. Der Verlauf bleibt damit unverändert
/// („append-only“), wie es die API für spätere Anfragen verlangt.
public struct MessageAccumulator: Sendable {
    public private(set) var blocks: [JSONValue] = []
    public private(set) var stopReason: String?
    public private(set) var model: String?
    /// Text-Eingaben der Werkzeugaufrufe, Fragment für Fragment (Index → bisheriger Text).
    private var partialJSON: [Int: String] = [:]
    /// Index → Fehler beim Zusammensetzen einer Werkzeug-Eingabe.
    public private(set) var invalidToolInputs: [String: String] = [:]

    public init() {}

    public enum StreamError: LocalizedError {
        case api(type: String, message: String)

        public var errorDescription: String? {
            switch self {
            case .api(_, let message): message
            }
        }
    }

    /// Verarbeitet ein `data:`-Objekt aus dem Stream. Gibt den geänderten Blockindex zurück.
    @discardableResult
    public mutating func apply(_ event: JSONValue) throws -> Int? {
        guard let type = event["type"]?.stringValue else { return nil }
        switch type {
        case "message_start":
            model = event["message"]?["model"]?.stringValue
            return nil

        case "content_block_start":
            guard let index = event["index"]?.numberValue.map(Int.init), let block = event["content_block"] else { return nil }
            while blocks.count <= index { blocks.append(.null) }
            blocks[index] = block
            if block["type"]?.stringValue == "tool_use" { partialJSON[index] = "" }
            return index

        case "content_block_delta":
            guard let index = event["index"]?.numberValue.map(Int.init), blocks.indices.contains(index),
                  let delta = event["delta"], case .object(var block) = blocks[index] else { return nil }
            switch delta["type"]?.stringValue {
            case "text_delta":
                block["text"] = .string((block["text"]?.stringValue ?? "") + (delta["text"]?.stringValue ?? ""))
            case "thinking_delta":
                block["thinking"] = .string((block["thinking"]?.stringValue ?? "") + (delta["thinking"]?.stringValue ?? ""))
            case "signature_delta":
                block["signature"] = delta["signature"] ?? .string("")
            case "input_json_delta":
                partialJSON[index, default: ""] += delta["partial_json"]?.stringValue ?? ""
            default:
                break // z. B. citations_delta – für Organizer nicht nötig
            }
            blocks[index] = .object(block)
            return index

        case "content_block_stop":
            guard let index = event["index"]?.numberValue.map(Int.init), blocks.indices.contains(index),
                  let raw = partialJSON.removeValue(forKey: index), case .object(var block) = blocks[index] else { return nil }
            // Werkzeug-Eingabe streng parsen; bei Fehlern nichts erfinden, sondern merken.
            if raw.isEmpty {
                block["input"] = .object([:])
            } else if let input = try? JSONValue.parse(raw), case .object = input {
                block["input"] = input
            } else {
                block["input"] = .object([:])
                if let id = block["id"]?.stringValue { invalidToolInputs[id] = raw }
            }
            blocks[index] = .object(block)
            return index

        case "message_delta":
            if let reason = event["delta"]?["stop_reason"]?.stringValue { stopReason = reason }
            return nil

        case "error":
            throw StreamError.api(
                type: event["error"]?["type"]?.stringValue ?? "error",
                message: event["error"]?["message"]?.stringValue ?? "Unbekannter Fehler"
            )

        default:
            return nil // message_stop, ping
        }
    }

    /// Die fertige Antwort als Nachricht für den Verlauf.
    public var assistantMessage: JSONValue {
        .object(["role": "assistant", "content": .array(blocks.filter { $0 != .null })])
    }

    public var toolUses: [(id: String, name: String, input: JSONValue)] {
        blocks.compactMap { block in
            guard block["type"]?.stringValue == "tool_use",
                  let id = block["id"]?.stringValue, let name = block["name"]?.stringValue else { return nil }
            return (id, name, block["input"] ?? .object([:]))
        }
    }

    /// Gesamter sichtbarer Text der Antwort.
    public var text: String {
        blocks.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }.joined()
    }
}

/// Prüft Werkzeug-Eingaben gegen ein (einfaches) JSON-Schema, bevor ein Werkzeug läuft.
/// Nötig, weil mit `eager_input_streaming` die API die Eingaben nicht mehr selbst prüft.
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
