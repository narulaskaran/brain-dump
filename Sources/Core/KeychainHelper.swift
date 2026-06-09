import Foundation
import Security

/// Convenience wrapper around the Security framework's keychain APIs.
public struct KeychainHelper {
    private static let service = "com.braindump.app"

    private init() {}

    /// Persist a string value in the keychain for the given key.
    public static func save(key: String, value: String) throws {
        let data = Data(value.utf8)

        // Remove any existing item first so we can re-add cleanly.
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Load a string value from the keychain for the given key, or `nil` if absent.
    public static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Remove the keychain item for the given key (no-op if absent).
    public static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
}
