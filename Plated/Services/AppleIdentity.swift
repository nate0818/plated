import Foundation
import AuthenticationServices
import Security

/// The one durable fact of sign-in: Apple's stable user identifier, kept in
/// the Keychain (never UserDefaults — it survives reinstalls and is the key
/// CloudKit sharing will hang seats on). Revocation closes the door again.
enum AppleIdentity {
    private static let service = "com.natemeadows.plated.apple-id"
    private static let account = "apple-user-id"

    static func save(_ userID: String) {
        guard let data = userID.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// True only when Apple says the stored credential was revoked. No
    /// stored identifier (dev builds signed in before one was kept) and
    /// transient failures both answer false — the door only re-closes on
    /// a definite revocation.
    static func credentialRevoked() async -> Bool {
        guard let id = load() else { return false }
        let state = try? await ASAuthorizationAppleIDProvider()
            .credentialState(forUserID: id)
        return state == .revoked
    }
}
