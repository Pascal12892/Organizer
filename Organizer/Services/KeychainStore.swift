import Foundation
import Security

/// Speichert den Anthropic-API-Schlüssel im macOS-Schlüsselbund – nie in einer Datei.
enum KeychainStore {
    private static let service = "de.pascallupo.Organizer.anthropic"
    private static let account = "api-key"

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Schlüssel konnte nicht im Schlüsselbund gespeichert werden (\(status))."])
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Wählbare Modelle für den Chat.
enum AssistantModel: String, CaseIterable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var title: String {
        switch self {
        case .opus: "Claude Opus 5.5 (Standard)"
        case .sonnet: "Claude Sonnet 5.5 (schneller, günstiger)"
        case .haiku: "Claude Haiku 5.5 (am günstigsten)"
        }
    }

    /// Server-seitiger Rückfall bei Ablehnungen gibt es für Opus und Sonnet, nicht für Haiku.
    var supportsFallback: Bool { self != .haiku }
}
