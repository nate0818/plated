import WidgetKit
import SwiftUI

/// Whose turn it is — the question that actually starts arguments. Answers
/// with tonight's cook when there is one, and otherwise with the next night
/// that has a name against it. The medium size shows the next few, which is
/// the argument settled for the week.

/// "You cook tonight" / "Riley cooks Thursday" — built outside the body so
/// the ViewBuilder never has to type-check string work.
private func turnLine(_ turn: WeekSnapshot.Turn) -> String {
    let when = turn.when == "Tonight" ? "tonight" : turn.when == "Tomorrow" ? "tomorrow" : turn.when
    return turn.isMine ? "cook \(when)" : "cooks \(when)"
}

struct CookTurnWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var turns: [WeekSnapshot.Turn] { entry.snapshot?.turns ?? [] }

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(PlatedLink.plan)
        .containerBackground(Plate.canvas, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroCap(text: "WHOSE TURN")
            Spacer(minLength: 0)
            if let turn = turns.first {
                CookDot(initial: turn.initial, hex: turn.hex, size: 52)
                // Your own turn is addressed to you. Reading the owner
                // their own name is how a database talks; the notifications
                // already say "you", and the home screen should agree.
                Text(turn.isMine ? "You" : turn.name)
                    .font(.jakarta(17))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(turnLine(turn))
                    .font(.jakarta(12, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
                    .lineLimit(1)
            } else {
                nobody
            }
            Spacer(minLength: 0)
        }
    }

    /// The next three turns in a row: who, then when.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroCap(text: "WHOSE TURN")
            if turns.isEmpty {
                Spacer(minLength: 0)
                nobody
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(turns.prefix(3).enumerated()), id: \.offset) { index, turn in
                        VStack(spacing: 6) {
                            CookDot(initial: turn.initial, hex: turn.hex, size: index == 0 ? 44 : 36)
                                .frame(height: 44)
                            Text(turn.isMine ? "You" : turn.name)
                                .font(.jakarta(13))
                                .foregroundStyle(Plate.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(turn.when)
                                .font(.jakarta(11, "SemiBold"))
                                .foregroundStyle(Plate.inkSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var nobody: some View {
        VStack(alignment: .leading, spacing: 8) {
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
    }
}

struct CookTurnWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CookTurnWidget", provider: WeekProvider()) { entry in
            CookTurnWidgetView(entry: entry)
        }
        .configurationDisplayName("Whose Turn")
        .description("Who's cooking next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Lock Screen

struct CookTurnLockView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var turn: WeekSnapshot.Turn? { entry.snapshot?.nextTurn }
    private var sentence: String {
        guard let turn else { return "Nobody cooking yet" }
        return "\(turn.isMine ? "You" : turn.name) \(turnLine(turn))"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(sentence, systemImage: "person")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let turn {
                    Text(turn.initial)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: "person")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .widgetLabel(sentence)

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                Text("WHOSE TURN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .widgetAccentable()
                if let turn {
                    Text(turn.isMine ? "You" : turn.name)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text(turnLine(turn))
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("Nobody yet")
                        .font(.system(size: 15, weight: .bold))
                    Text("Tap to hand out the week")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct CookTurnLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CookTurnLockWidget", provider: WeekProvider()) { entry in
            CookTurnLockView(entry: entry)
                .widgetURL(PlatedLink.plan)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Whose Turn (Lock Screen)")
        .description("Who's cooking next, on the lock screen.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
