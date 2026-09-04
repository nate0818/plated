import SwiftUI

/// Small, articulated objects drawn on a shared 40 × 36 grid. The timeline
/// belongs to the icon, not the destination view, so even the first tap plays.
struct TrayNavigationIcon: View {
    let tab: AppTab
    let active: Bool
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if tab == .cookbook {
            TrayCookbookIcon(active: active, trigger: trigger)
        } else if tab == .groceries {
            TrayGroceriesIcon(active: active, trigger: trigger)
        } else {
            KeyframeAnimator(initialValue: 0.0, trigger: trigger) { progress in
                Canvas { context, size in
                    context.translateBy(x: (size.width - 40) / 2, y: (size.height - 36) / 2)
                    let painter = TrayIconPainter(tone: active ? .canvas : .inkSecondary)
                    let time = reduceMotion ? 0 : progress
                    switch tab {
                    case .week: painter.calendar(context, time)
                    case .cookbook: break // The book keeps its selected pose.
                    case .groceries: break // The basket keeps its selected contents.
                    case .table: painter.placeSetting(context, time)
                    case .home: break // Profile is reached from the masthead.
                    }
                }
            } keyframes: { _ in
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.92)
                MoveKeyframe(0)
            }
            .frame(width: 60, height: 37)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

private struct TrayCookbookIcon: View {
    let active: Bool
    let trigger: Int
    @State private var pageTurnTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Interaction: Equatable {
        let active: Bool
        let trigger: Int
    }

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: pageTurnTrigger) { progress in
            TrayCookbookDrawing(opening: active ? 1 : 0,
                                settledOpening: reduceMotion ? (active ? 1 : 0) : nil,
                                pageTurn: reduceMotion ? 0 : progress,
                                tone: active ? .canvas : .inkSecondary)
                .animation(reduceMotion ? nil : .smooth(duration: 0.62), value: active)
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.92)
            MoveKeyframe(0)
        }
        .onChange(of: Interaction(active: active, trigger: trigger)) { previous, current in
            // Opening owns the first selection. An already open book turns
            // a page on re-tap, without snapping its cover shut first.
            if previous.active && current.active && previous.trigger != current.trigger {
                pageTurnTrigger += 1
            }
        }
        .frame(width: 60, height: 37)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct TrayCookbookDrawing: View, Animatable {
    var opening: Double
    let settledOpening: Double?
    let pageTurn: Double
    let tone: Color

    var animatableData: Double {
        get { opening }
        set { opening = newValue }
    }

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: (size.width - 40) / 2, y: (size.height - 36) / 2)
            TrayIconPainter(tone: tone).cookbook(context, pageTurn, opening: settledOpening ?? opening)
        }
    }
}

private struct TrayGroceriesIcon: View {
    let active: Bool
    let trigger: Int
    @State private var settleTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Interaction: Equatable {
        let active: Bool
        let trigger: Int
    }

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: settleTrigger) { progress in
            TrayGroceriesDrawing(filling: active ? 1 : 0,
                                 settledFill: reduceMotion ? (active ? 1 : 0) : nil,
                                 jostle: reduceMotion ? 0 : progress,
                                 tone: active ? .canvas : .inkSecondary)
                .animation(reduceMotion || !active ? nil : .linear(duration: 0.92), value: active)
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.92)
            MoveKeyframe(0)
        }
        .onChange(of: Interaction(active: active, trigger: trigger)) { previous, current in
            // Selection fills an empty basket. Re-tapping gently settles
            // its contents without flashing back to an empty basket.
            if previous.active && current.active && previous.trigger != current.trigger {
                settleTrigger += 1
            }
        }
        .frame(width: 60, height: 37)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct TrayGroceriesDrawing: View, Animatable {
    var filling: Double
    let settledFill: Double?
    let jostle: Double
    let tone: Color

    var animatableData: Double {
        get { filling }
        set { filling = newValue }
    }

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: (size.width - 40) / 2, y: (size.height - 36) / 2)
            TrayIconPainter(tone: tone).basket(context, jostle, filling: settledFill ?? filling)
        }
    }
}

private struct TrayIconPainter {
    let tone: Color
    private let pen = StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)

    private func stroke(_ path: Path, in context: GraphicsContext, opacity: Double = 1) {
        context.stroke(path, with: .color(tone.opacity(opacity)), style: pen)
    }

    private func line(_ points: [CGPoint], in context: GraphicsContext, opacity: Double = 1) {
        stroke(Path { p in p.addLines(points) }, in: context, opacity: opacity)
    }

    /// Smooth local beats, all returning to zero at the end of the tap.
    private func beat(_ time: Double, _ start: Double, _ end: Double) -> Double {
        guard time > start, time < end else { return 0 }
        return sin(.pi * (time - start) / (end - start))
    }

    private func move(_ context: GraphicsContext, center: CGPoint,
                      x: Double = 0, y: Double = 0, angle: Double = 0,
                      scaleX: Double = 1, scaleY: Double = 1) -> GraphicsContext {
        var copy = context
        copy.translateBy(x: center.x + x, y: center.y + y)
        copy.rotate(by: .degrees(angle))
        copy.scaleBy(x: scaleX, y: scaleY)
        copy.translateBy(x: -center.x, y: -center.y)
        return copy
    }

    // A sheet peels up around the calendar rings; a new checked day appears
    // underneath. The rings stay planted while the page turns.
    func calendar(_ context: GraphicsContext, _ t: Double) {
        let lift = beat(t, 0.02, 0.69)
        let body = Path(roundedRect: CGRect(x: 9, y: 7, width: 22, height: 23), cornerRadius: 4)
        stroke(body, in: context)
        line([CGPoint(x: 9, y: 12), CGPoint(x: 31, y: 12)], in: context)
        for x in [15.0, 25.0] {
            line([CGPoint(x: x, y: 4.5), CGPoint(x: x, y: 9)], in: context)
        }
        // The underside is visible as the old page clears it.
        var underneath = context
        underneath.opacity = lift * 0.6
        dayMark(underneath, progress: 1)
        let page = move(context, center: CGPoint(x: 20, y: 12),
                        x: 2 * lift, y: -2 * lift, angle: -9 * lift,
                        scaleY: 1 - 0.87 * lift)
        let sheet = Path(roundedRect: CGRect(x: 10, y: 13.5, width: 20, height: 15), cornerRadius: 2)
        page.fill(sheet, with: .color(tone.opacity(0.13)))
        dayMark(page, progress: 1)
        line([CGPoint(x: 11, y: 28), CGPoint(x: 28, y: 28)], in: page, opacity: 0.45)
    }

    private func dayMark(_ context: GraphicsContext, progress: Double) {
        let check = Path { p in
            p.move(to: CGPoint(x: 15.5, y: 20.5))
            p.addLine(to: CGPoint(x: 19, y: 24))
            p.addLine(to: CGPoint(x: 25, y: 17.5))
        }
        stroke(check.trimmedPath(from: 0, to: progress), in: context)
    }

    // The front cover swings across its spine, revealing the right-hand
    // page, and stays open for the whole selection. Both poses are centered.
    func cookbook(_ context: GraphicsContext, _ t: Double, opening: Double) {
        let amount = min(1, max(0, opening))
        let spine = 11 + 9 * amount
        let width = 18 - 5 * amount
        let edge = spine + width * cos(.pi * amount)
        let book = move(context, center: CGPoint(x: 20, y: 19),
                        y: -sin(.pi * amount), scaleX: 1 + 0.04 * beat(t, 0, 0.62))

        func page(to edge: Double) -> Path {
            Path { p in
                p.move(to: CGPoint(x: spine, y: 7 + 3 * amount))
                p.addQuadCurve(to: CGPoint(x: edge, y: 7 + amount),
                               control: CGPoint(x: (spine + edge) / 2, y: 7 - 2 * amount))
                p.addLine(to: CGPoint(x: edge, y: 29 - 3 * amount))
                p.addQuadCurve(to: CGPoint(x: spine, y: 29),
                               control: CGPoint(x: (spine + edge) / 2, y: 29 - 4 * amount))
                p.closeSubpath()
            }
        }

        let rightPage = page(to: spine + width)
        book.fill(rightPage, with: .color(tone.opacity(0.08)))
        stroke(rightPage, in: book)
        var revealed = book
        revealed.clip(to: Path(CGRect(x: max(spine, edge) + 0.9, y: 5, width: 24, height: 25)))
        for y in [14.0, 18.0] {
            stroke(Path { p in
                p.move(to: CGPoint(x: spine + 3.5, y: y + 1))
                p.addQuadCurve(to: CGPoint(x: spine + width - 3.5, y: y),
                               control: CGPoint(x: spine + width / 2, y: y - 0.5))
            }, in: revealed, opacity: 0.65)
        }

        let cover = page(to: edge)
        book.fill(cover, with: .color(tone.opacity(0.12)))
        stroke(cover, in: book)
        // Cover embossing disappears edge-on; text emerges on its inside.
        var front = book
        front.opacity = max(0, 1 - 2 * amount)
        let fold = cos(.pi * amount)
        line([CGPoint(x: spine + 3 * fold, y: 8), CGPoint(x: spine + 3 * fold, y: 27)], in: front, opacity: 0.55)
        for y in [14.0, 18.0] {
            line([CGPoint(x: spine + 7 * fold, y: y), CGPoint(x: spine + 13 * fold, y: y)], in: front)
        }
        if amount > 0.5 {
            for y in [14.0, 18.0] {
                stroke(Path { p in
                    p.move(to: CGPoint(x: spine + 3.5 * fold, y: y + 1))
                    p.addQuadCurve(to: CGPoint(x: edge - 3.5 * fold, y: y),
                                   control: CGPoint(x: (spine + edge) / 2, y: y - 0.5))
                }, in: book, opacity: 0.65 * (2 * amount - 1))
            }
        }
        // The page riffle is a separate re-tap response. Fade it if the
        // user switches away before it completes.
        var pages = book
        pages.opacity = max(0, 2 * amount - 1)
        if t > 0.14 && t < 0.76 {
            let turn = (t - 0.14) / 0.62
            let edge = 20 + 12 * cos(.pi * turn)
            let leaf = Path { p in
                p.move(to: CGPoint(x: 20, y: 10))
                p.addQuadCurve(to: CGPoint(x: edge, y: 7), control: CGPoint(x: edge, y: 3))
                p.addLine(to: CGPoint(x: edge, y: 25))
                p.addQuadCurve(to: CGPoint(x: 20, y: 29), control: CGPoint(x: edge, y: 24))
                p.closeSubpath()
            }
            pages.fill(leaf, with: .color(tone.opacity(0.18 * sin(.pi * turn))))
            stroke(leaf, in: pages, opacity: sin(.pi * turn))
        }
        let ribbon = move(pages, center: CGPoint(x: 25, y: 24),
                          angle: 18 * beat(t, 0.5, 0.98))
        stroke(Path { p in
            p.addLines([CGPoint(x: 24, y: 24), CGPoint(x: 24, y: 31),
                        CGPoint(x: 26, y: 29.5), CGPoint(x: 28, y: 30.5), CGPoint(x: 28, y: 24)])
        }, in: ribbon)
    }

    // An empty basket folds its handle down, then catches a loaf and an
    // apple in two beats. Contents remain in place for the whole selection.
    func basket(_ context: GraphicsContext, _ t: Double, filling: Double) {
        let amount = min(1, max(0, filling))
        let breadDrop = min(1, max(0, (amount - 0.04) / 0.38))
        let appleDrop = min(1, max(0, (amount - 0.28) / 0.40))
        let breadLanding = beat(amount, 0.42, 0.59)
        let appleLanding = beat(amount, 0.68, 0.87)
        let impact = 0.7 * breadLanding + appleLanding
            - 0.25 * beat(amount, 0.87, 1)
            + amount * (beat(t, 0.4, 0.7) - 0.35 * beat(t, 0.7, 0.96))
        let basket = move(context, center: CGPoint(x: 20, y: 29),
                          scaleX: 1 + 0.07 * impact, scaleY: 1 - 0.11 * impact)
        let handleHeight = 13 * (1 - min(1, amount / 0.24))
        stroke(Path { p in
            p.move(to: CGPoint(x: 11, y: 17))
            p.addCurve(to: CGPoint(x: 29, y: 17),
                       control1: CGPoint(x: 11, y: 17 - handleHeight),
                       control2: CGPoint(x: 29, y: 17 - handleHeight))
        }, in: basket, opacity: 0.75)

        // Accelerating descent, followed by a small landing dip. Items
        // enter slightly smaller so their silhouettes clear the canvas top.
        var loaf = move(context, center: CGPoint(x: 25, y: 14),
                        y: 3 - 8 * (1 - breadDrop * breadDrop) + 0.8 * breadLanding
                            - amount * 3 * beat(t, 0.02, 0.48),
                        angle: -12 * (1 - breadDrop) + amount * 15 * beat(t, 0.02, 0.48),
                        scaleX: 0.75 + 0.25 * breadDrop, scaleY: 0.75 + 0.25 * breadDrop)
        loaf.opacity = min(1, max(0, (amount - 0.04) / 0.06))
        let bread = Path(roundedRect: CGRect(x: 22, y: 4, width: 7, height: 18), cornerRadius: 3.5)
        loaf.fill(bread, with: .color(tone.opacity(0.1)))
        stroke(bread, in: loaf)
        for y in [8.5, 12.5] {
            line([CGPoint(x: 23, y: y + 1), CGPoint(x: 25.5, y: y)], in: loaf, opacity: 0.6)
        }
        var apple = move(context, center: CGPoint(x: 15, y: 15),
                         x: -2 * (1 - appleDrop) - amount * 2 * beat(t, 0.13, 0.6),
                         y: 1 - 8 * (1 - appleDrop * appleDrop) + 1.5 * appleLanding
                            - amount * 4 * beat(t, 0.13, 0.6),
                         angle: 16 * (1 - appleDrop) - amount * 20 * beat(t, 0.13, 0.6),
                         scaleX: 0.82 + 0.18 * appleDrop, scaleY: 0.82 + 0.18 * appleDrop)
        apple.opacity = min(1, max(0, (amount - 0.28) / 0.06))
        stroke(Path { p in
            p.move(to: CGPoint(x: 15, y: 11))
            p.addCurve(to: CGPoint(x: 10, y: 16), control1: CGPoint(x: 9, y: 8), control2: CGPoint(x: 8, y: 13))
            p.addCurve(to: CGPoint(x: 15, y: 21), control1: CGPoint(x: 10, y: 20), control2: CGPoint(x: 13, y: 22))
            p.addCurve(to: CGPoint(x: 20, y: 16), control1: CGPoint(x: 19, y: 23), control2: CGPoint(x: 21, y: 19))
            p.addCurve(to: CGPoint(x: 15, y: 11), control1: CGPoint(x: 23, y: 11), control2: CGPoint(x: 18, y: 9))
        }, in: apple)
        line([CGPoint(x: 15, y: 11), CGPoint(x: 16, y: 7), CGPoint(x: 19, y: 6)], in: apple)
        let bowl = Path { p in
            p.addLines([CGPoint(x: 7, y: 17), CGPoint(x: 10.5, y: 29),
                        CGPoint(x: 29.5, y: 29), CGPoint(x: 33, y: 17)])
            p.closeSubpath()
        }
        // Clear the parts of the produce hidden inside the woven basket.
        var contents = basket
        contents.clip(to: bowl)
        contents.blendMode = .destinationOut
        contents.fill(bowl, with: .color(.ink))
        basket.fill(bowl, with: .color(tone.opacity(0.09)))
        stroke(bowl, in: basket)
        line([CGPoint(x: 6, y: 17), CGPoint(x: 34, y: 17)], in: basket)
        for x in [14.0, 20.0, 26.0] {
            line([CGPoint(x: x, y: 21), CGPoint(x: x, y: 25.5)], in: basket, opacity: 0.65)
        }
    }

    // A place is set: cutlery pulls apart, slides home in two beats, and the
    // plate makes a little settling turn. The rim catches a brief glint.
    func placeSetting(_ context: GraphicsContext, _ t: Double) {
        let arrival = beat(t, 0.01, 0.64)
        let settle = beat(t, 0.58, 0.95)
        let plate = move(context, center: CGPoint(x: 20, y: 18),
                         y: -3 * arrival + 0.8 * settle, angle: -22 * arrival + 7 * settle,
                         scaleX: 1 - 0.14 * arrival, scaleY: 1 - 0.14 * arrival)
        let rim = Path(ellipseIn: CGRect(x: 10.5, y: 8.5, width: 19, height: 19))
        plate.fill(rim, with: .color(tone.opacity(0.08)))
        stroke(rim, in: plate)
        stroke(Path(ellipseIn: CGRect(x: 14.5, y: 12.5, width: 11, height: 11)), in: plate, opacity: 0.65)
        // The asymmetric rim mark makes the plate's rotation perceptible.
        stroke(Path { p in
            p.addArc(center: CGPoint(x: 20, y: 18), radius: 7.3,
                     startAngle: .degrees(205), endAngle: .degrees(243), clockwise: false)
        }, in: plate, opacity: 0.5)
        let forkBeat = beat(t, 0, 0.59)
        let fork = move(context, center: CGPoint(x: 5, y: 19),
                        x: -3 * forkBeat, y: -3 * forkBeat, angle: -17 * forkBeat)
        line([CGPoint(x: 5, y: 16), CGPoint(x: 5, y: 28)], in: fork)
        stroke(Path { p in
            p.move(to: CGPoint(x: 2.5, y: 8))
            p.addLine(to: CGPoint(x: 2.5, y: 13.5))
            p.addQuadCurve(to: CGPoint(x: 7.5, y: 13.5), control: CGPoint(x: 5, y: 19))
            p.addLine(to: CGPoint(x: 7.5, y: 8))
        }, in: fork)
        line([CGPoint(x: 5, y: 8), CGPoint(x: 5, y: 13.5)], in: fork)
        let knifeBeat = beat(t, 0.12, 0.75)
        let knife = move(context, center: CGPoint(x: 34, y: 19),
                         x: 3 * knifeBeat, y: 3 * knifeBeat, angle: 15 * knifeBeat)
        stroke(Path { p in
            p.move(to: CGPoint(x: 35.5, y: 28))
            p.addLine(to: CGPoint(x: 35.5, y: 8))
            p.addQuadCurve(to: CGPoint(x: 32, y: 19), control: CGPoint(x: 30, y: 11))
            p.addLine(to: CGPoint(x: 35.5, y: 19))
        }, in: knife)
        let glint = beat(t, 0.52, 0.94)
        if glint > 0 {
            let shine = move(context, center: CGPoint(x: 28, y: 7), scaleX: glint, scaleY: glint)
            line([CGPoint(x: 28, y: 4), CGPoint(x: 28, y: 10)], in: shine, opacity: glint)
            line([CGPoint(x: 25, y: 7), CGPoint(x: 31, y: 7)], in: shine, opacity: glint)
        }
    }
}

#Preview("Tray icons") {
    @Previewable @State var selection: AppTab = .week
    PlateTabBar(selection: $selection) {}
        .padding(20)
        .background(Color.canvas)
}
