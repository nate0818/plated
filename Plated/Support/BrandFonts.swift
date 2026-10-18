import SwiftUI
import CoreText

/// Newsreader sets the editorial voice; DM Sans keeps controls and prose direct.
enum BrandFonts {
    private static var registered = false

    static func registerAll() {
        guard !registered else { return }
        for name in ["Newsreader", "DMSans"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
                if code != CTFontManagerError.alreadyRegistered.rawValue && code != CTFontManagerError.duplicatedName.rawValue {
                    assertionFailure("Font registration failed for \(name): \(String(describing: error))")
                }
            }
        }
        registered = true
    }
}

extension Font {
    enum EditorialWeight: String {
        case regular, medium, semibold, bold, extraBold
        // Newsreader's light strokes supply hierarchy through size, not heavy ink.
        var face: String { self == .regular ? "Newsreader16pt-Regular" : "NewsreaderRoman-Medium" }
    }
    enum SansWeight: String {
        case regular = "DMSans-9ptRegular_Regular"
        case medium = "DMSans-9ptRegular_Medium"
        case semibold = "DMSans-9ptRegular_SemiBold"
        case bold = "DMSans-9ptRegular_Bold"
        case extraBold = "DMSans-9ptRegular_ExtraBold"
    }
    static func editorial(_ size: CGFloat, _ weight: EditorialWeight = .regular) -> Font {
        .custom(weight.face, size: size)
    }
    static func sans(_ size: CGFloat, _ weight: SansWeight = .regular) -> Font {
        .custom(weight.rawValue, size: size)
    }
}

enum TypeScale {
    case micro, caption, footnote, body, callout, tileTitle, heading, cardTitle, title, pageTitle, featureTitle, display, hero
    var isDisplay: Bool {
        switch self {
        case .tileTitle, .heading, .cardTitle, .title, .pageTitle, .featureTitle, .display, .hero: true
        default: false
        }
    }
    var size: CGFloat {
        switch self {
        case .micro: 11
        case .caption: 12
        case .footnote: 13
        case .body: 15
        case .callout: 16
        case .tileTitle: 20
        case .heading: 23
        case .cardTitle: 27
        case .title: 29
        case .pageTitle: 32
        case .featureTitle: 33
        case .display: 34
        case .hero: 40
        }
    }
    var defaultFamily: TypeFamily { isDisplay ? .display : .text }
    var trackingEm: CGFloat {
        switch self {
        case .micro: 0.08
        case .caption, .footnote, .body: 0
        case .callout: -0.005
        case .tileTitle, .heading: -0.012
        case .cardTitle, .title, .pageTitle, .featureTitle, .display: -0.018
        case .hero: -0.025
        }
    }
    var lineSpacing: CGFloat { isDisplay ? 0 : 3 }
    // A shared scaling curve preserves ordering at every content-size category.
    var relativeTo: Font.TextStyle { .body }
}

#if DEBUG
extension TypeScale {
    static func assertMonotone() {
        let ordered: [TypeScale] = [.micro, .caption, .footnote, .body, .callout, .tileTitle, .heading, .cardTitle, .title, .pageTitle, .featureTitle, .display, .hero]
        let categories: [UIContentSizeCategory] = [.extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge]
        for category in categories {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let metrics = UIFontMetrics(forTextStyle: .body)
            var previous: CGFloat = 0
            for step in ordered {
                let resolved = metrics.scaledValue(for: step.size, compatibleWith: traits)
                assert(resolved > previous, "TypeScale must remain ordered at \(category.rawValue)")
                previous = resolved
            }
        }
    }
}
#endif

enum TypeWeight {
    case regular, medium, semibold, bold, extraBold
    var editorial: Font.EditorialWeight {
        switch self {
        case .regular: .regular
        default: .medium
        }
    }
    var sans: Font.SansWeight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold, .extraBold: .semibold
        }
    }
}

enum TypeFamily { case display, text }

private struct PLTypeModifier: ViewModifier {
    let style: TypeScale
    let weight: TypeWeight
    let family: TypeFamily
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        let font: Font = family == .display
            ? .custom(weight.editorial.face, size: style.size, relativeTo: style.relativeTo)
            : .custom(weight.sans.rawValue, size: style.size, relativeTo: style.relativeTo)
        content.font(font)
            .tracking(style.size * scale * style.trackingEm)
            .lineSpacing(style.lineSpacing * scale)
    }
}

extension View {
    func plType(_ style: TypeScale, _ weight: TypeWeight? = nil, family: TypeFamily? = nil) -> some View {
        let resolved: TypeWeight = weight ?? {
            switch style {
            case .micro, .callout: .semibold
            case .caption, .footnote, .body: .regular
            default: .regular
            }
        }()
        return modifier(PLTypeModifier(style: style, weight: resolved, family: family ?? style.defaultFamily))
    }
}

/// Cap heights measured from the bundled files at 16 points.
enum CapHeight {
    static let editorial: CGFloat = 0.67
    static let sans: CGFloat = 0.70
    static let editorialToSans: CGFloat = sans / editorial
    static let sfPro: CGFloat = 0.7046
    static let sfToSans: CGFloat = sans / sfPro
    static let sfToEditorial: CGFloat = editorial / sfPro
}

extension Font {
    static func editorialMatching(_ size: CGFloat, _ weight: EditorialWeight = .regular) -> Font {
        .custom(weight.face, size: size * CapHeight.editorialToSans)
    }
    static func symbolMatching(_ size: CGFloat, _ weight: Font.Weight = .regular, display: Bool = false) -> Font {
        .system(size: size * (display ? CapHeight.sfToEditorial : CapHeight.sfToSans), weight: weight)
    }
}
