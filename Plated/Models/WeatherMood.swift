import Foundation

/// A coarse bucket for "what kind of day is it", used to match a forecast to
/// dishes. Deliberately small — the point is a nudge, not a taxonomy.
enum WeatherMood: String, Codable, CaseIterable, Identifiable {
    case cold          // soups, stews, braises, chili
    case cool          // roasts, bakes, pasta
    case mild          // anything goes
    case warm          // salads, bowls, lighter plates
    case hot           // no-cook, cold noodles, grilling outside
    case rainy         // comfort food
    case grillWeather  // clear and warm enough to cook outdoors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cold: return "Cold day"
        case .cool: return "Cool day"
        case .mild: return "Mild day"
        case .warm: return "Warm day"
        case .hot: return "Hot day"
        case .rainy: return "Rainy day"
        case .grillWeather: return "Grill weather"
        }
    }

    var symbolName: String {
        switch self {
        case .cold: return "thermometer.snowflake"
        case .cool: return "wind"
        case .mild: return "cloud.sun"
        case .warm: return "sun.max"
        case .hot: return "thermometer.sun"
        case .rainy: return "cloud.rain"
        case .grillWeather: return "flame"
        }
    }

    /// Maps a high temperature in Fahrenheit and a precipitation chance onto a mood.
    static func from(highF: Double, precipitationChance: Double, isClear: Bool) -> WeatherMood {
        if precipitationChance >= 0.5 { return .rainy }
        switch highF {
        case ..<40: return .cold
        case 40..<58: return .cool
        case 58..<75: return isClear ? .grillWeather : .mild
        case 75..<88: return .warm
        default: return .hot
        }
    }
}
