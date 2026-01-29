import Foundation
import Security

/// Service for securely storing sensitive data in the iOS Keychain
nonisolated struct KeychainService: Sendable {

    nonisolated enum KeychainKey: String, Sendable {
        case openRouterAPIKey = "com.bobk.FitnessApp.openRouterAPIKey"
        case stravaClientId = "com.bobk.FitnessApp.stravaClientId"
        case stravaClientSecret = "com.bobk.FitnessApp.stravaClientSecret"
    }

    nonisolated enum KeychainError: Error, Sendable {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case invalidData
        case invalidAPIKeyFormat
    }

    // MARK: - Save

    /// Save a string value to the Keychain
    nonisolated static func save(key: KeychainKey, value: String) throws {
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
    nonisolated static func read(key: KeychainKey) throws -> String {
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
    nonisolated static func delete(key: KeychainKey) throws {
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
    nonisolated static func exists(key: KeychainKey) -> Bool {
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

    @MainActor
    static func saveOpenRouterAPIKey(_ key: String) throws {
        // FIX: Validate API key format before saving
        // OpenRouter keys typically start with "sk-or-" and have a minimum length
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            throw KeychainError.invalidAPIKeyFormat
        }

        // OpenRouter API keys should start with "sk-or-" prefix
        // Allow keys that start with "sk-" as some may have different prefixes
        guard trimmedKey.hasPrefix("sk-") && trimmedKey.count >= 20 else {
            throw KeychainError.invalidAPIKeyFormat
        }

        try save(key: .openRouterAPIKey, value: trimmedKey)
        UserDefaults.standard.set(true, forKey: .hasOpenRouterAPIKey)
    }

    nonisolated static func getOpenRouterAPIKey() -> String? {
        try? read(key: .openRouterAPIKey)
    }

    @MainActor
    static func deleteOpenRouterAPIKey() throws {
        try delete(key: .openRouterAPIKey)
        UserDefaults.standard.set(false, forKey: .hasOpenRouterAPIKey)
    }

    nonisolated static var hasOpenRouterAPIKey: Bool {
        exists(key: .openRouterAPIKey)
    }
}

// MARK: - Strava Credentials

extension KeychainService {

    /// Save Strava API credentials to Keychain
    static func saveStravaCredentials(clientId: String, clientSecret: String) throws {
        let trimmedId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedId.isEmpty, !trimmedSecret.isEmpty else {
            throw KeychainError.invalidData
        }

        try save(key: .stravaClientId, value: trimmedId)
        try save(key: .stravaClientSecret, value: trimmedSecret)
    }

    /// Get Strava Client ID from Keychain
    nonisolated static func getStravaClientId() -> String? {
        try? read(key: .stravaClientId)
    }

    /// Get Strava Client Secret from Keychain
    nonisolated static func getStravaClientSecret() -> String? {
        try? read(key: .stravaClientSecret)
    }

    /// Check if Strava credentials are configured
    nonisolated static var hasStravaCredentials: Bool {
        exists(key: .stravaClientId) && exists(key: .stravaClientSecret)
    }

    /// Delete Strava credentials
    static func deleteStravaCredentials() throws {
        try delete(key: .stravaClientId)
        try delete(key: .stravaClientSecret)
    }
}
