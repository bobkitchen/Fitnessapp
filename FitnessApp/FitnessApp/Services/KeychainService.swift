import Foundation
import Security

/// Service for securely storing sensitive data in the iOS Keychain
struct KeychainService {

    enum KeychainKey: String {
        case openRouterAPIKey = "com.bobk.FitnessApp.openRouterAPIKey"
    }

    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case invalidData
    }

    // MARK: - Save

    /// Save a string value to the Keychain
    static func save(key: KeychainKey, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Try to delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Read

    /// Read a string value from the Keychain
    static func read(key: KeychainKey) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return string
    }

    // MARK: - Delete

    /// Delete a value from the Keychain
    static func delete(key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Check Existence

    /// Check if a key exists in the Keychain
    static func exists(key: KeychainKey) -> Bool {
        do {
            _ = try read(key: key)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Convenience API Key Methods

extension KeychainService {

    static func saveOpenRouterAPIKey(_ key: String) throws {
        try save(key: .openRouterAPIKey, value: key)
        UserDefaults.standard.set(true, forKey: "hasOpenRouterAPIKey")
    }

    static func getOpenRouterAPIKey() -> String? {
        try? read(key: .openRouterAPIKey)
    }

    static func deleteOpenRouterAPIKey() throws {
        try delete(key: .openRouterAPIKey)
        UserDefaults.standard.set(false, forKey: "hasOpenRouterAPIKey")
    }

    static var hasOpenRouterAPIKey: Bool {
        exists(key: .openRouterAPIKey)
    }
}
