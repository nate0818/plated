import WidgetKit
import SwiftUI

/// The newest thing on the table. The photo does all the work — this is the
/// one widget where the food fills the frame and the type gets out of the way.

struct TableWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var card: WeekSnapshot.TableCard? { entry.snapshot?.table }
    private var photo: UIImage? { card?.hasPhoto == true ? entry.tablePhoto : nil }

    /// The system's content margin, applied by hand: the photograph takes
    /// the whole frame and the words keep their inset.
    private let inset: CGFloat = 16

    var body: some View {
        Group {
            if let card {
                switch family {
                case .systemSmall: small(card)
                case .systemLarge: large(card)
                default: medium(card)
                }
            } else {
                empty
            }
        }
        .widgetURL(PlatedLink.table)
        .containerBackground(Plate.canvas, for: .widget)
    }

    // MARK: Small — the photograph is the widget, one line of credit over it.

    private func small(_ card: WeekSnapshot.TableCard) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                fill(photo)
                GlassBand(inset: inset) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.dishTitle.isEmpty ? card.firstName : card.dishTitle)
                            .font(.jakarta(15))
                            .foregroundStyle(Plate.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        credit(card)
                    }
                }
            } else {
                textOnly(card)
                    .padding(inset)
            }
        }
    }

    // MARK: Medium — the photograph on the left, the words beside it.

    private func medium(_ card: WeekSnapshot.TableCard) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if let photo {
                    fill(photo)
                        .frame(width: geo.size.width * 0.42)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 6) {
                    MicroCap(text: "ON THE TABLE")
                    if !card.dishTitle.isEmpty {
                        Text(card.dishTitle)
                            .font(.jakarta(15))
                            .foregroundStyle(Plate.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(card.caption)
                        .font(.jakarta(12, "Medium"))
                        .foregroundStyle(Plate.inkSecondary)
                        .lineLimit(card.dishTitle.isEmpty ? 4 : 2)
                    Spacer(minLength: 0)
                    credit(card)
                }
                .padding(inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Large — the photograph as a band, the post beneath it.

    private func large(_ card: WeekSnapshot.TableCard) -> some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                if let photo {
                    fill(photo)
                        .frame(height: geo.size.height * 0.54)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 6) {
                    MicroCap(text: "ON THE TABLE")
                    HStack(spacing: 7) {
                        CookDot(initial: card.authorInitial, hex: card.authorHex, size: 22)
                        Text(card.authorName)
                            .font(.jakarta(13))
                            .foregroundStyle(Plate.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        plates(card)
                    }
                    if !card.dishTitle.isEmpty {
                        Text(card.dishTitle)
                            .font(.jakarta(17))
                            .foregroundStyle(Plate.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(card.caption)
                        .font(.jakarta(13, "Medium"))
                        .foregroundStyle(Plate.inkSecondary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .padding(inset)
            }
        }
    }

    private func fill(_ photo: UIImage) -> some View {
        GeometryReader { geo in
            Image(uiImage: photo)
                .resizable()
                // Image-only, so it sits between resizable and the fill,
                // never after a frame. A tinted home screen (iOS 18)
                // flattens every view to the accent colour unless it says
                // otherwise; a photograph of dinner stays a photograph.
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }

    private func textOnly(_ card: WeekSnapshot.TableCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroCap(text: "ON THE TABLE")
            Spacer(minLength: 0)
            CookDot(initial: card.authorInitial, hex: card.authorHex, size: 30)
            Text(card.dishTitle.isEmpty ? card.caption : card.dishTitle)
                .font(.jakarta(14))
                .foregroundStyle(Plate.ink)
                .lineLimit(3)
            Spacer(minLength: 0)
            plates(card)
        }
    }

    /// Who posted it, and the plates it has drawn.
    private func credit(_ card: WeekSnapshot.TableCard) -> some View {
        HStack(spacing: 6) {
            CookDot(initial: card.authorInitial, hex: card.authorHex, size: 16)
            Text(card.firstName)
                .font(.jakarta(11, "SemiBold"))
                .foregroundStyle(Plate.inkSecondary)
                .lineLimit(1)
            plates(card)
                .padding(.leading, 2)
        }
    }

    /// The plate mark is the reaction, so the count wears the plate — never a
    /// heart, never a pill. And no numeral until there is something to count:
    /// a mounted zero on a dinner nobody has got to yet is a verdict, not a
    /// fact (DESIGN.md, "A count is evidence, never furniture").
    @ViewBuilder
    private func plates(_ card: WeekSnapshot.TableCard) -> some View {
        if card.plates > 0 || card.commentCount > 0 {
            HStack(spacing: 4) {
                if card.plates > 0 {
                    Image(systemName: card.plates >= 10 ? "circle.circle.fill" : "circle.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(card.plates)")
                        .font(.jakarta(11))
                }
                if card.commentCount > 0 {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.leading, card.plates > 0 ? 4 : 0)
                    Text("\(card.commentCount)")
                        .font(.jakarta(11))
                }
            }
            .foregroundStyle(Plate.inkSecondary)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroCap(text: "ON THE TABLE")
            Spacer(minLength: 0)
            Image(systemName: "circle.circle")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Plate.inkFaint)
            Text("Nothing on the table yet")
                .font(.jakarta(14))
                .foregroundStyle(Plate.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(inset)
    }
}

struct TableWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TableWidget", provider: WeekProvider()) { entry in
            TableWidgetView(entry: entry)
        }
        .configurationDisplayName("The Table")
        .description("The newest dish your table posted.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // The photograph takes the whole frame; the words inset themselves.
        .contentMarginsDisabled()
    }
}
