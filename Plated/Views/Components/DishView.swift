import SwiftUI
import CoreImage

// MARK: - The generative plate engine
// Every piece of food in Plated renders as a circular plated dish: porcelain,
// a well ring, a MeshGradient "food" disc seeded from the recipe's identity,
// and a few garnish marks. Deterministic — the same dish every launch.

// MARK: Seeded RNG (SplitMix64 over an FNV-1a hash of the title)

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private func fnv1a(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}

// MARK: Palette families

struct DishPalette {
    let deep: Color
    let mid: Color
    let bright: Color

    private init(_ deep: UInt32, _ mid: UInt32, _ bright: UInt32) {
        self.deep = Color(rgb: deep)
        self.mid = Color(rgb: mid)
        self.bright = Color(rgb: bright)
    }

    static let ember   = DishPalette(0x5C190D, 0xC7452B, 0xF2B279) // chili, stew, braise
    static let wine    = DishPalette(0x471522, 0x9E3547, 0xEDA47C) // ragù, pasta, tomato
    static let saffron = DishPalette(0x6E4210, 0xDD9C34, 0xF6E3B4) // curry, rice, roast
    static let copper  = DishPalette(0x4C3A1E, 0xA5622F, 0xE8D9A6) // bakes, desserts
    static let basilP  = DishPalette(0x2E4B23, 0x6FA544, 0xEDE289) // salads, greens
    static let sea     = DishPalette(0x16455C, 0x3E8FA8, 0xF2DE8E) // fish, citrus
    static let char_   = DishPalette(0x3B2A22, 0xB4502A, 0xF4A259) // grill, bbq
    static let beet    = DishPalette(0x3E1533, 0x8E3A68, 0xE7B3CB) // fallback

    private static let keywordMap: [(pattern: String, palette: DishPalette)] = [
        ("chili|stew|braise|rib", .ember),
        ("salad|green|herb|pesto|slaw", .basilP),
        ("bolognese|ragù|ragu|pasta|tomato|pizza", .wine),
        ("fish|salmon|shrimp|ceviche|tuna", .sea),
        ("curry|rice|roast|chicken", .saffron),
        ("grill|bbq|char|burger|steak", .char_),
        ("beet|berry|plum", .beet),
        ("chocolate|bake|dessert|cake|cookie", .copper),
    ]

    static func resolve(title: String, tags: [String], moods: [WeatherMood]) -> DishPalette {
        let haystack = (title + " " + tags.joined(separator: " ")).lowercased()
        for entry in keywordMap {
            for word in entry.pattern.split(separator: "|") where haystack.contains(word) {
                return entry.palette
            }
        }
        switch moods.first {
        case .cold: return .ember
        case .rainy: return .wine
        case .cool: return .saffron
        case .mild: return .copper
        case .warm: return .basilP
        case .hot: return .sea
        case .grillWeather: return .char_
        case nil: return .beet
        }
    }
}

// MARK: DishView

struct DishView: View {
    let title: String
    var tags: [String] = []
    var moods: [WeatherMood] = []
    var diameter: CGFloat
    /// Ambient mesh drift — the Plan hero only. One animated mesh per screen.
    var animated: Bool = false

    init(recipe: Recipe, diameter: CGFloat, animated: Bool = false) {
        self.title = recipe.title
        self.tags = recipe.tags
        self.moods = recipe.moods
        self.diameter = diameter
        self.animated = animated
    }

    init(title: String, diameter: CGFloat) {
        self.title = title
        self.diameter = diameter
    }

    private var palette: DishPalette {
        DishPalette.resolve(title: title, tags: tags, moods: moods)
    }

    var body: some View {
        PorcelainBase(diameter: diameter)
            .overlay {
                food
                    .frame(width: diameter * 0.82, height: diameter * 0.82)
                    .clipShape(Circle())
            }
            .overlay {
                if diameter >= 96 {
                    GarnishMarks(seed: fnv1a(title), palette: palette)
                        .frame(width: diameter * 0.78, height: diameter * 0.78)
                        .clipShape(Circle())
                }
            }
            .frame(width: diameter, height: diameter)
            .compositingGroup()
    }

    @ViewBuilder
    private var food: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                mesh(driftPhase: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else if diameter <= 140 {
            mesh(driftPhase: nil).drawingGroup()
        } else {
            mesh(driftPhase: nil)
        }
    }

    private func mesh(driftPhase: TimeInterval?) -> some View {
        var rng = SplitMix64(seed: fnv1a(title))

        // 3×3 grid: corners pinned, interior jittered ±0.15.
        var points: [SIMD2<Float>] = []
        for row in 0..<3 {
            for column in 0..<3 {
                var x = Float(column) / 2
                var y = Float(row) / 2
                let interiorX = column == 1
                let interiorY = row == 1
                if interiorX { x += Float.random(in: -0.15...0.15, using: &rng) }
                if interiorY { y += Float.random(in: -0.15...0.15, using: &rng) }
                points.append(SIMD2(x, y))
            }
        }

        // Ambient drift: two interior points ride an 8-second sine. Hero only.
        if let t = driftPhase {
            let wave = Float(sin(t / 8 * 2 * .pi)) * 0.03
            points[4].x += wave
            points[4].y -= wave
            points[1].y += wave
        }

        // Colors: guaranteed deep pool + bright zone; center never bright.
        var colors: [Color] = [
            palette.bright, palette.bright, palette.bright,
            palette.mid, palette.mid, palette.mid,
            palette.mid, palette.deep, palette.deep,
        ].shuffled(using: &rng)
        if colors[4] == palette.bright {
            let swapIndex = colors.firstIndex(of: palette.mid) ?? 0
            colors.swapAt(4, swapIndex)
        }
        let corners = [0, 2, 6, 8]
        if !corners.contains(where: { colors[$0] == palette.bright }) {
            let brightIndex = colors.firstIndex(of: palette.bright) ?? 0
            colors.swapAt(brightIndex, corners.randomElement(using: &rng) ?? 0)
        }

        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .overlay {
                // Fine grain so the mesh reads as food, not vinyl. A cached
                // Core Image noise tile; swap for a Metal layerEffect once the
                // Metal toolchain is installed.
                GrainOverlay.shared
                    .opacity(0.05)
                    .blendMode(.overlay)
            }
    }
}

// MARK: Grain

private enum GrainOverlay {
    static let shared: Image = {
        let filter = CIFilter(name: "CIRandomGenerator")!
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let rect = CGRect(x: 0, y: 0, width: 256, height: 256)
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: rect) else {
            return Image(uiImage: UIImage())
        }
        return Image(uiImage: UIImage(cgImage: cgImage))
            .resizable()
    }()
}

// MARK: Porcelain + well ring, shared by every plate state

private struct PorcelainBase: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(Color.cardFill)
            .overlay {
                if scheme == .dark {
                    Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                }
            }
            .overlay {
                // The well ring — what makes it read "plate", not "colored circle".
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
                    .frame(width: diameter * 0.86, height: diameter * 0.86)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 20, y: 8)
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 2, y: 1)
    }
}

// MARK: Garnish

private struct GarnishMarks: View {
    let seed: UInt64
    let palette: DishPalette

    var body: some View {
        Canvas { canvas, size in
            var rng = SplitMix64(seed: seed ^ 0xA5A5A5A5)
            let count = Int.random(in: 5...9, using: &rng)
            var placed: [CGPoint] = []
            let minSpacing = size.width * 0.18

            for _ in 0..<count {
                var point = CGPoint.zero
                var attempts = 0
                repeat {
                    let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                    let radius = Double.random(in: 0.1...0.42, using: &rng) * size.width
                    point = CGPoint(
                        x: size.width / 2 + cos(angle) * radius,
                        y: size.height / 2 + sin(angle) * radius
                    )
                    attempts += 1
                } while attempts < 8 && placed.contains(where: {
                    hypot($0.x - point.x, $0.y - point.y) < minSpacing
                })
                placed.append(point)

                let kind = Int.random(in: 0...2, using: &rng)
                let rotation = Angle.degrees(Double.random(in: 0..<360, using: &rng))
                switch kind {
                case 0: // stroked arc
                    let arcRadius = CGFloat.random(in: 10...20, using: &rng)
                    var path = Path()
                    path.addArc(
                        center: point, radius: arcRadius,
                        startAngle: rotation, endAngle: rotation + .degrees(120),
                        clockwise: false
                    )
                    canvas.stroke(path, with: .color(palette.deep.opacity(0.25)), lineWidth: 2)
                case 1: // seed ellipse
                    let w = CGFloat.random(in: 4...8, using: &rng)
                    let rect = CGRect(x: point.x - w / 2, y: point.y - w / 4, width: w, height: w / 2)
                    var context = canvas
                    context.translateBy(x: point.x, y: point.y)
                    context.rotate(by: rotation)
                    context.translateBy(x: -point.x, y: -point.y)
                    context.fill(Path(ellipseIn: rect), with: .color(palette.bright.opacity(0.35)))
                default: // leaf ellipse
                    let w = CGFloat.random(in: 12...20, using: &rng)
                    let rect = CGRect(x: point.x - w / 2, y: point.y - w / 6, width: w, height: w / 3)
                    var context = canvas
                    context.translateBy(x: point.x, y: point.y)
                    context.rotate(by: rotation)
                    context.translateBy(x: -point.x, y: -point.y)
                    context.fill(Path(ellipseIn: rect), with: .color(palette.deep.opacity(0.25)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Plate states — the app's state language

enum PlateState {
    case empty
    case planned(Recipe)
    case cleared
}

struct PlateView: View {
    @Environment(\.displayScale) private var displayScale
    let state: PlateState
    var diameter: CGFloat

    var body: some View {
        switch state {
        case .empty:
            Circle()
                .strokeBorder(Color.inkSecondary.opacity(0.4), lineWidth: 1.5)
                .overlay {
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
                        .frame(width: diameter * 0.86, height: diameter * 0.86)
                }
                .frame(width: diameter, height: diameter)
        case .planned(let recipe):
            DishView(recipe: recipe, diameter: diameter)
        case .cleared:
            PorcelainBase(diameter: diameter)
                .overlay {
                    if diameter >= 22 {
                        Image(systemName: "checkmark")
                            .font(.system(size: max(9, diameter * 0.3), weight: .semibold))
                            .foregroundStyle(Color.successTone)
                    }
                }
                .frame(width: diameter, height: diameter)
        }
    }
}
