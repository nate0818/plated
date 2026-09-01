import WidgetKit
import SwiftUI

/// Tonight — the one question the app exists to answer, at a glance.

struct TonightWidgetView: View {
    var entry: WeekEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroCap(text: "TONIGHT")
            Spacer(minLength: 0)
            DishCircle(
                photo: entry.photo,
                planned: entry.snapshot?.tonight != nil,
                size: 58
            )
            Spacer(minLength: 0)
            if let tonight = entry.snapshot?.tonight {
                Text(tonight.title)
                    .font(.jakarta(14))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                HStack(spacing: 5) {
                    if !tonight.cookInitial.isEmpty {
                        CookDot(initial: tonight.cookInitial, hex: tonight.cookHex, size: 14)
                    }
                    Text(tonight.minutes > 0 ? "\(tonight.minutes) min" : "Plated")
                        .font(.jakarta(11, "SemiBold"))
                        .foregroundStyle(Plate.inkSecondary)
                }
            } else {
                Text("Nothing plated yet")
                    .font(.jakarta(13))
                    .foregroundStyle(Plate.ink)
                Text("Tap to pick")
                    .font(.jakarta(11, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(PlatedLink.plan)
        .containerBackground(Plate.canvas, for: .widget)
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TonightWidget", provider: WeekProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("What's on the plate tonight.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Lock Screen
// The same answer where you actually look for it. Accessory families render
// monochrome, so these lean on shape and type, never colour.

struct TonightLockView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var tonight: WeekSnapshot.Tonight? { entry.snapshot?.tonight }

    var body: some View {
        switch family {
        case .accessoryInline:
            // One line, system-styled — a symbol and the dish, nothing else.
            Label(tonight?.title ?? "Nothing plated", systemImage: "fork.knife")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let tonight {
                    VStack(spacing: 0) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 13, weight: .semibold))
                        Text(tonight.cookInitial.isEmpty ? "•" : tonight.cookInitial)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                } else {
                    // An open night is a gap, and it should look like one.
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .widgetLabel(tonight?.title ?? "Open night")

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                Text("TONIGHT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .widgetAccentable()
                if let tonight {
                    Text(tonight.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text(subtitle(tonight))
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("Nothing plated")
                        .font(.system(size: 15, weight: .bold))
                    Text("Tap to pick a dish")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func subtitle(_ tonight: WeekSnapshot.Tonight) -> String {
        var parts: [String] = []
        if let name = tonight.cookName, !name.isEmpty { parts.append("\(name) cooks") }
        if tonight.minutes > 0 { parts.append("\(tonight.minutes) min") }
        return parts.isEmpty ? "Plated" : parts.joined(separator: " · ")
    }
}

struct TonightLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TonightLockWidget", provider: WeekProvider()) { entry in
            TonightLockView(entry: entry)
                .widgetURL(PlatedLink.plan)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Tonight (Lock Screen)")
        .description("Tonight's dish on the lock screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
