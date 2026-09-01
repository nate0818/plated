import WidgetKit
import SwiftUI
import CoreText

// The household on the home screen — quiet chrome, the photo does the
// talking. Reads the snapshot the app writes into the shared app-group
// container; JSON keys are the contract with WidgetBridge.swift, change both
// or neither.
//
// This file holds the plumbing every widget shares. The widgets themselves
// live one per file alongside it.

// MARK: - Snapshot (reader side)

struct WeekSnapshot: Codable {
    /// Who is holding the phone. Optional: a snapshot written by an older
    /// build has no such field, and the widget must not go blank over it.
    var ownerName: String?
    struct Day: Codable {
        var day: String
        var planned: Bool
        var cookInitial: String
        var cookHex: String
        var cookName: String?
        var title: String?
    }
    struct Tonight: Codable {
        var title: String
        var cookInitial: String
        var cookHex: String
        var minutes: Int
        var hasPhoto: Bool
        var cookName: String?
    }
    struct Grocery: Codable {
        var openCount: Int
        var totalCount: Int
        var sample: [String]
    }
    struct TableCard: Codable {
        var authorName: String
        var authorInitial: String
        var authorHex: String
        var dishTitle: String
        var caption: String
        var plates: Int
        var commentCount: Int
        var hasPhoto: Bool
        var postedAt: Date

        var firstName: String {
            authorName.split(separator: " ").first.map(String.init) ?? authorName
        }
    }
    var generatedAt: Date
    var plannedCount: Int
    var tonight: Tonight?
    var days: [Day]
    var grocery: Grocery?
    var table: TableCard?

    static let appGroupID = "group.com.natemeadows.plated"

    /// Everything one read off disk produces: the snapshot plus the two
    /// photos that ride alongside it.
    struct Loaded {
        var snapshot: WeekSnapshot
        var dishPhoto: UIImage?
        var tablePhoto: UIImage?
    }

    static func load() -> Loaded? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        guard let data = try? Data(contentsOf: container.appendingPathComponent("week-snapshot.json")),
              let snapshot = try? JSONDecoder().decode(WeekSnapshot.self, from: data) else { return nil }
        let dish = (try? Data(contentsOf: container.appendingPathComponent("tonight.jpg")))
            .flatMap(UIImage.init(data:))
        let table = (try? Data(contentsOf: container.appendingPathComponent("table.jpg")))
            .flatMap(UIImage.init(data:))
        return snapshot.aged(dishPhoto: dish, tablePhoto: table)
    }

    /// The snapshot describes the day it was written. If the app hasn't run
    /// since, roll the window forward so a widget never calls yesterday's
    /// dinner TONIGHT: drop the days that have passed, pad the tail as open,
    /// and only keep tonight's plate on the day it was true.
    ///
    /// The table card is exempt — it carries its own timestamp and stays true
    /// however long it sits there.
    func aged(dishPhoto: UIImage?, tablePhoto: UIImage?) -> Loaded {
        let calendar = Calendar.current
        let written = calendar.startOfDay(for: generatedAt)
        let today = calendar.startOfDay(for: .now)
        let delta = calendar.dateComponents([.day], from: written, to: today).day ?? 0
        guard delta > 0 else {
            return Loaded(snapshot: self, dishPhoto: dishPhoto, tablePhoto: tablePhoto)
        }
        guard delta < 7 else {
            let empty = WeekSnapshot(
                generatedAt: generatedAt,
                plannedCount: 0,
                tonight: nil,
                days: Self.openWeek(from: today),
                grocery: nil,
                table: table
            )
            return Loaded(snapshot: empty, dishPhoto: nil, tablePhoto: tablePhoto)
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
            days: rolled,
            grocery: grocery,
            table: table
        )
        return Loaded(snapshot: aged, dishPhoto: nil, tablePhoto: tablePhoto)
    }

    static func openWeek(from start: Date) -> [Day] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
            return Day(day: formatter.string(from: date).uppercased(), planned: false, cookInitial: "", cookHex: "")
        }
    }

    /// Tonight's cook if there is one, otherwise the next night that has one —
    /// the answer to "whose turn is it", which is rarely about tonight.
    var nextTurn: (name: String, hex: String, initial: String, when: String, isMine: Bool)? {
        for (offset, day) in days.enumerated() {
            guard day.planned, let name = day.cookName, !name.isEmpty else { continue }
            let mine = ownerName.map { !$0.isEmpty && $0 == name } ?? false
            return (name, day.cookHex, day.cookInitial,
                    offset == 0 ? "Tonight" : day.day.capitalized, mine)
        }
        return nil
    }
}

// MARK: - Deep links
// A widget that doesn't land you in the right place is a poster.

enum PlatedLink {
    static func url(_ destination: String) -> URL {
        URL(string: "plated://\(destination)") ?? URL(string: "plated://plan")!
    }
    static let plan = url("plan")
    static let table = url("table")
    static let grocery = url("grocery")
    static let cookbook = url("cookbook")
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
    static let fill = color(0xF4F1EC, 0x282119)
    static let basil = color(0x3DA35D, 0x55BE76)
    static let tomato = color(0xFF5A3C, 0xF75434)

    static func person(_ hex: String) -> (tint: Color, tone: Color) {
        switch hex.uppercased() {
        case "3DA35D": return (color(0xEDF5EF, 0x1F2E24), color(0x3DA35D, 0x55BE76))
        // Amber darkened to clear 3:1 on canvas — see Color.amber. The key
        // stays "C88A00" because it is the stored `colorHex`, not a colour.
        case "C88A00": return (color(0xFFF4DC, 0x332A15), color(0xBF8300, 0xE3A83C))
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
    var tablePhoto: UIImage?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: .now, snapshot: .sample, photo: nil, tablePhoto: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        let loaded = WeekSnapshot.load()
        // Sample content belongs to the gallery only — a real home screen with
        // no snapshot gets the honest open week.
        let fallback: WeekSnapshot? = context.isPreview ? .sample : nil
        completion(WeekEntry(
            date: .now,
            snapshot: loaded?.snapshot ?? fallback,
            photo: loaded?.dishPhoto,
            tablePhoto: loaded?.tablePhoto
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let loaded = WeekSnapshot.load()
        let entry = WeekEntry(
            date: .now,
            snapshot: loaded?.snapshot,
            photo: loaded?.dishPhoto,
            tablePhoto: loaded?.tablePhoto
        )
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
        tonight: Tonight(title: "Salmon Night", cookInitial: "N", cookHex: "FF5A3C", minutes: 25, hasPhoto: false, cookName: "Nate"),
        days: [
            Day(day: "FRI", planned: true, cookInitial: "N", cookHex: "FF5A3C", cookName: "Nate", title: "Salmon Night"),
            Day(day: "SAT", planned: true, cookInitial: "S", cookHex: "3DA35D", cookName: "Sam", title: "Pizza Night"),
            Day(day: "SUN", planned: true, cookInitial: "S", cookHex: "3DA35D", cookName: "Sam", title: "BBQ Skewers"),
            Day(day: "MON", planned: false, cookInitial: "", cookHex: ""),
            Day(day: "TUE", planned: true, cookInitial: "R", cookHex: "C88A00", cookName: "Riley", title: "Steak Bowls"),
            Day(day: "WED", planned: true, cookInitial: "N", cookHex: "FF5A3C", cookName: "Nate", title: "Poke Night"),
            Day(day: "THU", planned: false, cookInitial: "", cookHex: "")
        ],
        grocery: Grocery(openCount: 7, totalCount: 12, sample: ["Salmon fillets", "Jasmine rice", "Green beans", "Limes"]),
        table: TableCard(
            authorName: "Sam Meadows",
            authorInitial: "SM",
            authorHex: "3DA35D",
            dishTitle: "Pizza Night",
            caption: "Kids picked the toppings. No regrets.",
            plates: 8,
            commentCount: 3,
            hasPhoto: false,
            postedAt: .now
        )
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
                .fill(Plate.fill)
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

/// A cook's initial in their colour — the app's avatar, shrunk.
struct CookDot: View {
    let initial: String
    let hex: String
    var size: CGFloat = 18

    var body: some View {
        let tone = Plate.person(hex)
        Circle()
            .fill(tone.tint)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.jakarta(size * 0.5))
                    .foregroundStyle(tone.tone)
            }
    }
}

struct MicroCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.jakarta(10))
            .tracking(1.0)
            .foregroundStyle(Plate.inkFaint)
    }
}

// MARK: - Bundle

@main
struct PlatedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TonightWidget()
        WeekWidget()
        GroceryWidget()
        TableWidget()
        CookTurnWidget()
        TonightLockWidget()
    }
}
