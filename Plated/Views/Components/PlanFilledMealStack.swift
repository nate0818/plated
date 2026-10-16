import SwiftUI

/// Dish square + title + avatar + who-line, for a filled Plan row.
///
/// The square's top is the meal title's top and its bottom is the who-line
/// avatar's bottom — the full vertical stack, cover-cropped, no float and
/// no letterbox. Growing the square to match is the fail-closed move;
/// shrinking the face or inventing Plan chrome is not. Meal title
/// ellipsizes first; the who-line is allowed to wrap rather than truncate
/// mid-word.
struct PlanFilledMealStack<Face: View>: View {
    var photo: Data?
    var title: String
    var eatingOut: Bool
    var whoLine: String
    /// Tonight's card sits on `fill`, so its dish well is `canvas` or the
    /// square vanishes into the card. List rows sit on `canvas` and use
    /// `fill` for an empty well.
    var onFill = false
    /// Tonight's featured card is the same stack at a slightly larger type.
    var featured = false
    var today = false
    @ViewBuilder var face: () -> Face

    var body: some View {
        PlanPhotoStackLayout(spacing: 10) {
            PlanDishSquare(
                photo: photo,
                eatingOut: eatingOut,
                well: onFill ? Color.canvas : Color.fill
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .plType(featured ? .heading : .callout, .semibold, family: .text)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(alignment: .center, spacing: 6) {
                    face()
                    Text(whoLine)
                        .plType(.caption, .semibold)
                        .foregroundStyle(today ? Color.ink : Color.inkSecondary)
                        // The who-line is the sentence the row exists to say.
                        // Truncating it mid-word ("we're eating…") is the
                        // failure the title's lineLimit is there to prevent.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Square dish for a filled Plan row. Photos cover-crop; eat-out is a
/// building on a well, never a letterboxed plate.
private struct PlanDishSquare: View {
    var photo: Data?
    var eatingOut: Bool
    var well: Color

    var body: some View {
        well
            .overlay {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    if eatingOut {
                        Image(systemName: "building.2")
                            .font(.system(size: side * 0.38, weight: .regular))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.system(size: side * 0.38, weight: .light))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .clipShape(Radius.shape(Radius.small))
            .contentShape(Radius.shape(Radius.small))
            .accessibilityHidden(true)
    }
}

/// Two children: the dish (0) and the text stack (1). The dish is a square
/// whose side equals the stack's height, top-aligned with the title.
///
/// `SwiftUI.Layout`, not `Layout`: Theme.swift already owns that name for
/// chrome insets, and CookbookView's `FlowLayout` is the same qualification.
struct PlanPhotoStackLayout: SwiftUI.Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let stack = subviews[1]
        let proposedWidth = proposal.width
        var photo: CGFloat = 44
        var stackSize = CGSize.zero
        for _ in 0..<6 {
            let stackWidth: CGFloat?
            if let proposedWidth, proposedWidth.isFinite, proposedWidth > 0 {
                stackWidth = max(0, proposedWidth - photo - spacing)
            } else {
                stackWidth = nil
            }
            stackSize = stack.sizeThatFits(
                ProposedViewSize(width: stackWidth, height: proposal.height)
            )
            let next = max(stackSize.height, 1)
            if abs(next - photo) < 0.5 { break }
            photo = next
        }
        let height = max(photo, stackSize.height)
        let width: CGFloat
        if let proposedWidth, proposedWidth.isFinite, proposedWidth > 0 {
            width = proposedWidth
        } else {
            width = photo + spacing + stackSize.width
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        let photo = bounds.height
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: photo, height: photo)
        )
        let stackX = bounds.minX + photo + spacing
        let stackWidth = max(0, bounds.maxX - stackX)
        subviews[1].place(
            at: CGPoint(x: stackX, y: bounds.minY),
            proposal: ProposedViewSize(width: stackWidth, height: nil)
        )
    }
}
