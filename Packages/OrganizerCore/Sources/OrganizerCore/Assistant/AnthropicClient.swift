import Foundation

/// Minimaler Client für die Claude Messages API über URLSession (für Swift gibt es kein offizielles SDK).
public struct AnthropicClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    /// Server-seitiger Rückfall auf ein anderes Modell, falls eine Anfrage von den Sicherheitsfiltern abgelehnt wird.
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public enum ClientError: LocalizedError {
        case http(status: Int, type: String?, message: String)

        public var errorDescription: String? {
            switch self {
            case .http(let status, _, let message):
                switch status {
                case 401: "Der API-Schlüssel ist ungültig. Prüfe ihn in den Einstellungen unter „Claude“."
                case 403: "Der API-Schlüssel hat keine Berechtigung für diese Anfrage. (\(message))"
                case 429: "Zu viele Anfragen – bitte kurz warten und erneut senden."
                case 529: "Claude ist gerade überlastet. Bitte gleich noch einmal versuchen."
                case 500...599: "Fehler beim Server von Anthropic (\(status)). Bitte erneut versuchen."
                default: "Anfrage fehlgeschlagen (\(status)): \(message)"
                }
            }
        }

        public var isRetryable: Bool {
            if case .http(let status, _, _) = self { return status == 429 || status >= 500 }
            return false
        }
    }

    /// Sendet eine Anfrage mit `stream: true` und liefert jedes `data:`-Objekt des Streams.
    public func stream(body: JSONValue, betas: [String]) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 600
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
                    if !betas.isEmpty { request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
                    request.httpBody = try body.encoded()

                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let error = try? JSONValue.parse(data)
                        throw ClientError.http(
                            status: status,
                            type: error?["error"]?["type"]?.stringValue,
                            message: error?["error"]?["message"]?.stringValue ?? String(decoding: data, as: UTF8.self)
                        )
                    }
                    // Jede `data:`-Zeile enthält ein vollständiges JSON-Objekt mit eigenem `type`.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, let event = try? JSONValue.parse(payload) else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Prüft den Schlüssel ohne Kosten über die Modellliste.
    public func verifyKey(model: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(model)")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = try? JSONValue.parse(data)
            throw ClientError.http(status: status, type: error?["error"]?["type"]?.stringValue,
                                   message: error?["error"]?["message"]?.stringValue ?? "")
        }
    }
}
