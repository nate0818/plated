import Foundation
import SwiftData

/// Nights this phone planned that somebody else in the household changed.
///
/// The companion to `RemovedNights`, and deliberately NOT the same thing. A
/// removal is an absence: once the meal is deleted there is no second
/// version of any fact left for two writers to converge on, so this phone
/// may act on it alone. A cook, a title or a serving count is a VALUE, and
/// writing one into the author's `PlannedMeal` from a delivery is exactly
/// the two-writer shape the mirror law forbids. See CLAUDE.md, "A value
/// crossing the seam needs a human. An absence does not."
///
/// So nothing here is ever applied automatically. It is remembered, shown,
/// and applied only by `adopt`, which a person calls by tapping something.
/// That is a person copying a value across the seam on the device in their
/// hand, which the rule has always allowed.
///
/// Why it has to be remembered at all: `absorb` drops every delivered record
/// this phone authored, so the delivery is the only moment this fact exists.
/// Without a book, a member setting the author down to cook reaches every
/// phone except the one whose plan it is.
@MainActor
enum HouseholdEdits {
    private static let file = "household-edits.json"

    /// One night, as the household now has it.
    struct Change: Codable, Equatable {
        var shoppingID: String
        var recordName: String
        /// The household's version.
        var title: String
        var cookID: String
        var cookName: String
        var servings: Int
        var day: String
        var slot: String
        /// The recipe the household's version is built on, so adopting can
        /// ATTACH their dish rather than only detaching this phone's. Its
        /// sibling `RemovedNights.Gone` has carried this since add-back
        /// needed it for the same problem, and this was the one place that
        /// could take a night's name without being able to give it a dish.
        var recipeOriginKey: String = ""
        /// Explicit recipe presence avoids attaching a recipe merely because
        /// its title matches a no-cooking choice. Nil preserves old saved
        /// decisions whose payload predates this evidence.
        var hasRecipe: Bool? = nil
        var tagline: String? = nil
        var cooked: Bool? = nil
        var cookedAt: Date? = nil
        /// Who made it so, empty when the record names nobody. A screen
        /// built from this may not guess a name.
        var by: String
        var at: Date
        /// The person has seen it and decided, either way.
        var settled: Bool = false

        func answers(_ entry: PlanLedger.Entry) -> Bool {
            title == entry.title && cookID == entry.cookID
                && servings == entry.servings && day == entry.day && slot == entry.slot
                && recipeOriginKey == entry.recipeOriginKey
                && (hasRecipe == nil || hasRecipe == entry.hasRecipe)
                && (tagline == nil || tagline == entry.tagline)
                && cooked == entry.cooked && cookedAt == entry.cookedAt
        }
    }

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: file)
    }

    private static var cached: [Change]?

    static var all: [Change] {
        if let cached { return cached }
        var book: [Change] = []
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Change].self, from: data) {
            book = decoded
        }
        cached = book
        return book
    }

    private static func save(_ book: [Change]) {
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

    /// The latest version wins its slot: a night changed twice has one
    /// answer, and it is the newer.
    static func note(_ entries: [PlanLedger.Entry]) {
        guard !entries.isEmpty else { return }
        var book = all
        for e in entries where !e.shoppingID.isEmpty {
            // A question already answered is not asked again. `note` runs on
            // every delivery carrying the record, and a zone replay after a
            // reinstall or a token reset redelivers every night, so
            // replacing the row wholesale put "Use their version" back in
            // front of somebody who had already said Keep mine. Only a
            // household change to something DIFFERENT is a new question.
            let previous = book.first { $0.shoppingID == e.shoppingID }
            let sameAnswer = previous?.answers(e) ?? false
            if sameAnswer, previous?.settled == true { continue }
            book.removeAll { $0.shoppingID == e.shoppingID }
            book.append(Change(
                shoppingID: e.shoppingID, recordName: e.recordName,
                title: e.title, cookID: e.cookID, cookName: e.cookName,
                servings: e.servings, day: e.day, slot: e.slot,
                recipeOriginKey: e.recipeOriginKey, hasRecipe: e.hasRecipe, tagline: e.tagline,
                cooked: e.cooked, cookedAt: e.cookedAt,
                by: e.editorName ?? "", at: .now
            ))
        }
        save(book)
        print("PLATED HOUSEHOLD: \(entries.count) night(s) of this phone's own were changed by the household")
    }

    /// The newest unanswered change to a given night, for the screens.
    static func pending(on date: Date, slot: MealSlot = .dinner) -> Change? {
        let day = PlanDay.string(date)
        return all.filter { $0.day == day && $0.slot == slot.rawValue && !$0.settled }
            .max { $0.at < $1.at }
    }

    static func pending(shoppingID: String) -> Change? {
        all.first { $0.shoppingID == shoppingID && !$0.settled }
    }

    static var pendingCount: Int { all.filter { !$0.settled }.count }

    /// Take the household's version onto this phone's own night.
    ///
    /// The ONE writer of a household value into a `PlannedMeal`, and it runs
    /// because somebody tapped something. The cook is matched by
    /// `participantID` and never by name: two people can share a first name
    /// and the wrong face on a dinner is the interface asserting something
    /// nobody said.
    ///
    /// The caller saves, so this can be called from inside a delivery
    /// without scheduling a publisher pass mid-flight.
    enum AdoptionResult: Equatable {
        case adopted
        case unavailable(String)
    }

    @discardableResult
    static func adopt(_ change: Change, in context: ModelContext) -> Bool {
        adoptResult(change, in: context) == .adopted
    }

    /// A caller must keep the change available and show the recovery message
    /// when it cannot safely copy the household's explicit recipe intent.
    static func adoptResult(_ change: Change, in context: ModelContext,
                            settleOnSuccess: Bool = true) -> AdoptionResult {
        guard let meals = try? context.fetch(FetchDescriptor<PlannedMeal>()) else {
            return .unavailable("Your plan couldn’t be opened. Try again.")
        }
        guard let meal = meals.first(where: { $0.shoppingID == change.shoppingID }) else {
            settle(change.shoppingID)
            return .unavailable("This night is no longer on your plan.")
        }
        let isLeftovers = change.hasRecipe == false
            && PlanMealChoice.isLeftovers(title: change.title, hasRecipe: false)
        // Resolve before changing the model. A failed local fetch is not
        // evidence that the household's recipe is absent.
        var adoptedRecipe = meal.recipe
        if change.hasRecipe == false {
            adoptedRecipe = nil
        } else if change.hasRecipe == true || !change.recipeOriginKey.isEmpty {
            guard let recipes = try? context.fetch(FetchDescriptor<Recipe>()) else {
                return .unavailable("Your cookbook couldn’t be opened. Try again.")
            }
            if !change.recipeOriginKey.isEmpty {
                // An explicit identity never falls back to a same-named,
                // different recipe when that identity is not in this cookbook.
                adoptedRecipe = recipes.first { $0.planningKey == change.recipeOriginKey }
            } else {
                let matches = recipes.filter { $0.title == change.title }
                adoptedRecipe = matches.count == 1 ? matches.first : nil
            }
        }
        if adoptedRecipe == nil, change.hasRecipe != false,
           change.hasRecipe == true || !change.recipeOriginKey.isEmpty,
           PlanMealChoice.isLeftovers(title: change.title, hasRecipe: false) {
            // "Leftovers" is also a valid recipe title. Dropping that explicit
            // recipe while copying its name would turn it into the no-cooking
            // choice on this device and republish a different plan.
            return .unavailable("The household’s recipe isn’t in your cookbook yet. Refresh the household, then try again.")
        }
        // With neither presence nor identity in an old saved change, keep
        // the owner's recipe instead of guessing from a dinner's name.
        meal.recipe = adoptedRecipe
        if !change.title.isEmpty { meal.customTitle = change.title }
        if let tagline = change.tagline { meal.tagline = tagline }
        if change.servings > 0 { meal.servings = change.servings }
        if let cooked = change.cooked {
            meal.cookedAt = cooked ? (change.cookedAt ?? meal.cookedAt ?? change.at) : nil
        }
        if isLeftovers {
            meal.cook = nil
            meal.cookedAt = nil
            meal.cookReaction = 0
            meal.actualMinutes = 0
        } else if change.cookID.isEmpty {
            // The delivered record carries a full cook field. Empty means
            // explicitly unassigned, unlike an unresolved nonempty identity.
            meal.cook = nil
        } else {
            let members = (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? []
            // Only when somebody is actually found. Assigning the lookup
            // straight through wrote nil over a cook the person had chosen
            // whenever the household's id matched no row on this phone,
            // which is a guest, a member mid-join, or simply a roster this
            // device has not pulled yet: taking the cook OFF a night is not
            // what "use their version" offered to do.
            // BOTH ids, the way `Seats.match` does it. A member this phone
            // knows only through the directory carries a `userRecordName`
            // and no `participantID` until the share reconciles, so matching
            // on the participant alone finds nobody for exactly the people a
            // household has most recently added, and "use their version"
            // becomes "clear the cook" for them.
            if let cook = members.first(where: {
                $0.participantID == change.cookID || $0.userRecordName == change.cookID
            }) ?? (change.cookID == TableIdentity.cached ? members.me : nil) {
                meal.cook = cook
            }
        }
        if settleOnSuccess { settle(change.shoppingID) }
        return .adopted
    }

    /// Answered, either way. Keeping the row after it is settled is what
    /// stops the same change being offered again on the next delivery.
    static func settle(_ shoppingID: String) {
        var book = all
        guard let i = book.firstIndex(where: { $0.shoppingID == shoppingID }) else { return }
        book[i].settled = true
        save(book)
    }

    /// An Apple ID change or a household leave.
    static func clear() {
        cached = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
