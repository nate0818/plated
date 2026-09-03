import SwiftUI
import SwiftData
import AuthenticationServices

/// The journey: the opener sets the table, Sign in with Apple is the only
/// door, then your face and name, then your people, then the week. Each
/// stage is remembered, so returning users land straight on their week.
struct RootView: View {
    @AppStorage("didSignIn") private var didSignIn = false
    /// The photo-and-name step. Its own flag rather than folded into
    /// `didSetTable`, so an existing install that already has a table is
    /// not dragged back through onboarding to be asked for a picture.
    @AppStorage("didSetProfile") private var didSetProfile = false
    @AppStorage("didSetTable") private var didSetTable = false
    /// The four-card tour, owed once at the end of setting up.
    ///
    /// Its own flag, and carried forward for anybody whose table already
    /// exists: being walked around an app you have been using for weeks is
    /// the same wrong note as being asked for a photo on launch day two.
    /// See `carryTourForward`.
    @AppStorage("sawTour") private var sawTour = false
    /// Set the first time the opener plays all the way through. Its own
    /// flag rather than `didSignIn`, because the full opener is owed to
    /// anyone who has not seen it — including someone who quit during it.
    @AppStorage("sawOpener") private var sawOpener = false
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

    /// A table that already exists means the app has already been met.
    ///
    /// Runs once: after this the key exists and the check never fires again.
    /// Without it, shipping the tour would hand every existing household a
    /// walkthrough of the app they were in the middle of using.
    private func carryTourForward() {
        let store = UserDefaults.standard
        guard store.object(forKey: "sawTour") == nil else { return }
        store.set(store.bool(forKey: "didSetTable"), forKey: "sawTour")
    }

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            if !splashDone {
                LaunchOpenerView(ready: appReady, brief: sawOpener) {
                    sawOpener = true
                    splashDone = true
                }
                    .transition(.opacity)
            } else if !didSignIn {
                SignInView { didSignIn = true }
                    .transition(.opacity)
            } else if !didSetProfile && !didSetTable {
                // Only for a genuinely new table. Someone who onboarded
                // before this step existed has already met the app, and
                // being handed a "put a face to your name" screen on launch
                // day two reads as a bug rather than a feature. They get the
                // same well inside Edit profile instead.
                ProfileSetupView { didSetProfile = true }
                    .transition(.opacity)
            } else if !didSetTable {
                ContactsView { didSetTable = true }
                    .transition(.opacity)
            } else if !sawTour {
                TourView { sawTour = true }
                    .transition(.opacity)
            } else {
                MainShellView()
                    .transition(.opacity)
            }
        }
        .animation(.plSettle, value: splashDone)
        .animation(.plSettle, value: didSignIn)
        .animation(.plSettle, value: didSetProfile)
        .animation(.plSettle, value: didSetTable)
        .animation(.plSettle, value: sawTour)
        .onAppear(perform: carryTourForward)
        .task {
            // There is no wake-up work. This was a 1.4 second sleep standing
            // in for some, which means every cold launch paid 1.4 seconds for
            // nothing, forever, on the one screen every session begins with.
            // The opener's own settle animation is the moment; it does not
            // need padding out. The slow path stays for testing the case
            // where real work does outlast the wordmark.
            #if DEBUG
            if LaunchFlags.consume("-plated-slow-wake") {
                try? await Task.sleep(for: .seconds(8))
            }
            #endif
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
