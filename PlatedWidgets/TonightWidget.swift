import WidgetKit
import SwiftUI

/// Tonight — the one question the app exists to answer, at a glance. Small
/// is the answer; medium adds the week's seven dots beside it; large spells
/// the nights out, because a whole week of names is worth the room when
/// you've given it the room.
///
/// One widget, three families, on purpose. When someone holds down the app
/// icon, iOS offers the sizes of the FIRST widget in the bundle and greys
/// out the rest: with Tonight small-only, "Medium-sized widget" and "Large
/// widget" sat disabled in Plated's own menu. The week used to be a second
/// widget whose medium was this medium exactly; it lives here now.

/// Names who has the turn without repeating a recipe's estimated duration.
/// W01 asked for the widget to answer who is cooking rather than how long it
/// takes, which is already visible in the recipe and cooking flow.
func factLine(_ tonight: WeekSnapshot.Tonight, owner: String?) -> String {
    if let name = tonight.cookName, !name.isEmpty {
        let mine = owner.map { !$0.isEmpty && $0 == name } ?? false
        return mine ? "You're cooking" : "\(name)'s cooking"
    }
    return "Dinner is planned"
}

/// Recipe.durationText, which the widget cannot import.
func durationText(_ minutes: Int) -> String {
    guard minutes > 0 else { return "" }
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
}

struct TonightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var tonight: WeekSnapshot.Tonight? {
        entry.snapshot?.isCurrent(on: entry.date) == true ? entry.snapshot?.tonight : nil
    }
    private var days: [WeekSnapshot.Day] {
        entry.snapshot?.days ?? WeekSnapshot.openWeek(from: .now)
    }
    private var plannedCount: Int { entry.snapshot?.plannedCount ?? 0 }
    /// The household is the picture in the Tonight widget. Meal photography
    /// belongs to the Table and Cookbook widgets; W02/W03 asked that Tonight
    /// represent the people sharing the meal instead.
    private var onHouseholdPhoto: Bool { entry.householdPhoto != nil }

    private var householdPeople: [WeekSnapshot.Day] {
        var seen = Set<String>()
        return days.filter { day in
            !day.cookInitial.isEmpty && seen.insert(day.cookInitial).inserted
        }.prefix(4).map { $0 }
    }

    /// The system's content margin, applied by hand: the picture wants the
    /// whole frame and the words still want their inset.
    private let inset: CGFloat = 16

    var body: some View {
        Group {
            switch family {
            case .systemLarge: large
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(PlatedLink.plan)
        .containerBackground(Plate.canvas, for: .widget)
    }

    // MARK: Small — the picture is the widget.

    private var small: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                householdArt
                if onHouseholdPhoto {
                    GlassBand(inset: inset) {
                        VStack(alignment: .leading, spacing: 4) {
                            MicroCap(text: "TONIGHT")
                            answer(titleSize: 15, lineSize: 11)
                        }
                    }
                } else {
                    MicroCap(text: "TONIGHT")
                        .padding(inset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    answer(titleSize: 15, lineSize: 11)
                        .padding(inset)
                }
            }
        }
    }

    // MARK: Medium — the picture on the left, the week on the right.

    private var medium: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                householdArt
                .frame(width: geo.size.width * 0.42)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    MicroCap(text: "TONIGHT")
                    answer(titleSize: 15, lineSize: 11)
                    Spacer(minLength: 0)
                    dots
                    plannedLine
                }
                .padding(.vertical, inset)
                .padding(.leading, inset)
                .padding(.trailing, inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Large — a hero, then the nights that follow.

    private var large: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    householdArt
                        .frame(width: geo.size.width * 0.42)
                        .clipped()
                    VStack(alignment: .leading, spacing: 6) {
                        MicroCap(text: "TONIGHT")
                        answer(titleSize: 16, lineSize: 11)
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Leave room for all six remaining nights on compact phones.
                .frame(height: min(110, geo.size.height * 0.36))
                .clipped()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        MicroCap(text: "THE WEEK")
                        Spacer()
                        Text("\(plannedCount) of 7 plated")
                            .font(.sans(11, "ExtraBold"))
                            .foregroundStyle(Plate.inkSecondary)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    // Tonight is the hero above, so the list starts
                    // tomorrow: a seventh row would only repeat it.
                    ForEach(Array(days.dropFirst().enumerated()), id: \.offset) { _, day in
                        nightRow(day)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, inset)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: Pieces

    /// Use the chosen shared banner when present. A household without one
    /// gets a small portrait of the cooks in the plan instead of a food
    /// photograph, without inventing a personal image.
    private var householdArt: some View {
        GeometryReader { geo in
            if let photo = entry.householdPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                householdIllustration
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
    }

    private var householdIllustration: some View {
        ZStack {
            Plate.fill
            Circle()
                .fill(Plate.olive.opacity(0.10))
                .frame(width: 180, height: 180)
                .offset(x: 72, y: -55)
            Circle()
                .stroke(Plate.basil.opacity(0.24), lineWidth: 2)
                .frame(width: 120, height: 120)
                .offset(x: -82, y: 58)
            HStack(spacing: 7) {
                if householdPeople.isEmpty {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Plate.basil)
                } else {
                    ForEach(Array(householdPeople.enumerated()), id: \.offset) { _, person in
                        CookDot(initial: person.cookInitial, hex: person.cookHex, size: 34)
                            .overlay(Circle().stroke(Plate.fill, lineWidth: 2))
                    }
                }
            }
            // The widget's own title and cook line carry the words. The
            // illustration contributes only people, centered in the open
            // space, so small and large families both stay collision-free.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// The dish and its fact line, or the invitation. Both wrap: "Nothing
    /// plated yet" was truncating to "Nothing plated…" at the small size.
    @ViewBuilder
    private func answer(titleSize: CGFloat, lineSize: CGFloat) -> some View {
        // Ink in every case: on canvas, or on the glass band over a photo.
        let ink = Plate.ink
        let quiet = Plate.inkSecondary
        VStack(alignment: .leading, spacing: 4) {
            if let tonight {
                Text(tonight.title)
                    .font(.editorial(titleSize + 2))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    if !tonight.cookInitial.isEmpty {
                        CookDot(initial: tonight.cookInitial, hex: tonight.cookHex, size: 14)
                    }
                    Text(factLine(tonight, owner: entry.snapshot?.ownerName))
                        .font(.sans(lineSize, "SemiBold"))
                        .foregroundStyle(quiet)
                        .lineLimit(1)
                }
            } else {
                Text(entry.snapshot?.isCurrent(on: entry.date) == true ? "Nothing plated yet" : "Open Plan to refresh")
                    .font(.sans(titleSize - 1))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.snapshot?.isCurrent(on: entry.date) == true ? "Tap to pick" : (entry.snapshot.map { "Updated " + $0.generatedAt.formatted(date: .abbreviated, time: .omitted) } ?? "Tap to refresh"))
                    .font(.sans(lineSize, "SemiBold"))
                    .foregroundStyle(quiet)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 4) {
                    Text(String(day.day.prefix(1)))
                        .font(.sans(9, "ExtraBold"))
                        .foregroundStyle(Plate.inkSecondary)
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
    }

    private var plannedLine: some View {
        HStack(spacing: 6) {
            Circle().fill(Plate.basil).frame(width: 7, height: 7)
            Text("\(plannedCount) of 7 plated")
                .font(.sans(12))
                .foregroundStyle(Plate.inkSecondary)
        }
    }

    private func nightRow(_ day: WeekSnapshot.Day) -> some View {
        HStack(spacing: 10) {
            Text(String(day.day.prefix(3)))
                .font(.sans(10, "ExtraBold"))
                .foregroundStyle(Plate.inkSecondary)
                .lineLimit(1)
                // 34, not 30: "MON" in ExtraBold set as "M…" at 30.
                .frame(width: 34, alignment: .leading)

            if day.planned {
                CookDot(initial: day.cookInitial, hex: day.cookHex, size: 20)
                Text(day.title ?? "Plated")
                    .font(.sans(13, "SemiBold"))
                    .foregroundStyle(Plate.ink)
                    .lineLimit(1)
            } else {
                Circle()
                    .strokeBorder(Plate.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 20, height: 20)
                Text(entry.snapshot?.isCurrent(on: entry.date) == true ? "Nothing plated yet" : "Open Plan to refresh")
                    .font(.sans(13, "SemiBold"))
                    .foregroundStyle(Plate.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Plate.hairlineDashed).frame(height: 1)
        }
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TonightWidget", provider: WeekProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's dish, and the week around it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // The photograph takes the whole frame; the words inset themselves.
        .contentMarginsDisabled()
    }
}

// MARK: - Lock Screen
// The same answer where you actually look for it. Accessory families render
// monochrome, so these lean on shape and type, never colour.

struct TonightLockView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    private var tonight: WeekSnapshot.Tonight? {
        entry.snapshot?.isCurrent(on: entry.date) == true ? entry.snapshot?.tonight : nil
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            // One line, system-styled — a symbol and the dish, nothing else.
            Label(tonight?.title ?? (entry.snapshot?.isCurrent(on: entry.date) == true ? "Nothing plated" : "Open Plan to refresh"), systemImage: "fork.knife")

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
            .widgetLabel(tonight?.title ?? (entry.snapshot?.isCurrent(on: entry.date) == true ? "Open night" : "Open Plan to refresh"))

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
                    Text(factLine(tonight, owner: entry.snapshot?.ownerName))
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text(entry.snapshot?.isCurrent(on: entry.date) == true ? "Nothing plated" : "Open Plan to refresh")
                        .font(.system(size: 15, weight: .bold))
                    Text(entry.snapshot?.isCurrent(on: entry.date) == true ? "Tap to pick a dish" : "The plan needs an update")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
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
