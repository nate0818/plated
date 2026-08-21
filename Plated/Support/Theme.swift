import SwiftUI

// MARK: - Palette
// Semantic tokens only — no raw hex anywhere else in the app.
// Dark mode is warmer, not inverted (see docs/design-spec.md).

extension Color {
    private init(light: UInt32, dark: UInt32) {
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

    // Core
    static let canvas       = Color(light: 0xFAF5EC, dark: 0x191511)
    static let cardFill     = Color(light: 0xFFFFFF, dark: 0x231E18)
    static let ink          = Color(light: 0x2C241C, dark: 0xF3EDE3)
    static let inkSecondary = Color(light: 0x6E6459, dark: 0xA99E90)
    static let inkTertiary  = Color(light: 0x9C9184, dark: 0x6B6157)
    static let hairline     = Color(light: 0xE9E1D3, dark: 0x372F26)
    static let tomato       = Color(light: 0xBE3A2B, dark: 0xE5765F)

    // Slot accents — tags, dots, tint washes only; never large fills.
    static let honey        = Color(light: 0xB47816, dark: 0xE7B75C)
    static let basil        = Color(light: 0x5F7A3D, dark: 0x9DB268)
    static let copper       = Color(light: 0xA5622F, dark: 0xD9A054)
    static let mulledWine   = Color(light: 0x8E4A54, dark: 0xC98392)

    // Semantic
    static let warningTone  = Color(light: 0xB45309, dark: 0xF0A24F)
    static let successTone  = Color(light: 0x3E6B4A, dark: 0x7FA98B)

    // Ink field — the dark band that always means "done / collected".
    static let inkWell      = Color(light: 0x241C14, dark: 0x100D0A)
    static let inkWellText  = Color(light: 0xF3EDE3, dark: 0xF3EDE3)

    /// Tone-on-tone chip wash: 12% of the color over the local surface.
    func wash(over surface: Color = .canvas) -> Color {
        self.mix(with: surface, by: 0.88)
    }
}

extension MealSlot {
    var tone: Color {
        switch self {
        case .breakfast: return .honey
        case .lunch: return .basil
        case .snack: return .copper
        case .dinner: return .mulledWine
        }
    }
}

// MARK: - Scales

enum Radius {
    static let chip: CGFloat = 10
    static let control: CGFloat = 14
    static let card: CGFloat = 16
    static let hero: CGFloat = 20
    static let sheet: CGFloat = 28
}

extension Animation {
    static let appSnappy = Animation.snappy(duration: 0.25)
    static let appSmooth = Animation.smooth(duration: 0.35)
    static let appBouncy = Animation.bouncy(duration: 0.45, extraBounce: 0.1)
}

// MARK: - Typography
// Two voices, strictly cast: New York serif for food and editorial moments,
// SF Pro for everything functional. A serif button is a firing offense.

extension Font {
    /// New York 34 semibold — "Tonight", greetings.
    static let heroTitle = Font.system(.largeTitle, design: .serif, weight: .semibold)
    /// New York 28 semibold — screen titles.
    static let screenTitle = Font.system(.title, design: .serif, weight: .semibold)
    /// New York 20 semibold — card/recipe titles.
    static let cardTitle = Font.system(.title3, design: .serif, weight: .semibold)
    /// New York 24 semibold — title overlaid on the Today card.
    static let heroCardTitle = Font.system(.title2, design: .serif, weight: .semibold)
    /// New York 56 semibold — big stat numerals in the Insights ledger.
    static let statNumeral = Font.system(size: 56, weight: .semibold, design: .serif)
    /// New York 54 semibold — the masthead word at the top of every screen.
    static let masthead = Font.system(size: 54, weight: .semibold, design: .serif)
    static let mastheadCompact = Font.system(size: 44, weight: .semibold, design: .serif)
    /// New York 20 — date numerals in the week rows.
    static let dayNumeral = Font.system(.title3, design: .serif, weight: .semibold)
}

/// SF 12 semibold, uppercase, tracked — "THIS WEEK", "PRODUCE".
struct Eyebrow: View {
    let text: String
    var color: Color = .inkSecondary

    init(_ text: String, color: Color = .inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .fontWidth(.condensed)
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// The masthead every screen opens with: condensed eyebrow, one serif word
/// at 54pt breaking left, one flush-right datum. The type is the menu.
struct Masthead<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(eyebrow)
            HStack(alignment: .lastTextBaseline) {
                ViewThatFits(in: .horizontal) {
                    Text(title).font(.masthead)
                    Text(title).font(.mastheadCompact)
                }
                .foregroundStyle(Color.ink)
                Spacer()
                trailing
            }
        }
    }
}

// MARK: - Card recipe
// One elevation story for the whole app: white card, hairline, two faint
// shadow layers in light mode; a lighter surface step in dark mode.

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    var radius: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(Color.cardFill, in: shape)
            .overlay(
                shape.strokeBorder(
                    scheme == .dark ? Color.white.opacity(0.06) : .hairline,
                    lineWidth: 1 / displayScale
                )
            )
            .shadow(
                color: .black.opacity(scheme == .dark ? 0 : (elevated ? 0.06 : 0)),
                radius: 20, y: 8
            )
            .shadow(
                color: .black.opacity(scheme == .dark ? 0 : 0.05),
                radius: 2, y: 1
            )
    }
}

extension View {
    /// The global card recipe. `elevated` adds the ambient layer (hero cards).
    func cardSurface(radius: CGFloat = Radius.card, elevated: Bool = false) -> some View {
        modifier(CardSurface(radius: radius, elevated: elevated))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(scheme == .dark ? Color(red: 0.10, green: 0.08, blue: 0.07) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                (configuration.isPressed ? Color.tomato.mix(with: .black, by: 0.12) : .tomato).gradient,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Color.ink.opacity(configuration.isPressed ? 0.09 : 0.05),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Whole-card press affordance: scale 0.985, no highlight.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Chips

/// Tone-on-tone capsule: 12% wash fill, full-strength text. Never white-on-color.
struct SlotChip: View {
    let slot: MealSlot
    var label: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: slot.symbolName)
                .font(.system(size: 10, weight: .medium))
            Text(label ?? slot.title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(slot.tone)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(slot.tone.wash(), in: Capsule())
    }
}

struct WarningPill: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.warningTone)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.warningTone.wash(), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Progress ring
// Small ring motif shared by Plan ("5 of 7 dinners") and Grocery ("14 of 23").

struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 24
    var tone: Color = .tomato

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.hairline, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tone, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.appSmooth, value: progress)
        }
        .frame(width: size, height: size)
    }
}

