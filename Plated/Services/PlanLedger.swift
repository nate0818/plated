import Foundation
import Observation

/// Other phones' planned nights. Deliberately **not** SwiftData.
///
/// A night planned on another Apple ID has one authority, the shared zone,
/// and the planner draws it beside this phone's own nights as a read-only
/// overlay. It is never a `PlannedMeal`: every planner surface takes the
/// first meal per day, thirty aggregators count `PlannedMeal` rows as this
/// household's activity, two of one person's devices would each insert the
/// same record and the mirror would carry both across, and CLAUDE.md says
/// share-derived state stays out of the mirror. docs/plan-share.md has the
/// full argument and every rule below.
///
/// Same shape as `TableLedger`: a JSON book in the app group, synchronous
/// reads that register with Observation, one writer (`absorb`) on the main
/// actor.
@MainActor
@Observable
final class PlanLedger {
    static let shared = PlanLedger()

    /// A night as this phone holds it. `id` is the record name.
    struct Entry: Codable, Identifiable, Equatable {
        var recordName: String
        /// Canonical zone owner, "" for this phone's own zone.
        var zoneOwner: String
        var authorID: String
        var authorName: String
        var authorColorHex: String
        var cookID: String
        var cookName: String
        var cookColorHex: String
        var cookSeat: String
        /// `PlanDay` string, `yyyy-MM-dd`.
        var day: String
        var slot: String
        var title: String
        var servings: Int
        var tagline: String
        var cooked: Bool
        var cookedAt: Date?
        var hasRecipe: Bool
        var recipeMinutes: Int
        var recipeOriginKey: String
        var shoppingID: String
        var hasPhoto: Bool
        var createdAt: Date
        var changedAt: Date

        var id: String { recordName }
        /// Start of the night's day in the reader's own calendar.
        var date: Date { PlanDay.date(day) ?? .distantPast }
        var slotValue: MealSlot { MealSlot(rawValue: slot) ?? .dinner }
        var authorFirstName: String { Entry.firstName(authorName) }
        var cookFirstName: String { Entry.firstName(cookName) }
        /// A cook with a real seat. A name typed five seconds ago for an
        /// invited seat is not a cook, and the writer already blanks it.
        var hasCook: Bool { !cookName.isEmpty && cookSeat != HouseholdMember.Seat.invited.rawValue }

        static func firstName(_ name: String) -> String {
            name.split(separator: " ").first.map(String.init) ?? name
        }

        init(_ r: TableShare.RemotePlan) {
            recordName = r.recordName
            zoneOwner = r.zoneOwner
            authorID = r.authorID
            authorName = r.authorName
            authorColorHex = r.authorColorHex
            cookID = r.cookID
            cookName = r.cookName
            cookColorHex = r.cookColorHex
            cookSeat = r.cookSeat
            day = r.day
            slot = r.slot
            title = r.title
            servings = r.servings
            tagline = r.tagline
            cooked = r.cooked
            cookedAt = r.cookedAt
            hasRecipe = r.hasRecipe
            recipeMinutes = r.recipeMinutes
            recipeOriginKey = r.recipeOriginKey
            shoppingID = r.shoppingID
            hasPhoto = r.photoData != nil
            createdAt = r.createdAt
            changedAt = r.changedAt
        }
    }

    /// What one delivery changed, computed BEFORE the book is overwritten,
    /// so the digest can say "moved" and "put you down". `removed` and
    /// `changed` carry only nights today or later: a past-day deletion is
    /// the writer's housekeeping and never news.
    struct Delta {
        var added: [Entry] = []
        var changed: [(before: Entry, after: Entry)] = []
        var removed: [Entry] = []
        var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }
    }

    private struct Book: Codable {
        var entries: [String: Entry] = [:]
    }

    private var book = Book()
    private var photos: [String: Data] = [:]

    static let householdOwnerKey = "plated.plan.householdOwner"
    static let rehearsalOwner = "rehearsal-zone"

    /// Posted when nights leave the ledger outside a delivery: a leave, a
    /// household flip, an identity reset, a rehearsal ending. A delivery
    /// hands its delta to `ShareAcceptor`, which rebuilds the reminders;
    /// these paths have no delta, and a "Your night tomorrow" for a table
    /// this phone has left would fire at 19:00 regardless. `PlatedApp`
    /// answers with the same rebuild.
    static let nightsDropped = Notification.Name("PlanLedger.nightsDropped")

    private static var store: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)
    }
    private static var url: URL? { directory?.appending(path: "plan-ledger.json") }
    private static var photoDirectory: URL? { directory?.appending(path: "plan-photos") }

    private init() { load() }

    // MARK: The household

    /// Which zone's nights this phone draws: "" for its own, a host's
    /// record name for a table it joined, nil while unresolved. Written by
    /// `PlanShare` from the shares (docs/plan-share.md, "Which zone is the
    /// household's"); a zone never counts because it merely exists.
    var householdOwner: String? {
        // The household invite's own key wins when it exists: written on
        // join and on the head's first mint, cleared on leave
        // (docs/household.md). This ledger's key is the fallback the
        // resolution writes for installs that predate the invite.
        get {
            Self.store.string(forKey: TableShare.householdOwnerKey)
                ?? Self.store.string(forKey: Self.householdOwnerKey)
        }
        set {
            if let newValue { Self.store.set(newValue, forKey: Self.householdOwnerKey) }
            else { Self.store.removeObject(forKey: Self.householdOwnerKey) }
            // Touch the book so bodies re-evaluate against the new filter.
            book = book
        }
    }

    // MARK: Reading

    /// Every night this phone should draw, household only.
    var all: [Entry] {
        // Read the book before the household guard: `householdOwner` lives
        // in UserDefaults, not in a tracked property, so a body that reads
        // `all` while unresolved would otherwise register no dependency
        // and never redraw when the owner resolves.
        let entries = book.entries.values
        guard let owner = householdOwner else { return [] }
        return entries.filter { $0.zoneOwner == owner }
            .sorted { ($0.day, $0.slot, $0.title) < ($1.day, $1.slot, $1.title) }
    }

    /// The nights on one day in one slot, household only.
    func plans(on date: Date, slot: MealSlot = .dinner) -> [Entry] {
        let day = PlanDay.string(date)
        return all.filter { $0.day == day && $0.slot == slot.rawValue }
    }

    /// The first dinner somebody else planned for a day, for the surfaces
    /// that show one night.
    func dinner(on date: Date) -> Entry? {
        plans(on: date, slot: .dinner).first
    }

    /// Nights whose cook is this person, for the reminders.
    func myNights() -> [Entry] {
        all.filter { isMine(cook: $0) }
    }

    func entry(_ recordName: String) -> Entry? {
        book.entries[recordName]
    }

    /// By identity, never by name. `participantID` and `TableIdentity` are
    /// the same CloudKit user record name.
    func isMine(cook entry: Entry) -> Bool {
        !entry.cookID.isEmpty && entry.cookID == TableIdentity.cached
    }

    /// The hero's own strings, so a night says the same thing on every
    /// surface. Nil when there is no cook worth naming.
    func cookLine(for entry: Entry) -> String? {
        if isMine(cook: entry) { return "You're cooking" }
        guard entry.hasCook else { return nil }
        return "\(entry.cookFirstName) is cooking"
    }

    func photo(for recordName: String) -> Data? {
        if let cached = photos[recordName] { return cached }
        guard let entry = book.entries[recordName], entry.hasPhoto,
              let url = Self.photoDirectory?.appending(path: "\(recordName).jpg"),
              let data = try? Data(contentsOf: url) else { return nil }
        photos[recordName] = data
        return data
    }

    // MARK: Folding

    /// Fold a delivery. Nights this person planned are never kept: their
    /// own phones hold them as `PlannedMeal` rows already. A replayed zone
    /// carries no deletions, so for each replayed owner the delivered set
    /// is the whole truth.
    @discardableResult
    func absorb(_ changes: TableShare.Changes, me: String) -> Delta {
        prune()
        var delta = Delta()
        let today = PlanDay.string(.now)
        func isNews(_ e: Entry) -> Bool { e.day >= today }

        // Deletions by name. Only `plan-` names are nights.
        for name in changes.deleted where name.hasPrefix("plan-") {
            if let old = book.entries.removeValue(forKey: name) {
                removePhoto(name)
                if isNews(old) { delta.removed.append(old) }
            }
        }

        // Replay: anything for that owner not delivered is gone.
        if !changes.replayedOwners.isEmpty {
            let delivered = Set(changes.plans.map(\.recordName))
            for (name, old) in book.entries
            where changes.replayedOwners.contains(old.zoneOwner) && !delivered.contains(name) {
                book.entries.removeValue(forKey: name)
                removePhoto(name)
                if isNews(old) { delta.removed.append(old) }
            }
        }

        for remote in changes.plans {
            let entry = Entry(remote)
            guard !entry.authorID.isEmpty, entry.authorID != me else {
                // Mine, echoed back. If a stale copy was kept under a
                // placeholder identity, let it go.
                if book.entries.removeValue(forKey: entry.recordName) != nil { removePhoto(entry.recordName) }
                continue
            }
            if let before = book.entries[entry.recordName] {
                if before != entry, isNews(entry) || isNews(before) {
                    delta.changed.append((before, entry))
                }
            } else if isNews(entry) {
                delta.added.append(entry)
            }
            book.entries[entry.recordName] = entry
            if let data = remote.photoData { writePhoto(entry.recordName, data) }
        }

        // The pair a two-device shoppingID backfill mints: one night taken
        // off and the same night added in one delivery. Readers never see it.
        let addedKeys = Set(delta.added.map { "\($0.day)/\($0.slot)/\($0.title)" })
        let removedKeys = Set(delta.removed.map { "\($0.day)/\($0.slot)/\($0.title)" })
        let pairs = addedKeys.intersection(removedKeys)
        if !pairs.isEmpty {
            delta.added.removeAll { pairs.contains("\($0.day)/\($0.slot)/\($0.title)") }
            delta.removed.removeAll { pairs.contains("\($0.day)/\($0.slot)/\($0.title)") }
        }

        save()
        if !delta.isEmpty {
            print("[PlanLedger] +\(delta.added.count) ~\(delta.changed.count) -\(delta.removed.count)")
        }
        return delta
    }

    /// A leave, a flip, or a rehearsal ending: that table's nights go.
    func forget(zoneOwner: String) {
        let names = book.entries.filter { $0.value.zoneOwner == zoneOwner }.map(\.key)
        for name in names {
            book.entries.removeValue(forKey: name)
            removePhoto(name)
        }
        if !names.isEmpty {
            save()
            NotificationCenter.default.post(name: Self.nightsDropped, object: nil)
        }
    }

    /// An identity confirm: nights stamped with the id this phone turns out
    /// to own are its own, not somebody else's.
    func reattribute(from old: String, to new: String) {
        let names = book.entries.filter { $0.value.authorID == new }.map(\.key)
        for name in names {
            book.entries.removeValue(forKey: name)
            removePhoto(name)
        }
        if !names.isEmpty { save() }
    }

    /// An Apple ID change, and tests.
    func clear() {
        let had = !book.entries.isEmpty
        book = Book()
        photos = [:]
        if let dir = Self.photoDirectory { try? FileManager.default.removeItem(at: dir) }
        householdOwner = nil
        save()
        if had { NotificationCenter.default.post(name: Self.nightsDropped, object: nil) }
    }

    /// Thirty days back, one hundred and eighty ahead. Runs before every
    /// fold so a writer's age-out delete finds nothing to announce.
    private func prune() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let floor = calendar.date(byAdding: .day, value: -30, to: today),
              let ceiling = calendar.date(byAdding: .day, value: 180, to: today) else { return }
        let low = PlanDay.string(floor), high = PlanDay.string(ceiling)
        let stale = book.entries.filter { $0.value.day < low || $0.value.day > high }.map(\.key)
        for name in stale {
            book.entries.removeValue(forKey: name)
            removePhoto(name)
        }
    }

    // MARK: Persistence

    private func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Book.self, from: data) else { return }
        book = decoded
    }

    private func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(book) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func writePhoto(_ name: String, _ data: Data) {
        guard let dir = Self.photoDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "\(name).jpg"), options: .atomic)
        photos[name] = data
    }

    private func removePhoto(_ name: String) {
        photos[name] = nil
        guard let url = Self.photoDirectory?.appending(path: "\(name).jpg") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
