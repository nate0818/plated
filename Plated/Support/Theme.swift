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

    /// One token, two rooms. Light is the white tablecloth; dark is After
    /// Dark — warm espresso black, chosen in Home, never system-decided.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let value = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    // Chrome
    static let canvas         = Color(light: 0xFFFFFF, dark: 0x16120E)
    static let ink            = Color(light: 0x221B14, dark: 0xF4EDE3)
    static let inkSecondary   = Color(light: 0x8A8074, dark: 0xA79B8B)
    static let inkFaint       = Color(light: 0xB5AC9E, dark: 0x6B6157)
    static let hairline       = Color(light: 0xF0EBE4, dark: 0x2B241C)   // card borders
    static let hairlineSoft   = Color(light: 0xF7F3EE, dark: 0x231D17)   // row separators
    static let hairlineDashed = Color(light: 0xEFE7DD, dark: 0x342C22)   // empty-state dashes
    static let navHairline    = Color(light: 0xEFECE7, dark: 0x2D261E)   // floating bar edge
    static let fill           = Color(light: 0xF4F1EC, dark: 0x282119)   // neutral avatar / wells
    static let chipFill       = Color(light: 0xF7F5F1, dark: 0x241E17)   // link chips
    static let raisedFill     = Color(light: 0xFFFFFF, dark: 0x362E24)   // the lifted pill inside a well

    // Earned color — lifted a touch after dark so it still lands
    static let tomato         = Color(light: 0xFF5A3C, dark: 0xF75434)   // dark value keeps white labels ≥3:1
    /// THE label color on tomato, both rooms — tomato's dark value is tuned
    /// for white (≥3:1, above). Never canvas, never a bare .white literal.
    static let onTomato       = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let tomatoPressed  = Color(light: 0xD6401F, dark: 0xD6401F)   // pressed always darkens
    static let mango          = Color(light: 0xFFB020, dark: 0xFFB63A)   // the chef's kiss only
    static let basil          = Color(light: 0x3DA35D, dark: 0x55BE76)   // progress, "seated"
    static let amber          = Color(light: 0xC88A00, dark: 0xE3A83C)
    static let grape          = Color(light: 0xB95CF4, dark: 0xC98BF7)

    // Tints — avatar and chip washes, one per person color
    static let tomatoTint     = Color(light: 0xFFEDE3, dark: 0x39241C)
    static let basilTint      = Color(light: 0xEDF5EF, dark: 0x1F2E24)
    static let mangoTint      = Color(light: 0xFFF4DC, dark: 0x332A15)
    static let grapeTint      = Color(light: 0xF5EDFB, dark: 0x2E2138)
    static let todayTint      = Color(light: 0xFFF7F0, dark: 0x2A1D16)   // today cell in cook grid

    // Shadow inks — warm brown on white, true black after dark
    static let shadowInk      = Color(light: 0x3C3228, dark: 0x000000)
    static let shadowWarm     = Color(light: 0x825028, dark: 0x000000)

    // Kept for DishView's generative palette families
    static let cardFill       = Color(light: 0xFFFFFF, dark: 0x1E1913)
    static let copper         = Color(light: 0xA5622F, dark: 0xC97F4A)
    static let successTone    = Color(light: 0x3DA35D, dark: 0x55BE76)
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
    // Stored generators stay warm — a fresh generator per call pays
    // first-fire latency on every single tap.
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()
    private static let selector = UISelectionFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func plate() { medium.impactOccurred() }
    static func kiss() { notice.notificationOccurred(.success) }
    /// The tick of moving between options — chips, toggles, segments,
    /// drag targets. Quieter than a tap; it marks position, not action.
    static func select() { selector.selectionChanged() }
    /// Something didn't take — a denied permission, a failed export.
    static func warn() { notice.notificationOccurred(.warning) }
}

// MARK: - Press feedback

/// The house press state: everything tappable gives a little under the
/// finger. Quiet by design — no color, no shadow change, just the object
/// yielding — so it layers safely under any label, bounce, or spin the
/// button already owns. This replaces `.plain` as the default dress for
/// custom buttons; `.plain` alone is a dead surface.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.plSnap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Floating chrome

enum Layout {
    /// Where the perch sits and how big it is — the tab bar's own bottom
    /// padding (4) plus its height (68) plus a 12pt gap.
    static let perchBottom: CGFloat = 84
    static let perchHeight: CGFloat = 50

    /// How much room the floating chrome needs at the bottom of a scroll.
    /// Derived, not typed: a hand-written constant drifted 6pt short of
    /// the chrome it was supposed to clear the first time.
    static let floatingChromeInset: CGFloat = perchBottom + perchHeight + 8
}

/// A slow ambient breath for empty-state glyphs — the room is set and
/// waiting, not dead. Sits out under Reduce Motion.
private struct PLBreathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { view, up in
                view
                    .scaleEffect(up ? 1.05 : 1)
                    .opacity(up ? 1 : 0.9)
            } animation: { _ in .easeInOut(duration: 2.4) }
        }
    }
}

extension View {
    func plBreathing() -> some View { modifier(PLBreathing()) }
}

// MARK: - Shadows

/// Black at light-mode opacities is invisible on espresso — dark elevation
/// needs a real boost, so the modifiers read the room.
private struct PLShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let lightOpacity: Double
    let darkOpacity: Double
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content.shadow(
            color: Color.shadowInk.opacity(scheme == .dark ? darkOpacity : lightOpacity),
            radius: radius, y: y
        )
    }
}

extension View {
    /// Cards and photo tiles: 0 8 24 @ 10%, deepened after dark.
    func plCardShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.10, darkOpacity: 0.45, radius: 12, y: 8))
    }
    /// Floating chrome (nav pill, + button): 0 12 32 @ 8%.
    func plFloatShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.08, darkOpacity: 0.5, radius: 16, y: 12))
    }
    /// Dish circles: 0 4 12 @ 14%.
    func plDishShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.14, darkOpacity: 0.5, radius: 6, y: 4))
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
            .foregroundStyle(Color.onTomato)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(TomatoPillStyle())
    }
}

/// The quiet sibling of the tomato pill — for the screen's committing action
/// when the tomato budget is already spent (e.g. a reaction at rest).
struct InkPillButton: View {
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
            .foregroundStyle(Color.canvas)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(InkPillStyle())
    }
}

private struct InkPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.ink.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
            .plFloatShadow()
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.plSnap, value: configuration.isPressed)
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
