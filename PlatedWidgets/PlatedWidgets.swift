import WidgetKit
import SwiftUI
import CoreText

// The week on the home screen — quiet chrome, the photo does the talking.
// Reads the snapshot the app writes into the shared app-group container;
// JSON keys are the contract with WidgetBridge.swift, change both or neither.

// MARK: - Snapshot (reader side)

struct WeekSnapshot: Codable {
    struct Day: Codable {
        var day: String
        var planned: Bool
        var cookInitial: String
        var cookHex: String
    }
    struct Tonight: Codable {
        var title: String
        var cookInitial: String
        var cookHex: String
        var minutes: Int
        var hasPhoto: Bool
    }
    var generatedAt: Date
    var plannedCount: Int
    var tonight: Tonight?
    var days: [Day]

    static let appGroupID = "group.com.natemeadows.plated"

    static func load() -> (WeekSnapshot, UIImage?)? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        guard let data = try? Data(contentsOf: container.appendingPathComponent("week-snapshot.json")),
              let snapshot = try? JSONDecoder().decode(WeekSnapshot.self, from: data) else { return nil }
        let photo = (try? Data(contentsOf: container.appendingPathComponent("tonight.jpg")))
            .flatMap(UIImage.init(data:))
        return snapshot.aged(photo: photo)
    }

    /// The snapshot describes the day it was written. If the app hasn't run
    /// since, roll the window forward so a widget never calls yesterday's
    /// dinner TONIGHT: drop the days that have passed, pad the tail as open,
    /// and only keep tonight's plate on the day it was true.
    func aged(photo: UIImage?) -> (WeekSnapshot, UIImage?) {
        let calendar = Calendar.current
        let written = calendar.startOfDay(for: generatedAt)
        let today = calendar.startOfDay(for: .now)
        let delta = calendar.dateComponents([.day], from: written, to: today).day ?? 0
        guard delta > 0 else { return (self, photo) }
        guard delta < 7 else {
            return (WeekSnapshot(generatedAt: generatedAt, plannedCount: 0, tonight: nil, days: Self.openWeek(from: today)), nil)
        }
        var rolled = Array(days.dropFirst(delta))
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        for offset in (7 - delta)..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            rolled.append(Day(day: formatter.string(from: date).uppercased(), planned: false, cookInitial: "", cookHex: ""))
        }
        let aged = WeekSnapshot(
            generatedAt: generatedAt,
            plannedCount: rolled.filter(\.planned).count,
            tonight: nil, // the app knows tonight; a stale snapshot doesn't
            days: rolled
        )
        return (aged, nil)
    }

    static func openWeek(from start: Date) -> [Day] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
            return Day(day: formatter.string(from: date).uppercased(), planned: false, cookInitial: "", cookHex: "")
        }
    }
}

// MARK: - Brand type
// Jakarta rides along in the appex; Gabarito stays home — nothing in a
// widget reaches display scale.

enum WidgetFonts {
    static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "PlusJakartaSans", withExtension: "ttf") else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return true
    }()
}

extension Font {
    static func jakarta(_ size: CGFloat, _ weight: String = "Bold") -> Font {
        _ = WidgetFonts.registered
        return .custom("PlusJakartaSans-Regular_\(weight)", size: size)
    }
}

// MARK: - Palette
// A pocket edition of the app's tokens; widgets follow the system scheme.

enum Plate {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            let value = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let canvas = color(0xFFFFFF, 0x16120E)
    static let ink = color(0x221B14, 0xF4EDE3)
    static let inkSecondary = color(0x8A8074, 0xA79B8B)
    static let inkFaint = color(0xB5AC9E, 0x6B6157)
    static let hairlineDashed = color(0xEFE7DD, 0x342C22)
    static let basil = color(0x3DA35D, 0x55BE76)

    static func person(_ hex: String) -> (tint: Color, tone: Color) {
        switch hex.uppercased() {
        case "3DA35D": return (color(0xEDF5EF, 0x1F2E24), color(0x3DA35D, 0x55BE76))
        case "C88A00": return (color(0xFFF4DC, 0x332A15), color(0xC88A00, 0xE3A83C))
        case "B95CF4": return (color(0xF5EDFB, 0x2E2138), color(0xB95CF4, 0xC98BF7))
        case "FF5A3C": return (color(0xFFEDE3, 0x39241C), color(0xFF5A3C, 0xF75434))
        default:       return (color(0xF4F1EC, 0x282119), color(0x221B14, 0xF4EDE3))
        }
    }
}

// MARK: - Timeline

struct WeekEntry: TimelineEntry {
    var date: Date
    var snapshot: WeekSnapshot?
    var photo: UIImage?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: .now, snapshot: .sample, photo: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        let loaded = WeekSnapshot.load()
        // Sample content belongs to the gallery only — a real home screen with
        // no snapshot gets the honest open week.
        let fallback: WeekSnapshot? = context.isPreview ? .sample : nil
        completion(WeekEntry(date: .now, snapshot: loaded?.0 ?? fallback, photo: loaded?.1))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let loaded = WeekSnapshot.load()
        let entry = WeekEntry(date: .now, snapshot: loaded?.0, photo: loaded?.1)
        // The app pushes reloads on data changes; midnight rolls the week.
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

extension WeekSnapshot {
    /// Gallery/placeholder content only — never shown once the app has run.
    static let sample = WeekSnapshot(
        generatedAt: .now,
        plannedCount: 5,
        tonight: Tonight(title: "Salmon Night", cookInitial: "N", cookHex: "FF5A3C", minutes: 25, hasPhoto: false),
        days: [
            Day(day: "FRI", planned: true, cookInitial: "N", cookHex: "FF5A3C"),
            Day(day: "SAT", planned: true, cookInitial: "S", cookHex: "3DA35D"),
            Day(day: "SUN", planned: true, cookInitial: "S", cookHex: "3DA35D"),
            Day(day: "MON", planned: false, cookInitial: "", cookHex: ""),
            Day(day: "TUE", planned: true, cookInitial: "R", cookHex: "C88A00"),
            Day(day: "WED", planned: true, cookInitial: "N", cookHex: "FF5A3C"),
            Day(day: "THU", planned: false, cookInitial: "", cookHex: "")
        ]
    )
}

// MARK: - Shared pieces

struct DishCircle: View {
    let photo: UIImage?
    let planned: Bool
    let size: CGFloat

    var body: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if planned {
            Circle()
                .fill(Plate.color(0xF4F1EC, 0x282119))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: size * 0.3, weight: .medium))
                        .foregroundStyle(Plate.inkSecondary)
                }
        } else {
            Circle()
                .strokeBorder(Plate.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.28, weight: .bold))
                        .foregroundStyle(Plate.inkFaint)
                }
        }
    }
}

// MARK: - Tonight (small)

struct TonightWidgetView: View {
    var entry: WeekEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TONIGHT")
                .font(.jakarta(10))
                .tracking(1.0)
                .foregroundStyle(Plate.inkFaint)
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
                        let tone = Plate.person(tonight.cookHex)
                        Circle().fill(tone.tint)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Text(tonight.cookInitial)
                                    .font(.jakarta(8))
                                    .foregroundStyle(tone.tone)
                            }
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

// MARK: - The Week (medium)

struct WeekWidgetView: View {
    var entry: WeekEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TONIGHT")
                    .font(.jakarta(10))
                    .tracking(1.0)
                    .foregroundStyle(Plate.inkFaint)
                DishCircle(
                    photo: entry.photo,
                    planned: entry.snapshot?.tonight != nil,
                    size: 54
                )
                if let tonight = entry.snapshot?.tonight {
                    Text(tonight.title)
                        .font(.jakarta(13))
                        .foregroundStyle(Plate.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("Open night")
                        .font(.jakarta(13))
                        .foregroundStyle(Plate.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(Array((entry.snapshot?.days ?? WeekSnapshot.openWeek(from: .now)).enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 4) {
                            Text(String(day.day.prefix(1)))
                                .font(.jakarta(9, "ExtraBold"))
                                .foregroundStyle(Plate.inkFaint)
                            if day.planned {
                                let tone = Plate.person(day.cookHex)
                                Circle().fill(tone.tint)
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Text(day.cookInitial)
                                            .font(.jakarta(9))
                                            .foregroundStyle(tone.tone)
                                    }
                            } else {
                                Circle()
                                    .strokeBorder(Plate.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(Plate.basil).frame(width: 7, height: 7)
                    Text("\(entry.snapshot?.plannedCount ?? 0) of 7 plated")
                        .font(.jakarta(12))
                        .foregroundStyle(Plate.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(Plate.canvas, for: .widget)
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekWidget", provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Week")
        .description("The week at a glance — who cooks, what's open.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Bundle

@main
struct PlatedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TonightWidget()
        WeekWidget()
    }
}
