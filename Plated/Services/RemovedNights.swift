import Foundation
import SwiftData

/// Nights this phone planned that the household has taken off.
///
/// A removal crosses Apple IDs as a `removed` flag on the night's record
/// (docs/household.md 3.2a), and `PlanLedger.absorb` hands the author's own
/// ones back as `Delta.ownRemoved`. Acting on that deletes a `PlannedMeal`,
/// which is the first place in this app where a person's own row goes away
/// because of something somebody else did, so it is worth being slow about.
///
/// **This is not the merge the mirror law forbids.** After the deletion the
/// household's night lives only in the zone and this phone's `PlannedMeal`
/// is gone, so there is no second version of any fact for two writers to
/// converge on and nothing to ping-pong. A VALUE crossing that seam would
/// need a person; an ABSENCE does not.
///
/// This book holds three things at once, which is why it is a type rather
/// than a set of ids:
///
/// 1. **What is waiting.** Both hold-backs can outlive the delivery that
///    brought the removal, and one of them can outlive the process, so the
///    intent is in the app group rather than in memory.
/// 2. **What the author is owed.** Once the meal is deleted nothing else on
///    this phone remembers the night existed, so the screens that tell the
///    person their dinner went have nowhere to read from. `since(_:)` is
///    that.
/// 3. **Which records the publisher must not delete.** A tombstone is the
///    only carrier of who removed the night. The author's own publisher
///    would otherwise see a book entry with no live meal and hard-delete
///    the record within seconds, and every phone that had not pulled yet
///    would get a bare absence, which names nobody and so says nothing.
@MainActor
enum RemovedNights {
    private static let file = "removed-nights.json"

    /// One night the household took off, as this phone needs to remember it.
    struct Gone: Codable, Equatable {
        var shoppingID: String
        var recordName: String
        var title: String
        /// The remover's name, empty when the record named nobody. A screen
        /// built from this may not guess: a household is eight people, so a
        /// wrong "someone" is a person in the room.
        var by: String
        /// `PlanDay` string, so the sentence can name the night.
        var day: String
        /// Which meal of that day, because a day can hold more than one and
        /// the screen that explains an EMPTY night has only the date and the
        /// slot to find it by.
        var slot: String
        /// The recipe the night was built on, when it had one that came from
        /// somewhere nameable. Putting a night back looks the dish up by
        /// TITLE otherwise, which finds the wrong recipe when two share a
        /// name and none at all when one has been renamed. "" is the honest
        /// answer for a home-written recipe, and the title is the fallback.
        var recipeOriginKey: String = ""
        var at: Date
        /// The `PlannedMeal` has gone, or was kept because it was cooked.
        /// Either way there is nothing left to do but say so.
        var settled: Bool = false
        /// It was cooked, so it stays. A different sentence from a night
        /// that simply went.
        var kept: Bool = false
    }

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: file)
    }

    private static var cached: [Gone]?

    static var all: [Gone] {
        if let cached { return cached }
        var book: [Gone] = []
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Gone].self, from: data) {
            book = decoded
        }
        cached = book
        return book
    }

    private static func save(_ book: [Gone]) {
        // A night whose day is well past has nothing left to say about it.
        let floor = PlanDay.string(
            Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        )
        let kept = book.filter { $0.day >= floor }
        cached = kept
        guard let url else { return }
        if kept.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(kept) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func park(_ entries: [PlanLedger.Entry]) {
        guard !entries.isEmpty else { return }
        var book = all
        var added = 0
        for e in entries where !e.shoppingID.isEmpty {
            guard !book.contains(where: { $0.shoppingID == e.shoppingID }) else { continue }
            book.append(Gone(
                shoppingID: e.shoppingID, recordName: e.recordName, title: e.title,
                by: e.editorName ?? "", day: e.day, slot: e.slot,
                recipeOriginKey: e.recipeOriginKey, at: .now
            ))
            added += 1
        }
        guard added > 0 else { return }
        save(book)
        print("PLATED HOUSEHOLD: \(added) night(s) taken off by the household, waiting to leave this phone")
    }

    /// Take off the plan every parked night that is free to go.
    ///
    /// Returns true when something was deleted, so the caller can save and
    /// rebuild in the same pass rather than leaving the Lock Screen serving
    /// a dinner that is off the plan. The caller saves: a save schedules a
    /// publisher pass, and this runs from inside a delivery.
    @discardableResult
    static func drain(in context: ModelContext) -> Bool {
        var book = all
        guard book.contains(where: { !$0.settled }) else { return false }
        let meals = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        // A night that has been planned again has nothing left to explain.
        // Swept here rather than at the four places that can plan one,
        // because `forget(day:slot:)` being called from `addBack` and not
        // from plate, pickForMe or markEatingOut is exactly the kind of
        // rule that holds until somebody adds a fifth door.
        // ONLY a settled entry, and this is the whole of the bug that was
        // here: the sweep keyed on day and slot, so a night removed, planned
        // again and removed a second time put TWO entries on one slot, and
        // the still-live meal of the second removal made the key match and
        // took both. The removal this drain had been called to act on was
        // deleted before the loop below could reach it, and the night stayed
        // on the plan for good, which is the exact failure the feature
        // exists to prevent. An entry with work left to do is never swept.
        book.removeAll { gone in
            gone.settled && meals.contains {
                $0.shoppingID != gone.shoppingID
                    && PlanDay.string($0.date) == gone.day && $0.slot == gone.slot
            }
        }
        var deleted = false
        staged = []
        for i in book.indices where !book[i].settled {
            let id = book[i].shoppingID
            guard let meal = meals.first(where: { $0.shoppingID == id }) else {
                // No row to take off: already gone, or never on this device.
                book[i].settled = true
                continue
            }
            if meal.cookedAt != nil {
                // `cookedAt` is what `Recipe.timesCooked`, Awards and the
                // insights all count, none of it snapshotted. The zone does
                // not get to erase what happened in a kitchen.
                print("PLATED HOUSEHOLD: \(id) was cooked, so it stays on this phone's week")
                book[i].settled = true
                book[i].kept = true
                continue
            }
            // By the night AND by its recipe. A session's `mealID` is
            // stamped once, so cooking the same recipe from a second night
            // leaves the first night's id on it; asking both ways means the
            // answer is wrong only in the safe direction, which is a night
            // that waits one more pass.
            let cooking = CookLedger.shared.isCooking(mealID: id)
                || (meal.recipe.map { CookLedger.shared.isCooking($0) } ?? false)
            if cooking {
                print("PLATED HOUSEHOLD: \(id) is being cooked, it leaves when the session does")
                continue
            }
            context.delete(meal)
            staged.append(book[i].shoppingID)
            deleted = true
        }
        save(book)
        return deleted
    }

    /// The caller's save went through, so the deletions it committed are
    /// settled.
    ///
    /// Split from `drain` because `settled` gates every retry AND every
    /// caption: written before the save, a `Persist.save` that threw left a
    /// night that would never be retried and screens saying it had gone
    /// while it sat on the week. The caller cannot save from inside a
    /// delivery either, so the two halves cannot be one call.
    static func confirmDeletions() {
        guard !staged.isEmpty else { return }
        var book = all
        for i in book.indices where staged.contains(book[i].shoppingID) {
            book[i].settled = true
        }
        staged = []
        save(book)
    }

    /// Nights whose `context.delete` has been issued and whose save has not
    /// been confirmed. In memory: an unconfirmed deletion that does not
    /// survive a kill is one the next drain simply tries again.
    private static var staged: [String] = []

    /// The record names this phone must not delete out of the zone.
    ///
    /// The tombstone carries who removed the night, and it is the only thing
    /// that does. The author's publisher sees a book entry with no live meal
    /// and would hard-delete the record seconds later, so a phone that had
    /// not pulled yet would find a bare absence: it takes the night off, but
    /// it names nobody, so nothing can be said about it. Left alone, the
    /// record ages out of the zone on the ordinary -30 day rule.
    static func isTombstoned(_ recordName: String) -> Bool {
        all.contains { $0.recordName == recordName }
    }

    /// What the household has taken off recently, newest first, for the
    /// screens that tell the person their dinner went. Nothing else on this
    /// phone remembers the night once the meal is deleted.
    static func since(_ cutoff: Date) -> [Gone] {
        all.filter { $0.at >= cutoff }.sorted { $0.at > $1.at }
    }

    /// The night the household took off a given day and slot, if any.
    ///
    /// By slot as well as day, because a day can hold more than one meal and
    /// the screen that has to explain an EMPTY night has nothing else to
    /// find it by: the row it would have drawn is gone.
    static func gone(on date: Date, slot: MealSlot = .dinner) -> Gone? {
        let day = PlanDay.string(date)
        // NEWEST, not first. The book appends, so `first` answered with the
        // OLDEST removal of that night: plan a dinner, have it taken off,
        // plan another, have that taken off, and every screen named the
        // person who removed the first one and offered to restore a dish
        // nobody had touched since. `since` already sorted this way and the
        // two readers disagreed.
        return all.filter { $0.day == day && $0.slot == slot.rawValue }
            .max { $0.at < $1.at }
    }

    /// The night is back on the plan, so the sentence explaining its
    /// absence is spent.
    ///
    /// Called when the person plans that slot again. The captions are all
    /// gated on the night having no meal, so leaving the entry is harmless
    /// TODAY; it is cleared anyway because that gate is a property of four
    /// call sites rather than of the data, and the fifth reader of
    /// `gone(on:slot:)` will not know to write it.
    static func forget(day: String, slot: MealSlot = .dinner) {
        var book = all
        let before = book.count
        book.removeAll { $0.day == day && $0.slot == slot.rawValue }
        guard book.count != before else { return }
        save(book)
    }

    /// An Apple ID change or a household leave: these name nights in a
    /// household this account is no longer in.
    static func clear() {
        cached = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
