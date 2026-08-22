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
    @State private var arrived = false

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
                    .font(.gabarito(32, .extraBold))
                    .tracking(-0.8)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text("Plan the week, cook together, and share your table with only the people you choose.")
                    .font(.jakarta(15, .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)
            .opacity(arrived ? 1 : 0)

            Spacer()

            VStack(spacing: 14) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    if case .success(let auth) = result,
                       let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                        userFirstName = credential.fullName?.givenName ?? userFirstName
                        userFamilyName = credential.fullName?.familyName ?? userFamilyName
                    }
                    // Auth errors (no entitlement in dev, user cancel) still
                    // open the door to a local table — sync waits for a
                    // signed build, planning shouldn't.
                    Haptic.tap()
                    onSignedIn()
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 56)
                .clipShape(Capsule())

                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("No passwords. Nothing public. Just your people.")
                        .font(.jakarta(12, .medium))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(arrived ? 1 : 0)
        }
        .onAppear { withAnimation(.plSettle.delay(0.1)) { arrived = true } }
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
            .shadow(color: Color.shadowWarm.opacity(0.18), radius: 24, y: 18)
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
