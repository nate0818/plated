import SwiftUI
import SwiftData
import AuthenticationServices

/// The journey: the opener sets the table → Sign in with Apple (the only
/// door) → set your table from contacts → the week. Each stage is
/// remembered, so returning users land straight on their week.
struct RootView: View {
    @AppStorage("didSignIn") private var didSignIn = false
    @AppStorage("didSetTable") private var didSetTable = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var splashDone = false
    @State private var appReady = false

    /// A dead Apple credential — revoked in Settings, or unknown to the
    /// signed-in iCloud account (a handed-down device) — closes the door
    /// again. Checked at launch, on every return to foreground (apps sit
    /// suspended for weeks), and on Apple's revocation notification.
    ///
    /// Scope, decided: signing out clears only the Keychain identity and
    /// the door flag. The table itself — recipes, weeks, household — stays:
    /// it belongs to the household on this device, not to the credential,
    /// and the next sign-in walks back into it. Wiping data on revocation
    /// would turn "I reset my Apple ID permissions" into "dinner is gone."
    private func recheckCredential() async {
        if didSignIn, await AppleIdentity.credentialInvalid() {
            AppleIdentity.clear()
            didSignIn = false
        }
    }

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            if !splashDone {
                LaunchOpenerView(ready: appReady) { splashDone = true }
                    .transition(.opacity)
            } else if !didSignIn {
                SignInView { didSignIn = true }
                    .transition(.opacity)
            } else if !didSetTable {
                ContactsView { didSetTable = true }
                    .transition(.opacity)
            } else {
                MainShellView()
                    .transition(.opacity)
            }
        }
        .animation(.plSettle, value: splashDone)
        .animation(.plSettle, value: didSignIn)
        .animation(.plSettle, value: didSetTable)
        .task {
            // Stand-in for real wake-up work. The opener holds in its
            // simmer loop if this ever outlasts the wordmark settling —
            // `-plated-slow-wake` forces that path for testing.
            #if DEBUG
            let wake: Double = LaunchFlags.consume("-plated-slow-wake") ? 8 : 1.4
            #else
            let wake: Double = 1.4
            #endif
            try? await Task.sleep(for: .seconds(wake))
            appReady = true
        }
        .task { await recheckCredential() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await recheckCredential() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: ASAuthorizationAppleIDProvider.credentialRevokedNotification
        )) { _ in
            Task { await recheckCredential() }
        }
    }
}

/// A bundled stand-in dish photo. Real plates are always user-submitted;
/// these exist so onboarding and previews have food on the table.
extension Image {
    init?(sampleNamed name: String) {
        guard let data = SampleData.photo(name), let ui = UIImage(data: data) else { return nil }
        self.init(uiImage: ui)
    }
}

#Preview {
    RootView().modelContainer(SampleData.previewContainer)
}
