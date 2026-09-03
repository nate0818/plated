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
              line: "Paste a link, scan a card, or write it out."),
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

            illustration(index)
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
            .padding(.horizontal, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(panel.eyebrow). \(panel.title). \(panel.line)")
    }

    @ViewBuilder
    private func illustration(_ index: Int) -> some View {
        switch index {
        case 0: tonightPlate
        case 1: weekStrip
        case 2: tableSeats
        default: cookbookShelf
        }
    }

    /// The real plate the plan draws, at the size the Tonight card uses.
    private var tonightPlate: some View {
        DishView(title: "Sheet-pan chicken", diameter: 132)
            .plDishShadow()
    }

    /// The week's date chips, with today tinted, at the geometry the list
    /// uses: `Radius.small`, `hairline`, and the one standing exception
    /// DESIGN.md allows for today's card.
    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { day in
                let today = day == 3
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(today ? Color.tomatoTint : Color.cardFill)
                    .frame(width: 34, height: today ? 78 : 62)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(today ? Color.tomato.opacity(0.16) : Color.hairline,
                                          lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        Circle()
                            .fill(day < 4 ? Color.basil : Color.hairline)
                            .frame(width: 6, height: 6)
                            .padding(.top, 10)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// The seat cluster the Table's masthead wears, ending in the dashed
    /// invitation that is the real control for asking somebody in.
    private var tableSeats: some View {
        HStack(spacing: -12) {
            AvatarCircle(initials: "N", tone: .tomatoPair, size: 62)
                .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
            AvatarCircle(initials: "S", tone: .basilPair, size: 62)
                .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
            AvatarCircle(initials: "R", tone: .grapePair, size: 62)
                .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
            Circle()
                .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .frame(width: 62, height: 62)
                .background(Circle().fill(Color.canvas))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.inkFaint)
                }
        }
        .accessibilityHidden(true)
    }

    /// Three plates, the way the cookbook grid holds them.
    private var cookbookShelf: some View {
        HStack(spacing: -18) {
            DishView(title: "Lemon orzo", diameter: 88).plDishShadow()
            DishView(title: "Chili", diameter: 104).plDishShadow()
            DishView(title: "Roast squash", diameter: 88).plDishShadow()
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
