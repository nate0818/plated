import SwiftUI
import AuthenticationServices

/// Apple unlocks sharing, but it is not a tollbooth in front of the local
/// planner. Someone can set up their week first and add identity when they
/// invite, join, or publish.
struct SignInView: View {
    var reviewOnly = false
    let onSignedIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("userFirstName") private var userFirstName = ""
    @AppStorage("userFamilyName") private var userFamilyName = ""
    /// Set when Sign in with Apple failed for a reason other than cancel,
    /// or Apple succeeded and Keychain never got the id. Planning is not
    /// hostage to Apple's outage; the person has to see that, and choose.
    @AppStorage("appleIdentityMissing") private var appleIdentityMissing = false
    @State private var arrived = false
    /// The fail-open sheet. Apple did not land; Continue still opens the
    /// door, Try again asks Apple again. The app does not open silently.
    @State private var appleFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlatedWordmark(size: 28)
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.content)
                .padding(.bottom, Spacing.content)

            Color.clear
                .frame(height: 240)
                .overlay {
                    GeometryReader { geometry in
                        Image("EditorialWelcome")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
                .clipShape(Radius.shape(Radius.hero))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Text("Good food.\nA little more together.")
                    .plType(.hero, .regular)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your recipes, dinner plans, and shopping list. Together.")
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.page)
            .opacity(arrived ? 1 : 0)

            Spacer(minLength: 28)

            VStack(spacing: 14) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        applyApple(auth)
                    case .failure(let error):
                        handleAppleFailure(error)
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 56)
                .clipShape(Radius.shape(Radius.chip))
                .id(colorScheme)

                SecondaryActionButton(title: "Continue on this device") {
                    if !reviewOnly { appleIdentityMissing = true }
                    onSignedIn()
                }
                .accessibilityIdentifier("welcome-local")
                .accessibilityHint("Plan locally now. Sign in later to share or join a household.")

                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("Sign in to share with your household.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(arrived ? 1 : 0)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .plFitsOrScrolls()
        .frame(maxWidth: .infinity)
        .background { OnboardingAtmosphere().ignoresSafeArea() }
        .onAppear { arrived = true }
        .sheet(isPresented: $appleFailed) {
            AppleFailOpenSheet(
                onTryAgain: {
                    appleFailed = false
                    Task { await retryApple() }
                },
                onContinue: {
                    appleFailed = false
                    Haptic.tap()
                    onSignedIn()
                }
            )
        }
    }

    /// Names land even when Keychain does not: they are not the identity.
    private func applyCredential(_ credential: ASAuthorizationAppleIDCredential) {
        userFirstName = credential.fullName?.givenName ?? userFirstName
        userFamilyName = credential.fullName?.familyName ?? userFamilyName
        let name = credential.fullName?.givenName ?? userFirstName
        if AppleIdentity.accept(credential, displayName: name) {
            appleIdentityMissing = false
            appleFailed = false
            Haptic.tap()
            onSignedIn()
        } else {
            presentFailOpen()
        }
    }

    private func applyApple(_ auth: ASAuthorization) {
        guard !reviewOnly else { onSignedIn(); return }
        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
            presentFailOpen()
            return
        }
        applyCredential(credential)
    }

    private func handleAppleFailure(_ error: Error) {
        // Cancel means cancel — the door stays shut. Any other failure
        // (broken auth service, no network to Apple) still offers a local
        // table: planning must not be hostage to an outage. Debug builds
        // always offer Continue — unentitled dev builds fail auth by design.
        #if DEBUG
        _ = error
        presentFailOpen()
        #else
        if (error as? ASAuthorizationError)?.code != .canceled {
            presentFailOpen()
        }
        #endif
    }

    private func presentFailOpen() {
        appleIdentityMissing = true
        Haptic.warn()
        appleFailed = true
    }

    /// Ask Apple again after the sheet is gone. Presenting over a
    /// disappearing sheet would take the system dialog with it.
    private func retryApple() async {
        try? await Task.sleep(for: .milliseconds(400))
        switch await AppleIdentity.request() {
        case .success(let credential):
            applyCredential(credential)
        case .failure(let error):
            handleAppleFailure(error)
        }
    }

    private func bob(_ t: Double, _ phase: Double, amp: Double = 7) -> Double {
        reduceMotion ? 0 : sin(t * 0.8 + phase) * amp
    }

    private func avatarBubble(_ emoji: String, tone: PersonTone, size: CGFloat) -> some View {
        Circle()
            .fill(tone.tint)
            .frame(width: size, height: size)
            .overlay(Text(emoji).font(.system(size: size * 0.5)))
            .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 4))
            .plFloatShadow()
    }

    private func foodChip(_ emoji: String, size: CGFloat) -> some View {
        Circle()
            .fill(Color.canvas)
            .frame(width: size, height: size)
            .overlay(Text(emoji).font(.system(size: size * 0.5)))
            .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
            .plDishShadow()
    }

    /// A small date card puts the planning promise in the sign-in story,
    /// behind the people and dishes, without borrowing Apple's app icon.
    private var calendarCard: some View {
        VStack(spacing: 0) {
            Text(Date.now.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Color.olive)
            Text("\(Calendar.current.component(.day, from: .now))")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 62, height: 66)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        .plDishShadow()
    }
}

/// Copywriter-locked fail-open sheet. Swiping it away leaves the door shut,
/// the same as Try again without asking Apple again.
private struct AppleFailOpenSheet: View {
    let onTryAgain: () -> Void
    let onContinue: () -> Void
    @State private var measured: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Signed in without Apple")
                .plType(.title, .semibold)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sharing and invites are off.")
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Planning still works on this iPhone.")
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                PrimaryActionButton(title: "Try again", action: onTryAgain)
                Button("Continue without Apple") {
                    onContinue()
                }
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline, lineWidth: 1.5))
                .contentShape(Radius.shape(Radius.chip))
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured = $0 }
        .presentationDetents([.height(measured), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }
}
