import SwiftUI

extension Color {
    /// Builds a color from a 6-digit hex string, with or without a leading `#`.
    /// Falls back to the app accent color on malformed input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .accentColor
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Palette offered when creating a household member.
    static let memberPalette = [
        "C86629", "2E7D6B", "7A4EA8", "B23A48", "3D6FB4", "C9962B", "4F7942", "A2547E"
    ]
}
