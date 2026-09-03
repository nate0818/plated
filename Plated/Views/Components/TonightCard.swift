import SwiftUI
import SwiftData

/// The answer to the question the app is for, at the top of the week.
///
/// On a Thursday, tonight's dinner was the fifth row of the plan, sitting at
/// the vertical centre of the screen under four nights already eaten. The
/// largest type on the screen said "Your week". This hands that weight to
/// the name of the food.
///
/// It is the same object the Home Screen widget has always drawn and the
/// same sentence Siri has always spoken. The app was the last surface to
/// say it.
///
/// Emphasis here is position and size, not paint: the card wears the same
/// `Radius.row` container, the same `navHairline` at 1.5 and the same
/// `cardFill` as every row beneath it, because DESIGN.md's rule is that a
/// filled ground is this app's SELECTION idiom and a set of peers gets one
/// treatment. What makes this one the head of the list is that it is
/// centred, it is tall, and it is first.
struct TonightCard: View {
    let state: TonightAnswer.State
    /// The plan's namespace, so the plate is the thing that opens. Tonight's
    /// row has left the list below, so this card is the only door to it and
    /// it has to carry the source.
    var zoom: Namespace.ID
    /// Tapping the dish opens it. Nil states draw no door.
    var onOpenDish: (PlannedMeal) -> Void = { _ in }
    var onPlanTonight: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            MicroLabel(eyebrow)

            plate

            Text(headline)
                // 32pt against the masthead's 27, so the food is the largest
                // thing on the screen. Semibold rather than the step's own
                // extraBold: the weight law keeps extraBold off display sizes.
                .plType(.hero, .semibold)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                // A title wraps, it never truncates.
                .fixedSize(horizontal: false, vertical: true)

            if let line = factLine {
                Text(line)
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .open = state {
                TomatoPillButton(title: "Plan tonight", haptic: Haptic.plate) {
                    onPlanTonight()
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.cardFill, in: Radius.shape(Radius.row))
        .overlay {
            Radius.shape(Radius.row)
                .strokeBorder(Color.navHairline, lineWidth: 1.5)
        }
        .plCardShadow()
        .contentShape(Radius.shape(Radius.row))
        .accessibilityElement(children: .combine)
    }

    // MARK: Pieces

    @ViewBuilder
    private var plate: some View {
        switch state {
        case let .plated(meal), let .cooked(meal):
            Button {
                Haptic.tap()
                onOpenDish(meal)
            } label: {
                dish(for: meal)
            }
            .buttonStyle(.pressable)
            .matchedTransitionSource(id: meal.date, in: zoom)
            .accessibilityLabel("Open \(meal.title)")
        case .open:
            // The same dashed invitation an open night wears in the list, at
            // the card's scale. One dashed thing per state is enough to say
            // "nothing here yet".
            Circle()
                .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [7, 7]))
                .frame(width: 140, height: 140)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        // An icon on a control that is genuinely waiting.
                        .foregroundStyle(Color.inkFaint)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func dish(for meal: PlannedMeal) -> some View {
        Group {
            if let data = meal.recipe?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
            } else if let recipe = meal.recipe {
                // The first plate in the shipping app drawn with its drift
                // running. DishView has carried the animation since it was
                // written and nothing has ever passed true.
                DishView(recipe: recipe, diameter: 140, animated: !reduceMotion)
            } else {
                DishView(title: meal.title, diameter: 140)
            }
        }
        .plDishShadow()
    }

    private var eyebrow: String {
        switch state {
        case .cooked: return "Tonight · cooked"
        case .plated, .open: return "Tonight"
        }
    }

    private var headline: String {
        switch state {
        case let .plated(meal), let .cooked(meal): return meal.title
        case .open: return "Nothing plated for tonight"
        }
    }

    private var factLine: String? {
        switch state {
        case let .plated(meal): return TonightAnswer.factLine(for: meal)
        case let .cooked(meal):
            // Past tense, because it happened. The cook still gets the credit.
            guard let cook = meal.cook else { return "Cooked" }
            return cook.isOwner ? "You cooked it" : "\(cook.name) cooked it"
        case .open: return nil
        }
    }
}
