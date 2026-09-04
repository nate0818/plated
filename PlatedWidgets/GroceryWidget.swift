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
            switch family {
            case .systemLarge: large
            case .systemMedium: medium
            default: small
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
                // An empty list is decoration; a finished one earned basil.
                Image(systemName: "basket")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(grocery == nil ? Plate.inkFaint : Plate.basil)
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
                if let grocery, grocery.openCount > 0 {
                    Text("\(grocery.openCount)")
                        .font(.jakarta(40, "ExtraBold"))
                        .foregroundStyle(Plate.ink)
                    Text("to buy")
                        .font(.jakarta(12))
                        .foregroundStyle(Plate.inkSecondary)
                    progress(grocery)
                } else {
                    // The same state the small size shows. A "0" here was
                    // a mounted zero: the list being done is the news, and
                    // basil says it where a numeral cannot.
                    Image(systemName: "basket")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(grocery == nil ? Plate.inkFaint : Plate.basil)
                    Text(grocery == nil ? "Nothing to shop for" : "All bought")
                        .font(.jakarta(14))
                        .foregroundStyle(Plate.ink)
                        .lineLimit(2)
                }
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

    // MARK: Large — the list itself, as far as it goes.

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MicroCap(text: "GROCERY")
                Spacer()
                if let grocery, grocery.openCount > 0 {
                    Text(grocery.openCount == 1 ? "1 to buy" : "\(grocery.openCount) to buy")
                        .font(.jakarta(11, "ExtraBold"))
                        .foregroundStyle(Plate.inkSecondary)
                }
            }
            .padding(.bottom, 8)
            if let grocery, grocery.openCount > 0 {
                progress(grocery)
                    .padding(.bottom, 10)
                ForEach(Array(grocery.sample.prefix(9).enumerated()), id: \.offset) { _, name in
                    HStack(spacing: 10) {
                        Circle()
                            .strokeBorder(Plate.hairlineDashed, lineWidth: 2)
                            .frame(width: 16, height: 16)
                        Text(name)
                            .font(.jakarta(13, "SemiBold"))
                            .foregroundStyle(Plate.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 26)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Plate.hairlineDashed).frame(height: 1)
                    }
                }
                if grocery.openCount > min(grocery.sample.count, 9) {
                    Text("+ \(grocery.openCount - min(grocery.sample.count, 9)) more")
                        .font(.jakarta(12))
                        .foregroundStyle(Plate.inkSecondary)
                        .padding(.top, 8)
                }
            } else {
                Spacer(minLength: 0)
                Image(systemName: "basket")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(grocery == nil ? Plate.inkFaint : Plate.basil)
                Text(grocery == nil ? "Nothing to shop for" : "All bought")
                    .font(.jakarta(16))
                    .foregroundStyle(Plate.ink)
                Text(grocery == nil ? "Plate a few nights and the list builds itself." : "The basket is full for the week.")
                    .font(.jakarta(12, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
            }
            Spacer(minLength: 0)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Lock Screen
// The count where you look on the way out the door.

struct GroceryLockView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var grocery: WeekSnapshot.Grocery? { entry.snapshot?.grocery }
    private var open: Int { grocery?.openCount ?? 0 }
    private var line: String {
        guard grocery != nil else { return "Nothing to shop for" }
        return open == 0 ? "All bought" : open == 1 ? "1 to buy" : "\(open) to buy"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(line, systemImage: "basket")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if open > 0 {
                    Text("\(open)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: grocery == nil ? "basket" : "checkmark")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .widgetLabel(line)

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                Text("GROCERY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .widgetAccentable()
                Text(line)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                if let grocery, open > 0 {
                    Text(grocery.sample.prefix(3).joined(separator: ", "))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct GroceryLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GroceryLockWidget", provider: WeekProvider()) { entry in
            GroceryLockView(entry: entry)
                .widgetURL(PlatedLink.grocery)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Grocery (Lock Screen)")
        .description("What's still to buy, on the lock screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
