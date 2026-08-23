import WidgetKit
import SwiftUI

/// Whose turn it is — the question that actually starts arguments. Answers
/// with tonight's cook when there is one, and otherwise with the next night
/// that has a name against it.

struct CookTurnWidgetView: View {
    var entry: WeekEntry

    private var turn: (name: String, hex: String, initial: String, when: String)? {
        entry.snapshot?.nextTurn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroCap(text: "WHOSE TURN")
            Spacer(minLength: 0)
            if let turn {
                CookDot(initial: turn.initial, hex: turn.hex, size: 52)
                Text(turn.name)
                    .font(.jakarta(17))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(turn.when == "Tonight" ? "cooks tonight" : "cooks \(turn.when.lowercased())")
                    .font(.jakarta(12, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
                    .lineLimit(1)
            } else {
                Circle()
                    .strokeBorder(Plate.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "person")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Plate.inkFaint)
                    }
                Text("Nobody yet")
                    .font(.jakarta(15))
                    .foregroundStyle(Plate.ink)
                Text("Tap to hand out the week")
                    .font(.jakarta(12, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(PlatedLink.plan)
        .containerBackground(Plate.canvas, for: .widget)
    }
}

struct CookTurnWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CookTurnWidget", provider: WeekProvider()) { entry in
            CookTurnWidgetView(entry: entry)
        }
        .configurationDisplayName("Whose Turn")
        .description("Who's cooking next.")
        .supportedFamilies([.systemSmall])
    }
}
