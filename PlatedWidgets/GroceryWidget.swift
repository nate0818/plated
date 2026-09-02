import WidgetKit
import SwiftUI

/// What's still to buy. The number is the point — the small size is a count
/// you can read from across the room, the medium adds the first few lines so
/// you know whether it's a corner-shop run or a proper trip.

struct GroceryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var grocery: WeekSnapshot.Grocery? { entry.snapshot?.grocery }

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(PlatedLink.grocery)
        .containerBackground(Plate.canvas, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroCap(text: "GROCERY")
            Spacer(minLength: 0)
            if let grocery, grocery.openCount > 0 {
                // No box around the number — the count is the thing itself.
                Text("\(grocery.openCount)")
                    .font(.jakarta(44, "ExtraBold"))
                    .foregroundStyle(Plate.ink)
                Text(grocery.openCount == 1 ? "item to buy" : "items to buy")
                    .font(.jakarta(13))
                    .foregroundStyle(Plate.inkSecondary)
                progress(grocery)
            } else {
                Image(systemName: "basket")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Plate.inkFaint)
                Text(grocery == nil ? "Nothing to shop for" : "All bought")
                    .font(.jakarta(14))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                MicroCap(text: "GROCERY")
                Spacer(minLength: 0)
                Text("\(grocery?.openCount ?? 0)")
                    .font(.jakarta(40, "ExtraBold"))
                    .foregroundStyle(Plate.ink)
                Text((grocery?.openCount ?? 0) == 1 ? "to buy" : "to buy")
                    .font(.jakarta(12))
                    .foregroundStyle(Plate.inkSecondary)
                if let grocery { progress(grocery) }
                Spacer(minLength: 0)
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                if let grocery, !grocery.sample.isEmpty {
                    ForEach(Array(grocery.sample.prefix(4).enumerated()), id: \.offset) { _, name in
                        HStack(spacing: 8) {
                            Circle()
                                .strokeBorder(Plate.hairlineDashed, lineWidth: 2)
                                .frame(width: 14, height: 14)
                            Text(name)
                                .font(.jakarta(13, "SemiBold"))
                                .foregroundStyle(Plate.ink)
                                .lineLimit(1)
                        }
                    }
                    if grocery.openCount > grocery.sample.count {
                        Text("+ \(grocery.openCount - grocery.sample.count) more")
                            .font(.jakarta(12))
                            .foregroundStyle(Plate.inkSecondary)
                    }
                } else {
                    Text("Plate a few nights and the list builds itself.")
                        .font(.jakarta(13, "SemiBold"))
                        .foregroundStyle(Plate.inkSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Bought-so-far as a hairline, not a chart. Basil only when it's done.
    private func progress(_ grocery: WeekSnapshot.Grocery) -> some View {
        let bought = max(grocery.totalCount - grocery.openCount, 0)
        let fraction = grocery.totalCount > 0 ? Double(bought) / Double(grocery.totalCount) : 0
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Plate.fill)
                    Capsule()
                        .fill(fraction >= 1 ? Plate.basil : Plate.ink)
                        .frame(width: max(geometry.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 4)
            Text("\(bought) of \(grocery.totalCount) in the basket")
                .font(.jakarta(10, "SemiBold"))
                .foregroundStyle(Plate.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.top, 4)
    }
}

struct GroceryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GroceryWidget", provider: WeekProvider()) { entry in
            GroceryWidgetView(entry: entry)
        }
        .configurationDisplayName("Grocery")
        .description("What's still to buy for the week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
