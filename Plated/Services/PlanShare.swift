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

        var photoCount: Int { photoData?.count ?? 0 }
        var fingerprint: String {
            PlanShare.fingerprint(
                day: day, slot: slot, title: title, servings: servings,
                cookID: cookID, cookName: cookName, cookSeat: cookSeat, tagline: tagline,
                cooked: cooked, cookedAt: cookedAt, hasRecipe: hasRecipe,
                recipeMinutes: recipeMinutes, recipeOriginKey: recipeOriginKey
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
        recipeMinutes: Int, recipeOriginKey: String
    ) -> String {
        let cookedStamp = cookedAt.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        let parts = [
            day, slot, title, String(servings), cookID, cookName, cookSeat, tagline,
            cooked ? "1" : "0", cookedStamp, hasRecipe ? "1" : "0",
            String(recipeMinutes), recipeOriginKey
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
            createdAt: meal.createdAt, photoData: recipe?.photoData
        )
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
        print("[PlanShare] book forgotten")
    }

    // MARK: Publishing

    private static var pendingSave: Task<Void, Never>?
    private static var inFlight: Task<Void, Never>?
    private static var again = false

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
                await pass(reason: reason)
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

        let known = work.save.filter(\.known).map(\.plan.recordName)
        let existing = await TableShare.fetchPlanRecords(named: known, in: db, zone: zoneID)
        var records: [CKRecord] = []
        var temps: [URL] = []
        for upload in work.save {
            let photo: TableShare.PlanPhoto
            if !upload.sendPhoto {
                photo = .keep
            } else if let data = upload.plan.photoData, let small = downscale(data) {
                photo = .set(small)
            } else {
                photo = .clear
            }
            let (record, temp) = TableShare.planRecord(
                upload.plan, existing: existing[upload.plan.recordName],
                zone: zoneID, photo: photo, now: now
            )
            records.append(record)
            if let temp { temps.append(temp) }
        }
        let saved = await TableShare.savePlans(records, in: db)
        for temp in temps { try? FileManager.default.removeItem(at: temp) }
        for upload in work.save where saved.contains(upload.plan.recordName) {
            book[upload.plan.recordName] = BookEntry(
                fingerprint: upload.plan.fingerprint, photoCount: upload.plan.photoCount,
                zoneOwner: target, day: upload.plan.day, slot: upload.plan.slot
            )
        }
        let removals = work.delete + work.ageOut
        let gone = await TableShare.deletePlans(names: removals, in: db, zone: zoneID)
        for name in gone { book[name] = nil }
        saveBook(book)
        print("[PlanShare] \(reason): saved \(saved.count)/\(work.save.count), deleted \(gone.count)/\(removals.count) in \(target.isEmpty ? "the own table" : target)")
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
