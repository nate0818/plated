import WidgetKit
import SwiftUI

/// The newest thing on the table. The photo does all the work — this is the
/// one widget where the food fills the frame and the type gets out of the way.

struct TableWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var card: WeekSnapshot.TableCard? { entry.snapshot?.table }

    var body: some View {
        Group {
            if let card {
                if family == .systemSmall {
                    small(card)
                } else {
                    wide(card)
                }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(PlatedLink.table)
        .containerBackground(Plate.canvas, for: .widget)
    }

    // MARK: Small — photo edge to edge, one line of credit over it.

    private func small(_ card: WeekSnapshot.TableCard) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let photo = entry.tablePhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                // A scrim, not a slab: legible type without dimming the food.
                LinearGradient(
                    colors: [Plate.scrimInk.opacity(0), Plate.scrimInk.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.firstName)
                        .font(.jakarta(13))
                        .foregroundStyle(Plate.onScrim)
                    plates(card, onPhoto: true)
                }
                .padding(12)
            } else {
                textOnly(card)
            }
        }
    }

    // MARK: Medium/large — photo beside the words.

    private func wide(_ card: WeekSnapshot.TableCard) -> some View {
        HStack(spacing: 14) {
            if let photo = entry.tablePhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: family == .systemLarge ? 150 : 108,
                           height: family == .systemLarge ? 150 : 108)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            VStack(alignment: .leading, spacing: 6) {
                MicroCap(text: "ON THE TABLE")
                HStack(spacing: 7) {
                    CookDot(initial: card.authorInitial, hex: card.authorHex, size: 22)
                    Text(card.authorName)
                        .font(.jakarta(13))
                        .foregroundStyle(Plate.ink)
                        .lineLimit(1)
                }
                if !card.dishTitle.isEmpty {
                    Text(card.dishTitle)
                        .font(.jakarta(15))
                        .foregroundStyle(Plate.ink)
                        .lineLimit(1)
                }
                Text(card.caption)
                    .font(.jakarta(12, "Medium"))
                    .foregroundStyle(Plate.inkSecondary)
                    .lineLimit(family == .systemLarge ? 4 : 2)
                Spacer(minLength: 0)
                plates(card, onPhoto: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            plates(card, onPhoto: false)
        }
    }

    /// The plate mark is the reaction, so the count wears the plate — never a
    /// heart, never a pill.
    private func plates(_ card: WeekSnapshot.TableCard, onPhoto: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: card.plates >= 10 ? "circle.circle.fill" : "circle.circle")
                .font(.system(size: 12, weight: .semibold))
            Text("\(card.plates)")
                .font(.jakarta(12))
            if card.commentCount > 0 {
                Image(systemName: "bubble.right")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.leading, 4)
                Text("\(card.commentCount)")
                    .font(.jakarta(12))
            }
        }
        .foregroundStyle(onPhoto ? Plate.onScrim.opacity(0.92) : Plate.inkSecondary)
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
    }
}
