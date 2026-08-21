import SwiftUI

// MARK: - Palette · "quiet chrome, earned color"
// Chrome is near-monochrome so every family's photos carry the color.
// Tomato appears only when something good happens: the + button, a plate
// reaction landing, the chef's kiss. Never as ambient decoration.

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255
        )
    }

    // Chrome
    static let canvas         = Color(rgb: 0xFFFFFF)
    static let ink            = Color(rgb: 0x221B14)
    static let inkSecondary   = Color(rgb: 0x8A8074)
    static let inkFaint       = Color(rgb: 0xB5AC9E)
    static let hairline       = Color(rgb: 0xF0EBE4)   // card borders
    static let hairlineSoft   = Color(rgb: 0xF7F3EE)   // row separators
    static let hairlineDashed = Color(rgb: 0xEFE7DD)   // empty-state dashes
    static let navHairline    = Color(rgb: 0xEFECE7)   // floating bar edge
    static let fill           = Color(rgb: 0xF4F1EC)   // neutral avatar / wells
    static let chipFill       = Color(rgb: 0xF7F5F1)   // link chips

    // Earned color
    static let tomato         = Color(rgb: 0xFF5A3C)
    static let tomatoPressed  = Color(rgb: 0xD6401F)
    static let mango          = Color(rgb: 0xFFB020)   // the chef's kiss only
    static let basil          = Color(rgb: 0x3DA35D)   // progress, "seated"
    static let amber          = Color(rgb: 0xC88A00)
    static let grape          = Color(rgb: 0xB95CF4)

    // Tints — avatar and chip washes, one per person color
    static let tomatoTint     = Color(rgb: 0xFFEDE3)
    static let basilTint      = Color(rgb: 0xEDF5EF)
    static let mangoTint      = Color(rgb: 0xFFF4DC)
    static let grapeTint      = Color(rgb: 0xF5EDFB)
    static let todayTint      = Color(rgb: 0xFFF7F0)   // today cell in cook grid

    // Kept for DishView's generative palette families
    static let cardFill       = Color(rgb: 0xFFFFFF)
    static let copper         = Color(rgb: 0xA5622F)
    static let successTone    = Color(rgb: 0x3DA35D)
}

// MARK: - Person palette
// Fixed (tint, tone) pairs so avatars match everywhere. Chosen by the stored
// colorHex; anything unknown falls back to the neutral pair.

struct PersonTone: Equatable {
    let tint: Color
    let tone: Color

    static let tomatoPair  = PersonTone(tint: .tomatoTint, tone: .tomato)
    static let basilPair   = PersonTone(tint: .basilTint, tone: .basil)
    static let amberPair   = PersonTone(tint: .mangoTint, tone: .amber)
    static let grapePair   = PersonTone(tint: .grapeTint, tone: .grape)
    static let neutralPair = PersonTone(tint: .fill, tone: .ink)

    static func from(hex: String) -> PersonTone {
        switch hex.uppercased() {
        case "FF5A3C": return .tomatoPair
        case "3DA35D": return .basilPair
        case "C88A00": return .amberPair
        case "B95CF4": return .grapePair
        default:       return .neutralPair
        }
    }

    /// Assignment order for new household members and seats.
    static let rotation: [String] = ["FF5A3C", "3DA35D", "C88A00", "B95CF4"]
}

extension HouseholdMember {
    var tone: PersonTone { PersonTone.from(hex: colorHex) }
}

// MARK: - Scales

enum Radius {
    static let chip: CGFloat = 16
    static let row: CGFloat = 18
    static let card: CGFloat = 20
    static let hero: CGFloat = 24
    static let sheet: CGFloat = 28
}

// MARK: - Motion
// One overshoot spring everywhere — the SwiftUI twin of the canvas's
// cubic-bezier(0.34, 1.56, 0.64, 1) at 0.28–0.32s.

extension Animation {
    /// Icon and reaction bounce.
    static let plPop = Animation.spring(response: 0.32, dampingFraction: 0.55)
    /// State changes without theater.
    static let plSnap = Animation.spring(response: 0.28, dampingFraction: 0.75)
    /// Sheets, splash, big arrivals.
    static let plSettle = Animation.spring(response: 0.55, dampingFraction: 0.8)
}

// MARK: - Haptics
// Sound-free fun: light on chrome, medium when a plate lands, a full
// success tap when the kiss is earned.

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func plate() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func kiss() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - Shadows

extension View {
    /// Cards and photo tiles: 0 8 24 @ 10%.
    func plCardShadow() -> some View {
        shadow(color: Color(rgb: 0x3C3228).opacity(0.10), radius: 12, y: 8)
    }
    /// Floating chrome (nav pill, + button): 0 12 32 @ 8%.
    func plFloatShadow() -> some View {
        shadow(color: Color(rgb: 0x3C3228).opacity(0.08), radius: 16, y: 12)
    }
    /// Dish circles: 0 4 12 @ 14%.
    func plDishShadow() -> some View {
        shadow(color: Color(rgb: 0x3C3228).opacity(0.14), radius: 6, y: 4)
    }
}

// MARK: - Shared atoms

/// The tracked micro-label above titles: "AUGUST 21–27", "WHO COOKS WHEN".
struct MicroLabel: View {
    let text: String
    var color: Color = .inkFaint

    init(_ text: String, color: Color = .inkFaint) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.jakarta(12, .bold))
            .tracking(1.0)
            .foregroundStyle(color)
    }
}

/// Initials in a tinted circle — people are circles, like dishes.
struct AvatarCircle: View {
    let initials: String
    let tone: PersonTone
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(tone.tint)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.jakarta(size * 0.38, .bold))
                    .foregroundStyle(tone.tone)
            }
    }
}

/// The full-width tomato pill — reserved for the one committing action
/// on a screen. Anything less takes the ink or outline pill.
struct TomatoPillButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title).font(.jakarta(17, .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(TomatoPillStyle())
    }
}

private struct TomatoPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.tomatoPressed : Color.tomato, in: Capsule())
            .plFloatShadow()
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.plSnap, value: configuration.isPressed)
    }
}
