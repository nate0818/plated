import Foundation
import Observation
import SwiftData

/// What happened while somebody was cooking one dish, one evening, on this
/// phone. Deliberately **not** SwiftData, for the reason CLAUDE.md gives.
///
/// A checked ingredient is a fact about tonight, not a fact about the recipe.
/// Put `isChecked` on `Ingredient` and the SwiftData mirror becomes a second
/// writer to it: "I have the garlic" syncs to the iPad, nothing ever clears
/// it, and next March the page opens with half its list struck through by a
/// cook in March. A mirrored step cursor is worse — it is an index into an
/// array that can be edited, so it can point confidently at the wrong
/// sentence, and a silently wrong instruction is the worst failure this app
/// has available.
///
/// Same shape as `TableLedger` for the same reasons: one JSON book in the app
/// group beside it, synchronous reads so touching the book inside a SwiftUI
/// body registers with Observation, atomic writes so a force-quit mid-tap
/// cannot leave a half-written file. `PlatedStore.schema` does not move, and
/// the store migration CLAUDE.md calls precious is not approached.
@MainActor
@Observable
final class CookLedger {
    static let shared = CookLedger()

    /// One checked ingredient, identified by BOTH its position and its name.
    ///
    /// Either alone is a quiet lie waiting to happen. Position alone puts a
    /// tick on whatever ingredient moved into slot three; name alone puts it
    /// on the second of two lines that both say "salt". A tick is drawn only
    /// when both still match, so editing a recipe mid-cook loses a tick
    /// rather than moving it somewhere wrong.
    struct Line: Codable, Hashable {
        var sortIndex: Int
        /// `Ingredient.normalizedName` at the moment it was ticked.
        var name: String
    }

    struct Session: Codable {
        var startedAt: Date
        var lastTouched: Date
        var checked: [Line] = []
        /// Nil until a step is actually tapped. There is no step 1 by default,
        /// because "you are on step 1" is a claim about somebody who has not
        /// started.
        var step: Int?
        /// `recipe.steps.count` when the cursor was last set, so an edited
        /// recipe can be detected rather than pointed into.
        var stepCount: Int = 0
        /// When the timer rings — never how much is left. A remembered
        /// "remaining" resumed after twenty minutes of backgrounding turns a
        /// twenty minute timer into forty.
        var timerEndsAt: Date?
        var timerStep: Int?
    }

    private struct Book: Codable {
        /// recipe key -> session
        var sessions: [String: Session] = [:]
    }

    private var book = Book()

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "cook-ledger.json")
    }

    /// An evening survives a phone lock, a trip to the shop and a nap. It does
    /// not survive until tomorrow: a page left on the counter overnight must
    /// redraw clean rather than show last night's ticks under a finger.
    private static let sessionLife: TimeInterval = 12 * 60 * 60

    private init() {
        load()
        pruneStale()
    }

    // MARK: Keys

    /// The shape SwiftData actually encodes a `PersistentIdentifier` into.
    /// Only read here, to lift a stable key out of it.
    private struct EncodedID: Decodable {
        struct Implementation: Decodable {
            var uriRepresentation: String?
            var storeIdentifier: String?
            var entityName: String?
            var primaryKey: String?
        }
        var implementation: Implementation
    }

    /// A stable string for one recipe. Fails closed: no key means no session,
    /// because no ticks is strictly better than ticks on the wrong dish.
    ///
    /// **Not the raw JSON of the identifier.** That was the first version, and
    /// it is silently wrong: `JSONEncoder` does not promise key order, and
    /// `PersistentIdentifier` encodes through an unordered container, so two
    /// calls in the same function returned two different strings. Every tap
    /// wrote a session under one key and read back under another — the tick
    /// never appeared, and each toggle leaked a dead session into the book.
    /// It looked exactly like a persistence bug and was a hashing one.
    ///
    /// The URI is the identifier's own stable form
    /// ("x-coredata://<store>/Recipe/p1"), which is also short enough to read
    /// in a log. The store-plus-entity-plus-key fallback covers a future
    /// encoding that drops it, and `.sortedKeys` is the last resort so this
    /// cannot silently return to being order-dependent.
    ///
    /// Stability across a store migration is not documented by SwiftData, so
    /// the twelve-hour life above bounds the worst case to a dropped session
    /// rather than a wrong one.
    static func key(for recipe: Recipe) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(recipe.persistentModelID) else { return nil }
        guard let shape = try? JSONDecoder().decode(EncodedID.self, from: data) else {
            return String(decoding: data, as: UTF8.self)
        }
        if let uri = shape.implementation.uriRepresentation, !uri.isEmpty { return uri }
        if let store = shape.implementation.storeIdentifier,
           let entity = shape.implementation.entityName,
           let primary = shape.implementation.primaryKey {
            return "\(store)/\(entity)/\(primary)"
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Reading

    /// The live session for this recipe, with the cursor dropped if the recipe
    /// has been edited since it was set.
    ///
    /// The ticks survive that edit and the cursor does not: a tick carries its
    /// own identity and can be checked, an index cannot.
    func session(for recipe: Recipe) -> Session? {
        guard let key = Self.key(for: recipe), var s = book.sessions[key] else { return nil }
        guard Date.now.timeIntervalSince(s.lastTouched) < Self.sessionLife else { return nil }
        if s.stepCount != recipe.steps.count {
            s.step = nil
            s.timerEndsAt = nil
            s.timerStep = nil
        }
        return s
    }

    /// Something is actually going on: at least one tick, or a cursor.
    ///
    /// A servings lens on its own does not count. Browsing curiosity is not
    /// cooking, and the page's posture should not change for it.
    func isCooking(_ recipe: Recipe) -> Bool {
        guard let s = session(for: recipe) else { return false }
        return !s.checked.isEmpty || s.step != nil
    }

    func isChecked(_ ingredient: Ingredient, in recipe: Recipe) -> Bool {
        session(for: recipe)?.checked.contains(
            Line(sortIndex: ingredient.sortIndex, name: ingredient.normalizedName)
        ) ?? false
    }

    func checkedCount(for recipe: Recipe) -> Int {
        session(for: recipe)?.checked.count ?? 0
    }

    func step(for recipe: Recipe) -> Int? { session(for: recipe)?.step }

    /// The end date and the step it belongs to, or nil.
    func timer(for recipe: Recipe) -> (endsAt: Date, step: Int)? {
        guard let s = session(for: recipe), let ends = s.timerEndsAt, let step = s.timerStep
        else { return nil }
        return (ends, step)
    }

    // MARK: Writing

    func toggle(_ ingredient: Ingredient, in recipe: Recipe) {
        let line = Line(sortIndex: ingredient.sortIndex, name: ingredient.normalizedName)
        mutate(recipe) { s in
            if let at = s.checked.firstIndex(of: line) {
                s.checked.remove(at: at)
            } else {
                s.checked.append(line)
            }
        }
        print("[CookLedger] toggle \(ingredient.normalizedName) -> \(isChecked(ingredient, in: recipe))")
    }

    func setStep(_ index: Int?, in recipe: Recipe) {
        mutate(recipe) { s in
            s.step = index
            s.stepCount = recipe.steps.count
        }
        print("[CookLedger] step -> \(String(describing: index)) of \(recipe.steps.count)")
    }

    func startTimer(endingAt date: Date, step: Int, in recipe: Recipe) {
        mutate(recipe) { s in
            s.timerEndsAt = date
            s.timerStep = step
        }
        print("[CookLedger] timer ends \(date) for step \(step)")
    }

    func clearTimer(in recipe: Recipe) {
        mutate(recipe) { s in
            s.timerEndsAt = nil
            s.timerStep = nil
        }
        print("[CookLedger] timer cleared")
    }

    /// The evening is over. Called when a dish is marked cooked.
    func forget(_ recipe: Recipe) {
        guard let key = Self.key(for: recipe) else { return }
        book.sessions[key] = nil
        save()
        print("[CookLedger] forgot session for \(recipe.title)")
    }

    /// Runs on init and again whenever the app comes back to the foreground,
    /// so a session that aged out while the phone was in a pocket is gone
    /// before anything is drawn from it.
    func pruneStale() {
        let before = book.sessions.count
        book.sessions = book.sessions.filter {
            Date.now.timeIntervalSince($0.value.lastTouched) < Self.sessionLife
        }
        if book.sessions.count != before {
            save()
            print("[CookLedger] pruned \(before - book.sessions.count) stale session(s)")
        }
    }

    // MARK: Persistence

    private func mutate(_ recipe: Recipe, _ body: (inout Session) -> Void) {
        guard let key = Self.key(for: recipe) else {
            print("[CookLedger] no key for \(recipe.title) — not recording")
            return
        }
        var s = book.sessions[key] ?? Session(startedAt: .now, lastTouched: .now)
        // An edited recipe drops its cursor here too, so a write cannot
        // resurrect an index the reader has already decided to ignore.
        if s.stepCount != recipe.steps.count, s.step != nil {
            s.step = nil
            s.timerEndsAt = nil
            s.timerStep = nil
        }
        body(&s)
        s.lastTouched = .now
        // An empty session is no session: nothing checked, no cursor and no
        // timer means the page is back to browsing.
        if s.checked.isEmpty, s.step == nil, s.timerEndsAt == nil {
            book.sessions[key] = nil
        } else {
            book.sessions[key] = s
        }
        save()
    }

    private func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Book.self, from: data) else {
            print("[CookLedger] no book on disk")
            return
        }
        book = decoded
        print("[CookLedger] loaded \(book.sessions.count) session(s)")
    }

    private func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(book) else { return }
        // Atomic: a force-quit mid-tap must not leave a half-written book,
        // which decodes as nothing and drops the evening.
        try? data.write(to: url, options: .atomic)
    }
}
