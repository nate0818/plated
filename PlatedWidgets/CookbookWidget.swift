import WidgetKit
import SwiftUI

/// The dish the household keeps coming back to. A favourite with a
/// photograph first, then whatever has been cooked most: the widget is the
/// picture, and the fact line under it says why this one.

private func cookbookLine(_ card: WeekSnapshot.CookbookCard) -> String {
    var parts: [String] = []
    if card.isFavorite { parts.append("Favorite") }
    if card.minutes > 0 { parts.append(durationText(card.minutes)) }
    if card.timesCooked > 0 {
        parts.append(card.timesCooked == 1 ? "Cooked once" : "Cooked \(card.timesCooked) times")
    }
    return parts.joined(separator: " · ")
}

struct CookbookWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var card: WeekSnapshot.CookbookCard? { entry.snapshot?.cookbook }
    private var photo: UIImage? { card?.hasPhoto == true ? entry.cookbookPhoto : nil }
    private let inset: CGFloat = 16

    var body: some View {
        Group {
            if let card {
                if family == .systemMedium { medium(card) } else { small(card) }
            } else {
                empty
            }
        }
        .widgetURL(PlatedLink.cookbook)
        .containerBackground(Plate.canvas, for: .widget)
    }

    private func small(_ card: WeekSnapshot.CookbookCard) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                fill(photo)
                GlassBand(inset: inset) { words(card, titleSize: 15) }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MicroCap(text: "COOKBOOK")
                    Spacer(minLength: 0)
                    words(card, titleSize: 15)
                }
                .padding(inset)
            }
        }
    }

    private func medium(_ card: WeekSnapshot.CookbookCard) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if let photo {
                    fill(photo)
                        .frame(width: geo.size.width * 0.42)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 6) {
                    MicroCap(text: "COOKBOOK")
                    Spacer(minLength: 0)
                    words(card, titleSize: 17)
                    Spacer(minLength: 0)
                }
                .padding(inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func words(_ card: WeekSnapshot.CookbookCard, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if photo != nil, family == .systemSmall {
                MicroCap(text: "COOKBOOK")
            }
            Text(card.title)
                .font(.jakarta(titleSize))
                .foregroundStyle(Plate.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
            let line = cookbookLine(card)
            if !line.isEmpty {
                Text(line)
                    .font(.jakarta(11, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func fill(_ photo: UIImage) -> some View {
        GeometryReader { geo in
            Image(uiImage: photo)
                .resizable()
                // Image-only, between resizable and the fill. A tinted home
                // screen (iOS 18) flattens everything else to the accent.
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroCap(text: "COOKBOOK")
            Spacer(minLength: 0)
            Image(systemName: "book.closed")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Plate.inkFaint)
            Text("No recipes yet")
                .font(.jakarta(14))
                .foregroundStyle(Plate.ink)
            Text("Tap to add one")
                .font(.jakarta(11, "SemiBold"))
                .foregroundStyle(Plate.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(inset)
    }
}

struct CookbookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CookbookWidget", provider: WeekProvider()) { entry in
            CookbookWidgetView(entry: entry)
        }
        .configurationDisplayName("Cookbook")
        .description("The dish your table keeps coming back to.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
