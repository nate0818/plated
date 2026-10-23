import SwiftUI
import UIKit
import SwiftData

// MARK: - Editorial palette
// Exact green/cream palette from the approved October 18 design review.
// Values are mirrored in widgets.

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255
        )
    }

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
    static let canvas         = Color(light: 0xFAF9F4, dark: 0x191C17)
    static let ink            = Color(light: 0x26382C, dark: 0xEFF0E6)
    static let inkSecondary   = Color(light: 0x606A57, dark: 0xB4BEAA)
    static let inkFaint       = Color(light: 0xA5AD9A, dark: 0x727D68)
    static let hairline       = Color(light: 0xDCE0D2, dark: 0x384031)   // card borders
    static let hairlineSoft   = Color(light: 0xDCE0D2, dark: 0x384031)   // row separators
    static let hairlineDashed = Color(light: 0xCCD2C2, dark: 0x4C5844)   // empty-state dashes
    static let navHairline    = Color(light: 0xDCE0D2, dark: 0x384031)   // navigation rule
    static let fill           = Color(light: 0xEEEEE4, dark: 0x24291F)   // neutral avatar / wells
    static let chipFill       = Color(light: 0xE2E8D9, dark: 0x2B3327)   // link chips
    static let raisedFill     = Color(light: 0xE2E8D9, dark: 0x2B3327)   // neutral raised surface
    static let selectionFill = ink
    static let onSelection = canvas

    // The approved polish retains orange, with its specified appearance variants.
    static let primaryAction = Color(light: 0xF45132, dark: 0xFF5738)
    static let onPrimary = Color(light: 0x241D14, dark: 0x241D14)
    static let primaryPressed = Color(light: 0xF36A4F, dark: 0xF36A4F)
    static let olive         = Color(light: 0x365C43, dark: 0xB7CAA5)   // supporting selection
    static let onOlive = Color(light: 0xFFFFFF, dark: 0x182219)
    static let accentText = Color(light: 0x365C43, dark: 0xB7CAA5)
    static let dangerText = Color(light: 0xA33D2D, dark: 0xF0A595)
    static let completion = Color(light: 0x365C43, dark: 0xB7CAA5)
    static let olivePressed  = Color(light: 0x284632, dark: 0x9BB98B)   // pressed always darkens

    static let scrim          = Color.scrimInk.opacity(0.7)
    static let scrimInk       = Color(light: 0x172018, dark: 0x172018)
    static let onScrim        = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let mango          = Color(light: 0xFFB020, dark: 0xFFB63A)   // the chef's kiss only
    static let basil          = Color(light: 0x3DA35D, dark: 0x55BE76)   // progress, "seated"
    static let amber          = Color(light: 0xBF8300, dark: 0xE3A83C)
    static let grape          = Color(light: 0xB95CF4, dark: 0xC98BF7)

    // Tints — avatar and chip washes, one per person color
    static let oliveTint     = Color(light: 0xE8EDE1, dark: 0x262D22)
    static let basilTint      = Color(light: 0xE8EDE1, dark: 0x303B29)
    static let mangoTint      = Color(light: 0xFFF4DC, dark: 0x332A15)
    static let grapeTint      = Color(light: 0xF5EDFB, dark: 0x2E2138)
    static let todayTint      = Color(light: 0xECEFE5, dark: 0x2A3425)   // today cell in cook grid

    // Retained for photo artwork and system-adjacent effects
    static let shadowInk      = Color(light: 0x27362A, dark: 0x000000)
    static let shadowWarm     = Color(light: 0x27362A, dark: 0x000000)

    // Kept for DishView's generative palette families
    static let cardFill       = Color(light: 0xFAF9F4, dark: 0x1E211B)
    static let copper         = Color(light: 0xA5622F, dark: 0xC97F4A)
    static let successTone    = Color(light: 0x3DA35D, dark: 0x55BE76)
}

// MARK: - Person palette
// Fixed (tint, tone) pairs so avatars match everywhere. Chosen by the stored
// colorHex; anything unknown falls back to the neutral pair.

struct PersonTone: Equatable {
    let tint: Color
    let tone: Color

    static let tomatoPair  = PersonTone(tint: .oliveTint, tone: .olive)
    static let basilPair   = PersonTone(tint: .basilTint, tone: .basil)
    static let amberPair   = PersonTone(tint: .mangoTint, tone: .amber)
    static let grapePair   = PersonTone(tint: .grapeTint, tone: .grape)
    static let neutralPair = PersonTone(tint: .fill, tone: .ink)

    static func from(hex: String) -> PersonTone {
        switch hex.uppercased() {
        case "FF5A3C", "C86629": return .tomatoPair
        case "3DA35D": return .basilPair
        // C88A00 is the stored rotation key; BF8300 is amber's light value
        // after the contrast darkening — both must resolve or a seat that
        // somehow held the colour token would fall through to neutral.
        case "C88A00", "BF8300": return .amberPair
        case "B95CF4": return .grapePair
        default:       return .neutralPair
        }
    }

    static let rotation: [String] = ["FF5A3C", "3DA35D", "C88A00", "B95CF4"]
}

extension HouseholdMember {
    var tone: PersonTone { PersonTone.from(hex: colorHex) }
}

private struct TappableField: ViewModifier {
    @FocusState private var focused: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { focused = true }
    }
}

extension View {
    func plTappableField(radius: CGFloat = Radius.chip) -> some View {
        modifier(TappableField(radius: radius))
    }

    func plTapToFocus(radius: CGFloat = Radius.chip, _ focus: @escaping () -> Void) -> some View {
        contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture(perform: focus)
    }
}

extension View {
    func plName(_ minScale: CGFloat = 0.7) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(minScale)
            .truncationMode(.tail)
            .allowsTightening(true)
    }

    func plActionLabel(_ minScale: CGFloat = 0.78) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
            .truncationMode(.tail)
    }
}

extension Collection where Element == HouseholdMember {
    func photo(forAuthor name: String, authorID: String = "") -> Data? {
        ProfileIdentity.member(authorID: authorID, name: name, in: Array(self))?.photoData
    }
}

// MARK: - Scales

enum Radius {
    static let small: CGFloat = 4
    static let chip: CGFloat = 8
    static let row: CGFloat = 6
    static let card: CGFloat = 12
    static let hero: CGFloat = 12
    static let sheet: CGFloat = 18

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static func nested(in outer: CGFloat, inset: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: max(outer - inset, 2), style: .continuous)
    }
}

// MARK: - Shared layout tokens

enum Spacing {
    static let inline: CGFloat = 8
    static let compact: CGFloat = 12
    static let content: CGFloat = 16
    static let page: CGFloat = 20
    static let section: CGFloat = 28
}

enum ControlMetrics {
    static let minimumTarget: CGFloat = 44
    static let primaryHeight: CGFloat = 48
    static let actionHorizontalInset: CGFloat = 20
    static let actionVerticalInset: CGFloat = 12
}

// MARK: - Motion
// One overshoot spring everywhere — the SwiftUI twin of the canvas's
// cubic-bezier(0.34, 1.56, 0.64, 1) at 0.28–0.32s.

extension Animation {
    private static var wantsReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    private static func calm(_ duration: TimeInterval) -> Animation {
        .spring(duration: duration, bounce: 0)
    }

    static var plPop: Animation {
        wantsReduced ? calm(0.32) : .spring(response: 0.32, dampingFraction: 0.55)
    }
    static var plSnap: Animation {
        wantsReduced ? calm(0.28) : .spring(response: 0.28, dampingFraction: 0.75)
    }
    static var plSettle: Animation {
        wantsReduced ? calm(0.55) : .spring(response: 0.55, dampingFraction: 0.8)
    }
}

// A spring that has been flattened still scales a view into place, and the
// scale is the movement. These are the two arrivals the app uses; both
// become a plain fade when the reader has asked for less.

extension AnyTransition {
    static var plArrive: AnyTransition {
        UIAccessibility.isReduceMotionEnabled
            ? .opacity
            : .scale(scale: 0.92).combined(with: .opacity)
    }

    private static var wantsCrossFade: Bool { UIAccessibility.prefersCrossFadeTransitions }

    static var plRise: AnyTransition {
        wantsCrossFade ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    static var plUnfold: AnyTransition {
        wantsCrossFade ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
}

// MARK: - Haptics
// Sound-free fun: light on chrome, medium when a plate lands, a full
// success tap when the kiss is earned.

enum Haptic {
    // Stored generators avoid paying allocation on every tap, which is
    // necessary but not sufficient: the Taptic Engine itself idles a
    // couple of seconds after any fire, and the next impact then pays the
    // wake-up and lands a beat AFTER the animation it was meant to
    // accompany. `prepare()` is the API for that window and `PressableStyle`
    // calls it on the press, which is exactly that window — the finger is
    // down before the action runs.
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()
    private static let selector = UISelectionFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func plate() { medium.impactOccurred() }
    static func kiss() { notice.notificationOccurred(.success) }
    static func select() { selector.selectionChanged() }
    static func warn() { notice.notificationOccurred(.warning) }

    static func prepare() {
        light.prepare()
        medium.prepare()
        notice.prepare()
        selector.prepare()
    }
}

// MARK: - Press feedback

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptic.prepare() }
            }
            .opacity(!isEnabled ? 0.55 : configuration.isPressed ? 0.85 : 1)
            .animation(.plSnap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Floating chrome

enum Layout {
    static let readableMaxWidth: CGFloat = 760

    static let floatingChromeMaxWidth: CGFloat = 680

    /// Content height; the system bottom safe area is painted separately.
    static let tabBarHeight: CGFloat = 47

    static let tabBarInset: CGFloat = 72

    static let perchBottom: CGFloat = tabBarInset
    static let perchHeight: CGFloat = 50

    static let floatingChromeInset: CGFloat =
        ProngsbyFeature.isEnabled ? perchBottom + perchHeight + 8 : tabBarInset + 8

    static let focusedPageBottom: CGFloat = 32
}

// PLBreathing lived here: a 2.4s pulse on every empty-state glyph. Deleted
// rather than left unused, because an unused modifier is an invitation. An
// icon does not perform — not a bounce, not a spin, not a breath. A glyph
// that pulses while you read the sentence next to it is the app fidgeting
// for attention in the one moment it has nothing to say.

// MARK: - Shadows

private struct PLShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let lightOpacity: Double
    let darkOpacity: Double
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View { content }

}

extension View {
    func plTileShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.13, darkOpacity: 0.40, radius: 5, y: 3))
    }
    func plDishShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.11, darkOpacity: 0.46, radius: 10, y: 6))
    }
    func plCardShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.09, darkOpacity: 0.52, radius: 18, y: 11))
    }
    func plFloatShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.07, darkOpacity: 0.58, radius: 28, y: 17))
    }
}

// MARK: - Masthead alignment

extension VerticalAlignment {
    private enum DiscCentreID: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            d[VerticalAlignment.center]
        }
    }
    static let discCentre = VerticalAlignment(DiscCentreID.self)
}

extension View {
    func plDiscAligned(_ diameter: CGFloat) -> some View {
        alignmentGuide(.discCentre) { _ in diameter / 2 }
    }
}

// MARK: - Touch targets

extension View {
    func plTapTarget(_ shape: some Shape = Rectangle()) -> some View {
        frame(minWidth: ControlMetrics.minimumTarget, minHeight: ControlMetrics.minimumTarget).contentShape(shape)
    }
}

// MARK: - Chrome that has to hold still

extension View {
    func plChrome() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    func plFitsOrScrolls() -> some View {
        GeometryReader { proxy in
            ScrollView {
                frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Zoom transitions

enum Stamp {
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if isRecent(date) { return weekdayFormat.string(from: date) }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return dateFormat.string(from: date)
        }
        return datedYearFormat.string(from: date)
    }

    static func dayPhrase(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        if isRecent(date) { return "on \(weekdayFormat.string(from: date))" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return "on \(dateFormat.string(from: date))"
        }
        return "on \(datedYearFormat.string(from: date))"
    }

    static func nightPhrase(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "tonight" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days > 0 && days < 6 { return weekdayFormat.string(from: date) }
        if days < 0 && days > -6 { return "last \(weekdayFormat.string(from: date))" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return dateFormat.string(from: date)
        }
        return datedYearFormat.string(from: date)
    }

    static func isRecent(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: .now)
        ).day ?? 0
        return days < 6
    }

    static let weekdayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f
    }()
    static let datedYearFormat: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM yyyy"); return f
    }()
}

enum ZoomID: Hashable {
    case host
    case person(String)
    case author(PersistentIdentifier)
}

// MARK: - Shared atoms

struct PlanEdgeMark: View {
    static let size = CGSize(width: 3, height: 20)

    var body: some View {
        Capsule()
            .fill(Color.inkFaint)
            .frame(width: Self.size.width, height: Self.size.height)
            .allowsHitTesting(false)
            // A reader hears the week or month actions on each day, never
            // the punctuation between them.
            .accessibilityHidden(true)
    }
}

struct MicroLabel: View {
    let text: String
    var color: Color = .inkSecondary

    init(_ text: String, color: Color = .inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .plType(.micro)
            .foregroundStyle(color)
    }
}

struct IconDiscButton: View {
    let systemName: String
    let label: String
    var glyphSize: CGFloat = 22
    var targetSize: CGFloat = ControlMetrics.minimumTarget
    let action: () -> Void
    var body: some View {
        Button { Haptic.tap(); action() } label: {
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: .regular))
                .foregroundStyle(Color.ink)
                .frame(minWidth: targetSize, minHeight: targetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .plChrome()
    }
}

struct AddCircleButton: View {
    let label: String
    var count: Int = 1
    var disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(disabled ? Color.fill : Color.ink)
                .frame(width: 38, height: 38)
                .overlay {
                    if count > 1 {
                        Text("\(count)")
                            .plType(.footnote, .extraBold)
                            .foregroundStyle(Color.canvas)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(disabled ? Color.inkFaint : Color.canvas)
                    }
                }
                .plTapTarget()
                .animation(.plSnap, value: count)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(count > 1 ? "\(label), \(count)" : label)
        .disabled(disabled)
    }
}

struct OptionRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    // Fixed width, so a wide glyph and a narrow one start
                    // their labels at the same x. SF Symbols are not
                    // monospaced and "camera" is a good deal wider than
                    // "book.closed".
                    .frame(width: 26)
                    // Inert unless the caller swaps the symbol for its own
                    // opposite, which the share sheet's Copy row does.
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(Color.canvas)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        // Two lines that are one sentence: without this VoiceOver reads the
        // title and the detail as two separate elements inside a button.
        .accessibilityElement(children: .combine)
    }
}

struct DurationField: View {
    let label: String
    @Binding var minutes: Int

    @State private var hourText = ""
    @State private var minText = ""
    @FocusState private var focused: Part?

    private enum Part { case hours, mins }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(label)
            HStack(spacing: 8) {
                box(text: $hourText, unit: "hr", spoken: "hours", part: .hours)
                box(text: $minText, unit: "min", spoken: "minutes", part: .mins)
            }
        }
        .onAppear(perform: pull)
        .onChange(of: hourText) { _, _ in push() }
        .onChange(of: minText) { _, _ in push() }
        .onChange(of: minutes) { _, new in
            // Only re-read when somebody else wrote it — loading a recipe —
            // rather than echoing our own push back into the boxes.
            if new != composed { pull() }
        }
    }

    private var composed: Int { (Int(hourText) ?? 0) * 60 + (Int(minText) ?? 0) }

    private func push() {
        // Minutes clamp at 59 rather than carrying. A box that silently turns
        // 90 into "1 hr 30" while you are still typing is the same class of
        // surprise as a parser rewriting an ingredient.
        let cleaned = String(minText.filter(\.isNumber).prefix(2))
        if cleaned != minText { minText = cleaned; return }
        if let m = Int(minText), m > 59 { minText = "59"; return }
        let cleanedHours = String(hourText.filter(\.isNumber).prefix(2))
        if cleanedHours != hourText { hourText = cleanedHours; return }
        minutes = composed
    }

    private func pull() {
        hourText = minutes / 60 == 0 ? "" : String(minutes / 60)
        minText = minutes % 60 == 0 ? "" : String(minutes % 60)
    }

    private func box(
        text: Binding<String>, unit: String, spoken: String, part: Part
    ) -> some View {
        HStack(spacing: 5) {
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .plType(.heading)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
                .focused($focused, equals: part)
                .frame(minWidth: 30)
            Text(unit)
                .plType(.footnote, .semibold)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(minHeight: 52)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Color.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .onTapGesture { focused = part }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(spoken)")
    }
}

struct EditableLine: View {
    @Binding var text: String
    var placeholder: String = ""
    var focus: FocusState<AnyHashable?>.Binding? = nil
    var focusID: AnyHashable? = nil

    var body: some View {
        let field = TextField(placeholder, text: $text, axis: .vertical)
            .plType(.body, .medium)
            .foregroundStyle(Color.ink)
            // No upper line limit. It was 1...3 for an ingredient, and a
            // three-line ingredient — "3 lb boneless pork shoulder or pork
            // butt, trimmed of most excess fat" — was drawn with its last
            // line sliced in half. A field that hides the text you are
            // editing is not a field.
            .lineLimit(1...)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Color.hairline)
            )

        if let focus, let focusID {
            field.focused(focus, equals: focusID).plTapToFocus { focus.wrappedValue = focusID }
        } else {
            field.plTappableField()
        }
    }
}

struct RemoveLineButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            Image(systemName: "xmark")
                .accessibilityLabel(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.inkSecondary)
                .plTapTarget()
        }
        .buttonStyle(.pressable)
    }
}

struct SelectChip<Label: View>: View {
    let active: Bool
    var height: CGFloat = 38
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            Haptic.select()
            withAnimation(.plSnap) { action() }
        } label: {
            label()
                .fixedSize()
                .foregroundStyle(active ? Color.onSelection : Color.ink)
                .padding(.horizontal, 13)
                .frame(minHeight: height)
                .background {
                    if active {
                        Capsule().fill(Color.selectionFill)
                    } else {
                        Radius.shape(Radius.chip).strokeBorder(Color.hairline)
                    }
                }
                // The target goes outside the drawn capsule, and stays a
                // capsule: `plTapTarget` forces `minWidth: 44` and a
                // Rectangle, which would square off the hit area and widen
                // short chips inside a flow layout.
                .frame(minHeight: 44)
                .contentShape(Radius.shape(Radius.chip))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct CountBlock: View {
    let value: String
    let label: String
    var accent: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                // Amber, not mango: mango on canvas measures 1.83:1, which
                // is unreadable for a numeral this size. Amber is the same
                // family two steps darker and is already the app's token
                // for "mango, but as text".
                .plType(.title)
                .foregroundStyle(accent ? Color.amber : Color.ink)
                .contentTransition(.numericText())
                // Most values here are a numeral or two, but not all: the
                // recipe page shows "Not set" when a dish has no time on it.
                // Shrink rather than truncate.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .plType(.micro, .semibold)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct CountDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }
}

struct PhotoWell: View {
    let image: UIImage
    var height: CGFloat?
    var clamped = false
    var maximumHeight: CGFloat = 320
    var cornerRadius: CGFloat = Radius.card

    private var ratio: CGFloat {
        let natural = image.size.height > 0 ? image.size.width / image.size.height : 1
        return min(max(natural, 4.0 / 5.0), 1.91)
    }

    var body: some View {
        Group {
            if clamped {
                Color.clear
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxHeight: maximumHeight)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: height ?? 240)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
        .clipShape(Radius.shape(cornerRadius))
        .contentShape(Radius.shape(cornerRadius))
    }
}

struct PlatedWordmark: View {
    var size: CGFloat = 26
    var body: some View {
        Text("Plated")
            .font(.editorial(size, .medium))
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .accessibilityLabel("Plated")
    }
}

struct AvatarCircle: View {
    let initials: String
    let tone: PersonTone
    var size: CGFloat = 34
    var photo: Data?

    init(member: HouseholdMember, size: CGFloat = 34) {
        self.initials = member.initials.isEmpty ? member.firstInitial : member.initials
        self.tone = member.tone
        self.size = size
        self.photo = member.photoData
    }

    init(initials: String, tone: PersonTone, size: CGFloat = 34, photo: Data? = nil) {
        self.initials = initials
        self.tone = tone
        self.size = size
        self.photo = photo
    }

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            monogram
        }
    }

    private var monogram: some View {
        Circle()
            .fill(tone.tint)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.sans(size * 0.38, .bold))
                    .foregroundStyle(Color.ink)
                    // The circle is a fixed size but `Font.custom` scales
                    // with Dynamic Type, so at accessibility sizes the
                    // glyph can outgrow its container: two-letter initials
                    // put about 0.2pt of ink outside the disc at AX3.
                    //
                    // **The bound is a CHORD, not the inscribed square**,
                    // and getting that wrong cost a whole round. Text is not
                    // a square — it is a wide, short band, and a band of
                    // half-height h fits a width of 2√(r²−h²), which is
                    // ≈0.96·size here against the inscribed square's 0.707.
                    // Constraining to the square was 26% tighter than the
                    // real limit, which made `minimumScaleFactor`'s floor
                    // binding and reinstated the ellipsis at AX5 — for
                    // "MC", a name in our own sample data — while shrinking
                    // wide pairs ~10% at default size for no containment
                    // gain, and leaving "+2" 30% smaller than "S" beside it
                    // in the same stack.
                    //
                    // The version that would work fits the ink box's
                    // CORNERS to the circle, or sizes the font as a
                    // fraction of the circle instead of scaling a fixed
                    // one. Deliberately not attempted here: this is the
                    // third pass at this component in a day, and 0.2pt of
                    // overflow is a smaller defect than an ellipsis.
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
    }
}

struct PrimaryActionButton: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var systemImage: String?
    var busy: Bool = false
    var haptic: () -> Void = Haptic.tap
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var awake: Bool { isEnabled || busy }

    var body: some View {
        Button {
            // A pill can be busy without being disabled. Guard here rather
            // than trusting every future call site to pair the two.
            guard !busy else { return }
            haptic()
            action()
        } label: { // design-ok(action-wrap): accessibility sizes wrap and grow the primary action instead of shrinking its text
            HStack(spacing: Spacing.inline) {
                if busy {
                    ProgressView().tint(awake ? Color.onPrimary : Color.inkSecondary)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .plType(.body, .semibold)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.onPrimary)
            .padding(.horizontal, ControlMetrics.actionHorizontalInset)
            .padding(.vertical, ControlMetrics.actionVerticalInset)
            .frame(maxWidth: .infinity)
            .frame(minHeight: ControlMetrics.primaryHeight)
            .contentShape(Radius.shape(Radius.chip))
        }
        .buttonStyle(PrimaryActionStyle(enabled: awake))
        .disabled(busy)
        .accessibilityValue(busy ? "In progress" : "")
    }
}

struct SecondaryActionButton: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: { // design-ok(action-wrap): accessibility sizes wrap and grow the primary action instead of shrinking its text
            HStack(spacing: Spacing.inline) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .plType(.body, .semibold)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isEnabled ? Color.accentText : Color.inkSecondary)
            .padding(.horizontal, ControlMetrics.actionHorizontalInset)
            .padding(.vertical, ControlMetrics.actionVerticalInset)
            .frame(maxWidth: .infinity)
            .frame(minHeight: ControlMetrics.primaryHeight)
            .contentShape(Radius.shape(Radius.chip))
        }
        .buttonStyle(SecondaryActionStyle())
    }
}

private struct SecondaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isEnabled ? Color.raisedFill : Color.fill, in: Radius.shape(Radius.chip))
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
            .animation(.plSnap, value: configuration.isPressed)
    }
}

private struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(ground(pressed: configuration.isPressed), in: Radius.shape(Radius.chip))
            .opacity(enabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? 0.98 : 1)
            .animation(.plSnap, value: configuration.isPressed)
    }

    private func ground(pressed: Bool) -> Color {
        guard enabled else { return .primaryAction }
        return pressed ? .primaryPressed : .primaryAction
    }
}

private struct FloatingGlass: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(Color.canvas, in: Radius.shape(Radius.card))
            .overlay(Radius.shape(Radius.card).strokeBorder(contrast == .increased ? Color.inkSecondary : Color.hairline))
    }
}

extension View {
    func plFloatingGlass() -> some View { modifier(FloatingGlass()) }
}
