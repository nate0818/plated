import Foundation
import Contacts

/// Who else is on Plated.
///
/// **Why a server at all.** iOS gives an app no way to answer "which of my
/// contacts already use this app". `CKContainer.discoverUserIdentity` and
/// `CKApplicationPermissionUserDiscoverability` were the local answer and
/// Apple deprecated both — they are still dead in the iOS 26 SDK. So the
/// directory is the one part of Plated that is not on-device.
///
/// **What is published.** A salted hash of your phone number and the first
/// name you already show your household. Never the raw number: the pepper
/// lives on the server, so the hashes in the table cannot be walked back
/// into a phone book, and this app's key cannot read that table at all.
///
/// **What is asked.** Lookups send contact numbers over TLS to be peppered
/// server-side, because a pepper shipped inside an app is not a pepper —
/// there are only ~10^10 phone numbers and an attacker with the binary
/// could enumerate every one.
enum Directory {

    // The publishable key is designed to ship in clients; row-level
    // security means it can read nothing. Every real answer comes from an
    // edge function that checks a token first.
    private static let base = URL(string: "https://dyvrksooelbkzkprqlhk.supabase.co/functions/v1")!
    private static let publishableKey = "sb_publishable_E8Jx1GJNYSDAAT-KDfvLqw_WjjGy9GL"

    /// The session token minted at registration. Keychain, not
    /// UserDefaults: it is the credential that lets this device ask who
    /// somebody's contacts are.
    private static let tokenAccount = "plated.directory.token"

    static var isRegistered: Bool { token != nil }

    private static var token: String? {
        get { Keychain.string(for: tokenAccount) }
        set { Keychain.set(newValue, for: tokenAccount) }
    }

    struct Match: Identifiable, Hashable {
        var id: String { phone }
        let phone: String
        let name: String
    }

    // MARK: Register

    /// Publish this device's presence. Called after Sign in with Apple,
    /// which is the only place an identity token exists.
    ///
    /// Silent on failure by design: a household that never opens Find
    /// people should never see a network error, and the app works fully
    /// without the directory.
    @discardableResult
    static func register(identityToken: String, displayName: String, phone: String?) async -> Bool {
        var body: [String: Any] = [
            "identity_token": identityToken,
            "display_name": displayName
        ]
        if let phone, let e164 = normalize(phone) { body["phone_e164"] = e164 }

        guard let data = await post("register", body: body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let minted = json["api_token"] as? String
        else { return false }

        token = minted
        return true
    }

    // MARK: Lookup

    /// Which of these contacts are already here. Returns [] when the
    /// device has never registered, which is the honest answer rather than
    /// an error: without a registration there is nobody to ask on behalf of.
    static func onPlated(contacts: [CNContact]) async -> [Match] {
        guard let token else { return [] }

        // One number per contact, and only the ones we can normalize —
        // sending 300 unparseable strings would just be noise.
        var byNumber: [String: String] = [:]
        for contact in contacts {
            guard let raw = contact.phoneNumbers.first?.value.stringValue,
                  let e164 = normalize(raw) else { continue }
            let name = "\(contact.givenName) \(contact.familyName)"
                .trimmingCharacters(in: .whitespaces)
            byNumber[e164] = name.isEmpty ? contact.nickname : name
        }
        guard !byNumber.isEmpty else { return [] }

        // The function caps at 500; cap here too so the tail isn't
        // silently dropped without us knowing it happened.
        let numbers = Array(byNumber.keys.prefix(500))
        guard let data = await post("lookup", body: ["api_token": token, "phone_e164s": numbers]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["matches"] as? [[String: Any]]
        else { return [] }

        return rows.compactMap { row in
            guard let phone = row["phone_e164"] as? String else { return nil }
            // Their name in your phone beats their name in our table —
            // you know them as "Mum", not "Susan Fitzgerald".
            let name = byNumber[phone] ?? (row["display_name"] as? String ?? "")
            return name.isEmpty ? nil : Match(phone: phone, name: name)
        }
    }

    // MARK: Plumbing

    private static func post(_ path: String, body: [String: Any]) async -> Data? {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                // The console is the only place a directory failure is
                // visible at all — the UI stays quiet on purpose.
                print("PLATED DIRECTORY: \(path) failed — \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            return data
        } catch {
            print("PLATED DIRECTORY: \(path) failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Best-effort E.164. Two phones must agree on a number's spelling or
    /// their hashes will never match, so this is deliberately strict: keep
    /// the digits, honour a written +, and assume the device's own region
    /// for everything else.
    static func normalize(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        if raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return "+\(digits)" }

        let region = Locale.current.region?.identifier ?? "US"
        if region == "US" || region == "CA" {
            if digits.count == 10 { return "+1\(digits)" }
            if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
            return nil
        }
        // Elsewhere a leading trunk 0 is dropped in E.164, but the country
        // code is unknowable from digits alone — so only already-plussed
        // numbers are trustworthy abroad.
        return nil
    }
}

/// The smallest Keychain wrapper that does the job. The directory token is
/// a credential; UserDefaults is a plist in a backup.
private enum Keychain {
    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        // This device only: a directory session should not ride an iCloud
        // restore onto hardware that never signed in.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
