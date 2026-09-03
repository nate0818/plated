import SwiftUI
import UIKit
import SwiftData

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
    /// Every supporting sentence in the app. 4.63:1 on canvas, 6.8:1 after
    /// dark. It was 0x8A8074, which measured 3.87:1 — under the 4.5:1 floor
    /// for text this size, so half the words in the app were below the line
    /// while looking, to a designer with good eyes on a bright screen, fine.
    /// Same hue and saturation, doing a job it can actually do.
    static let inkSecondary   = Color(light: 0x7F7364, dark: 0xA79B8B)
    /// Decoration only: strokes, dashes, an icon on a control that is off.
    /// 2.24:1 on canvas and 3.08:1 after dark — it cannot legibly carry a
    /// word at any size, so it is never a `Text` colour. See DESIGN.md.
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

    /// The darkening under a control that sits on somebody's photograph.
    ///
    /// Dark in BOTH rooms, because a photograph is a photograph in both
    /// rooms. This existed as `Color.ink.opacity(0.7)` in two places, and
    /// `ink` is the primary TEXT colour, so after dark it inverts to cream:
    /// a white glyph on a cream disc over a photo. The remove-photo button
    /// did not degrade after dark, it vanished. A semantic token that
    /// inverts is the wrong kind of colour for a scrim, and there was no
    /// right kind, which is why it happened twice.
    static let scrim          = Color.scrimInk.opacity(0.7)
    /// The scrim's colour with no alpha spent yet, for the places that need
    /// their own: a gradient ramp cannot use a token that has already picked
    /// one opacity. Warm rather than black, so it sits under food photographs
    /// without turning them grey.
    static let scrimInk       = Color(light: 0x241C12, dark: 0x241C12)
    /// THE label colour on a scrim, both rooms. Never a bare `.white`.
    static let onScrim        = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let mango          = Color(light: 0xFFB020, dark: 0xFFB63A)   // the chef's kiss only
    static let basil          = Color(light: 0x3DA35D, dark: 0x55BE76)   // progress, "seated"
    /// Light value darkened from 0xC88A00 (2.96:1 on canvas — a hair under
    /// the 3.0 floor for large text) to 3.25:1. Also lifts the person-tone
    /// pairing on mangoTint rather than harming it. Dark value already
    /// measured 8.81:1.
    static let amber          = Color(light: 0xBF8300, dark: 0xE3A83C)
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

/// Makes a text field's whole drawn box focus it, not just the text inside.
///
/// `.padding()` around a `TextField` is dead space. The field's hit area is
/// its own bounds, so a 48pt box holding a 20pt line of text leaves 28pt
/// that looks exactly like a control and does nothing when tapped. Aiming
/// at it feels like the app is ignoring you, and on "Add to the household"
/// it stopped the flow dead: the box is the only thing on screen to press.
///
/// The modifier owns its own `@FocusState`, which is what lets one line fix
/// a field without threading a focus binding through every screen. Fields
/// that already own a focus binding use `plTapToFocus` instead, because two
/// bindings on one field is undefined behaviour rather than two chances.
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

    /// The same target, for a field whose focus somebody else already owns.
    func plTapToFocus(radius: CGFloat = Radius.chip, _ focus: @escaping () -> Void) -> some View {
        contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture(perform: focus)
    }
}

extension View {
    /// A person's or a household's name: one line, shrinking rather than
    /// breaking.
    ///
    /// SwiftUI hyphenates nothing and will break anywhere when a single
    /// word is wider than its column, so "Alessandra" in a member row whose
    /// right side is taken by a day chip came back as "Alessand" over "ra".
    /// A name is not prose. It never reads better across two lines, and an
    /// orphaned syllable is worse than small type, so this shrinks first
    /// and truncates at the tail only when shrinking runs out.
    ///
    /// One modifier rather than a fix at each call site, because there are
    /// sixteen places a name is drawn and the next one added would have had
    /// the same bug.
    func plName(_ minScale: CGFloat = 0.7) -> some View {
        self.lineLimit(1)
            .minimumScaleFactor(minScale)
            .truncationMode(.tail)
            .allowsTightening(true)
    }
}

extension Collection where Element == HouseholdMember {
    /// The face belonging to a name stamped on a post or a comment.
    ///
    /// Authorship is a stored string rather than a relationship, so a post
    /// knows a name and nothing else. Matching is EXACT and deliberately so:
    /// a first-name match would put your sister's face on a guest who shares
    /// her name, and a wrong face is worse than initials.
    func photo(forAuthor name: String) -> Data? {
        first { $0.name == name }?.photoData
    }
}

// MARK: - Scales

/// Corner radii.
///
/// **Every corner in Plated is `.continuous`.** A circular arc meets the
/// straight edge at a visible crease that grows with the radius — at `card`
/// (20) and `hero` (24) it is plainly there. Every corner iOS draws around
/// us is continuous, so a circular one reads as a foreign object without
/// anyone being able to say why. The app used to draw both: twelve
/// continuous corners in the Plan tab and eighty-five circular ones
/// everywhere else, one tap apart.
///
/// Use `Radius.shape(_:)` or pass `style: .continuous` explicitly. A bare
/// `RoundedRectangle(cornerRadius: , style: .continuous)` is the wrong corner.
enum Radius {
    /// Small rectangles nested inside a larger one: a thumbnail, a poll
    /// option, a day cell in the month grid, the date chip in a plan row.
    ///
    /// DESIGN.md says to add a fifth step rather than write a literal, and
    /// this is that step. Thirteen inline radii had accumulated below the
    /// chip's 16 — six 12s, a 14, an 11, a 10 — which is not a scale, it is
    /// whatever each author's eye picked that day. The worst of it was the
    /// plan list's own date chip: 14 when the night is ahead of you and 11
    /// once it has passed, for one element in one column.
    static let small: CGFloat = 12
    static let chip: CGFloat = 16
    static let row: CGFloat = 18
    static let card: CGFloat = 20
    static let hero: CGFloat = 24
    static let sheet: CGFloat = 28

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// A corner nested inside another, inset by the gap between them.
    ///
    /// Concentric corners share a centre: the inner radius is the outer
    /// minus the padding. Repeating the outer radius on an inner shape
    /// leaves the two arcs visibly non-parallel, which is one of the few
    /// craft errors people notice without knowing what they are seeing.
    static func nested(in outer: CGFloat, inset: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: max(outer - inset, 2), style: .continuous)
    }
}

// MARK: - Motion
// One overshoot spring everywhere — the SwiftUI twin of the canvas's
// cubic-bezier(0.34, 1.56, 0.64, 1) at 0.28–0.32s.

extension Animation {
    /// Reduce Motion is answered here, once, rather than at the hundred and
    /// eighteen places that call `withAnimation`. A rule that has to be
    /// remembered at every call site is a rule that will be forgotten at the
    /// next one, and the count was eighteen guards against a hundred and
    /// eighteen springs when this was measured.
    ///
    /// What changes is the travel, not the change: a spring overshoots and
    /// settles, which is exactly the movement the setting asks us to drop.
    /// The state still changes, and it still takes a moment doing it.
    ///
    /// Known and deliberately not fixed here: SwiftUI does not observe
    /// `UIAccessibility.isReduceMotionEnabled`, so a body already on screen
    /// keeps whatever Animation it captured until something else invalidates
    /// it. Driving this from an `@Observable` on
    /// `reduceMotionStatusDidChangeNotification` is the right answer; the
    /// setting is almost always chosen before the app is opened, so the cost
    /// of the gap is one relaunch.
    private static var wantsReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Reduced does not mean uniform.
    ///
    /// All three springs used to collapse into one `easeInOut(duration: 0.2)`,
    /// so for the readers who asked for less motion a chip and a sheet moved
    /// at exactly the same speed: 123 `withAnimation` calls and 38
    /// `.animation` modifiers flattened to a single pace, which is not the
    /// app with its overshoot removed, it is a different app. Bounce 0 is
    /// precisely what the setting asks for — the travel stops overshooting
    /// and settling — and each step keeps the duration that made it feel
    /// like itself.
    private static func calm(_ duration: TimeInterval) -> Animation {
        .spring(duration: duration, bounce: 0)
    }

    /// Icon and reaction bounce.
    static var plPop: Animation {
        wantsReduced ? calm(0.32) : .spring(response: 0.32, dampingFraction: 0.55)
    }
    /// State changes without theater.
    static var plSnap: Animation {
        wantsReduced ? calm(0.28) : .spring(response: 0.28, dampingFraction: 0.75)
    }
    /// Sheets, splash, big arrivals.
    static var plSettle: Animation {
        wantsReduced ? calm(0.55) : .spring(response: 0.55, dampingFraction: 0.8)
    }
}

// A spring that has been flattened still scales a view into place, and the
// scale is the movement. These are the two arrivals the app uses; both
// become a plain fade when the reader has asked for less.

extension AnyTransition {
    /// Something arriving in a list or a grid.
    static var plArrive: AnyTransition {
        UIAccessibility.isReduceMotionEnabled
            ? .opacity
            : .scale(scale: 0.92).combined(with: .opacity)
    }

    /// A slide is not the movement Reduce Motion is about.
    ///
    /// `prefersCrossFadeTransitions` is documented as the conjunction of
    /// Reduce Motion and Prefer Cross-Fade Transitions, which is the exact
    /// question these two are asking: iOS itself keeps sliding a pushed view
    /// in under Reduce Motion alone and only cross-fades when the second
    /// switch is on. Gating on the first one made the app read flatter than
    /// the OS around it for people who never asked for that.
    /// `plArrive` is a scale — the zoom the setting genuinely targets — so it
    /// stays on Reduce Motion.
    private static var wantsCrossFade: Bool { UIAccessibility.prefersCrossFadeTransitions }

    /// Something arriving from off the bottom edge: a toast, a composer bar.
    static var plRise: AnyTransition {
        wantsCrossFade ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    /// Something unfolding downward under the control that revealed it:
    /// an explanation, a draft row.
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
    /// The tick of moving between options — chips, toggles, segments,
    /// drag targets. Quieter than a tap; it marks position, not action.
    static func select() { selector.selectionChanged() }
    /// Something didn't take — a denied permission, a failed export.
    static func warn() { notice.notificationOccurred(.warning) }

    /// The finger is down; whatever fires next should land on time.
    static func prepare() {
        light.prepare()
        medium.prepare()
        notice.prepare()
        selector.prepare()
    }
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
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptic.prepare() }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.plSnap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Floating chrome

enum Layout {
    /// What a control docked to the bottom of a pushed page needs to clear
    /// the floating tab bar: the bar's own bottom padding (4) plus its
    /// height (68) plus a 12pt gap. A page that docks something here also
    /// owes the perch a `.hidesProngsbyPerch()`.
    static let tabBarInset: CGFloat = 84

    /// Where the perch sits and how big it is — directly on top of the
    /// bar's clearance.
    static let perchBottom: CGFloat = tabBarInset
    static let perchHeight: CGFloat = 50

    /// How much room the floating chrome needs at the bottom of a scroll.
    /// Derived, not typed: a hand-written constant drifted 6pt short of
    /// the chrome it was supposed to clear the first time.
    ///
    /// It follows the perch's own switch, because the perch is the taller
    /// half of that sum and it is currently parked. Reserving its 58pt
    /// anyway left eleven scroll views ending two thumbs above the bar with
    /// nothing in the gap — the clearance was real, the thing it cleared
    /// was not.
    static let floatingChromeInset: CGFloat =
        ProngsbyFeature.isEnabled ? perchBottom + perchHeight + 8 : tabBarInset + 8
}

// PLBreathing lived here: a 2.4s pulse on every empty-state glyph. Deleted
// rather than left unused, because an unused modifier is an invitation. An
// icon does not perform — not a bounce, not a spin, not a breath. A glyph
// that pulses while you read the sentence next to it is the app fidgeting
// for attention in the one moment it has nothing to say.

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

/// The elevation ramp. Four steps, one light.
///
/// Two rules hold it together, and the app was breaking both.
///
/// **Opacity falls as a thing rises.** A shadow spreads and softens with
/// height; it does not darken. The ramp ran 0.06 → 0.14 → 0.10 → 0.08, so a
/// dish circle cast the darkest shadow in the app from nearly the lowest
/// elevation, and the floating chrome cast a lighter one than the card it
/// hovers over.
///
/// **y ÷ radius is constant, or the light source moves.** It ran 0.33, 0.67,
/// 0.67, 0.75 — two lights in one room, which is exactly the kind of
/// wrongness a person feels and cannot name. It is 0.60 everywhere now.
///
/// After dark the ramp had collapsed as well (dish and float both 0.50, so
/// elevation stopped being readable); it steps again.
extension View {
    /// The lowest step: small tiles sitting on a card rather than on the
    /// canvas, like the plan's date tile. Tightest and darkest.
    func plTileShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.13, darkOpacity: 0.40, radius: 5, y: 3))
    }
    /// Dish circles.
    func plDishShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.11, darkOpacity: 0.46, radius: 10, y: 6))
    }
    /// Cards and photo tiles.
    func plCardShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.09, darkOpacity: 0.52, radius: 18, y: 11))
    }
    /// Floating chrome: the nav pill and the + button. The highest things in
    /// the app, so the widest and faintest shadow of the four.
    func plFloatShadow() -> some View {
        modifier(PLShadow(lightOpacity: 0.07, darkOpacity: 0.58, radius: 28, y: 17))
    }
}

// MARK: - Masthead alignment

extension VerticalAlignment {
    /// Aligns a masthead's round controls on the centres of their DISCS
    /// rather than on the centres of their layout blocks.
    ///
    /// The bell and the gear are 36pt discs inside 44pt tap frames, so their
    /// discs land on the block's centreline for free. The host avatar is a
    /// 38-42pt disc with a caption under it, so its block runs about 55pt
    /// and centring the block puts the face roughly 8pt above the two
    /// circles beside it — permanently, on all three screens that carry it.
    /// One control looks like it slipped.
    private enum DiscCentreID: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            d[VerticalAlignment.center]
        }
    }
    static let discCentre = VerticalAlignment(DiscCentreID.self)
}

extension View {
    /// Put this view's own disc on the masthead's centreline. `diameter` is
    /// the disc's, and it is assumed to sit at the top of the block.
    func plDiscAligned(_ diameter: CGFloat) -> some View {
        alignmentGuide(.discCentre) { _ in diameter / 2 }
    }
}

// MARK: - Touch targets

extension View {
    /// A 44pt target that is actually tappable.
    ///
    /// `.frame` is layout. Hit testing needs a shape, and a `Button` whose
    /// label draws only a glyph is hit-testable only where the glyph is —
    /// `.pressable` adds scale and opacity, not a surface. Sixteen controls
    /// shipped with the frame and without the shape.
    ///
    /// That is not sixteen mistakes, it is one idiom copied sixteen times,
    /// and it is the same shape of failure as Reduce Motion before `plPop`
    /// answered it in one place: DESIGN.md states this rule twice, in two
    /// different sections, which is the strongest possible evidence that
    /// stating it does not work. So it stops being a sentence and becomes a
    /// type.
    ///
    /// It hides from review twice over. `.contentShape` is invisible by
    /// definition, and a mouse pointer aimed at the middle of a glyph in a
    /// simulator hits every one of these controls perfectly. A thumb on a
    /// phone does not. That is CLAUDE.md's "the simulator lies about this
    /// app", extended to a class that was never on the list.
    func plTapTarget(_ shape: some Shape = Rectangle()) -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(shape)
    }
}

// MARK: - Chrome that has to hold still

extension View {
    /// **Chrome caps its type; content does not.**
    ///
    /// A tab bar, a masthead's icon cluster, a notification badge, a date
    /// chip: these are fixed-size furniture with nowhere to reflow to, and
    /// past a point they stop being readable and start being broken. At
    /// AX5 the tab bar's five labels ran into each other, the bell's 16pt
    /// badge held 32pt digits, and the Plan list's 66pt date chip set
    /// "MON" as "M" over "O" over "N". Meanwhile the dish name beside that
    /// chip — the thing a person is actually reading — has a whole row to
    /// grow into and should keep growing.
    ///
    /// So the furniture holds at xxLarge and the content runs to AX5. iOS
    /// does the same with its own tab bars, and swaps presentation entirely
    /// at accessibility sizes, which a floating custom bar cannot do.
    ///
    /// This changes what is DRAWN, never what is READ: VoiceOver takes the
    /// string, and every one of these already carries an accessibility
    /// label that says the whole thing.
    func plChrome() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// A fixed composition until the text outgrows the screen.
    ///
    /// The counterpart to `plChrome()`. Chrome caps its Dynamic Type because
    /// it has nowhere to reflow; a whole screen cannot cap — a title is
    /// content and DESIGN.md says it keeps growing — so instead it has to be
    /// draggable once it stops fitting. Onboarding was the one part of the
    /// app with neither answer: at accessibility sizes the hero, the
    /// illustration and the button do not fit together on any iPhone, so the
    /// button left the screen and there was nothing to scroll to reach it.
    /// The keyboard did the same thing at the default size.
    ///
    /// The content is floored to the viewport, so a layout that already fits
    /// is untouched, Spacers still push, and nothing bounces.
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

/// Stable identities for zoom transitions whose source is not a model
/// object — a masthead avatar, a person row. Anything backed by SwiftData
/// uses its own `persistentModelID` instead, which is already stable and
/// already unique.
enum ZoomID: Hashable {
    /// The masthead avatar that opens your own profile.
    case host
    /// A row or avatar that opens somebody's profile. Keyed on the name,
    /// which `Seats.isTaken` already keeps unique at one table.
    case person(String)
    /// An author's face on one specific post.
    ///
    /// Keyed on the post rather than the name, because a feed routinely
    /// shows two dinners by the same person and two sources may not share
    /// one id in one namespace. It is deliberately not the post's own id
    /// either: that already belongs to the card, which is the door to the
    /// thread, and the face beside it goes somewhere else.
    case author(PersistentIdentifier)
}

// MARK: - Shared atoms

/// The tracked micro-label above titles: "AUGUST 21–27", "WHO COOKS WHEN".
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

/// The app's icon button: a 38pt hairline circle around a 14pt glyph,
/// floored to a 44pt target.
///
/// It was hand-drawn in twelve places and every one of them agreed, which is
/// the tell that it wanted to be a component. The thirteenth place did not
/// agree: Discover's back control was a bare 17pt chevron in a 44pt box, so
/// pushing into Discover from the Table — one tap from Activity, which uses
/// the disc — dropped the container off the back button and shifted the
/// heading 10pt left. The top 60pt of the screen is the thing a person
/// orients on, and it changed shape between two destinations reached from
/// the same place.
struct IconDiscButton: View {
    let systemName: String
    let label: String
    /// 14 everywhere but the Table's masthead, which sets 15.
    var glyphSize: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: glyphSize, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .plTapTarget()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        // A 38pt disc with a fixed glyph is furniture, and furniture caps.
        // ActivityBellButton beside it already did; this one did not, so a
        // masthead holding both grew unevenly. Capping the component rather
        // than each masthead is the point of having a component.
        .plChrome()
    }
}

/// The round commit button at the end of an entry field.
///
/// Two of these sat in one recipe form disagreeing on three things with no
/// state behind any of them: diameter (36 against 40), ground (a filled disc
/// against a stroked ring), and whether being disabled looked like anything
/// at all. The filled one wins, because it is the only one of the pair that
/// showed you it was off, and the only one that can carry a count. 38 is the
/// diameter the rest of the app's round controls already use.
struct AddCircleButton: View {
    let label: String
    /// Above one, the disc says how many things are about to be added, so
    /// what is going to happen is visible before it happens.
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

/// A tappable choice: a glyph, what it does, and what that means. The row
/// every stacked-option sheet in the app is made of.
///
/// **It takes no emphasis parameter, and that is the point.** Two hand-kept
/// copies of this row lived in `MainShellView` and `RecipeShareSheet`, and
/// both carried a `weighted` flag that filled one row of a peer set with
/// `Color.fill`. Two things were wrong with that. `fill` is this app's
/// SELECTION ground, so a row nobody had selected was painted as though
/// somebody had. And `hairline` on `fill` measures 1.05:1, which is not a
/// border, so the weighted row also lost the outline every other row in the
/// set was wearing: same stroke in the code, 3.5 times more visible on the
/// row beside it. One choice read as a solid block among outlines.
///
/// Emphasis in a list of choices is position and copy. See DESIGN.md,
/// "One row, one geometry".
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
            .background(Radius.shape(Radius.card).fill(Color.canvas))
            .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        // Two lines that are one sentence: without this VoiceOver reads the
        // title and the detail as two separate elements inside a button.
        .accessibilityElement(children: .combine)
    }
}

/// A chip that is on or off: a filter, a meal, a kind of dish, a sort.
///
/// Two hand-kept copies of this control carried three defects between them,
/// and the first is why it lives here rather than in a comment at each site.
///
/// **It was barely tappable.** An unselected chip draws
/// `Capsule().strokeBorder`, and a stroked shape hit-tests its ring and
/// nothing else. With no `contentShape` the live area collapsed to the
/// label's own layout box — roughly 18pt inside a 36pt control on the
/// cookbook filter, across about twenty controls on the tab's only filtering
/// surface. The one chip that answered a tap reliably was the one already
/// selected, because a filled capsule does hit-test. Two other copies in the
/// app already carried the fix, one with a comment naming this mechanism.
///
/// **It never said it was on.** Neither copy set `.isSelected`, so VoiceOver
/// read twenty identical buttons and never said which filter was applied.
/// Colour is the only other carrier and colour is inaudible.
///
/// **It buzzed like a commit.** Both opened with `Haptic.tap`. Moving
/// between options is a change of position, which is what `select` is for.
struct SelectChip<Label: View>: View {
    let active: Bool
    /// The height of the drawn capsule. The touch target is always 44; this
    /// only sets how big the chip looks.
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
                .foregroundStyle(active ? Color.canvas : Color.ink)
                .padding(.horizontal, 13)
                .frame(minHeight: height)
                .background {
                    if active {
                        Capsule().fill(Color.ink)
                    } else {
                        Capsule().strokeBorder(Color.hairline)
                    }
                }
                // The target goes outside the drawn capsule, and stays a
                // capsule: `plTapTarget` forces `minWidth: 44` and a
                // Rectangle, which would square off the hit area and widen
                // short chips inside a flow layout.
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A number and the thing it counts. No glyph, no box.
///
/// Instagram's profile triad and X's metric row agree on this: a count
/// that needs an icon to be legible has the wrong label, and a hairline
/// box around a number reads as a button that isn't one. So the label
/// carries the meaning and the chrome goes away. Sentence case, not the
/// all-caps micro-type — a household is not a dashboard.
struct CountBlock: View {
    let value: String
    let label: String
    /// Mango, for the one count that is a compliment.
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

/// The rule between two counts — a hairline, since the boxes are gone.
struct CountDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }
}

/// A photo filling a fixed-height well, which never makes its row wider
/// than the row was offered.
///
/// `.scaledToFill().frame(maxWidth: .infinity).frame(height: h)` looks
/// like it does this, and doesn't. `maxWidth: .infinity` is a ceiling, not
/// a clamp: `scaledToFill` sizes a landscape photo to cover the height, so
/// the image reports a width wider than the screen and the frame happily
/// accepts it. One of those inside a feed card made the whole card wider
/// than the viewport, and a vertical ScrollView centres content it can't
/// fit — so every row shunted left with its avatar, plate count and
/// caption half off the screen.
///
/// An overlay never affects its parent's layout size, so the well stays
/// exactly as wide as it was offered and the overflow is clipped instead
/// of measured.
struct PhotoWell: View {
    let image: UIImage
    /// A fixed band. Right where the photograph is furniture and the layout
    /// around it must not move: a profile banner, a recipe hero, the
    /// composer's preview.
    var height: CGFloat?
    /// The photograph's own shape, clamped to the range a feed can hold.
    ///
    /// Right where the photograph IS the content. The Table forced every
    /// dinner into the same 300pt band with `scaledToFill`, so a portrait
    /// photo — which is most photos of a plate taken standing over it — lost
    /// its top and bottom to the crop, and a wide one lost its sides. This
    /// is the one screen whose stated register is "a family's own
    /// photographs are the only loud thing on screen", and the photographs
    /// were the least considered thing on it.
    ///
    /// Clamped rather than free: 4:5 up and 1.91:1 across, which is
    /// Instagram's range and exists so one very tall photo cannot take the
    /// whole screen and push the next post out of the scroll.
    var clamped = false
    var cornerRadius: CGFloat = Radius.card

    /// Portrait ceiling and landscape floor, as width ÷ height.
    private var ratio: CGFloat {
        let natural = image.size.height > 0 ? image.size.width / image.size.height : 1
        return min(max(natural, 4.0 / 5.0), 1.91)
    }

    var body: some View {
        Group {
            if clamped {
                Color.clear
                    .aspectRatio(ratio, contentMode: .fit)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: height ?? 240)
            }
        }
        .overlay {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
        .clipShape(Radius.shape(cornerRadius))
    }
}

/// The real mark — lowercase "plated" with its tomato period, the same
/// lockup the launch opener resolves into (dot ≈ 0.27em seated 0.34em down).
/// Gabarito medium is the wordmark's register, matching the opener.
struct PlatedWordmark: View {
    var size: CGFloat = 26
    /// `Font.custom(_:size:)` scales against the body style on its own, so
    /// the word grew with Dynamic Type while the dot, its gap and its
    /// baseline offset were all plain points and stayed put: by AX5 the
    /// wordmark had a tiny dot floating beside a large word, at the wrong
    /// height. Everything geometric here is measured in the same unit the
    /// text is.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        let s = size * unit
        return HStack(alignment: .top, spacing: s * 0.10) {
            Text("plated")
                .font(.gabarito(size, .medium))
                .tracking(-0.022 * s)
                .foregroundStyle(Color.ink)
            Circle()
                .fill(Color.tomato)
                .frame(width: s * 0.27, height: s * 0.27)
                .padding(.top, s * 0.34)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plated")
    }
}

/// Initials in a tinted circle — people are circles, like dishes.
struct AvatarCircle: View {
    let initials: String
    let tone: PersonTone
    var size: CGFloat = 34
    /// Their actual face, when we have one. The initials are what we fall
    /// back to, not what we lead with.
    var photo: Data?

    /// The common case: draw a household member, face first.
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
                    .font(.jakarta(size * 0.38, .bold))
                    .foregroundStyle(tone.tone)
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

/// The full-width tomato pill — reserved for the one committing action
/// on a screen. Anything less takes the ink or outline pill.
struct TomatoPillButton: View {
    let title: String
    var systemImage: String?
    /// Working. The spinner replaces the glyph rather than joining it, so
    /// the pill does not change width mid-press. A committing action that
    /// can take a moment is common enough that hand-rolling the busy state
    /// is what put two 48pt copies of this pill in the import sheet.
    var busy: Bool = false
    /// Haptics carry meaning here: `tap` for ordinary chrome, `plate` for
    /// something landing, `kiss` for the good thing. Most committing pills
    /// are a tap, but a save that earns the kiss must keep it — flattening
    /// every pill to one buzz is how a shared component quietly costs a
    /// screen its voice.
    var haptic: () -> Void = Haptic.tap
    let action: () -> Void

    /// Set by `.disabled()` on the caller. Read here so the pill can dress
    /// its own off state instead of every call site fading the whole thing.
    @Environment(\.isEnabled) private var isEnabled

    /// Working is not the same as not ready, and the two states were wearing
    /// one dress.
    ///
    /// Every call site that shows a spinner also disables the pill so the
    /// action cannot be fired twice — `busy: reading` beside
    /// `.disabled(… || reading)`. That drove `isEnabled` false, so the ground
    /// went to `fill` and the spinner kept its `onTomato` tint: white on
    /// 0xF4F1EC, about 1.13:1, which is not a spinner, it is nothing. For the
    /// twenty seconds `RecipeImporter` allows a parse, the import sheet's
    /// primary control sat greyed out and apparently idle while it worked.
    ///
    /// So busy wins the paint and disabled keeps the tap. Nothing changes at
    /// a call site.
    private var awake: Bool { isEnabled || busy }

    var body: some View {
        Button {
            // A pill can be busy without being disabled. Guard here rather
            // than trusting every future call site to pair the two.
            guard !busy else { return }
            haptic()
            action()
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(awake ? Color.onTomato : Color.inkSecondary)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title).plType(.callout)
            }
            .foregroundStyle(awake ? Color.onTomato : Color.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
        }
        .buttonStyle(TomatoPillStyle(enabled: awake))
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
                Text(title).plType(.callout)
            }
            .foregroundStyle(Color.canvas)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
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
    var enabled: Bool = true

    /// A disabled pill changes colour; it does not fade.
    ///
    /// Every call site used to write `.disabled(x)` next to `.opacity(x ? 1 :
    /// 0.4)`, and fading the whole pill fades the label and the fill by the
    /// same amount, so the two collapse toward each other. Measured in the
    /// light room: white on tomato is 3.10:1 enabled, 1.80:1 at 0.5 opacity,
    /// and the label itself composites to exactly the canvas colour — 1.00:1
    /// against the page. It is not dim, it is gone. The first screen after
    /// sign-in opens with its primary button in that state.
    ///
    /// inkSecondary on fill measures 4.11:1 in the light room and 5.83:1
    /// after dark, and the fill still reads as a capsule against canvas, so
    /// the control is plainly present and plainly not ready.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(ground(pressed: configuration.isPressed), in: Capsule())
            .plFloatShadow()
            .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
            .animation(.plSnap, value: configuration.isPressed)
    }

    private func ground(pressed: Bool) -> Color {
        guard enabled else { return .fill }
        return pressed ? .tomatoPressed : .tomato
    }
}
