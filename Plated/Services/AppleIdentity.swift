import Foundation
import AuthenticationServices
import Security
import UIKit

/// The one durable fact of sign-in: Apple's stable user identifier, kept in
/// the Keychain (never UserDefaults — it is the key CloudKit sharing will
/// hang seats on). ThisDeviceOnly on purpose: an identity that rode a backup
/// onto someone else's device would resurrect a session that was never
/// theirs. Revocation closes the door again.
enum AppleIdentity {
    private static let service = "com.natemeadows.plated.apple-id"
    private static let account = "apple-user-id"

    /// Persist the Apple user id and offer the identity token to the
    /// directory. The token exists only here and only for minutes, so this
    /// is the one moment registration can happen. A false return means
    /// Keychain never got the id: sharing and invites stay dark.
    @discardableResult
    static func accept(_ credential: ASAuthorizationAppleIDCredential, displayName: String) -> Bool {
        let saved = save(credential.user)
        if let tokenData = credential.identityToken,
           let identityToken = String(data: tokenData, encoding: .utf8) {
            Task { await Directory.register(
                identityToken: identityToken,
                displayName: displayName,
                phone: nil
            ) }
        }
        return saved
    }

    /// True when the identifier is durably stored. A false return means
    /// revocation checking is dark until the next successful sign-in —
    /// callers should at least leave a trace in the console.
    @discardableResult
    static func save(_ userID: String) -> Bool {
        if load() != userID { Directory.clearSession() }
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
        Directory.clearSession()
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

    /// Present Sign in with Apple from a custom control. The door itself
    /// uses `SignInWithAppleButton`; Try again after a miss cannot.
    @MainActor
    static func request() async -> Result<ASAuthorizationAppleIDCredential, Error> {
        await SignInRunner().run()
    }

    @MainActor
    private final class SignInRunner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private var continuation: CheckedContinuation<Result<ASAuthorizationAppleIDCredential, Error>, Never>?
        /// The controller does not retain its delegate. Pin self until Apple answers.
        private var pin: SignInRunner?

        func run() async -> Result<ASAuthorizationAppleIDCredential, Error> {
            pin = self
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.fullName]
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        }

        private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
            continuation?.resume(returning: result)
            continuation = nil
            pin = nil
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                finish(.success(credential))
            } else {
                finish(.failure(ASAuthorizationError(.unknown)))
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            finish(.failure(error))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first {
                return window
            }
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first ?? UIWindow()
        }
    }
}
