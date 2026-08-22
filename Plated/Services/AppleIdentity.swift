import Foundation
import AuthenticationServices
import Security

/// The one durable fact of sign-in: Apple's stable user identifier, kept in
/// the Keychain (never UserDefaults — it is the key CloudKit sharing will
/// hang seats on). ThisDeviceOnly on purpose: an identity that rode a backup
/// onto someone else's device would resurrect a session that was never
/// theirs. Revocation closes the door again.
enum AppleIdentity {
    private static let service = "com.natemeadows.plated.apple-id"
    private static let account = "apple-user-id"

    /// True when the identifier is durably stored. A false return means
    /// revocation checking is dark until the next successful sign-in —
    /// callers should at least leave a trace in the console.
    @discardableResult
    static func save(_ userID: String) -> Bool {
        guard let data = userID.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            print("PLATED IDENTITY: keychain clear failed (\(deleteStatus))")
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("PLATED IDENTITY: keychain save failed (\(addStatus)) — revocation checks are dark until next sign-in")
            return false
        }
        return true
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

    /// True when Apple gives a definitive "this credential is dead":
    /// revoked, or not found — the latter is the handed-down-device case,
    /// where the signed-in iCloud account has never heard of the stored ID.
    /// No stored identifier and transient failures both answer false — the
    /// door only re-closes on a verdict, never on a network hiccup.
    static func credentialInvalid() async -> Bool {
        guard let id = load() else { return false }
        guard let state = try? await ASAuthorizationAppleIDProvider()
            .credentialState(forUserID: id) else { return false }
        return state == .revoked || state == .notFound
    }
}
