import SwiftUI
import AuthenticationServices

/// The only door in. Apple-only on purpose: one tap, no passwords, and the
/// private-relay email keeps the table yours.
struct SignInView: View {
    let onSignedIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        VStack(spacing: 0) {
            // The table as a group thread: friends and the dishes they're
            // passing around, all drifting like a conversation in progress.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    avatarBubble("😄", tone: .basilPair, size: 96)
                        .offset(x: 30, y: 92 + bob(t, 1.7))
                    avatarBubble("😋", tone: .tomatoPair, size: 148)
                        .offset(x: 122, y: 58 + bob(t, 0))
                    avatarBubble("🤩", tone: .grapePair, size: 88)
                        .offset(x: 278, y: 132 + bob(t, 3.4))
                    foodChip("🍕", size: 56).offset(x: 82, y: 216 + bob(t, 1.1))
                    foodChip("🌮", size: 46).offset(x: 256, y: 46 + bob(t, 2.6))
                    foodChip("🥗", size: 58).offset(x: 180, y: 244 + bob(t, 4.2))
                    foodChip("🍜", size: 44).offset(x: 306, y: 240 + bob(t, 5.1))
                    Circle().fill(Color.mango)
                        .frame(width: 30, height: 30)
                        // A coloured glow on a drawn object, not a shadow
                        // under a surface. The ramp does not apply to art.
                        .shadow(color: Color.mango.opacity(0.4), radius: 8, y: 8)
                        .offset(x: 322, y: 36 + bob(t, 2.0, amp: 5))
                    Circle().fill(Color.basil.opacity(0.85))
                        .frame(width: 16, height: 16)
                        .offset(x: 46, y: 42 + bob(t, 4.6, amp: 5))
                }
                .frame(maxWidth: .infinity, maxHeight: 400, alignment: .topLeading)
                .background(alignment: .topTrailing) {
                    RadialGradient(colors: [.tomatoTint, .tomatoTint.opacity(0)], center: .center, startRadius: 0, endRadius: 240)
                        .frame(width: 480, height: 480)
                        .scaleEffect(reduceMotion ? 1 : 1 + 0.06 * sin(t * 0.45))
                        .offset(x: 140, y: -160)
                }
            }
            .scaleEffect(arrived ? 1 : 0.92)
            .opacity(arrived ? 1 : 0)

            VStack(spacing: 10) {
                PlatedWordmark(size: 26)
                Text("Dinner's better with your people.")
                    .plType(.hero)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Plan the week, cook together, and share your table with only the people you choose.")
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .opacity(arrived ? 1 : 0)

            Spacer()

            VStack(spacing: 14) {
                SignInWithAppleButton(.signIn) { request in
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
                .clipShape(Capsule())

                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("No passwords. Nothing public. Just your people.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(arrived ? 1 : 0)
        }
        .plFitsOrScrolls()
        .onAppear { withAnimation(.plSettle.delay(0.1)) { arrived = true } }
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
            Text("Sharing and invites are off until Apple sign-in works. Planning still works on this iPhone.")
                .plType(.body, .medium)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                TomatoPillButton(title: "Try again", action: onTryAgain)
                Button("Continue without Apple") {
                    onContinue()
                }
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                .contentShape(Capsule())
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
