import Foundation
import Security

/// Stockage de la clé API Anthropic dans le trousseau iOS.
enum Keychain {
    private static let service = "museapp.anthropic"
    private static let account = "api-key"

    static var apiKey: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var out: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data, let key = String(data: data, encoding: .utf8),
                  !key.isEmpty else { return nil }
            return key
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)
            guard let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(value.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
