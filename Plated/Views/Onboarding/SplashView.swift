import SwiftUI

/// A plate settles onto the table, the wordmark under it. Three course dots
/// pulse while the app wakes up.
struct SplashView: View {
    @State private var settled = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Soft warm glows drifting off-canvas — the only ambient color
            // the register allows, and barely.
            RadialGradient(colors: [.tomatoTint, .tomatoTint.opacity(0)], center: .center, startRadius: 0, endRadius: 210)
                .frame(width: 420, height: 420)
                .offset(x: -160, y: -330)
            RadialGradient(colors: [.mangoTint, .mangoTint.opacity(0)], center: .center, startRadius: 0, endRadius: 230)
                .frame(width: 460, height: 460)
                .offset(x: 170, y: 360)

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.canvas)
                        .frame(width: 104, height: 104)
                        .shadow(color: Color(rgb: 0x825028).opacity(0.16), radius: 24, y: 12)
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 2)
                        .frame(width: 74, height: 74)
                    Circle()
                        .fill(LinearGradient(colors: [.tomato, .mango], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                }
                VStack(spacing: 6) {
                    Text("Plated")
                        .font(.gabarito(42, .extraBold))
                        .tracking(-1)
                        .foregroundStyle(Color.ink)
                    Text("Set the table.")
                        .font(.jakarta(15, .medium))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .scaleEffect(settled ? 1 : 0.86)
            .opacity(settled ? 1 : 0)

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill([Color.tomato, .mango, .basil][index])
                            .frame(width: 8, height: 8)
                            .opacity(pulse ? 1 : 0.25)
                            .animation(
                                .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                                value: pulse
                            )
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.plSettle) { settled = true }
            pulse = true
        }
    }
}
