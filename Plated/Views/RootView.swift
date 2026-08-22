import SwiftUI
import SwiftData

/// The journey: the opener sets the table → Sign in with Apple (the only
/// door) → set your table from contacts → the week. Each stage is
/// remembered, so returning users land straight on their week.
struct RootView: View {
    @AppStorage("didSignIn") private var didSignIn = false
    @AppStorage("didSetTable") private var didSetTable = false
    @State private var splashDone = false
    @State private var appReady = false

    /// A revoked Apple credential (Settings → Apple ID → Sign out of app)
    /// closes the door again on next launch.
    private func recheckCredential() async {
        if didSignIn, await AppleIdentity.credentialRevoked() {
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
