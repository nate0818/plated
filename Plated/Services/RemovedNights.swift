import Foundation
import SwiftData

/// Nights this phone planned that the household has taken off, waiting to
/// leave this phone's own plan.
///
/// A removal crosses Apple IDs as a `removed` flag on the night's record
/// (docs/household.md 3.2), and `PlanLedger.absorb` hands the author's own
/// ones back as `Delta.ownRemoved`. Acting on that is a `PlannedMeal`
/// deletion, which is the first place in this app where a person's own row
/// goes away because of something somebody else did, so it is worth being
/// slow about.
///
/// **This is not the merge the mirror law forbids.** After the deletion the
/// household's night lives only in the zone and this phone's `PlannedMeal`
/// is gone, so there is no second version of any fact for two writers to
/// converge on and nothing to ping-pong. A VALUE crossing that seam would
/// need a person; an ABSENCE does not.
///
/// Parked rather than acted on immediately, and parked in the app group
/// rather than in memory, because both hold-backs can outlive the delivery
/// that brought the removal and one of them can outlive the process:
///
/// - **A night that was cooked is never deleted.** `cookedAt` is what
///   `Recipe.timesCooked`, `Awards` and the insights all count, none of it
///   snapshotted, so deleting a cooked night silently rewrites a person's
///   history. The zone does not get to erase what happened in a kitchen.
/// - **A night being cooked right now is not deleted under the person's
///   hands.** It goes when they are finished. Re-checked at drain time and
///   never at park time, because `CookingFocusView.finish()` writes
///   `cookedAt` and then ends the session: a decision made when the removal
///   arrived would delete the night it had just marked cooked.
@MainActor
enum RemovedNights {
    private static let file = "removed-nights.json"

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: file)
    }

    private static var cached: [String]?

    /// Shopping ids, which is what a night is called on both sides of the
    /// seam: the record is `plan-<shoppingID>` and the meal carries the
    /// same id.
    static var parked: [String] {
        if let cached { return cached }
        var ids: [String] = []
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ids = decoded
        }
        cached = ids
        return ids
    }

    private static func save(_ ids: [String]) {
        cached = ids
        guard let url else { return }
        if ids.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func park(_ entries: [PlanLedger.Entry]) {
        let ids = entries.map(\.shoppingID).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        var all = parked
        for id in ids where !all.contains(id) { all.append(id) }
        save(all)
        print("PLATED HOUSEHOLD: \(ids.count) night(s) taken off by the household, waiting to leave this phone")
    }

    /// Take off the plan every parked night that is free to go.
    ///
    /// Returns true when something was deleted, so the caller can save and
    /// rebuild in the same pass rather than leaving the Lock Screen serving
    /// a dinner that is off the plan.
    ///
    /// The caller saves. This function does not, for the reason
    /// `PlanShare.takeRetractions` exists: a save schedules a publisher
    /// pass, and a publisher pass that runs from inside a delivery is how
    /// the queue ate itself the last time.
    @discardableResult
    static func drain(in context: ModelContext) -> Bool {
        let waiting = parked
        guard !waiting.isEmpty else { return false }
        let meals = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        var keep: [String] = []
        var deleted = false
        for id in waiting {
            guard let meal = meals.first(where: { $0.shoppingID == id }) else {
                // No row to take off: already gone, or never on this device.
                continue
            }
            if meal.cookedAt != nil {
                print("PLATED HOUSEHOLD: \(id) was cooked, so it stays on this phone's week")
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
                keep.append(id)
                continue
            }
            context.delete(meal)
            deleted = true
        }
        save(keep)
        return deleted
    }

    /// An Apple ID change or a household leave: these name nights in a
    /// household this account is no longer in.
    static func clear() {
        save([])
    }
}
