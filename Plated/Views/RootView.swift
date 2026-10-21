import SwiftUI
import SwiftData
import AuthenticationServices

/// Welcome is the only mandatory introduction. Shared actions ask for identity when needed.
struct RootView: View {
    @AppStorage("didSignIn") private var didSignIn = false
    @AppStorage("didSetTable") private var didSetTable = false
    @AppStorage("sawTour") private var sawTour = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var splashDone = false
    @State private var appReady = false
    /// Finishes a launch-argument tour preview without touching `sawTour`.
    /// Reviewers can move on to the real shell, then relaunch to replay.
    @State private var tourReviewDone = false
    @State private var onboardingReviewDone = false
    /// A household invitation that arrived before the table was set. Held
    /// here rather than parked in `LinkRelay`, because the shell must not
    /// route it a second time after onboarding has already answered it.
    /// State, not storage: a link lost to a kill mid-onboarding can be
    /// tapped again, and a stale one must never join anybody later.
    @State private var joinLink: Invitation.Parsed?

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
        guard !PlatedApp.usesPreviewContainer else { return }
        if didSignIn, await AppleIdentity.credentialInvalid() {
            AppleIdentity.clear()
            didSignIn = false
        }
    }

    private static var designReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-plated-design-review")
        #else
        false
        #endif
    }

    /// A non-destructive route into the tour for screenshots and motion
    /// review. Unlike resetting defaults, it cannot sign somebody out,
    /// recreate their profile or make the real tour become owed again.
    private static var tourReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-plated-review-tour")
        #else
        false
        #endif
    }

    /// The complete post-sign-in walkthrough, backed only by local sample
    /// state. It is deliberately a separate flag from the one-screen Tour
    /// review so existing screenshot and UI-test launch arguments keep working.
    private static var onboardingReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-plated-review-onboarding")
        #else
        false
        #endif
    }

    /// Holds the launch canvas without changing onboarding defaults.
    private static var openerReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-plated-review-opener")
        #else
        false
        #endif
    }

    private static var signInReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-plated-review-sign-in")
        #else
        false
        #endif
    }

    @ViewBuilder
    private var designReviewContent: some View {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.first(where: { $0.hasPrefix("-plated-review-invitation-") }) {
            let state: HouseholdSync.JoinPreview.State = switch flag {
            case "-plated-review-invitation-removed": .removed
            case "-plated-review-invitation-own": .ownShare
            case "-plated-review-invitation-resume": .needsSeat(candidates: [.init(id: "seat-sam", name: "Sam", role: "partner")])
            default: .ready
            }
            // Deterministic presentation only: construct the same verified proof
            // as a freshly fetched grant, without reading or changing live shares.
            let freshGrant = flag == "-plated-review-invitation-rejoin"
                ? HouseholdReinvitation.verifiedInvitation(
                    for: "review-alessandra", seat: "review-seat",
                    fetchedEntries: HouseholdReinvitation.authorizing(
                        seat: "review-seat", entries: ["review-alessandra"]))
                : nil
            MainShellView()
                .sheet(isPresented: .constant(true)) {
                    JoinHouseholdSheet(metadata: nil, root: nil, seat: "review-seat", linkHost: "",
                        reviewPreview: .init(hostName: "Nate Meadows", householdName: "Meadows", state: state,
                            mealsFromToday: 0, hasGroceryState: false, broughtSeats: [], reinvitation: freshGrant))
                }
        } else {
            MainShellView()
        }
        #else
        MainShellView()
        #endif
    }

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            if Self.signInReview {
                SignInView(reviewOnly: true, onSignedIn: {})
            } else if Self.openerReview {
                LaunchOpenerView(ready: false) {}
            } else if Self.onboardingReview {
                if onboardingReviewDone {
                    MainShellView(initialTab: .cookbook)
                } else {
                    SignInView(reviewOnly: true) { onboardingReviewDone = true }
                }
            } else if Self.tourReview {
                if tourReviewDone {
                    MainShellView()
                        .transition(.opacity)
                } else {
                    TourView { tourReviewDone = true }
                        .transition(.opacity)
                }
            } else if Self.designReview {
                designReviewContent
            } else {
                switch FirstRunRoute.resolve(
                    ready: splashDone, signedIn: didSignIn,
                    completedSetup: didSetTable, hasInvitation: joinLink != nil
                ) {
                case .loading:
                    LaunchOpenerView(ready: appReady) { splashDone = true }
                        .transition(.opacity)
                case .welcome:
                    SignInView { didSignIn = true }
                        .transition(.opacity)
                case .invitation:
                    if let joinLink {
                        JoinFromLinkStep(parsed: joinLink) {
                            self.joinLink = nil
                            didSetTable = true
                        }
                        .transition(.opacity)
                    }
                case .app(let initialTab):
                    MainShellView(initialTab: initialTab)
                        .onAppear {
                            didSetTable = true
                            sawTour = true
                        }
                        .transition(.opacity)
                }
            }
        }
        .animation(.plSettle, value: splashDone)
        .animation(.plSettle, value: didSignIn)
        .animation(.plSettle, value: didSetTable)
        .animation(.plSettle, value: sawTour)
        .animation(.plSettle, value: tourReviewDone)
        .animation(.plSettle, value: onboardingReviewDone)
        .animation(.plSettle, value: joinLink != nil)
        // The one door for every URL. Nothing else may add `onOpenURL`:
        // SwiftUI calls every registered handler, so a second one on the
        // shell would route the same link twice.
        .onOpenURL { url in
            if !didSetTable, let parsed = Invitation.parse(url), parsed.kind == .household {
                print("PLATED HOUSEHOLD: a household link arrived during onboarding")
                joinLink = parsed
            } else {
                LinkRelay.open(url)
            }
        }
        .task {
            // There is no wake-up work. This was a 1.4 second sleep standing
            // in for some, which means every cold launch paid 1.4 seconds for
            // nothing, forever, on the one screen every session begins with.
            // The slow path verifies the canvas while readiness is pending.
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
