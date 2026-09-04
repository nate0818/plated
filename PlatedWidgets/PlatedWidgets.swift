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
    struct CookbookCard: Codable {
        var title: String
        var minutes: Int
        var isFavorite: Bool
        var timesCooked: Int
        var hasPhoto: Bool
    }
    var generatedAt: Date
    var plannedCount: Int
    var tonight: Tonight?
    var days: [Day]
    var grocery: Grocery?
    var table: TableCard?
    /// Optional: a snapshot from a build before the cookbook widget has none.
    var cookbook: CookbookCard?

    static let appGroupID = "group.com.natemeadows.plated"

    /// Everything one read off disk produces: the snapshot plus the two
    /// photos that ride alongside it.
    struct Loaded {
        var snapshot: WeekSnapshot
        var dishPhoto: UIImage?
        /// The app's drawn plate for a night with no photograph, in the
        /// dark room. Nil when tonight is a real photograph, which is the
        /// same picture in both rooms.
        var dishPhotoDark: UIImage?
        var tablePhoto: UIImage?
        var cookbookPhoto: UIImage?
    }

    static func load() -> Loaded? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        guard let data = try? Data(contentsOf: container.appendingPathComponent("week-snapshot.json")),
              let snapshot = try? JSONDecoder().decode(WeekSnapshot.self, from: data) else { return nil }
        let dish = (try? Data(contentsOf: container.appendingPathComponent("tonight.jpg")))
            .flatMap(UIImage.init(data:))
        let dishDark = (try? Data(contentsOf: container.appendingPathComponent("tonight-dark.png")))
            .flatMap(UIImage.init(data:))
        let table = (try? Data(contentsOf: container.appendingPathComponent("table.jpg")))
            .flatMap(UIImage.init(data:))
        let cookbook = (try? Data(contentsOf: container.appendingPathComponent("cookbook.jpg")))
            .flatMap(UIImage.init(data:))
        var loaded = snapshot.aged(dishPhoto: dish, dishPhotoDark: dishDark, tablePhoto: table)
        // The cookbook card, like the table's, is true however long it sits.
        loaded.cookbookPhoto = cookbook
        return loaded
    }

    /// The snapshot describes the day it was written. If the app hasn't run
    /// since, roll the window forward so a widget never calls yesterday's
    /// dinner TONIGHT: drop the days that have passed, pad the tail as open,
    /// and only keep tonight's plate on the day it was true.
    ///
    /// The table card is exempt — it carries its own timestamp and stays true
    /// however long it sits there.
    func aged(dishPhoto: UIImage?, dishPhotoDark: UIImage?, tablePhoto: UIImage?) -> Loaded {
        let calendar = Calendar.current
        let written = calendar.startOfDay(for: generatedAt)
        let today = calendar.startOfDay(for: .now)
        let delta = calendar.dateComponents([.day], from: written, to: today).day ?? 0
        guard delta > 0 else {
            return Loaded(snapshot: self, dishPhoto: dishPhoto, dishPhotoDark: dishPhotoDark, tablePhoto: tablePhoto)
        }
        guard delta < 7 else {
            let empty = WeekSnapshot(
                generatedAt: generatedAt,
                plannedCount: 0,
                tonight: nil,
                days: Self.openWeek(from: today),
                grocery: nil,
                table: table,
                cookbook: cookbook
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
            table: table,
            cookbook: cookbook
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

    struct Turn {
        var name: String
        var hex: String
        var initial: String
        /// "Tonight", "Tomorrow", or the weekday.
        var when: String
        var isMine: Bool
    }

    /// Every night this week with a name against it, in order — tonight's
    /// cook first if there is one. Only what is recorded: an open night
    /// contributes nothing rather than a guess about a person.
    var turns: [Turn] {
        days.enumerated().compactMap { offset, day in
            guard day.planned, let name = day.cookName, !name.isEmpty else { return nil }
            let mine = ownerName.map { !$0.isEmpty && $0 == name } ?? false
            let when = offset == 0 ? "Tonight" : offset == 1 ? "Tomorrow" : day.day.capitalized
            return Turn(name: name, hex: day.cookHex, initial: day.cookInitial, when: when, isMine: mine)
        }
    }

    /// Tonight's cook if there is one, otherwise the next night that has one —
    /// the answer to "whose turn is it", which is rarely about tonight.
    var nextTurn: Turn? { turns.first }
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

    static let canvas = color(0xFFFEFC, 0x16120E)
    static let ink = color(0x221B14, 0xF4EDE3)
    // 0x7F7364, not 0x8A8074. The old value measured 3.87:1 on canvas,
    // under the 4.5:1 floor, and was replaced in Theme.swift. This copy kept
    // shipping the failing one — and the amber note eleven lines down proves
    // somebody edited this very enum afterwards and walked straight past it.
    // A fork that receives SOME fixes is worse than one that receives none,
    // because you cannot tell by looking which state it is in. See
    // scripts/check-tokens, which now fails the build of a drift like this.
    static let inkSecondary = color(0x675D50, 0xB8AC9C)
    static let inkFaint = color(0xB5AC9E, 0x6B6157)
    static let hairlineDashed = color(0xEFE7DD, 0x342C22)
    static let fill = color(0xF4F1EC, 0x282119)
    static let basil = color(0x3DA35D, 0x55BE76)
    static let tomato = color(0xFF5A3C, 0xF75434)
    // A photograph is a photograph in both rooms, so these two do not flip.
    // The app has carried them since the remove-photo button vanished after
    // dark; the widget was still writing `.white` by hand over its own food
    // photos, which is the same fork drift the note above is about.
    static let scrimInk = color(0x241C12, 0x241C12)
    static let onScrim = color(0xFFFFFF, 0xFFFFFF)

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
    var photoDark: UIImage?
    var tablePhoto: UIImage?
    var cookbookPhoto: UIImage?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        // Sample content belongs to the gallery only — a real home screen with
        // no snapshot gets the honest open week.
        guard let loaded = WeekSnapshot.load() else {
            completion(context.isPreview ? .sample : WeekEntry(date: .now, snapshot: nil, photo: nil, photoDark: nil, tablePhoto: nil, cookbookPhoto: nil))
            return
        }
        completion(WeekEntry(
            date: .now,
            snapshot: loaded.snapshot,
            photo: loaded.dishPhoto,
            photoDark: loaded.dishPhotoDark,
            tablePhoto: loaded.tablePhoto,
            cookbookPhoto: loaded.cookbookPhoto
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let loaded = WeekSnapshot.load()
        let entry = WeekEntry(
            date: .now,
            snapshot: loaded?.snapshot,
            photo: loaded?.dishPhoto,
            photoDark: loaded?.dishPhotoDark,
            tablePhoto: loaded?.tablePhoto,
            cookbookPhoto: loaded?.cookbookPhoto
        )
        // The app pushes reloads on data changes; midnight rolls the week.
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

extension WeekEntry {
    /// The gallery's entry: the sample week with its photographs attached.
    static let sample = WeekEntry(
        date: .now,
        snapshot: .sample,
        photo: WidgetSamples.tonight,
        photoDark: nil,
        tablePhoto: WidgetSamples.table,
        cookbookPhoto: WidgetSamples.cookbook
    )
}

extension WeekSnapshot {
    /// Gallery/placeholder content only — never shown once the app has run.
    static let sample = WeekSnapshot(
        generatedAt: .now,
        plannedCount: 5,
        tonight: Tonight(title: "Salmon Night", cookInitial: "N", cookHex: "FF5A3C", minutes: 25, hasPhoto: WidgetSamples.tonight != nil, cookName: "Nate"),
        days: [
            Day(day: "FRI", planned: true, cookInitial: "N", cookHex: "FF5A3C", cookName: "Nate", title: "Salmon Night"),
            Day(day: "SAT", planned: true, cookInitial: "S", cookHex: "3DA35D", cookName: "Sam", title: "Pizza Night"),
            Day(day: "SUN", planned: true, cookInitial: "S", cookHex: "3DA35D", cookName: "Sam", title: "BBQ Skewers"),
            Day(day: "MON", planned: false, cookInitial: "", cookHex: ""),
            Day(day: "TUE", planned: true, cookInitial: "R", cookHex: "C88A00", cookName: "Riley", title: "Steak Bowls"),
            Day(day: "WED", planned: true, cookInitial: "N", cookHex: "FF5A3C", cookName: "Nate", title: "Poke Night"),
            Day(day: "THU", planned: false, cookInitial: "", cookHex: "")
        ],
        grocery: Grocery(openCount: 7, totalCount: 12, sample: [
            "Salmon fillets", "Jasmine rice", "Green beans", "Limes",
            "Cherry tomatoes", "Pizza dough", "Mozzarella"
        ]),
        table: TableCard(
            authorName: "Sam Meadows",
            authorInitial: "SM",
            authorHex: "3DA35D",
            dishTitle: "Pizza Night",
            caption: "Kids picked the toppings. No regrets.",
            plates: 8,
            commentCount: 3,
            hasPhoto: WidgetSamples.table != nil,
            postedAt: .now
        ),
        cookbook: CookbookCard(
            title: "Poke Night",
            minutes: 20,
            isFavorite: true,
            timesCooked: 6,
            hasPhoto: WidgetSamples.cookbook != nil
        )
    )
}

// MARK: - Shared pieces

struct DishCircle: View {
    @Environment(\.colorScheme) private var scheme
    let photo: UIImage?
    /// The drawn plate after dark; a photograph passes nil and is shown as is.
    var photoDark: UIImage? = nil
    let planned: Bool
    let size: CGFloat

    var body: some View {
        if let photo = (scheme == .dark ? photoDark : nil) ?? photo {
            Image(uiImage: photo)
                // A tinted home screen (iOS 18) would flatten dinner to the
                // accent colour with everything else. Image-only: it goes
                // between resizable and the fill, never after a frame.
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                // A tinted home screen (iOS 18) would flatten dinner to the
                // accent colour with everything else.
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
    /// `onScrim` when the eyebrow sits on a photograph; the default
    /// everywhere else.
    var color: Color = Plate.inkSecondary
    var body: some View {
        Text(text)
            .font(.jakarta(10))
            // 0.05em, which is TypeScale.micro's tracking. This was a flat
            // 1.0 at size 10, or 0.10em: every eyebrow in every widget set
            // twice as loose as the same eyebrow in the app.
            .tracking(10 * 0.05)
            // Not inkFaint. It measures 2.24:1 and cannot carry a word, and
            // MicroLabel's identical default is named in DESIGN.md as most
            // of why the app read as washed out.
            .foregroundStyle(color)
    }
}

/// The photographs the gallery shows. A widget is chosen from its preview,
/// and a preview of a grey glyph where dinner should be sells nothing; the
/// gallery gets the same bundled stand-ins the app's own previews use.
enum WidgetSamples {
    static let tonight = load("sample-tonight")
    static let table = load("sample-table")
    static let cookbook = load("sample-cookbook")
    private static func load(_ name: String) -> UIImage? {
        Bundle.main.url(forResource: name, withExtension: "jpg")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(UIImage.init(data:))
    }
}

/// Dinner at the size it deserves. A photograph fills whatever frame it is
/// given; the app's drawn plate is a disc that bleeds off a corner, big
/// enough to read as a plate rather than a badge; an open night is the same
/// disc as a dashed outline, which is how the Plan list draws one.
struct PlateArt: View {
    enum Corner { case topTrailing, leading }

    @Environment(\.colorScheme) private var scheme
    let entry: WeekEntry
    /// The plate's diameter when it is drawn; ignored for a photograph.
    let diameter: CGFloat
    var corner: Corner = .topTrailing

    /// A real photograph is the same in both rooms; the drawn plate answers
    /// the room, so it comes in two.
    private var picture: UIImage? { (scheme == .dark ? entry.photoDark : nil) ?? entry.photo }
    var isPhotograph: Bool { entry.snapshot?.tonight?.hasPhoto == true && entry.photo != nil }

    var body: some View {
        GeometryReader { geo in
            if isPhotograph, let picture {
                Image(uiImage: picture)
                    .resizable()
                    // A tinted home screen (iOS 18) would flatten dinner to
                    // the accent colour with everything else. Image-only:
                    // it goes between resizable and the fill, never after
                    // a frame.
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                Group {
                    if let picture, entry.snapshot?.tonight != nil {
                        Image(uiImage: picture)
                            .resizable()
                            .widgetAccentedRenderingMode(.fullColor)
                            .scaledToFit()
                    } else if entry.snapshot?.tonight != nil {
                        // A plate without a picture of any kind: the app
                        // has not run since this dinner was planned.
                        Circle()
                            .fill(Plate.fill)
                            .overlay {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: diameter * 0.22, weight: .medium))
                                    .foregroundStyle(Plate.inkSecondary)
                            }
                    } else {
                        Circle()
                            .strokeBorder(Plate.hairlineDashed, style: StrokeStyle(lineWidth: 2.5, dash: [7, 7]))
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: diameter * 0.2, weight: .bold))
                                    .foregroundStyle(Plate.inkFaint)
                            }
                    }
                }
                .frame(width: diameter, height: diameter)
                .position(center(in: geo.size))
            }
        }
    }

    /// Where the disc sits so that most of it shows and the corner takes
    /// the rest: a plate on a table, not a logo in a box.
    private func center(in size: CGSize) -> CGPoint {
        switch corner {
        case .topTrailing:
            CGPoint(x: size.width - diameter * 0.24, y: diameter * 0.24)
        case .leading:
            CGPoint(x: diameter * 0.30, y: size.height / 2)
        }
    }
}

/// Legible type on a photograph: a frosted band across the bottom, the
/// words in ink on it. A gradient scrim was tried first and was a gamble on
/// every photo, dark words on a bright plate one night and white on a pale
/// tablecloth the next. Glass answers the room on its own, so the text is
/// plain ink in both.
struct GlassBand<Content: View>: View {
    var inset: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, inset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
    }
}

// MARK: - Bundle

@main
struct PlatedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Order matters: holding down the app icon offers the sizes of the
        // FIRST widget here, so it has to be the one that comes in all three.
        TonightWidget()
        TableWidget()
        CookbookWidget()
        GroceryWidget()
        CookTurnWidget()
        TonightLockWidget()
        GroceryLockWidget()
        CookTurnLockWidget()
    }
}
