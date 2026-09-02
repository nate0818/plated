import SwiftUI
import CoreText

// MARK: - Brand faces
// Gabarito carries display type (titles, date numerals, the wordmark);
// Plus Jakarta Sans carries everything else. Both ship as variable TTFs in
// Resources/Fonts and are registered at launch — no Info.plist entries needed.

enum BrandFonts {
    private static var registered = false

    static func registerAll() {
        guard !registered else { return }
        registered = true
        for name in ["Gabarito", "PlusJakartaSans"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered is fine (previews, tests); anything else is loud.
                let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) }
                if code != CTFontManagerError.alreadyRegistered.rawValue &&
                    code != CTFontManagerError.duplicatedName.rawValue {
                    assertionFailure("Font registration failed for \(name): \(String(describing: error))")
                }
            }
        }
    }
}

extension Font {
    enum GabaritoWeight: String {
        case regular = "Gabarito-Regular"
        case medium = "Gabarito-Regular_Medium"
        case semibold = "Gabarito-Regular_SemiBold"
        case bold = "Gabarito-Regular_Bold"
        case extraBold = "Gabarito-Regular_ExtraBold"
    }

    enum JakartaWeight: String {
        case regular = "PlusJakartaSans-Regular"
        case medium = "PlusJakartaSans-Regular_Medium"
        case semibold = "PlusJakartaSans-Regular_SemiBold"
        case bold = "PlusJakartaSans-Regular_Bold"
        case extraBold = "PlusJakartaSans-Regular_ExtraBold"
    }

    /// Raw sizes. Prefer `.plType(_:)` — see `TypeScale` below for why.
    ///
    /// These stay reachable because a handful of places genuinely need an
    /// arbitrary size: the launch opener's authored scene maths, and any
    /// glyph sized to match a specific piece of text. Everything that is
    /// simply *text on a screen* should be going through the scale.
    static func gabarito(_ size: CGFloat, _ weight: GabaritoWeight = .bold) -> Font {
        .custom(weight.rawValue, size: size)
    }

    static func jakarta(_ size: CGFloat, _ weight: JakartaWeight = .regular) -> Font {
        .custom(weight.rawValue, size: size)
    }
}

// MARK: - The type scale

/// Nine steps, and the reason they exist.
///
/// Before this the app shipped **48 distinct size-and-weight combinations**
/// across 332 call sites: Jakarta at 9, 9.5, 10, 11, 11.5, 12, 13, 14, 15,
/// 16 and 17, Gabarito at 13, 14, 17, 19, 20, 21, 22, 24, 25, 26, 27 and 32.
/// Every whole number from 9 to 17 was in use.
///
/// That is not a scale, it is a slider, and it is the single loudest signal
/// that nobody decided. A person choosing type picks seven or eight sizes
/// and lives inside them; 48 combinations is what happens when each screen
/// is tuned alone. It is invisible on any one screen and unmistakable
/// across an app, which is exactly the quality of "looks generated".
///
/// Three things ride along that no call site can get right by hand:
///
/// **Tracking is derived from size, in em.** Eleven absolute point values
/// shipped, so identical intent produced different optical results: −0.8 at
/// 32pt is −0.025em, −0.3 at 25pt is −0.012em. `MicroLabel` was tracked
/// 1.0pt at 12pt, which is 83/1000 em, roughly 40% looser than the 40–60
/// range tracked uppercase actually wants — the app's sixty micro-labels
/// all read as letters drifting apart.
///
/// **Line height is set, not defaulted.** Display sizes want tighter
/// leading than body; leaving both to the system leaves headlines airy and
/// paragraphs cramped.
///
/// **Dynamic Type works.** There was not one `relativeTo:` in the codebase.
/// Every step is anchored to a system text style, so the app finally
/// responds to the setting most people who need it have already turned on.
enum TypeScale {
    /// All-caps meta and the quietest labels. `MicroLabel` is this.
    case micro
    /// Supporting text under a title; the second voice.
    case caption
    /// Secondary body: taglines, row subtitles.
    case footnote
    /// Default reading text and row titles.
    case body
    /// Buttons and anything that must be read at arm's length.
    case callout
    /// Section and sheet headings. Gabarito starts here.
    case heading
    /// Screen titles.
    case title
    /// Big numerals and mastheads.
    case display
    /// The opener, and nothing else.
    case hero

    var isDisplay: Bool {
        switch self {
        case .heading, .title, .display, .hero: return true
        default: return false
        }
    }

    var size: CGFloat {
        switch self {
        case .micro: return 11
        case .caption: return 12
        case .footnote: return 13
        case .body: return 15
        case .callout: return 17
        case .heading: return 20
        case .title: return 23
        case .display: return 27
        case .hero: return 32
        }
    }

    /// Which family draws this step by default. Overridable at the call
    /// site for the rare small numeral that wants Gabarito, or the rare
    /// large label that wants Jakarta.
    var defaultFamily: TypeFamily { isDisplay ? .display : .text }

    /// Tracking as a fraction of the size, applied as points at use.
    ///
    /// Large type needs negative tracking to stop looking loose; small
    /// uppercase needs positive to stop looking cramped. The one number
    /// that matters here is `micro`: 0.05em, not the 0.083em the app was
    /// shipping.
    var trackingEm: CGFloat {
        switch self {
        case .micro: return 0.05
        case .caption: return 0.005
        case .footnote: return 0
        case .body: return -0.002
        case .callout: return -0.008
        case .heading: return -0.014
        case .title: return -0.018
        case .display: return -0.022
        case .hero: return -0.025
        }
    }

    /// Extra leading beyond the font's own. Display type sets tight; body
    /// wants air so a wrapped sentence stays readable.
    var lineSpacing: CGFloat {
        switch self {
        case .micro, .caption: return 1
        case .footnote, .body: return 3
        case .callout: return 2
        case .heading, .title: return 0
        case .display, .hero: return -1
        }
    }

    /// The system style this step scales against under Dynamic Type.
    var relativeTo: Font.TextStyle {
        switch self {
        case .micro: return .caption2
        case .caption: return .caption
        case .footnote: return .footnote
        case .body: return .subheadline
        case .callout: return .callout
        case .heading: return .title3
        case .title: return .title2
        case .display: return .title
        case .hero: return .largeTitle
        }
    }
}

/// The five weights, spoken once rather than per family.
enum TypeWeight {
    case regular, medium, semibold, bold, extraBold

    var gabarito: Font.GabaritoWeight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .extraBold: return .extraBold
        }
    }

    var jakarta: Font.JakartaWeight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .extraBold: return .extraBold
        }
    }
}

/// Gabarito carries display, Plus Jakarta carries text. Named so a call
/// site can say which when the step's default is not what it wants.
enum TypeFamily { case display, text }

private struct PLTypeModifier: ViewModifier {
    let style: TypeScale
    let weight: TypeWeight
    let family: TypeFamily

    func body(content: Content) -> some View {
        let size = style.size
        let font: Font = family == .display
            ? .custom(weight.gabarito.rawValue, size: size, relativeTo: style.relativeTo)
            : .custom(weight.jakarta.rawValue, size: size, relativeTo: style.relativeTo)
        return content
            .font(font)
            .tracking(size * style.trackingEm)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    /// Type, with its tracking, leading and Dynamic Type attached.
    ///
    /// Each step carries a sensible default weight, so most call sites are
    /// just `.plType(.body)`. Pass a weight only where the emphasis is the
    /// point.
    func plType(_ style: TypeScale, _ weight: TypeWeight? = nil,
                family: TypeFamily? = nil) -> some View {
        let resolved: TypeWeight = weight ?? {
            switch style {
            case .micro: return .bold
            case .caption, .footnote: return .medium
            case .body: return .semibold
            case .callout: return .bold
            case .heading, .title, .display: return .semibold
            case .hero: return .extraBold
            }
        }()
        return modifier(PLTypeModifier(style: style, weight: resolved,
                                       family: family ?? style.defaultFamily))
    }
}

// MARK: - Two families in one line

/// Gabarito's capitals are shorter than Plus Jakarta's at the same nominal
/// size, measured from the shipped binaries: cap height 0.6810 em against
/// 0.7450 em. Set them at the same size and the Jakarta is visibly 9.4%
/// taller — which is what the Plan tab's date card does, Gabarito numeral
/// beside Jakarta weekday, and what every `CountBlock` does.
///
/// Multiply the Gabarito size by this when the two must align on a baseline
/// or share an optical weight. Do not apply it when Gabarito stands alone;
/// the scale is already tuned for that.
enum CapHeight {
    static let gabarito: CGFloat = 0.6810
    static let jakarta: CGFloat = 0.7450
    /// 1.094
    static let gabaritoToJakarta: CGFloat = jakarta / gabarito

    /// SF Symbols are cap-matched to SF Pro (0.7046 em), so a glyph beside
    /// Jakarta wants slightly more and beside Gabarito slightly less. Every
    /// glyph-next-to-text pair in the app was off by roughly 6%.
    static let sfPro: CGFloat = 0.7046
    static let sfToJakarta: CGFloat = jakarta / sfPro      // 1.057
    static let sfToGabarito: CGFloat = gabarito / sfPro    // 0.967
}

extension Font {
    /// A Gabarito face whose capitals match Jakarta at `size`.
    static func gabaritoMatching(_ size: CGFloat, _ weight: GabaritoWeight = .semibold) -> Font {
        .custom(weight.rawValue, size: size * CapHeight.gabaritoToJakarta)
    }

    /// An SF Symbol sized so its cap height matches the text beside it.
    static func symbolMatching(_ size: CGFloat, _ weight: Font.Weight = .semibold,
                               display: Bool = false) -> Font {
        .system(size: size * (display ? CapHeight.sfToGabarito : CapHeight.sfToJakarta),
                weight: weight)
    }
}
