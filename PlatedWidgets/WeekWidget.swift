import WidgetKit
import SwiftUI

/// The week at a glance — who cooks, what's open. Medium is the seven dots;
/// large spells the nights out, because a whole week of names is worth the
/// room when you've given it the room.

struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var days: [WeekSnapshot.Day] {
        entry.snapshot?.days ?? WeekSnapshot.openWeek(from: .now)
    }

    var body: some View {
        Group {
            if family == .systemLarge {
                large
            } else {
                medium
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(PlatedLink.plan)
        .containerBackground(Plate.canvas, for: .widget)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                MicroCap(text: "TONIGHT")
                DishCircle(
                    photo: entry.photo,
                    planned: entry.snapshot?.tonight != nil,
                    size: 54
                )
                Text(entry.snapshot?.tonight?.title ?? "Open night")
                    .font(.jakarta(13))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 4) {
                            Text(String(day.day.prefix(1)))
                                .font(.jakarta(9, "ExtraBold"))
                                .foregroundStyle(Plate.inkFaint)
                            if day.planned {
                                CookDot(initial: day.cookInitial, hex: day.cookHex)
                            } else {
                                Circle()
                                    .strokeBorder(Plate.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                }
                plannedLine
            }
        }
    }

    // MARK: Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MicroCap(text: "YOUR WEEK")
                Spacer()
                Text("\(entry.snapshot?.plannedCount ?? 0) of 7")
                    .font(.jakarta(11, "ExtraBold"))
                    .foregroundStyle(Plate.inkFaint)
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    if index > 0 {
                        Rectangle()
                            .fill(Plate.hairlineDashed)
                            .frame(height: 1)
                    }
                    nightRow(day, isTonight: index == 0)
                }
            }
        }
    }

    private func nightRow(_ day: WeekSnapshot.Day, isTonight: Bool) -> some View {
        HStack(spacing: 10) {
            Text(isTonight ? "TON" : String(day.day.prefix(3)))
                .font(.jakarta(10, "ExtraBold"))
                .foregroundStyle(isTonight ? Plate.ink : Plate.inkFaint)
                .frame(width: 30, alignment: .leading)

            if day.planned {
                CookDot(initial: day.cookInitial, hex: day.cookHex, size: 20)
                Text(day.title ?? "Plated")
                    .font(.jakarta(13, "SemiBold"))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(1)
            } else {
                Circle()
                    .strokeBorder(Plate.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 20, height: 20)
                Text("Nothing plated yet")
                    .font(.jakarta(13, "SemiBold"))
                    .foregroundStyle(Plate.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private var plannedLine: some View {
        HStack(spacing: 6) {
            Circle().fill(Plate.basil).frame(width: 7, height: 7)
            Text("\(entry.snapshot?.plannedCount ?? 0) of 7 plated")
                .font(.jakarta(12))
                .foregroundStyle(Plate.inkSecondary)
        }
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekWidget", provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Week")
        .description("The week at a glance — who cooks, what's open.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
