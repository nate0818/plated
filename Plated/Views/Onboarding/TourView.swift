import SwiftUI

/// Four cards, once, at the end of setting up.
///
/// Every panel draws the app's own furniture rather than a picture of it:
/// the real `DishView` plate, the real `AvatarCircle`, the same date chip
/// geometry the week list uses. A tour illustrated with things that do not
/// appear in the product teaches somebody an app they are not about to open,
/// and it goes stale the first time a screen changes.
///
/// Owed once, like the launch opener. Anybody whose table already exists has
/// met the app and is not walked through it: see `sawTour` in RootView.
struct TourView: View {
    var onDone: () -> Void

    @State private var page = 0

    private struct Panel: Identifiable {
        let id = UUID()
        let eyebrow: String
        let title: String
        let line: String
    }

    /// Four screens, named the way the app names them, so the tour teaches
    /// the real nouns rather than a set of marketing ones.
    ///
    /// Each line is a fact about what the app does, not a description of how
    /// it feels to use it. The first draft said "Everyone in the household
    /// sees the same week", which is false: the store is
    /// `cloudKitDatabase: .automatic`, so the plan reaches this person's own
    /// devices and nobody else's. Only the Table has a shared zone. An
    /// onboarding screen is the worst possible place to be wrong about that,
    /// because it is the one screen a person has no way to check.
    private let panels: [Panel] = [
        Panel(eyebrow: "Tonight",
              title: "What's for dinner",
              line: "Tonight's dish and tonight's cook, before you tap anything."),
        Panel(eyebrow: "Your week",
              title: "Seven nights",
              line: "Plan them ahead, and hand any night to somebody else to cook."),
        Panel(eyebrow: "The Table",
              title: "Invite only",
              line: "Post what you cooked. Only the people you invite can see it."),
        Panel(eyebrow: "Recipes",
              title: "Dishes you'll cook again",
              // 59 characters, like its three siblings. At 43 it was too
              // long for one line and too short to fill two, so the second
              // line was "it out." on its own: the only card in the set
              // whose copy did not wrap evenly, which is what made it look
              // broken rather than short.
              line: "Paste a link, scan a recipe card, or write one out by hand."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") {
                    Haptic.tap()
                    onDone()
                }
                .plType(.footnote, .semibold)
                .foregroundStyle(Color.inkSecondary)
                .plTapTarget()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(Array(panels.enumerated()), id: \.element.id) { index, panel in
                    panelView(panel, index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            dots
                .padding(.bottom, 20)

            TomatoPillButton(
                title: page == panels.count - 1 ? "Start planning" : "Next",
                haptic: page == panels.count - 1 ? Haptic.plate : Haptic.tap
            ) {
                if page == panels.count - 1 {
                    onDone()
                } else {
                    withAnimation(.plSnap) { page += 1 }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.canvas.ignoresSafeArea())
    }

    // MARK: Panels

    private func panelView(_ panel: Panel, index: Int) -> some View {
        // One group, centred, with the room above and below it rather than
        // between its two halves. Spacers on either side of the picture
        // pushed it to the top third and the words to the bottom third, so
        // a card that is one idea read as two things at opposite ends of a
        // screen.
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            illustration(index, isActive: page == index)
                .frame(height: 168)
                // The arrival the rest of the app uses, so the tour moves
                // the way the product moves.
                .transition(.plArrive)
                .padding(.bottom, 34)

            VStack(spacing: 10) {
                MicroLabel(panel.eyebrow)
                Text(panel.title)
                    .plType(.hero, .semibold)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(panel.line)
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A measure, not just a margin. At the full width minus 32 a
            // line held about fifty characters, so a two-line sentence put
            // forty-odd on the first line and two words on the second. The
            // fix is not shorter copy, it is a narrower column: the break
            // then lands near the middle at every text size instead of only
            // at the one the copy was counted against.
            .frame(maxWidth: 300)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(panel.eyebrow). \(panel.title). \(panel.line)")
    }

    @ViewBuilder
    private func illustration(_ index: Int, isActive: Bool) -> some View {
        switch index {
        case 0: tonightPlate
        case 1: TourWeek(isActive: isActive)
        case 2: TourSeats(isActive: isActive)
        default: cookbookShelf
        }
    }

    /// Tonight's dinner, at the size the Tonight card uses.
    private var tonightPlate: some View {
        TourPlate(asset: "TourNachos", fallbackTitle: "Sheet-pan chicken", diameter: 132)
    }

    /// Three plates, the way the cookbook grid holds them.
    private var cookbookShelf: some View {
        HStack(spacing: -18) {
            TourPlate(asset: "TourSalad", fallbackTitle: "Lemon orzo", diameter: 88)
            TourPlate(asset: "TourPasta", fallbackTitle: "Chili", diameter: 104)
            TourPlate(asset: "TourRamen", fallbackTitle: "Roast squash", diameter: 88)
        }
        .accessibilityHidden(true)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<panels.count, id: \.self) { index in
                Capsule()
                    // Ink and hairline, not tomato. A page indicator is
                    // chrome, and DESIGN.md keeps ambient accent out of
                    // chrome: the one tomato on this screen is the pill that
                    // moves you forward.
                    .fill(index == page ? Color.ink : Color.hairline)
                    .frame(width: index == page ? 18 : 6, height: 6)
            }
        }
        .animation(.plSnap, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(panels.count)")
    }
}
