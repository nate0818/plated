import SwiftUI
import AuthenticationServices

/// The only door in. Apple-only on purpose: one tap, no passwords, and the
/// private-relay email keeps the table yours.
struct SignInView: View {
    let onSignedIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("userFirstName") private var userFirstName = ""
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @State private var arrived = false

    var body: some View {
        VStack(spacing: 0) {
            // Dishes from real tables, drifting in like plates being set down.
            ZStack(alignment: .topLeading) {
                if let salmon = Image(sampleNamed: "salmon-plate") {
                    dish(salmon, size: 200).offset(x: 96, y: 78)
                }
                if let pizza = Image(sampleNamed: "pizza") {
                    dish(pizza, size: 118).offset(x: 22, y: 216)
                }
                if let poke = Image(sampleNamed: "poke") {
                    dish(poke, size: 96).offset(x: 265, y: 246)
                }
                Circle().fill(Color.mango)
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.mango.opacity(0.4), radius: 8, y: 8)
                    .offset(x: 292, y: 60)
                Circle().fill(Color.basil.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .offset(x: 56, y: 96)
            }
            .frame(maxWidth: .infinity, maxHeight: 400, alignment: .topLeading)
            .background(alignment: .topTrailing) {
                RadialGradient(colors: [.tomatoTint, .tomatoTint.opacity(0)], center: .center, startRadius: 0, endRadius: 240)
                    .frame(width: 480, height: 480)
                    .offset(x: 140, y: -160)
            }
            .scaleEffect(arrived ? 1 : 0.92)
            .opacity(arrived ? 1 : 0)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().strokeBorder(Color.hairline, lineWidth: 2).frame(width: 24, height: 24)
                        Circle()
                            .fill(LinearGradient(colors: [.tomato, .mango], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 9, height: 9)
                    }
                    Text("Plated")
                        .font(.gabarito(22, .extraBold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.ink)
                }
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
                    switch result {
                    case .success(let auth):
                        if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                            AppleIdentity.save(credential.user)
                            userFirstName = credential.fullName?.givenName ?? userFirstName
                            userFamilyName = credential.fullName?.familyName ?? userFamilyName
                        }
                        Haptic.tap()
                        onSignedIn()
                    case .failure:
                        // Debug builds still open the door — sync waits for
                        // a signed build, planning shouldn't. Release keeps
                        // it shut: cancel means cancel.
                        #if DEBUG
                        Haptic.tap()
                        onSignedIn()
                        #endif
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 56)
                .clipShape(Capsule())

                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("The only way in. Your table stays yours.")
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

    private func dish(_ image: Image, size: CGFloat) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .shadow(color: Color.shadowWarm.opacity(0.2), radius: 28, y: 20)
    }
}
