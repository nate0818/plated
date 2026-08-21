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

    static func gabarito(_ size: CGFloat, _ weight: GabaritoWeight = .bold) -> Font {
        .custom(weight.rawValue, size: size)
    }

    static func jakarta(_ size: CGFloat, _ weight: JakartaWeight = .regular) -> Font {
        .custom(weight.rawValue, size: size)
    }
}
