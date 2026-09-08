import Foundation
import SwiftData
import CloudKit
import CryptoKit
import UIKit

/// Publishes this phone's planned nights into the household's zone as
/// `PlatedHouseholdPlan` records, by diffing the plan against a book of what it
/// last published. docs/plan-share.md is the law.
///
/// Diff-based on purpose. Nights are inserted from eleven places, edited
/// from thirty and deleted from four, and half of those rely on autosave
/// with no explicit save call; hooking each one would miss the next one
/// somebody adds. So a pass reads the window, compares it with the book,
/// and sends the difference. Nothing here writes to `PlannedMeal` except
/// the `shoppingID` backfill the grocery builder already does.
@MainActor
enum PlanShare {

    // MARK: The household

    /// A table this phone could share its plan with.
    struct Table: Identifiable, Equatable {
        /// Canonical zone owner: "" for this phone's own table.
        let owner: String
        /// The root record's title, the host's name.
        let title: String
        var isOwn: Bool { owner.isEmpty }
        var id: String { owner.isEmpty ? "own" : owner }
    }

    /// Three states, never a guess, and a fourth for when the question
    /// could not be asked. `unresolved` is several candidates with no
    /// choice written down; Settings shows the picker. `unknown` is the
    /// answer before CloudKit has answered once this launch: no account,
    /// no network, an own share that would not read. It is never drawn as
    /// "nobody", because a member at Riley's table opening Settings in
    /// airplane mode is not a person nobody shares with.
    enum Household: Equatable {
        case unknown
        case none
        case unresolved([Table])
        case resolved(Table)

        var table: Table? {
            if case .resolved(let t) = self { return t }
            return nil
        }
    }

    /// The last resolution, for Settings. Refreshed by every pass that
    /// gets an answer; `unknown` until one does.
    private(set) static var household: Household = .unknown

    /// Resolve the household from the shares (docs/plan-share.md, "Which
    /// zone is the household's"), write the owner into the ledger, and
    /// return the answer. When CloudKit cannot be asked the last answer
    /// stands, and so does everything written under it.
    @discardableResult
    static func resolveHousehold() async -> Household {
        _ = await resolve()
        return household
    }

    /// The same, keeping the zone the publisher writes into. Nil when
    /// CloudKit could not be asked, which is never "no household".
    private static func resolve() async -> TableShare.HouseholdResolution? {
        let stored = PlanLedger.shared.householdOwner
        guard let r = await TableShare.resolveHousehold(stored: stored, me: TableIdentity.cached) else {
            return nil
        }
        let answer: Household
        switch r.choice {
        case .none:
            answer = .none
        case .unresolved(let owners):
            answer = .unresolved(r.tables.filter { owners.contains($0.owner) })
        case .resolved(let owner):
            answer = .resolved(r.tables.first { $0.owner == owner } ?? Table(owner: owner, title: ""))
        }
        household = answer
        let owner = answer.table?.owner
        // The setter nudges the ledger's observers; only a real change earns that.
        if PlanLedger.shared.householdOwner != owner {
            PlanLedger.shared.householdOwner = owner
        }
        if let owner, owner != stored {
            readAgain(owner)
        }
        return r
    }

    /// The ledger drops a table's nights when the household moves away
    /// from it, and a zone's deltas never come twice. Moving to a table,
    /// back or for the first time, reads it whole so the planner draws
    /// what is really there. The request is consumed inside the pull, so
    /// a fetch already in flight cannot store a token over it.
    private static func readAgain(_ owner: String) {
        TableShare.requestReplay(zoneOwner: owner)
        print("[PlanShare] household is now \(owner.isEmpty ? "the own table" : owner), reading it again")
        Task { @MainActor in await TablePull.pull(reason: "household") }
    }

    /// The person chose a table in Settings. Written down first, so the
    /// resolution honours it while it is a candidate; then the book's
    /// nights leave whatever table they were in, and a pass publishes
    /// them where they now belong. The full read is asked for here, not
    /// left to `resolve`: by the time that runs the choice is already the
    /// stored owner, so it would see nothing move.
    static func choose(owner: String) async {
        print("[PlanShare] chose \(owner.isEmpty ? "the own table" : owner)")
        let previous = PlanLedger.shared.householdOwner
        PlanLedger.shared.householdOwner = owner
        await rehome(to: owner)
        if previous != owner { readAgain(owner) }
        await publish(reason: "choose")
    }

    // MARK: The night as it travels

    /// Every wire field for one night, read off a `PlannedMeal` once so
    /// the rest of a pass never touches the model again. `photoData` is
    /// the recipe's SOURCE bytes: fingerprinted by count, downscaled only
    /// when that count changed.
    /// One ingredient of one night, already canonical, as the wire carries
    /// it.
    ///
    /// The record has to carry these, because nothing on the reader's phone
    /// can supply them. `GroceryListBuilder` builds from `PlannedMeal` and a
    /// night somebody else planned is never one (docs/household.md 3.2); the
    /// recipe behind it need not be in this cookbook, and a night is not
    /// required to have a recipe at all; and matching a title back to a
    /// recipe on the reader's phone is a guess. Canonicalised on the
    /// author's phone, where the recipe actually is, so that two phones key
    /// on the same `GroceryMeasure.key`. That is what lets a mark made on
    /// one of them land on the other's row rather than on nothing.
    nonisolated struct Line: Codable, Equatable, Sendable {
        var name: String
        var normalizedName: String
        var unit: String
        var quantity: Double
        var aisle: String
        var isPantryStaple: Bool
    }

    nonisolated struct Plan: Equatable, Sendable {
        var recordName: String
        var shoppingID: String
        var authorID: String
        var authorName: String
        var authorColorHex: String
        var cookID: String
        var cookName: String
        var cookColorHex: String
        var cookSeat: String
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
        var createdAt: Date
        var photoData: Data?
        var lines: [Line] = []

        var photoCount: Int { photoData?.count ?? 0 }
        /// Sorted, so the order `sortedIngredients` happens to return can
        /// never churn the fingerprint and republish a window that did not
        /// change.
        var linesKey: String {
            // Rounded, because a rescale is a multiply and 4 to 6 to 4
            // does not return the original bytes. At full precision that
            // drift reads as a changed night and republishes a window
            // nobody touched.
            lines.map { "\($0.normalizedName)\u{1F}\($0.unit)\u{1F}\(String(format: "%.4f", $0.quantity))\u{1F}\($0.aisle)\u{1F}\($0.isPantryStaple ? 1 : 0)" }
                .sorted().joined(separator: ";")
        }
        var fingerprint: String {
            PlanShare.fingerprint(
                day: day, slot: slot, title: title, servings: servings,
                cookID: cookID, cookName: cookName, cookSeat: cookSeat, tagline: tagline,
                cooked: cooked, cookedAt: cookedAt, hasRecipe: hasRecipe,
                recipeMinutes: recipeMinutes, recipeOriginKey: recipeOriginKey,
                lines: linesKey
            )
        }
    }

    /// A stable hash of everything on the record except the photo. Not
    /// `Hasher`: that is seeded per process, and a fingerprint that changed
    /// on every launch would republish the whole window every launch. Hex,
    /// so it never carries the "|" the news splits its keys on.
    nonisolated static func fingerprint(
        day: String, slot: String, title: String, servings: Int,
        cookID: String, cookName: String, cookSeat: String, tagline: String,
        cooked: Bool, cookedAt: Date?, hasRecipe: Bool,
        recipeMinutes: Int, recipeOriginKey: String, lines: String = ""
    ) -> String {
        let cookedStamp = cookedAt.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        // The ingredients are in here because they now ride the record, so
        // editing a recipe has to republish the nights that use it or a
        // member's list keeps the old quantities. It also means the first
        // pass after this shipped republishes the whole window, which is
        // how the existing records get a `lines` field at all.
        let parts = [
            day, slot, title, String(servings), cookID, cookName, cookSeat, tagline,
            cooked ? "1" : "0", cookedStamp, hasRecipe ? "1" : "0",
            String(recipeMinutes), recipeOriginKey, lines
        ]
        // Length-prefixed, so a title containing the separator cannot
        // collide with a different split of the same characters.
        let joined = parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// One night as the wire will carry it.
    ///
    /// The cook rules are the honesty rules: `cookID` is the cook's
    /// participant id, or this phone's own id when the cook is the owner,
    /// or "" so a reader never guesses; `cookName` is blank for an invited
    /// seat, because a name typed five seconds ago is not a cook.
    /// `recipeOriginKey` is the recipe's `originID`, "" for every
    /// home-written recipe, and an empty key never matches anything.
    static func plan(
        for meal: PlannedMeal, me: String,
        authorName: String = "", authorColorHex: String = "FF5A3C"
    ) -> Plan {
        let cook = meal.cook
        var cookID = ""
        if let cook {
            if let id = cook.participantID, !id.isEmpty { cookID = id }
            else if cook.isOwner { cookID = me }
        }
        let cookName = cook?.seat == .invited ? "" : (cook?.name ?? "")
        let recipe = meal.recipe
        let shoppingID = meal.shoppingID ?? ""
        return Plan(
            recordName: "plan-\(shoppingID)", shoppingID: shoppingID,
            authorID: me, authorName: authorName, authorColorHex: authorColorHex,
            cookID: cookID, cookName: cookName,
            cookColorHex: cook?.colorHex ?? "", cookSeat: cook?.seat.rawValue ?? "",
            day: PlanDay.string(meal.date), slot: meal.slot, title: meal.title,
            servings: meal.servings, tagline: meal.tagline,
            cooked: meal.cookedAt != nil, cookedAt: meal.cookedAt,
            hasRecipe: recipe != nil, recipeMinutes: recipe?.totalMinutes ?? 0,
            recipeOriginKey: recipe?.originID ?? "",
            createdAt: meal.createdAt, photoData: recipe?.photoData,
            lines: groceryLines(for: meal)
        )
    }

    /// The night's ingredients, scaled to its servings and canonicalised
    /// exactly the way `GroceryListBuilder.aggregate` does it locally.
    ///
    /// The same two steps in the same order, because the whole point is
    /// that the key this produces equals the key the reader's own nights
    /// produce. A pantry staple is carried and flagged rather than dropped:
    /// whether staples are shown is the reader's setting, not the author's.
    static func groceryLines(for meal: PlannedMeal) -> [Line] {
        meal.scaledIngredients.compactMap { ingredient, quantity in
            guard !ingredient.normalizedName.isEmpty else { return nil }
            let amount = GroceryMeasure.canonical(quantity, ingredient.unit)
            return Line(
                name: ingredient.name, normalizedName: ingredient.normalizedName,
                unit: amount.unit, quantity: amount.quantity,
                aisle: ingredient.aisleValue.rawValue,
                isPantryStaple: ingredient.isPantryStaple
            )
        }
    }

    // MARK: The book

    /// What was last published for one record name. Day and slot are here
    /// so the delete rule can tell a night taken off from one that aged
    /// out of the window.
    nonisolated struct BookEntry: Codable, Equatable, Sendable {
        var fingerprint: String
        var photoCount: Int
        var zoneOwner: String
        var day: String
        var slot: String
        /// The record's `modifiedAt` as this phone last left it, taken off
        /// what was saved and never off this phone's clock.
        ///
        /// The publisher's half of the check the edit path already makes
        /// with `movedOn`. Without it `pass` rewrote every field from the
        /// author's own `PlannedMeal` onto whatever the zone held, so a
        /// member's edit to a night survived only until its author next
        /// touched that night, and the author's SECOND DEVICE clobbered one
        /// with nobody touching anything: this book is per device, so the
        /// other phone has no entry, `diff` emits `known: false`, nothing
        /// is fetched, and a freshly minted record replays every key over
        /// the server copy through `saveOverServerCopy`.
        ///
        /// Optional because a book written before this existed has no
        /// answer, and nil is read as "never published under this rule", so
        /// the first pass after it ships establishes the value instead of
        /// refusing every night at once.
        var serverModifiedAt: Date?
        /// When the zone was found to have moved on and this phone stood
        /// down rather than overwrite. Cleared the moment the night sends.
        ///
        /// The author has no `PlanLedger.Entry` for their own night, so
        /// this book is the only place their phone can hold the fact that
        /// the household changed it. The sentence that says so is drawn
        /// from here.
        var contestedAt: Date?
        /// Who changed it and what they made it, read off the record at the
        /// moment this phone stood down.
        ///
        /// The one moment the author's phone ever holds their own night's
        /// server copy. `absorb` drops every record whose `authorID` is this
        /// phone, which is the whole reason a night can be contested at all,
        /// so the fetch in `pass` is the only place these two facts exist to
        /// be taken. Without them the sentence could say that something
        /// changed and never say who or to what, which is a notice that
        /// tells a person to go and look rather than telling them anything.
        var contestedBy: String?
        var contestedTitle: String?
        /// What this phone was about to publish, so the second clause can
        /// say what the author's own plan still reads without the screen
        /// having to go and fetch a `PlannedMeal` to find out.
        var contestedMineTitle: String?
    }

    typealias Book = [String: BookEntry]

    /// One night to save this pass.
    nonisolated struct Upload: Equatable, Sendable {
        var plan: Plan
        /// The book has seen this name: fetch before saving.
        var known: Bool
        /// The photo component changed, or the record is new to this
        /// table: send the asset, or clear it.
        var sendPhoto: Bool
    }

    nonisolated struct Work: Equatable, Sendable {
        var save: [Upload] = []
        /// Nights taken off the plan.
        var delete: [String] = []
        /// Nights more than thirty days past, deleted so the zone does not
        /// keep a year of dinners.
        var ageOut: [String] = []
        var isEmpty: Bool { save.isEmpty && delete.isEmpty && ageOut.isEmpty }
    }

    /// The Save and Delete rules from docs/plan-share.md, pure. Saves come
    /// nearest night first, so a capped pass sends the ones that matter.
    nonisolated static func diff(book: Book, meals: [Plan], target: String, now: Date = .now) -> Work {
        var work = Work()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let takenOffFloor = PlanDay.string(cal.date(byAdding: .day, value: -7, to: today) ?? today)
        let ageOutFloor = PlanDay.string(cal.date(byAdding: .day, value: -30, to: today) ?? today)

        var live = Set<String>()
        for plan in meals {
            live.insert(plan.recordName)
            let entry = book[plan.recordName]
            let moved = entry.map { $0.zoneOwner != target } ?? true
            let photoChanged = (entry?.photoCount ?? 0) != plan.photoCount
            let changed = entry?.fingerprint != plan.fingerprint
            guard entry == nil || changed || photoChanged || moved else { continue }
            work.save.append(Upload(
                plan: plan, known: entry != nil,
                sendPhoto: entry == nil || moved || photoChanged
            ))
        }
        for (name, entry) in book where !live.contains(name) {
            if entry.day >= takenOffFloor { work.delete.append(name) }
            else if entry.day < ageOutFloor { work.ageOut.append(name) }
        }
        work.save.sort {
            ($0.plan.day, $0.plan.slot, $0.plan.recordName) < ($1.plan.day, $1.plan.slot, $1.plan.recordName)
        }
        work.delete.sort()
        work.ageOut.sort()
        return work
    }

    /// Rehearsal and tests.
    static let bookFile = "plan-share.json"

    private static var cachedBook: Book?

    private static var bookURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: bookFile)
    }

    private static func loadBook() -> Book {
        if let cachedBook { return cachedBook }
        var book: Book = [:]
        if let url = bookURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Book.self, from: data) {
            book = decoded
        }
        cachedBook = book
        return book
    }

    private static func saveBook(_ book: Book) {
        cachedBook = book
        guard let url = bookURL, let data = try? JSONEncoder().encode(book) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// An Apple ID change: the book names records in a zone this account
    /// cannot see, so the next pass starts from nothing and republishes
    /// into the new account's table.
    static func forgetBook() {
        cachedBook = [:]
        if let url = bookURL { try? FileManager.default.removeItem(at: url) }
        // A queued edit names a record in that same unreachable zone, and it
        // was made by a person who is no longer signed in here. It goes with
        // the book rather than being sent from somebody else's account.
        forgetEdits()
        print("[PlanShare] book forgotten")
    }

    // MARK: Publishing

    private static var pendingSave: Task<Void, Never>?
    private static var inFlight: Task<Void, Never>?
    private static var again = false

    /// The tail of the queue of things writing the household zone.
    ///
    /// `publish` guarded itself with `inFlight` and `write` ignored it, so a
    /// pass draining this phone's own queued edit while a `write` was on the
    /// wire landed that edit, and the write's own fetch then read a
    /// `modifiedAt` newer than its `seenAt` and told the person somebody else
    /// had changed their night. Nobody had: it was this phone's own drain.
    /// The change still landed, so only the sentence was false, which is the
    /// honesty rule with nothing else wrong. One writer at a time makes that
    /// sentence impossible, and `deliver` catches the other half, an edit
    /// already sent by the pass this call waited for.
    private static var zoneTail: Task<Void, Never>?

    /// Run `work` with nothing else writing the zone. Internal so the
    /// serialisation itself can be tested without CloudKit.
    static func exclusively<T: Sendable>(_ work: @escaping @Sendable @MainActor () async -> T) async -> T {
        let ahead = zoneTail
        // Unstructured for the reason `publish`'s pass is: this must outlive
        // a cancelled caller rather than stop half way through a batch.
        let job = Task { @MainActor () -> T in
            await ahead?.value
            return await work()
        }
        let tail = Task { @MainActor in _ = await job.value }
        zoneTail = tail
        let result = await job.value
        // Only the last one out clears the slot: anybody who queued behind
        // this is now the tail and still has to be waited for.
        if zoneTail == tail { zoneTail = nil }
        return result
    }

    /// Ask for a pass. A burst of autosaves is one pass three seconds
    /// after the last; everything else runs now. One pass at a time, and
    /// a request during a pass runs one more after it.
    static func schedule(reason: String = "save") {
        if reason == "save" {
            pendingSave?.cancel()
            pendingSave = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                pendingSave = nil
                await publish(reason: reason)
            }
            return
        }
        Task { @MainActor in await publish(reason: reason) }
    }

    /// One pass now. Safe to call from anywhere on the main actor; returns
    /// when the pass is done, or when the pass it joined is done.
    static func publish(reason: String) async {
        if let running = inFlight {
            again = true
            await running.value
            return
        }
        // Unstructured on purpose: the pass must outlive a debounce task
        // that the next save cancels, or CloudKit's async calls would be
        // cancelled mid-batch. The slot is cleared as the task's last act,
        // not after `await task.value` resumes: a request landing in that
        // gap would join a finished task, set `again`, and be lost.
        let task = Task { @MainActor in
            repeat {
                again = false
                await exclusively { await pass(reason: reason) }
            } while again
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    /// Meals from seven days ago to ninety days ahead, every slot.
    private static func mealsInWindow(_ context: ModelContext, now: Date) -> [PlannedMeal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let end = cal.date(byAdding: .day, value: 90, to: today) ?? today
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.date >= start && $0.date <= end }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func pass(reason: String) async {
        guard !TableIdentity.isPlaceholder else {
            print("[PlanShare] \(reason): identity unconfirmed, nothing published")
            return
        }
        guard await TableSync.accountAvailable() else {
            print("[PlanShare] \(reason): no iCloud account, nothing published")
            return
        }
        guard let resolution = await resolve() else {
            print("[PlanShare] \(reason): could not ask which table, nothing changed")
            return
        }
        let target = household.table?.owner
        await rehome(to: target)
        guard let target, let db = resolution.database, let zoneID = resolution.zoneID else {
            switch household {
            case .unknown:
                print("[PlanShare] \(reason): the shares could not be read, nothing published")
            case .none:
                print("[PlanShare] \(reason): no table to share the plan with")
            case .unresolved(let tables):
                print("[PlanShare] \(reason): \(tables.count) tables and no choice, nothing published")
            case .resolved:
                print("[PlanShare] \(reason): the table has no zone this phone can write")
            }
            return
        }

        // Changes this phone made to other people's nights, which are people
        // waiting on something they can see, go before this phone's own diff.
        await drainEdits(in: db, zone: zoneID, target: target)

        let now = Date.now
        let me = TableIdentity.cached
        let context = PlatedStore.shared.mainContext
        let meals = mealsInWindow(context, now: now)
        // The record name is the shoppingID, so a night without one gets
        // one here, the way the grocery builder does. The one write to
        // `PlannedMeal` this file makes.
        var backfilled = 0
        for meal in meals where meal.shoppingID == nil {
            meal.shoppingID = UUID().uuidString
            backfilled += 1
        }
        if backfilled > 0 { Persist.save(context, "plan share backfill") }

        let owner = Seats.all(in: context).first(where: \.isOwner)
        let plans = meals.map {
            plan(for: $0, me: me, authorName: owner?.name ?? "",
                 authorColorHex: owner?.colorHex ?? "FF5A3C")
        }
        var book = loadBook()
        var work = diff(book: book, meals: plans, target: target, now: now)
        guard !work.isEmpty else {
            print("[PlanShare] \(reason): \(plans.count) night(s) in the window, nothing to change")
            return
        }
        // Not in front: a silent push or a background breath gets a small
        // budget, and the rest waits for the next foreground pass.
        if UIApplication.shared.applicationState != .active {
            let cap = 10
            work.save = Array(work.save.prefix(cap))
            work.delete = Array(work.delete.prefix(max(0, cap - work.save.count)))
            work.ageOut = Array(work.ageOut.prefix(max(0, cap - work.save.count - work.delete.count)))
        }

        // EVERY save fetches, not only the ones this book has seen. The
        // book is per device, so `known` is false on the author's second
        // phone for a night their first phone published, and skipping the
        // fetch there is exactly how that second phone minted a fresh
        // record and replayed it over a member's edit.
        let names = work.save.map(\.plan.recordName)
        let existing = await TableShare.fetchPlanRecords(named: names, in: db, zone: zoneID)
        var records: [CKRecord] = []
        var temps: [URL] = []
        var contested: [Contested] = []
        for upload in work.save {
            let name = upload.plan.recordName
            let served = existing[name]
            // A record this phone did not last write is not this phone's to
            // overwrite. Compared in whole seconds by `movedOn`, the same
            // comparison and the same rounding the edit path uses.
            //
            // `serverModifiedAt` nil means this book predates the rule, so
            // the night publishes once and the value is established rather
            // than every night standing down at once. A record the zone
            // does not have is not contested: that is a night to mint.
            if let served, let mine = book[name]?.serverModifiedAt,
               movedOn(served["modifiedAt"] as? Date, since: mine) {
                contested.append(Contested(
                    name: name,
                    by: served["editorName"] as? String ?? "",
                    title: served["title"] as? String ?? "",
                    mine: upload.plan.title
                ))
                continue
            }
            let photo: TableShare.PlanPhoto
            if !upload.sendPhoto {
                photo = .keep
            } else if let data = upload.plan.photoData, let small = downscale(data) {
                photo = .set(small)
            } else {
                photo = .clear
            }
            let (record, temp) = TableShare.planRecord(
                upload.plan, existing: served, zone: zoneID, photo: photo, now: now
            )
            records.append(record)
            if let temp { temps.append(temp) }
        }
        let saved = await TableShare.savePlans(records, in: db)
        for temp in temps { try? FileManager.default.removeItem(at: temp) }
        for upload in work.save where saved.contains(upload.plan.recordName) {
            book[upload.plan.recordName] = BookEntry(
                fingerprint: upload.plan.fingerprint, photoCount: upload.plan.photoCount,
                zoneOwner: target, day: upload.plan.day, slot: upload.plan.slot,
                // `planRecord` stamps this exact value onto the record, so
                // it is what the zone now holds, not a guess at it.
                serverModifiedAt: now, contestedAt: nil
            )
        }
        // A night that stood down keeps everything else the book knows and
        // gains the mark. It is deliberately NOT republished on the next
        // pass by clearing the fingerprint: standing down has to be stable,
        // or the two phones take turns overwriting each other every pass.
        for row in contested where book[row.name] != nil {
            // Only the first stand-down stamps the time, so the sentence
            // does not restate itself as new every pass. Who and what are
            // refreshed every time, because the household may have changed
            // it again since.
            if book[row.name]?.contestedAt == nil { book[row.name]?.contestedAt = now }
            book[row.name]?.contestedBy = row.by
            book[row.name]?.contestedTitle = row.title
            book[row.name]?.contestedMineTitle = row.mine
        }
        if !contested.isEmpty {
            print("[PlanShare] \(reason): \(contested.count) night(s) changed in the zone since this phone last wrote them, standing down")
        }
        let removals = work.delete + work.ageOut
        let gone = await TableShare.deletePlans(names: removals, in: db, zone: zoneID)
        for name in gone { book[name] = nil }
        saveBook(book)
        print("[PlanShare] \(reason): saved \(saved.count)/\(work.save.count), deleted \(gone.count)/\(removals.count) in \(target.isEmpty ? "the own table" : target)")
    }

    // MARK: A night the household changed under its author

    /// What `pass` read off the record when it stood down. Internal to the
    /// pass; the screen reads `Contest`.
    private struct Contested {
        var name: String; var by: String; var title: String; var mine: String
    }

    /// A night this phone planned that the household has since changed,
    /// with every noun the sentence about it needs.
    ///
    /// `by` is empty when the record predates `editorID`, and a sentence
    /// built from this may not guess at a name in that case: the digest's
    /// `changer(_:)` ladder made the same call, and says nothing rather
    /// than naming the author for somebody else's edit.
    nonisolated struct Contest: Equatable, Sendable {
        var recordName: String
        var day: String
        var at: Date
        var by: String
        var theirTitle: String
        var mineTitle: String
    }

    /// Nights this phone stood down on, by record name, with when it first
    /// stood down.
    ///
    /// The author has no `PlanLedger.Entry` for a night they planned
    /// themselves, so this book is the only place their phone holds the
    /// fact that somebody else changed it. A screen that says nothing here
    /// leaves the publisher quietly refusing to publish forever, which is
    /// the stall being silent rather than the stall being fixed.
    @MainActor
    static func contestedNights() -> [Contest] {
        loadBook().compactMap { name, entry in
            guard let at = entry.contestedAt else { return nil }
            return Contest(
                recordName: name, day: entry.day, at: at,
                by: entry.contestedBy ?? "",
                theirTitle: entry.contestedTitle ?? "",
                mineTitle: entry.contestedMineTitle ?? ""
            )
        }.sorted { $0.day < $1.day }
    }

    @MainActor
    static func contest(for recordName: String) -> Contest? {
        contestedNights().first { $0.recordName == recordName }
    }

    @MainActor
    static func isContested(_ recordName: String) -> Bool {
        loadBook()[recordName]?.contestedAt != nil
    }

    /// The author looked at a contested night and decided, either way.
    ///
    /// The book takes the zone's current version as this phone's starting
    /// point regardless of which way they went, because standing down again
    /// over the change they just answered would be the app refusing a
    /// decision the person had already made. After this, keeping their own
    /// version republishes it on the next pass, which is now a deliberate
    /// act by somebody who was shown the difference rather than a blind
    /// overwrite by a phone that never knew.
    ///
    /// False when the zone could not be reached, so the caller can leave
    /// the sentence standing rather than claim the night is settled.
    @MainActor
    @discardableResult
    static func settleContest(_ recordName: String) async -> Bool {
        var book = loadBook()
        guard let entry = book[recordName] else { return false }
        guard let (db, zoneID) = await TableShare.householdZone(ownedBy: entry.zoneOwner) else {
            return false
        }
        let served = await TableShare.fetchPlanRecords(named: [recordName], in: db, zone: zoneID)
        // Absent is an answer: the household took the night off, so there
        // is nothing left to stand down over.
        let stamp = served[recordName]?["modifiedAt"] as? Date
        book = loadBook()
        book[recordName]?.serverModifiedAt = stamp
        book[recordName]?.contestedAt = nil
        book[recordName]?.contestedBy = nil
        book[recordName]?.contestedTitle = nil
        book[recordName]?.contestedMineTitle = nil
        saveBook(book)
        print("[PlanShare] contest settled for \(recordName)")
        return true
    }

    /// The answer changed. Nights the book holds in any other table are
    /// deleted where that table is still reachable and forgotten either
    /// way, so the next pass publishes them afresh; that table's nights
    /// leave the ledger.
    private static func rehome(to target: String?) async {
        let book = loadBook()
        let strays = book.filter { $0.value.zoneOwner != target }
        guard !strays.isEmpty else { return }
        let byOwner = Dictionary(grouping: strays.keys) { strays[$0]?.zoneOwner ?? "" }
        for (owner, names) in byOwner {
            let gone = await TableShare.deletePlans(names: Array(names), zoneOwner: owner)
            print("[PlanShare] re-home: \(gone.count) of \(names.count) night(s) taken out of \(owner.isEmpty ? "the own table" : owner)")
            PlanLedger.shared.forget(zoneOwner: owner)
        }
        var updated = loadBook()
        for name in strays.keys { updated[name] = nil }
        saveBook(updated)
    }

    // MARK: Changing a night somebody else planned

    /// Who is holding this phone, for the `editorID` and `editorName` an
    /// edit signs its record with.
    ///
    /// The record already carries the person who PLANNED the night, and any
    /// member may now change one, so without this a household hears "Nate
    /// changed Thursday to Ragu" about a change Riley made: a false sentence
    /// about a real person, which DESIGN.md's honesty rule and
    /// docs/notifications.md both forbid outright. It is also the only way a
    /// reader's own edit coming back off the zone can be recognised as their
    /// own and kept quiet.
    ///
    /// The name comes from this household's own roster row for this
    /// identity, the same place the cook's name comes from, so the two
    /// sentences name a person the same way. A seat this phone cannot name
    /// travels without a name rather than with an invented one; the reader
    /// falls back to the author, and says nothing at all when the editor is
    /// somebody it has never heard of.
    static func editor() -> (id: String, name: String) {
        (TableIdentity.cached, Seats.me(in: PlatedStore.shared.mainContext)?.name ?? "")
    }

    /// What one person changed about one household night, on its way to the
    /// zone.
    ///
    /// **An edit writes the `PlatedHouseholdPlan` record. It never writes a
    /// `PlannedMeal`, and neither does anything downstream of it.** Nate's
    /// argument, which is the whole reason this type exists rather than a
    /// meal merge: `PlannedMeal` is a `@Model` in a store configured
    /// `cloudKitDatabase: .automatic`, so a household fact placed there has
    /// two writers by construction, the zone and this phone's own mirror
    /// carrying it to its other devices while they merge the same record.
    /// A collapse pass that runs after every merge repairs that shape rather
    /// than fixing it: it holds in the cases somebody tested and fails
    /// quietly in the rest. So the record is the one authority, the ledger
    /// is how this phone holds it, and last writer wins on `modifiedAt`.
    ///
    /// A `nil` field means "leave what the record says". An edit carries
    /// what the person touched, never a whole night, so two people changing
    /// two different things about one night do not undo each other unless
    /// they land inside the same version of the record.
    struct Edit: Codable, Equatable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable { case change, delete }

        /// `plan-<shoppingID>`, the night's one name in the zone.
        var recordName: String
        /// Which version of this night's queued entry this is.
        ///
        /// One entry per record, folded, so "the entry for plan-X" is not a
        /// stable thing to answer about: a second change made while the
        /// first is on the wire folds onto it and means something new. The
        /// drain used to drop by name after its send, which deleted that
        /// fold UNSENT and then handed its own `.landed` to the person who
        /// made it, so the sheet closed on a success that never left the
        /// phone. `enqueue` bumps this on every fold; `drop` removes an
        /// entry only when this still matches what was sent; and `answers`
        /// is keyed by it, so a caller can never read a different version's
        /// outcome as its own.
        ///
        /// Optional in the decode sense would be wrong here: a queue
        /// written before this existed decodes at 0, which is the same
        /// answer a fresh entry gets, and the first fold takes it to 1.
        var revision: Int = 0
        /// The household this edit was made in. An edit for a zone this
        /// phone has since left is dropped rather than sent.
        var zoneOwner: String
        var day: String
        var slot: String
        var kind: Kind = .change
        /// The record's `modifiedAt` as this phone last saw it. The write
        /// compares the server's against this and takes the server version
        /// when they differ, so a person is told somebody got there first
        /// instead of quietly overwriting them.
        var seenAt: Date?
        /// The night's AUTHOR, carried only for the mint in `record(for:)`.
        /// Never the editor: see the comment there.
        var authorID: String = ""
        var authorName: String = ""
        var authorColorHex: String = "FF5A3C"
        /// Who is making THIS change, written onto the record so a reader
        /// can say who did it. It rides on the edit rather than being
        /// resolved when the queue drains, because a drain happens on a
        /// scene change with no sheet and no roster in front of it, and an
        /// edit made under one identity must not be signed by whoever the
        /// phone belongs to when it finally goes out.
        ///
        /// Optional rather than defaulted, for the reason `pendingRemoval`
        /// is: a synthesised `init(from:)` throws on a missing key, and a
        /// queue written before these two fields would decode as nothing,
        /// silently dropping every change waiting on this phone.
        var editorID: String?
        var editorName: String?
        var createdAt: Date = .now
        var title: String?
        var servings: Int?
        var tagline: String?
        var cookID: String?
        var cookName: String?
        var cookColorHex: String?
        var cookSeat: String?
        var hasRecipe: Bool?
        var recipeMinutes: Int?
        var recipeOriginKey: String?
        var photo: PhotoIntent = .keep
        /// When the person made it, which is what the row shows and what a
        /// landed save stamps the record with.
        var at: Date = .now
        /// Refusals so far, the outbox's rule: a queue that retries forever
        /// is a battery that never rests.
        var tries: Int = 0

        var id: String { recordName }

        /// Addressed at the night as this phone holds it, with no field set
        /// yet: the caller sets the ones the person touched.
        ///
        /// On the main actor because it signs itself: `PlanShare.editor()`
        /// reads this phone's roster row, and an edit that leaves here
        /// unsigned reaches the zone as a change nobody made.
        @MainActor
        init(changing entry: PlanLedger.Entry) {
            recordName = entry.recordName
            zoneOwner = entry.zoneOwner
            day = entry.day
            slot = entry.slot
            seenAt = entry.changedAt
            authorID = entry.authorID
            authorName = entry.authorName
            authorColorHex = entry.authorColorHex
            createdAt = entry.createdAt
            let signer = PlanShare.editor()
            editorID = signer.id
            editorName = signer.name
        }

        /// Taking the night off the plan for everybody.
        @MainActor
        init(deleting entry: PlanLedger.Entry) {
            self.init(changing: entry)
            kind = .delete
        }
    }

    /// What an edit does with the record's photograph. A night whose dish
    /// changed may not keep the old dish's picture: that is the honesty rule
    /// with a photograph on it.
    enum PhotoIntent: String, Codable, Sendable {
        /// Nothing about the dish changed, so readers keep what they have
        /// and download nothing.
        case keep
        /// The dish changed and this phone has no picture of the new one.
        case clear
        /// Send the bytes queued beside this edit.
        case send
    }

    /// What a write did, in the words the sheet has to say out loud. A
    /// queued write is not a landed write, and nothing here lets a caller
    /// confuse the two.
    enum WriteOutcome: Equatable {
        /// It is in the zone, stamped with this clock.
        case landed(Date)
        /// Kept on this phone: the row says it has not gone yet and the next
        /// pass sends it. The string is the sentence for the person, because
        /// the causes are not one thing. "It goes out when this phone is back
        /// online" was said about an account that is fine and a household
        /// zone that would not read, and a person staring at four bars was
        /// being told something false about their own phone.
        case queued(String)
        /// Somebody changed this night first. Their version is in the ledger
        /// now, and the edit is gone.
        case theirs
        /// It will not land. The string is the sentence for the person.
        case refused(String)
    }

    // MARK: The queue

    /// Edits that have not reached the zone. A JSON book in the app group,
    /// per device, beside `plan-share.json`, for the reason `TableOutbox`
    /// and `HouseholdOutbox` are not mirrored: a mirrored queue is a
    /// distributed queue with no lease, and two of one person's devices
    /// would both drain the same row.
    ///
    /// The book of fingerprints cannot hold an intent (it answers "what did
    /// this phone last publish", which is a different question), so this is
    /// the small queue beside it. One entry per record: a second edit of the
    /// same night while the first is waiting folds onto it, because the
    /// person means the night to end up the way it looks now.
    static let editsFile = "plan-edits.json"

    private static var cachedEdits: [Edit]?

    private static var editsURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: editsFile)
    }

    private static var editPhotoDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "plan-edit-photos")
    }

    /// What is waiting, oldest first.
    static func queuedEdits() -> [Edit] {
        if let cachedEdits { return cachedEdits }
        var edits: [Edit] = []
        if let url = editsURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Edit].self, from: data) {
            edits = decoded
        }
        cachedEdits = edits
        return edits
    }

    private static func saveEdits(_ edits: [Edit]) {
        cachedEdits = edits
        guard let url = editsURL, let data = try? JSONEncoder().encode(edits) else { return }
        // Atomic: a kill mid-write must not leave half a queue, which
        // decodes as nothing and silently forgets the change a person made.
        try? data.write(to: url, options: .atomic)
    }

    /// A relaunch, and the tests that stand in for one.
    static func reloadEdits() {
        cachedEdits = nil
    }

    /// Park an edit. Two edits of one night fold: the later fields win, the
    /// earlier `seenAt` is kept (that is the version the person started
    /// from), and a delete stays a delete, because a night taken off and
    /// then edited is a night that is off.
    @discardableResult
    static func enqueue(_ edit: Edit, photo: Data? = nil) -> Int {
        var edits = queuedEdits()
        var entry = edit
        if let i = edits.firstIndex(where: { $0.recordName == edit.recordName }) {
            let waiting = edits[i]
            guard waiting.kind != .delete || edit.kind == .delete else { return waiting.revision }
            entry.revision = waiting.revision + 1
            entry.seenAt = waiting.seenAt
            entry.tries = waiting.tries
            entry.title = edit.title ?? waiting.title
            entry.servings = edit.servings ?? waiting.servings
            entry.tagline = edit.tagline ?? waiting.tagline
            entry.cookID = edit.cookID ?? waiting.cookID
            entry.cookName = edit.cookName ?? waiting.cookName
            entry.cookColorHex = edit.cookColorHex ?? waiting.cookColorHex
            entry.cookSeat = edit.cookSeat ?? waiting.cookSeat
            entry.hasRecipe = edit.hasRecipe ?? waiting.hasRecipe
            entry.recipeMinutes = edit.recipeMinutes ?? waiting.recipeMinutes
            entry.recipeOriginKey = edit.recipeOriginKey ?? waiting.recipeOriginKey
            if entry.photo == .keep { entry.photo = waiting.photo }
            edits[i] = entry
        } else {
            edits.append(entry)
        }
        if let photo, let small = downscale(photo) { writeEditPhoto(entry.recordName, small) }
        if entry.photo == .clear || entry.kind == .delete { removeEditPhoto(entry.recordName) }
        saveEdits(edits)
        return entry.revision
    }

    /// Off the queue, with the bytes it was carrying, but only the version
    /// that was actually sent.
    ///
    /// False when the queued entry has moved on, which means a fold arrived
    /// while this one was on the wire. That fold is a change the person made
    /// and nothing has sent, so removing it here would lose it silently and
    /// hand its author somebody else's `.landed`.
    @discardableResult
    private static func drop(_ recordName: String, ifRevision revision: Int) -> Bool {
        var edits = queuedEdits()
        guard let i = edits.firstIndex(where: { $0.recordName == recordName }) else { return true }
        guard edits[i].revision == revision else { return false }
        edits.remove(at: i)
        removeEditPhoto(recordName)
        saveEdits(edits)
        return true
    }

    /// The key an outcome is filed under: this night AND this version of it.
    nonisolated static func answerKey(_ edit: Edit) -> String {
        "\(edit.recordName)#\(edit.revision)"
    }

    /// An Apple ID change, a leave, and the tests.
    static func forgetEdits() {
        cachedEdits = []
        answers = [:]
        if let url = editsURL { try? FileManager.default.removeItem(at: url) }
        if let dir = editPhotoDirectory { try? FileManager.default.removeItem(at: dir) }
    }

    private static func writeEditPhoto(_ recordName: String, _ data: Data) {
        guard let dir = editPhotoDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "\(recordName).jpg"), options: .atomic)
    }

    static func editPhoto(_ recordName: String) -> Data? {
        guard let url = editPhotoDirectory?.appending(path: "\(recordName).jpg") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func removeEditPhoto(_ recordName: String) {
        guard let url = editPhotoDirectory?.appending(path: "\(recordName).jpg") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: The write

    /// One person's change to one household night, all the way through: the
    /// row moves under the finger, the edit is parked so a kill cannot lose
    /// it, and then it goes to the zone. The answer is what the sheet says.
    ///
    /// The optimistic row is marked as not landed until it has (see
    /// `PlanLedger.applyLocally`), because a queued write is not a landed
    /// write and the interface may never claim otherwise.
    @discardableResult
    static func write(_ edit: Edit, photo: Data? = nil) async -> WriteOutcome {
        print("PLATED HOUSEHOLD: plan edit \(edit.kind.rawValue) on \(edit.recordName) for \(edit.day)")
        if edit.kind == .change,
           queuedEdits().contains(where: { $0.recordName == edit.recordName && $0.kind == .delete }) {
            // The queue folds a change onto a waiting delete by keeping the
            // delete, because a night taken off is off. Applying this one to
            // the row anyway would move it under the finger with nothing on
            // its way to send it. The row stays visible while a delete is
            // going now, so that is reachable, and saying so is the only
            // honest answer.
            print("PLATED HOUSEHOLD: \(edit.recordName) is already on its way off the plan, refusing the change")
            return .refused("This night is on its way off the plan.")
        }
        PlanLedger.shared.applyLocally(edit)
        // The revision the fold produced, which is what this caller is
        // waiting on. Without it the caller looked up an answer by record
        // name and could read the outcome of a version somebody else's tap
        // had folded away.
        var mine = edit
        mine.revision = enqueue(edit, photo: photo)
        // Whatever was last said about this record was said about an older
        // edit; this one has not been answered yet.
        answers[answerKey(mine)] = nil
        let outcome = await exclusively { await deliver(mine) }
        if case .queued = outcome {
            // Nothing else was coming for it. The publisher runs on a scene
            // change or three seconds after a `ModelContext` save, and an
            // edit to somebody else's night is neither, so an edit made
            // offline in the foreground sat there until the person
            // backgrounded the app.
            schedule(reason: "plan edit")
        }
        return outcome
    }

    /// The wire half of `write`, with nothing else writing the zone.
    private static func deliver(_ edit: Edit) async -> WriteOutcome {
        // What is ON THE QUEUE for this night, not what this caller was
        // holding. `enqueue` folds a second change onto a waiting first one,
        // so the queue entry is the union of everything this phone has done
        // to the night and has not sent. Sending the caller's edit instead
        // put only the newest field on the wire and then dropped the whole
        // folded entry on `.landed`, so a title changed while the phone was
        // offline and a cook changed after it came back left the ledger
        // showing both with nothing queued and nothing said, while the
        // household had only the cook. The fold also keeps the earlier
        // `seenAt`, which is the version the person actually started from.
        guard let queued = queuedEdits().first(where: { $0.recordName == edit.recordName }) else {
            // A publisher pass drained this very edit while this call was
            // waiting for the zone. Sending it again would read back the
            // `modifiedAt` this phone itself just wrote and tell the person
            // somebody else got to their night first. What the drain answered
            // is what happened, so that is what is reported. The fallback is
            // the other way an edit leaves the queue unanswered: `forgetEdits`
            // on an identity change or a re-home took it.
            let answered = answers.removeValue(forKey: answerKey(edit))
                ?? .refused("This change could not be sent.")
            print("PLATED HOUSEHOLD: \(edit.recordName) was already answered by a publish pass")
            return answered
        }
        guard await TableSync.accountAvailable() else {
            print("PLATED HOUSEHOLD: no iCloud account, the change is kept on this phone")
            return .queued("It goes to your household when this phone is back on iCloud.")
        }
        guard let (db, zoneID, owner) = await TableShare.householdZone() else {
            print("PLATED HOUSEHOLD: the household zone could not be reached, the change is kept on this phone")
            return .queued("Your household could not be reached. It goes out on the next try.")
        }
        guard owner == queued.zoneOwner else {
            // The household moved between the tap and the write. The night
            // belongs to a zone this phone no longer publishes into, so the
            // edit cannot land and saying so is the only honest answer.
            print("PLATED HOUSEHOLD: the household changed under the edit, dropping it")
            return settle(queued, .refused("This night is at a household this phone has left."))
        }
        return settle(queued, await send(queued, in: db, zone: zoneID))
    }

    /// One edit on the wire. The fetch-compare-save the household contract
    /// calls "versions, not clocks": the record is read first, and a server
    /// copy this edit did not descend from wins outright.
    private static func send(_ edit: Edit, in db: CKDatabase, zone: CKRecordZone.ID) async -> WriteOutcome {
        if edit.kind == .delete {
            let gone = await TableShare.deletePlans(names: [edit.recordName], in: db, zone: zone)
            // `.unknownItem` counts as gone inside `deletePlans`: a night
            // that is not in the zone is a night that is off the plan.
            guard gone.contains(edit.recordName) else {
                print("PLATED HOUSEHOLD: \(edit.recordName) would not delete, keeping it queued")
                return .queued("Your household could not be reached. It goes out on the next try.")
            }
            print("PLATED HOUSEHOLD: \(edit.recordName) is off the plan")
            return .landed(edit.at)
        }
        // Three answers, not two. A zone that would not answer is NOT a
        // night the zone does not hold: taking one for the other mints a
        // fresh record over a real one, and a fresh record reports every
        // primed default as a changed key, so the save's own
        // `.serverRecordChanged` retry writes "" over the title and 4 over
        // the servings of the night being edited, and answers `.landed`.
        let existing: CKRecord?
        switch await TableShare.fetchPlan(named: edit.recordName, in: db, zone: zone) {
        case .found(let record): existing = record
        case .absent:
            if wasTakenOffElsewhere(edit) {
                // A ledger entry exists only because the record was
                // delivered, so a record that is not there now was taken off
                // by somebody between then and this edit. Minting it back
                // would stand a permanent ghost on every phone but one: the
                // mint carries the night's ORIGINAL author, and that author's
                // publish book no longer holds the name, so nothing on their
                // phone will ever republish or re-delete it. A deletion is
                // the other person's version and it wins the way a newer
                // `modifiedAt` does.
                PlanLedger.shared.nightIsGone(edit.recordName)
                print("PLATED HOUSEHOLD: \(edit.recordName) was taken off the plan on another phone, dropping the edit")
                return .refused("That night was taken off the plan on another phone.")
            }
            existing = nil
        case .unreachable:
            print("PLATED HOUSEHOLD: \(edit.recordName) could not be read, keeping the change queued")
            return .queued("This night could not be read just now. It goes out on the next try.")
        }
        if let existing, movedOn(existing["modifiedAt"] as? Date, since: edit.seenAt) {
            var theirs = TableShare.remotePlan(from: existing)
            // `remotePlan` reads a record, not a zone: the pull stamps the
            // owner on its way past, and here the caller knows it.
            theirs.zoneOwner = edit.zoneOwner
            PlanLedger.shared.fold(theirs)
            print("PLATED HOUSEHOLD: \(edit.recordName) changed on another phone first, taking that version")
            return .theirs
        }
        let now = Date.now
        let (record, temp) = record(for: edit, existing: existing, zone: zone, now: now)
        let saved = await TableShare.savePlans([record], in: db)
        if let temp { try? FileManager.default.removeItem(at: temp) }
        guard saved.contains(edit.recordName) else {
            print("PLATED HOUSEHOLD: \(edit.recordName) would not save, keeping it queued")
            return .queued("Your household did not take the change. It goes out on the next try.")
        }
        print("PLATED HOUSEHOLD: \(edit.recordName) saved into \(edit.zoneOwner.isEmpty ? "the own household" : edit.zoneOwner)")
        return .landed(now)
    }

    /// What the last write said about one record, for a caller whose edit was
    /// answered by the publisher's drain while it waited for the zone. Read
    /// once and removed; a record with nothing waiting keeps at most one
    /// entry, so this is as big as the nights edited since launch.
    private static var answers: [String: WriteOutcome] = [:]

    /// What the queue and the ledger do with an answer, and the answer the
    /// person is actually owed. Internal so the twenty-refusal drop can be
    /// tested without CloudKit.
    ///
    /// It returns rather than swallowing, because the drop after twenty
    /// refusals turns a queued write into a refused one: the caller was
    /// telling the person it would go out later while the row snapped back
    /// in front of them. One answer, and it is this one.
    @discardableResult
    static func settle(_ edit: Edit, _ outcome: WriteOutcome) -> WriteOutcome {
        var answer = outcome
        switch outcome {
        case .landed, .theirs, .refused:
            // Only the version that went out leaves the queue. A fold that
            // arrived while this one was on the wire is a change the person
            // made and this phone has not sent, so it stays queued and the
            // ledger keeps saying so: clearing `pendingSince` here would put
            // the new dish on the row with nothing on its way to send it.
            if drop(edit.recordName, ifRevision: edit.revision) {
                PlanLedger.shared.settle(edit, outcome)
            } else {
                print("PLATED HOUSEHOLD: \(edit.recordName) changed while it was on the wire, the newer version stays queued")
                answer = .queued("Your change goes out on the next try.")
            }
        case .queued:
            var edits = queuedEdits()
            if let i = edits.firstIndex(where: { $0.recordName == edit.recordName }) {
                edits[i].tries += 1
                // Twenty refusals is not a network blip. Dropping it is
                // honest; the row stops claiming it is on its way, and the
                // zone's next delivery says what the night really is.
                if edits[i].tries > 20 {
                    print("PLATED HOUSEHOLD: dropping the edit on \(edit.recordName) after \(edits[i].tries) refusals")
                    edits.remove(at: i)
                    let refusal = WriteOutcome.refused("This change could not reach your household.")
                    PlanLedger.shared.settle(edit, refusal)
                    answer = refusal
                }
                saveEdits(edits)
            }
        }
        answers[answerKey(edit)] = answer
        return answer
    }

    /// True when this edit was made against a record that is now absent, so
    /// the absence is somebody else's delete rather than a night that never
    /// had a record. `seenAt` is the ledger entry's `changedAt`, and a ledger
    /// entry exists only because the record was once delivered.
    nonisolated static func wasTakenOffElsewhere(_ edit: Edit) -> Bool {
        edit.seenAt != nil
    }

    /// True when the zone's copy is not the one this edit was made against.
    ///
    /// Whole seconds: a `Date` goes to CloudKit and comes back through a
    /// double, and a comparison at full precision would call every record
    /// moved and refuse every edit.
    nonisolated static func movedOn(_ served: Date?, since seen: Date?) -> Bool {
        guard let seen else {
            // The edit expected no record at all. One being there is
            // somebody else's night under the same name.
            return served != nil
        }
        guard let served else { return false }
        return abs(served.timeIntervalSince(seen)) >= 1
    }

    /// The record this edit saves: the fetched instance with the changed
    /// fields on it, or a new one when the zone has none.
    ///
    /// The mint is for a night with no record at all. An edit to a night the
    /// ledger holds never reaches it with `existing` nil: `send` reads that
    /// absence as somebody else's delete and refuses (`wasTakenOffElsewhere`),
    /// because re-minting one stands a ghost on every phone but the author's.
    ///
    /// The mint carries the night's ORIGINAL author, never the editor. A
    /// record authored by the editor is dropped by that editor's own ledger
    /// (`absorb` keeps nothing this phone wrote, because its own nights are
    /// `PlannedMeal` rows), and there is no `PlannedMeal` behind a night
    /// somebody else planned, so the night would vanish from the one phone
    /// that just changed it while standing on every other.
    static func record(
        for edit: Edit, existing: CKRecord?, zone: CKRecordZone.ID, now: Date
    ) -> (record: CKRecord, temp: URL?) {
        let record: CKRecord
        if let existing {
            record = existing
        } else {
            record = CKRecord(
                recordType: TableShare.planType,
                recordID: CKRecord.ID(recordName: edit.recordName, zoneID: zone)
            )
            // Every field primed non-nil, the way the publisher primes one:
            // a key first minted from nothing is minted at the wrong type,
            // permanently.
            record["authorID"] = edit.authorID as CKRecordValue
            record["authorName"] = edit.authorName as CKRecordValue
            record["authorColorHex"] = edit.authorColorHex as CKRecordValue
            record["cookID"] = "" as CKRecordValue
            record["cookName"] = "" as CKRecordValue
            record["cookColorHex"] = "" as CKRecordValue
            record["cookSeat"] = "" as CKRecordValue
            record["day"] = edit.day as CKRecordValue
            record["slot"] = edit.slot as CKRecordValue
            record["title"] = "" as CKRecordValue
            record["servings"] = 4 as CKRecordValue
            record["tagline"] = "" as CKRecordValue
            record["cooked"] = 0 as CKRecordValue
            record["hasRecipe"] = 0 as CKRecordValue
            record["recipeMinutes"] = 0 as CKRecordValue
            record["recipeOriginKey"] = "" as CKRecordValue
            record["shoppingID"] = shoppingID(of: edit.recordName) as CKRecordValue
            record["createdAt"] = edit.createdAt as CKRecordValue
            record["lines"] = "[]" as CKRecordValue
            // Both links, exactly as the publisher writes them: the
            // reference is the cascade, the parent is what puts the record
            // under the household share so a member can see it at all.
            let rootID = CKRecord.ID(recordName: TableShare.householdRootName, zoneID: zone)
            record["parent"] = CKRecord.Reference(recordID: rootID, action: .deleteSelf)
            record.setParent(rootID)
        }
        if let title = edit.title { record["title"] = title as CKRecordValue }
        if let servings = edit.servings {
            // Read before the overwrite: `record` IS `existing` here.
            let was = record["servings"] as? Int
            record["servings"] = servings as CKRecordValue
            // The record's ingredients are scaled to the servings they were
            // published at, and this phone does not have the recipe behind
            // somebody else's night, so it rescales what the record carries
            // rather than recomputing from a recipe it cannot see. Scaling
            // is linear, so this is the arithmetic `scaledIngredients` does.
            // Without it, doubling a night's servings left the household
            // shopping for the old quantities, which is the list quietly
            // lying about a change the person watched land.
            if let was, was > 0, servings != was {
                let factor = Double(servings) / Double(was)
                let raw = record["lines"] as? String
                let decoded = TableShare.decodeLines(raw)
                if decoded.isEmpty {
                    // No ingredients is nothing to rescale. A `lines` field
                    // that would not DECODE is a different thing, and
                    // leaving it stands the old servings' quantities under
                    // the new servings: a grocery list that is confidently
                    // wrong, which is worse than one that is short. Clearing
                    // costs the household those lines and says so by their
                    // absence.
                    if let raw, raw != "[]" {
                        print("PLATED HOUSEHOLD: \(edit.recordName) had ingredients that would not decode, clearing them rather than rescaling")
                        record["lines"] = "[]" as CKRecordValue
                    }
                } else {
                    let scaled = decoded.map { line -> Line in
                        var l = line
                        l.quantity *= factor
                        return l
                    }
                    record["lines"] = (TableShare.encodeLines(scaled) ?? "[]") as CKRecordValue
                }
            }
        }
        if let tagline = edit.tagline { record["tagline"] = tagline as CKRecordValue }
        if let cookID = edit.cookID { record["cookID"] = cookID as CKRecordValue }
        if let cookName = edit.cookName { record["cookName"] = cookName as CKRecordValue }
        if let hex = edit.cookColorHex { record["cookColorHex"] = hex as CKRecordValue }
        if let seat = edit.cookSeat { record["cookSeat"] = seat as CKRecordValue }
        if let hasRecipe = edit.hasRecipe { record["hasRecipe"] = (hasRecipe ? 1 : 0) as CKRecordValue }
        if let minutes = edit.recipeMinutes { record["recipeMinutes"] = minutes as CKRecordValue }
        if let key = edit.recipeOriginKey { record["recipeOriginKey"] = key as CKRecordValue }
        // Unconditional, like `modifiedAt` and unlike every line above it:
        // these two are not fields the person touched, they are who touched
        // them. A reader takes the sentence about a CHANGE from here, so a
        // save that left the previous editor standing would keep telling a
        // household that the last person to edit the night did this one too.
        record["editorID"] = (edit.editorID ?? "") as CKRecordValue
        record["editorName"] = (edit.editorName ?? "") as CKRecordValue
        record["modifiedAt"] = now as CKRecordValue
        var temp: URL?
        switch edit.photo {
        case .keep:
            break
        case .clear:
            record["photo"] = nil
        case .send:
            if let data = editPhoto(edit.recordName), let asset = TableShare.asset(from: data) {
                record["photo"] = asset
                temp = asset.fileURL
            } else {
                // The bytes are gone: a picture that cannot be sent must not
                // leave the old dish's photograph under the new dish's name.
                record["photo"] = nil
            }
        }
        return (record, temp)
    }

    /// `plan-<shoppingID>` is the one name a night has, so the id comes back
    /// out of it rather than being minted twice.
    nonisolated static func shoppingID(of recordName: String) -> String {
        recordName.hasPrefix("plan-") ? String(recordName.dropFirst("plan-".count)) : recordName
    }

    /// Everything waiting, aimed at the household this pass resolved.
    ///
    /// Edits go before the publisher's own diff: somebody is looking at a
    /// change they made on their screen, and the diff can have the rest of
    /// the pass.
    private static func drainEdits(in db: CKDatabase, zone: CKRecordZone.ID, target: String) async {
        // A row that says it has not landed with nothing queued behind it is
        // a row claiming something that is not going to happen: a kill
        // between the ledger write and the queue write leaves exactly that.
        PlanLedger.shared.clearPending(except: Set(queuedEdits().map(\.recordName)))
        for stray in queuedEdits() where stray.zoneOwner != target {
            print("PLATED HOUSEHOLD: dropping an edit for \(stray.zoneOwner.isEmpty ? "the own household" : stray.zoneOwner), which is not this phone's household now")
            settle(stray, .refused("This night is at a household this phone has left."))
        }
        let waiting = queuedEdits()
        guard !waiting.isEmpty else { return }
        print("PLATED HOUSEHOLD: draining \(waiting.count) plan edit(s)")
        for edit in waiting {
            // Re-read immediately before the send, the way `deliver` does.
            // The loop's own awaits are main-actor suspensions, so a tap can
            // fold onto any entry in this snapshot while an earlier one is
            // on the wire, and sending the stale copy would put only the old
            // fields up and then settle against a version that no longer
            // exists. Gone from the queue means an earlier iteration or a
            // `deliver` already answered it.
            guard let current = queuedEdits().first(where: { $0.recordName == edit.recordName })
            else { continue }
            let outcome = await send(current, in: db, zone: zone)
            settle(current, outcome)
        }
    }

    /// 600px on the long side at JPEG 0.7, the widget's treatment. Called
    /// only when the photo component changed: a pass never decodes a
    /// photo it has already sent.
    static func downscale(_ data: Data, maxSide: CGFloat = 600) -> Data? {
        guard let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.7)
    }
}
