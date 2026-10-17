import SwiftUI

/// Artwork has independent geometry so text reflow cannot enlarge it recursively.
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

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout {
            PlanDishSquare(
                photo: photo,
                eatingOut: eatingOut,
                well: onFill ? Color.canvas : Color.fill
            )
            .frame(width: featured ? 72 : 56, height: featured ? 72 : 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .plType(featured ? .heading : .callout, .semibold, family: .text)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
