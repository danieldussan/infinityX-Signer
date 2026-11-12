import Foundation
import Security

/// Certificate passwords, keyed by the .p12 file name.
enum KeychainStore {
    private static let service = "com.infinityx.signer.cert"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func setPassword(_ password: String, for account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard !password.isEmpty else { return }
        var attrs = baseQuery(account)
        attrs[kSecValueData as String] = Data(password.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func password(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
