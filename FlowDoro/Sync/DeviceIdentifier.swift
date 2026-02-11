import Foundation
import Security

// MARK: - Device Identification
//
// Provides a stable, per-device UUID that persists across app reinstalls.
// - macOS: UUID stored in Keychain (survives app deletion)
// - iOS: identifierForVendor with Keychain fallback
// - watchOS: identifierForVendor with Keychain fallback
//
// This ID is stamped on every FocusSession and AppUsageRecord so analytics
// can distinguish "sessions from my Watch vs. my Mac" without any login.

struct DeviceIdentifier {

    private static let keychainService = "com.flodoro.device-id"
    private static let keychainAccount = "device-uuid"

    /// Stable per-device identifier. Same value across app launches and reinstalls.
    static var current: String {
        #if os(iOS) || os(watchOS)
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            return vendorID
        }
        return getOrCreateKeychainID()
        #elseif os(macOS)
        return getOrCreateKeychainID()
        #endif
    }

    /// Short ID for Bonjour service naming (first 8 chars)
    static var shortID: String {
        String(current.prefix(8))
    }

    /// Device type string for tagging records
    static var deviceType: String {
        #if os(watchOS)
        return "watch"
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "ipad"
        }
        return "iphone"
        #elseif os(macOS)
        return "mac"
        #endif
    }

    // MARK: - Keychain Storage

    /// Retrieve existing device ID from Keychain, or create and store a new one.
    private static func getOrCreateKeychainID() -> String {
        if let existing = readFromKeychain() {
            return existing
        }
        let newID = UUID().uuidString
        saveToKeychain(newID)
        return newID
    }

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }
        return id
    }

    private static func saveToKeychain(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete any existing entry first (idempotent)
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
