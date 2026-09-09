import CloudKit
import CoreData
import CryptoKit
import Foundation
import SwiftData

/// The glue between the store and the household zone (docs/household.md
/// section 12): the save observer that turns edits into outbox entries, the
/// single minter, the duplicate collapse, and the two transitions a phone
/// makes between households (join, leave) plus the one made for it
/// (removed). `HouseholdShare` is the wire and knows nothing about when;
/// this file is the when.
///
/// Two members here predate the rest and every other piece leans on them:
/// `suppressed`, which keeps a merge's own saves out of the outbox, and
/// `fingerprint(of:)`, which decides whether a save is worth pushing. Their
/// shape is fixed.
@MainActor
enum HouseholdSync {
    /// True while a merge, a fixture or the post-push bookkeeping is writing
    /// rows that already match the wire, so the save observer parks nothing.
    /// Held only across synchronous work: an `await` under it would leak
    /// the suppression into somebody else's save.
    static var suppressed = false

    /// A stable SHA256 of a synced row's wire fields, and nothing else.
    ///
    /// The observer enqueues a push only when this differs from the stored
    /// `shareFingerprint`, which is what stops the merge's own save and the
    /// bookkeeping after a push from enqueueing themselves forever. So the
    /// bookkeeping fields (`shareRecordName`, `shareModifiedAt`,
    /// `shareFingerprint`), the per-person fields (`isFavorite`, `isPinned`),
    /// the per-device handles (`reminderID`, `calendarEventID`) and the
    /// host-only addresses (`phoneE164`, `inviteEmail`) never enter. Photo
    /// bytes enter as their own SHA256 so a hundred kilobytes of JPEG is
    /// hashed once, not copied into a string.
    ///
    /// Nil for a row that does not travel: a `PlannedMeal` (a night is not
    /// a household record at all, see `HouseholdOutbox.Kind`), an auto
    /// grocery line (rebuilt on every phone from the plan), or a type that
    /// is not synced.
    static func fingerprint(of model: any PersistentModel) -> String? {
        var fields: [(String, String)]
        switch model {
        case let member as HouseholdMember:
            fields = [
                ("authorID", member.authorID),
                ("name", member.name),
                ("role", member.role),
                ("roleLine", member.roleLine),
                ("colorHex", member.colorHex),
                ("dietaryNotes", member.dietaryNotes),
                ("avoidedIngredients", list(member.avoidedIngredients)),
                ("cookWeekdays", list(member.cookWeekdays.map(String.init))),
                ("isPrimaryCook", bool(member.isPrimaryCook)),
                ("seat", member.seatRaw),
                ("invitedAt", date(member.invitedAt)),
                ("joinedAt", date(member.joinedAt)),
                ("leftAt", date(member.leftAt)),
                ("participantID", member.participantID ?? ""),
                ("userRecordName", member.userRecordName ?? ""),
                ("bio", member.bio),
                ("photo", bytes(member.photoData)),
            ]
        case let recipe as Recipe:
            fields = [
                ("authorID", recipe.authorID),
                ("title", recipe.title),
                ("summary", recipe.summary),
                ("instructions", recipe.instructions),
                ("sourceURL", recipe.sourceURL),
                ("sourceName", recipe.sourceName),
                ("sourceText", recipe.sourceText),
                ("importMethod", recipe.importMethod),
                ("importedAt", date(recipe.importedAt)),
                ("servings", String(recipe.servings)),
                ("prepMinutes", String(recipe.prepMinutes)),
                ("cookMinutes", String(recipe.cookMinutes)),
                ("tags", list(recipe.tags)),
                ("category", recipe.category),
                ("difficulty", recipe.difficulty),
                ("mealType", recipe.mealType),
                ("steps", list(recipe.steps)),
                ("visibility", recipe.visibility),
                ("householdCanEdit", bool(recipe.householdCanEdit)),
                ("originID", recipe.originID),
                ("createdAt", date(recipe.createdAt)),
                ("cookNotes", recipe.cookNotes),
                ("weatherMoods", list(recipe.weatherMoods)),
                ("ingredients", list(recipe.sortedIngredients.map {
                    [$0.name, String($0.quantity), $0.unit, $0.aisle,
                     bool($0.isPantryStaple), String($0.sortIndex)].joined(separator: "\u{1F}")
                })),
                ("photo", bytes(recipe.photoData)),
                ("extraPhotos", list(recipe.sortedExtraPhotos.map { bytes($0.photoData) })),
            ]
        case let gathering as Gathering:
            fields = [
                ("authorID", gathering.authorID),
                ("title", gathering.title),
                ("notes", gathering.notes),
                ("startDate", date(gathering.startDate)),
                ("endDate", date(gathering.endDate)),
                ("guestCount", String(gathering.guestCount)),
                ("location", gathering.location),
            ]
        case let line as GroceryItem:
            // Auto lines never travel (docs/household.md section 3.5): the
            // builder rebuilds them from the plan on every phone.
            guard line.isManual, !line.shareRecordName.isEmpty else { return nil }
            fields = [
                ("authorID", line.authorID),
                ("name", line.name),
                ("quantity", String(line.quantity)),
                ("unit", line.unit),
                ("aisle", line.aisle),
                ("day", HouseholdMember.day(line.weekStart)),
                ("originTitle", line.originTitle),
                ("isChecked", bool(line.isChecked)),
            ]
        default:
            return nil
        }
        // Key, unit separator, value, record separator: a value containing a
        // newline or a comma cannot run into the next field.
        let canonical = fields.map { "\($0.0)\u{1F}\($0.1)" }.joined(separator: "\u{1E}")
        return hex(SHA256.hash(data: Data(canonical.utf8)))
    }

    // MARK: Canonical spellings

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func bytes(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "" }
        return hex(SHA256.hash(data: data))
    }

    /// Whole milliseconds: a Date that round-trips through CloudKit keeps
    /// millisecond precision and nothing finer, so anything finer would
    /// make the merged row look changed on its way back.
    private static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        return String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    private static func bool(_ value: Bool) -> String { value ? "1" : "0" }

    private static func list(_ values: [String]) -> String {
        values.joined(separator: "\u{1D}")
    }

    // MARK: Names the shell listens for

    /// Posted before `handleRemoved` tears the household down, so the shell
    /// can dismiss every sheet and pop to the tab roots first: a sheet
    /// editing a recipe that is about to be deleted is a crash waiting.
    static let householdRemoved = Notification.Name("plated.household.removed")

    /// App-group keys only this file writes.
    enum Keys {
        /// The identity that named the pre-field rows (§2, "Names are
        /// minted at birth"). Any other device of the same Apple ID waits
        /// for the mirror.
        static let minter = "plated.household.minter"
        /// The sentence the Plan tab's first empty week shows after a
        /// removal, instead of the ordinary invitation (§8).
        static let removedNotice = "plated.household.removedNotice"
    }

    private static var groupDefaults: UserDefaults { HouseholdShare.groupDefaults }

    private static var isSynced: Bool {
        switch HouseholdShare.membership {
        case .hosting, .member: return true
        case .solo: return false
        }
    }

    // MARK: The save observer (§2, "Enqueueing is content-based")

    /// One row on its way from a save to the outbox. Parked in `willSave`,
    /// committed in `didSave`: the fingerprint is computed before the save
    /// so a row deleted in the same transaction is still readable, and the
    /// entry is written after it so a save that fails enqueues nothing.
    private struct Parked {
        var kind: HouseholdOutbox.Kind
        var name: String
        var fingerprint: String
        /// `shareFingerprint` as the row carried it into the save.
        var stored: String
        var isDelete: Bool
    }

    private static var observed: ModelContext?
    private static var parked: [Parked] = []
    private static var drainTask: Task<Void, Never>?
    private static var collapseTask: Task<Void, Never>?

    /// Install once, on the live store's main context. `PlatedStore.shared`
    /// is a static initialiser and cannot reach the main actor, so the app
    /// calls this from its own init and every App Intent from `perform`,
    /// which are the two doors a save can come through.
    static func ensureObserving() {
        guard observed == nil else { return }
        observe(PlatedStore.shared.mainContext)
    }

    /// Subscribe to one context's saves. Every other context is ignored by
    /// identity: the test target's in-memory context must never feed the
    /// real outbox, and a throwaway context (the schema primer) must not
    /// either.
    static func observe(_ context: ModelContext) {
        guard observed == nil else { return }
        observed = context
        let center = NotificationCenter.default
        // Queue nil: the block runs synchronously on the posting thread,
        // which for the main context is the main thread, inside `save()`.
        // That is the only place `insertedModelsArray` still answers.
        center.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { note in
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated { willSave(note) }
        }
        center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated { didSave(note) }
        }
        // The mirror imported something. A member's second device can now
        // hold one record twice (§2, "The mirror does not dedupe").
        center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { _ in
            Task { @MainActor in scheduleCollapse() }
        }
        print("PLATED HOUSEHOLD: save observer installed")
    }

    private static func isObserved(_ note: Notification) -> Bool {
        guard let observed, let object = note.object as AnyObject? else { return false }
        return object === observed
    }

    /// What kind of record a row is, and its name. Nil for a row that does
    /// not travel. An unnamed row is skipped on purpose: naming it here
    /// would make this device a second minter (§2).
    private static func wire(_ model: any PersistentModel) -> (HouseholdOutbox.Kind, String)? {
        switch model {
        case let m as HouseholdMember: return m.shareRecordName.isEmpty ? nil : (.seat, m.shareRecordName)
        case let r as Recipe: return r.shareRecordName.isEmpty ? nil : (.recipe, r.shareRecordName)
        case let g as Gathering: return g.shareRecordName.isEmpty ? nil : (.gathering, g.shareRecordName)
        case let l as GroceryItem:
            guard l.isManual, !l.shareRecordName.isEmpty else { return nil }
            return (.line, l.shareRecordName)
        default: return nil
        }
    }

    private static func storedFingerprint(_ model: any PersistentModel) -> String {
        switch model {
        case let m as HouseholdMember: return m.shareFingerprint
        case let r as Recipe: return r.shareFingerprint
        case let g as Gathering: return g.shareFingerprint
        case let l as GroceryItem: return l.shareFingerprint
        default: return ""
        }
    }

    /// Stamp the creator on a new row. In `willSave` because a save is in
    /// progress and the stamp rides in it; a placeholder identity is
    /// rewritten by `reattribute` when CloudKit answers who this is.
    ///
    /// A `PlannedMeal` is stamped too, even though a night never goes to
    /// the zone: `Awards.metrics` reads `authorID` to decide whose night an
    /// uncooked, unassigned one is, and that question predates the
    /// household and outlives it.
    private static func stampAuthor(_ model: any PersistentModel, me: String) {
        switch model {
        case let m as HouseholdMember: if m.authorID.isEmpty { m.authorID = me }
        case let m as PlannedMeal: if m.authorID.isEmpty { m.authorID = me }
        case let r as Recipe: if r.authorID.isEmpty { r.authorID = me }
        case let g as Gathering: if g.authorID.isEmpty { g.authorID = me }
        case let l as GroceryItem: if l.isManual, l.authorID.isEmpty { l.authorID = me }
        default: break
        }
    }

    private static func willSave(_ note: Notification) {
        parked = []
        guard isObserved(note), !suppressed, let context = observed else { return }
        let me = TableIdentity.cached
        for model in context.insertedModelsArray {
            stampAuthor(model, me: me)
            guard let (kind, name) = wire(model) else { continue }
            parked.append(Parked(kind: kind, name: name, fingerprint: fingerprint(of: model) ?? "",
                                 stored: storedFingerprint(model), isDelete: false))
        }
        for model in context.changedModelsArray {
            guard let (kind, name) = wire(model) else { continue }
            parked.append(Parked(kind: kind, name: name, fingerprint: fingerprint(of: model) ?? "",
                                 stored: storedFingerprint(model), isDelete: false))
        }
        for model in context.deletedModelsArray {
            guard let (kind, name) = wire(model) else { continue }
            parked.append(Parked(kind: kind, name: name, fingerprint: "", stored: "", isDelete: true))
        }
    }

    private static func didSave(_ note: Notification) {
        let entries = parked
        parked = []
        guard isObserved(note), !suppressed, !entries.isEmpty, isSynced else { return }
        var queued = 0
        for entry in entries {
            if entry.isDelete {
                HouseholdOutbox.shared.enqueueDelete(entry.kind, entry.name)
                queued += 1
            } else if entry.fingerprint != entry.stored {
                HouseholdOutbox.shared.enqueueUpsert(entry.kind, entry.name)
                queued += 1
            }
        }
        guard queued > 0 else { return }
        print("PLATED HOUSEHOLD: save queued \(queued) record(s)")
        kickDrain()
    }

    /// One drain per burst. A person editing a recipe saves on every
    /// keystroke; the debounce turns that into one push a beat after the
    /// last one.
    private static func kickDrain() {
        drainTask?.cancel()
        // A main-actor task, not a detached one: the sleep suspends rather
        // than blocks, and a `ModelContext` may not cross an isolation
        // boundary, which a detached task would make it do on the way in.
        drainTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            drainTask = nil
            guard let context = observed else { return }
            await HouseholdOutbox.shared.drain(context: context)
        }
    }

    private static func scheduleCollapse() {
        guard isSynced else { return }
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let context = observed else { return }
            collapseDuplicates(in: context)
        }
    }

    // MARK: Launch

    /// Enqueue every row whose live fingerprint differs from the one last
    /// exchanged. A kill between the store commit and the outbox write loses
    /// the entry with no other repair (§2).
    static func sweep(in context: ModelContext) {
        guard isSynced else { return }
        var count = 0
        for row in fetchAll(HouseholdMember.self, context) where !row.shareRecordName.isEmpty {
            if fingerprint(of: row) != row.shareFingerprint {
                HouseholdOutbox.shared.enqueueUpsert(.seat, row.shareRecordName); count += 1
            }
        }
        for row in fetchAll(Recipe.self, context) where !row.shareRecordName.isEmpty {
            if fingerprint(of: row) != row.shareFingerprint {
                HouseholdOutbox.shared.enqueueUpsert(.recipe, row.shareRecordName); count += 1
            }
        }
        for row in fetchAll(Gathering.self, context) where !row.shareRecordName.isEmpty {
            if fingerprint(of: row) != row.shareFingerprint {
                HouseholdOutbox.shared.enqueueUpsert(.gathering, row.shareRecordName); count += 1
            }
        }
        for row in fetchAll(GroceryItem.self, context) where row.isManual && !row.shareRecordName.isEmpty {
            if fingerprint(of: row) != row.shareFingerprint {
                HouseholdOutbox.shared.enqueueUpsert(.line, row.shareRecordName); count += 1
            }
        }
        print("PLATED HOUSEHOLD: sweep queued \(count) drifted row(s)")
        if count > 0 { kickDrain() }
    }

    /// The owner row is stamped with this device's identity the first time
    /// CloudKit answers while the household is unshared (§5). Under
    /// suppression unless hosting, because on a host the stamp is a change
    /// the household should see.
    static func stampIdentityIfUnshared(in context: ModelContext, identity: String = TableIdentity.cached) {
        guard !identity.hasPrefix("local-") else { return }
        let membership = HouseholdShare.membership
        guard membership == .solo || membership == .hosting else { return }
        let members = fetchAll(HouseholdMember.self, context)
        guard !members.contains(where: { $0.userRecordName == identity }) else { return }
        guard let head = members.first(where: { $0.seat == .head })
                ?? members.first(where: \.isOwner),
              (head.userRecordName ?? "").isEmpty else { return }
        let hold = membership == .solo
        if hold { suppressed = true }
        defer { if hold { suppressed = false } }
        head.userRecordName = identity
        Persist.save(context, "identity stamp")
        print("PLATED HOUSEHOLD: stamped the head row with this identity")
    }

    // MARK: The single minter (§2)

    /// Name every row that predates `shareRecordName`. Only ever called
    /// from the two transitions (`publishAll`, `join`), on the one device
    /// that makes them; it records itself as the minter. The save observer skips
    /// unnamed rows, so no other device of this Apple ID can name them
    /// first: it waits for the mirror to bring the names.
    static func ensureRecordNames(in context: ModelContext) {
        suppressed = true
        defer { suppressed = false }
        var named = 0
        for row in fetchAll(HouseholdMember.self, context) where row.shareRecordName.isEmpty {
            row.shareRecordName = HouseholdShare.mintSeatName(); named += 1
        }
        for row in fetchAll(Recipe.self, context) where row.shareRecordName.isEmpty {
            row.shareRecordName = "recipe-\(UUID().uuidString)"; named += 1
        }
        for row in fetchAll(Gathering.self, context) where row.shareRecordName.isEmpty {
            row.shareRecordName = "gathering-\(UUID().uuidString)"; named += 1
        }
        for row in fetchAll(GroceryItem.self, context) where row.isManual && row.shareRecordName.isEmpty {
            row.shareRecordName = "line-\(UUID().uuidString)"; named += 1
        }
        groupDefaults.set(TableIdentity.cached, forKey: Keys.minter)
        Persist.save(context, "record names")
        print("PLATED HOUSEHOLD: minted \(named) record name(s)")
    }

    /// The host's first invitation: everything the household owns goes to
    /// the zone (§6).
    static func publishAll(in context: ModelContext) {
        ensureRecordNames(in: context)
        let me = TableIdentity.cached
        let outbox = HouseholdOutbox.shared
        var count = 0
        suppressed = true
        for row in fetchAll(HouseholdMember.self, context) {
            if row.authorID.isEmpty { row.authorID = me }
            outbox.enqueueUpsert(.seat, row.shareRecordName); count += 1
        }
        for row in fetchAll(Recipe.self, context) {
            if row.authorID.isEmpty { row.authorID = me }
            outbox.enqueueUpsert(.recipe, row.shareRecordName); count += 1
        }
        for row in fetchAll(Gathering.self, context) {
            if row.authorID.isEmpty { row.authorID = me }
            outbox.enqueueUpsert(.gathering, row.shareRecordName); count += 1
        }
        for row in fetchAll(GroceryItem.self, context) where row.isManual {
            if row.authorID.isEmpty { row.authorID = me }
            outbox.enqueueUpsert(.line, row.shareRecordName); count += 1
        }
        for mark in GroceryMarks.shared.all {
            outbox.enqueueUpsert(.mark, GroceryMarks.recordName(for: mark.lineKey), at: mark.at); count += 1
        }
        outbox.enqueueRoot()
        // Home's "Sharing with your household, 40 of 360" needs the size of
        // this first publish, and the outbox only knows what is left. The
        // queue's own count, not `count`: an upsert already queued is not
        // queued twice, so the queue is the true denominator.
        HouseholdShare.groupDefaults.set(outbox.pending.count, forKey: HouseholdOutbox.publishTotalKey)
        Persist.save(context, "publish all")
        suppressed = false
        if HouseholdShare.membership != .hosting { HouseholdShare.setMembership(.hosting) }
        print("PLATED HOUSEHOLD: publishAll queued \(count) record(s) and the root")
        kickDrain()
    }

    // MARK: Duplicates (§2, "The mirror does not dedupe")

    /// Rows sharing one `shareRecordName` collapse onto the oldest by
    /// `createdAt`; relationships are rehomed onto the survivor and the
    /// rest are deleted. A `Gathering` has no `createdAt`, so the survivor
    /// there is the row that already holds meals, else the first found.
    ///
    /// No pass over `PlannedMeal`, and there must never be one again. A
    /// night is not a household record, so two rows can no longer describe
    /// it; a collapse here was the repair for a shape (one fact, two
    /// writers) that has been taken out instead.
    ///
    /// Cook sessions are keyed on `persistentModelID` and `CookLedger`
    /// exposes no re-key, so a session on a deleted twin is lost; the
    /// twelve-hour session life bounds that to one evening.
    static func collapseDuplicates(in context: ModelContext) {
        suppressed = true
        defer { suppressed = false }
        var removed = 0

        let members = fetchAll(HouseholdMember.self, context)
        for group in groups(members, by: \.shareRecordName) {
            let survivor = group.min { $0.createdAt < $1.createdAt }!
            for twin in group where twin !== survivor {
                for meal in twin.assignedMeals ?? [] { meal.cook = survivor }
                if (survivor.userRecordName ?? "").isEmpty { survivor.userRecordName = twin.userRecordName }
                if survivor.photoData == nil { survivor.photoData = twin.photoData }
                context.delete(twin); removed += 1
            }
        }

        let recipes = fetchAll(Recipe.self, context)
        for group in groups(recipes, by: \.shareRecordName) {
            let survivor = group.min { $0.createdAt < $1.createdAt }!
            for twin in group where twin !== survivor {
                for meal in twin.plannedMeals ?? [] { meal.recipe = survivor }
                // Both copies carry their own ingredient and photo rows; the
                // twin's move over only when the survivor has none, or the
                // list would double.
                if (survivor.ingredients ?? []).isEmpty {
                    for ingredient in twin.ingredients ?? [] { ingredient.recipe = survivor }
                }
                if (survivor.extraPhotos ?? []).isEmpty {
                    for photo in twin.extraPhotos ?? [] { photo.recipe = survivor }
                }
                if survivor.photoData == nil { survivor.photoData = twin.photoData }
                CookLedger.shared.forget(twin)
                context.delete(twin); removed += 1
            }
        }

        let gatherings = fetchAll(Gathering.self, context)
        for group in groups(gatherings, by: \.shareRecordName) {
            let survivor = group.first { !($0.plannedMeals ?? []).isEmpty } ?? group[0]
            for twin in group where twin !== survivor {
                for meal in twin.plannedMeals ?? [] { meal.gathering = survivor }
                context.delete(twin); removed += 1
            }
        }

        let lines = fetchAll(GroceryItem.self, context).filter(\.isManual)
        for group in groups(lines, by: \.shareRecordName) {
            let survivor = group.min { $0.createdAt < $1.createdAt }!
            for twin in group where twin !== survivor {
                context.delete(twin); removed += 1
            }
        }

        guard removed > 0 else { return }
        Persist.save(context, "collapse duplicates")
        print("PLATED HOUSEHOLD: collapsed \(removed) duplicate row(s)")
    }

    private static func groups<T: AnyObject>(_ rows: [T], by key: KeyPath<T, String>) -> [[T]] {
        var byName: [String: [T]] = [:]
        for row in rows {
            let name = row[keyPath: key]
            guard !name.isEmpty else { continue }
            byName[name, default: []].append(row)
        }
        return byName.values.filter { $0.count > 1 }
    }

    // MARK: Identity (§5)

    /// A placeholder identity became a real one. Every row it signed is the
    /// same person's; the outbox held them back, and the next drain sends
    /// them under the real name. Not suppressed on purpose: the changed
    /// `authorID` is a change the household should receive.
    static func reattribute(from old: String, to new: String, in context: ModelContext) {
        guard old != new, !old.isEmpty, !new.isEmpty else { return }
        var count = 0
        for row in fetchAll(HouseholdMember.self, context) {
            if row.authorID == old { row.authorID = new; count += 1 }
            if row.userRecordName == old { row.userRecordName = new; count += 1 }
        }
        for row in fetchAll(PlannedMeal.self, context) where row.authorID == old { row.authorID = new; count += 1 }
        for row in fetchAll(Recipe.self, context) where row.authorID == old { row.authorID = new; count += 1 }
        for row in fetchAll(Gathering.self, context) where row.authorID == old { row.authorID = new; count += 1 }
        for row in fetchAll(GroceryItem.self, context) where row.authorID == old { row.authorID = new; count += 1 }
        GroceryMarks.shared.reattribute(from: old, to: new)
        if count > 0 { Persist.save(context, "reattribute") }
        print("PLATED HOUSEHOLD: reattributed \(count) field(s) from \(old.prefix(12)) to \(new.prefix(12))")
    }

    // MARK: The join sheet (§7)

    struct JoinPreview: Equatable {
        var hostName: String
        var hostPhoto: Data?
        var householdName: String
        var state: State
        var mealsFromToday: Int
        var hasGroceryState: Bool
        var broughtSeats: [String]
        var publishedAt: Date?

        enum State: Equatable {
            case ready
            case alreadyHere
            /// Already in this household, but no seat was ever claimed: the
            /// join was killed at the seat question. The share is accepted
            /// and the zone merged, so the link reopens straight into the
            /// picker rather than being refused as "already here" for ever.
            case needsSeat(candidates: [SeatCandidate])
            case ownShare
            case hostingWithJoined(names: [String])
            case willLeave(current: String)
            case removed
        }
    }

    /// The host's name for a sentence: the share's owner identity first,
    /// the root second, never the link. `linkHost` is accepted so the
    /// shell can pass what it parsed, and is deliberately not read: a link
    /// can say anything.
    static func hostName(metadata: CKShare.Metadata, root: HouseholdShare.RemoteRoot?, linkHost: String) -> String {
        let parts = metadata.ownerIdentity.nameComponents
        let fromIdentity = [parts?.givenName, parts?.familyName].compactMap { $0 }
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !fromIdentity.isEmpty { return fromIdentity }
        return (root?.hostName ?? "").trimmingCharacters(in: .whitespaces)
    }

    static func preview(
        for metadata: CKShare.Metadata, root: HouseholdShare.RemoteRoot?,
        linkHost: String, context: ModelContext
    ) -> JoinPreview {
        let host = hostName(metadata: metadata, root: root, linkHost: linkHost)
        let zoneOwner = metadata.hierarchicalRootRecordID?.zoneID.ownerName
            ?? metadata.share.recordID.zoneID.ownerName
        let me = TableIdentity.cached
        let membership = HouseholdShare.membership
        let members = fetchAll(HouseholdMember.self, context)

        let state: JoinPreview.State
        if !zoneOwner.isEmpty, zoneOwner == me {
            state = .ownShare
        } else if case .member(let owner) = membership, owner == zoneOwner {
            state = HouseholdShare.mySeat == nil ? .needsSeat(candidates: openSeats(in: members)) : .alreadyHere
        } else if let root, root.removedIDs.contains(me) {
            state = .removed
        } else if membership == .hosting,
                  members.contains(where: { $0.seat == .joined && !$0.isMe }) {
            let names = members.filter { $0.seat == .joined && !$0.isMe }
                .sorted { $0.shareRecordName < $1.shareRecordName }.map(\.firstName)
            state = .hostingWithJoined(names: names)
        } else if membership == .hosting || membership.owner != nil {
            state = .willLeave(current: currentHouseholdName(members: members))
        } else {
            state = .ready
        }

        let today = Calendar.current.startOfDay(for: .now)
        let meals = fetchAll(PlannedMeal.self, context).filter { $0.date >= today }.count
        let lines = fetchAll(GroceryItem.self, context).contains(where: \.isManual)
        let brought = members.filter { $0.seat == .notOnPlated }
            .sorted { $0.createdAt < $1.createdAt }.map(\.name)

        return JoinPreview(
            hostName: host, hostPhoto: root?.hostPhoto, householdName: root?.name ?? "",
            state: state, mealsFromToday: meals,
            hasGroceryState: lines || !GroceryMarks.shared.isEmpty,
            broughtSeats: brought, publishedAt: root?.publishedAt
        )
    }

    /// The seats on the roster nobody has claimed, for the seat question.
    ///
    /// A `.joined` row with nobody's identity on it is one an
    /// already-shipped `reconcile` promoted off a matching Table
    /// participant (§8, migration). It is claimable: refusing it forces a
    /// second seat beside the one the host is looking at.
    static func openSeats(in members: [HouseholdMember]) -> [SeatCandidate] {
        members
            .filter { $0.seat != .head && $0.seat != .left && ($0.userRecordName ?? "").isEmpty }
            .sorted { $0.shareRecordName < $1.shareRecordName }
            .map { SeatCandidate(id: $0.shareRecordName, name: $0.name, role: $0.role) }
    }

    /// What the household this phone is in is called, for "You'll leave the
    /// Meadows household first": the shared name, else the typed one, else
    /// the host's own name.
    private static func currentHouseholdName(members: [HouseholdMember]) -> String {
        let shared = HouseholdShare.cachedName.trimmingCharacters(in: .whitespaces)
        if !shared.isEmpty { return shared }
        let typed = (UserDefaults.standard.string(forKey: "householdName") ?? "")
            .trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        if case .member = HouseholdShare.membership {
            return HouseholdShare.cachedOwnerName
        }
        return members.first(where: { $0.seat == .head })?.name ?? members.me?.name ?? ""
    }

    // MARK: Join (§7)

    struct SeatCandidate: Identifiable, Equatable {
        /// The seat's `shareRecordName`.
        var id: String
        var name: String
        var role: String
    }

    enum JoinOutcome: Equatable {
        case joined
        case needsSeat(candidates: [SeatCandidate])
        case refused(String)
        case failed(String)
    }

    /// True between the first accept and the end of `join` (or of the
    /// `claimSeat` that finishes it), so the shell can hold its sheet.
    static var isJoining = false

    /// What `claimSeat` needs to finish a join that stopped to ask which
    /// seat is the joiner's.
    private static var pendingJoinHost = ""

    static func join(
        _ metadata: CKShare.Metadata, root: HouseholdShare.RemoteRoot?, seat: String?,
        context: ModelContext
    ) async -> JoinOutcome {
        isJoining = true
        let host = hostName(metadata: metadata, root: root, linkHost: "")
        let zoneOwner = metadata.hierarchicalRootRecordID?.zoneID.ownerName
            ?? metadata.share.recordID.zoneID.ownerName
        let me = TableIdentity.cached

        // A removed identity is refused at join (§1 and §8), and the root is
        // the only place `removedIDs` is written. The sheet's own check runs
        // only when the metadata happened to arrive with a root, and the
        // root fetch is best effort on every road, so it is asked for once
        // more here rather than letting a removed person walk back in on the
        // old link.
        var root = root
        if root == nil, let url = metadata.share.url,
           let again = try? await ShareAcceptor.metadataWithRoot(for: url) {
            root = again.rootRecord.map(HouseholdShare.remoteRoot(from:))
        }
        if let root, root.removedIDs.contains(me) {
            isJoining = false
            print("PLATED HOUSEHOLD: join refused, this identity is on the removed list")
            return .refused(removedSentence(host: host))
        }

        // 1. The household share. The Table follows and is retried on every
        // pull, so only this accept decides the outcome. Already-a-participant
        // is a seat (same rule as TableShare.accept): a second open of the
        // link must not fail a join that already landed.
        print("PLATED HOUSEHOLD: joining \(host.isEmpty ? "a household" : host + "'s household") as \(me.prefix(12))")
        let accepted = await HouseholdShare.accept(metadata)
        guard accepted.seated else {
            isJoining = false
            let reason = accepted.line
                ?? await acceptFailure(metadata: metadata, host: host)
            print("PLATED HOUSEHOLD: join refused: \(reason)")
            return .failed(reason)
        }
        // Giving up the old household gates the new one. A leave whose zone
        // delete failed, or a host whose own zone is still there, leaves two
        // households arriving at once: `fetchChanges` reads every household
        // zone it can see, and everything this join is about to delete comes
        // back on the next pull under the wrong owner.
        if let previous = HouseholdShare.membership.owner, previous != zoneOwner {
            print("PLATED HOUSEHOLD: leaving \(previous)'s household first")
            guard await leave(context: context) else {
                await discardAcceptedZone(ownedBy: zoneOwner)
                isJoining = false
                return .failed("Couldn't reach iCloud. Check your connection and open the link again.")
            }
        } else if HouseholdShare.membership == .hosting {
            guard await abandonHosting(context: context) else {
                await discardAcceptedZone(ownedBy: zoneOwner)
                isJoining = false
                return .failed("Couldn't reach iCloud. Check your connection and open the link again.")
            }
        }
        await acceptTableIfNeeded(url: root?.tableShareURL)

        // 2. Membership, so every pull from here reads the owner's zone.
        HouseholdShare.setMembership(.member(owner: zoneOwner), ownerName: host.isEmpty ? nil : host)
        if let root {
            HouseholdShare.groupDefaults.set(root.name, forKey: HouseholdShare.Keys.name)
            if let url = root.tableShareURL {
                HouseholdShare.groupDefaults.set(url.absoluteString, forKey: HouseholdShare.Keys.tableShareURL)
            }
        }
        ensureRecordNames(in: context)
        clearBeforeFirstPull(in: context)

        // 3. The zone, whole. The merge saves under suppression; the digest
        // is not run, so nothing here is news except the one row below.
        let changes = await HouseholdShare.fetchChanges()
        // A read that failed and a zone that is empty used to look identical
        // from here; `Changes.failed` is now set by every path that could
        // not read. A household whose link opens always has a root record
        // and this read starts from no token, so a replayed read that
        // brought no root is kept as a second witness. Seating anybody on
        // that evidence mints a second seat and leaves the host's invited
        // row standing forever (§7 step 4), so the join stops and the link
        // can be opened again.
        if changes.failed || changes.zoneGone || (changes.replayed && changes.root == nil) {
            HouseholdShare.merge(changes, into: context)
            Persist.save(context, "joined, pull incomplete")
            isJoining = false
            print("PLATED HOUSEHOLD: the first pull brought nothing, so nobody is seated")
            return .failed("Couldn't reach iCloud. Check your connection and open the link again.")
        }
        HouseholdShare.merge(changes, into: context)
        collapseDuplicates(in: context)
        // The merge caches the root on every road, so a removal this phone
        // could not see before the accept is visible now. Undo the accept
        // rather than leave somebody inside a household they were told they
        // may not be in.
        if HouseholdShare.cachedRemovedIDs.contains(me) {
            await discardAcceptedZone(ownedBy: zoneOwner)
            forgetHousehold(in: context, me: me, mySeat: nil)
            WidgetBridge.publish(from: context)
            isJoining = false
            print("PLATED HOUSEHOLD: the root says this identity was removed; the accept is undone")
            return .refused(removedSentence(host: host))
        }
        Persist.save(context, "joined")

        // 4. The seat.
        let members = fetchAll(HouseholdMember.self, context)
        let claimed: HouseholdMember
        // Only a seat that came from the zone can already carry this
        // identity. The local owner row carries it too, from onboarding's
        // own stamp, and matching that here is how the link's named seat
        // was never claimed: the host kept the invited row and received a
        // second joined one beside it.
        if let mine = members.first(where: {
            ($0.userRecordName == me || $0.participantID == me) && $0.shareModifiedAt != nil
        }) {
            claimed = mine
            print("PLATED HOUSEHOLD: a seat from the zone already carries this identity")
        } else if let seat, let named = members.first(where: { $0.shareRecordName == seat }),
                  named.seat == .invited, (named.userRecordName ?? "").isEmpty {
            claimed = named
            print("PLATED HOUSEHOLD: claiming the seat the link named")
        } else if seat == nil {
            let candidates = openSeats(in: members)
            pendingJoinHost = host
            // `join` ends here; `claimSeat` is its own span, so a sheet
            // dismissed at the question cannot leave the shell held.
            isJoining = false
            print("PLATED HOUSEHOLD: seatless link, asking which of \(candidates.count) seats is theirs")
            return .needsSeat(candidates: candidates)
        } else {
            guard let fresh = freshSeat(in: context) else {
                isJoining = false
                return .failed("Couldn't set up your seat. Open the link again.")
            }
            claimed = fresh
            print("PLATED HOUSEHOLD: the named seat is gone or taken, seating a fresh one")
        }
        return await finishJoin(claimed: claimed, host: host, context: context)
    }

    /// After `.needsSeat`. Nil means "none of these": a fresh seat from my
    /// own owner row.
    static func claimSeat(named: String?, context: ModelContext) async -> JoinOutcome {
        isJoining = true
        // `pendingJoinHost` is process-local, and the seat question can
        // outlive the process: the sheet is up when the app is killed, and
        // the answer arrives on the next launch to an empty string. The
        // cache is the same name, written by the join a moment before.
        let host = pendingJoinHost.isEmpty ? HouseholdShare.cachedOwnerName : pendingJoinHost
        let members = fetchAll(HouseholdMember.self, context)
        let claimed: HouseholdMember?
        if let named, let row = members.first(where: { $0.shareRecordName == named }),
           (row.userRecordName ?? "").isEmpty, row.seat != .head, row.seat != .left {
            claimed = row
        } else {
            claimed = freshSeat(in: context)
        }
        guard let claimed else {
            isJoining = false
            return .failed("Couldn't set up your seat. Open the link again.")
        }
        return await finishJoin(claimed: claimed, host: host, context: context)
    }

    /// Steps 4 to 6 of §7 from the moment the seat is known: retire the
    /// local owner row onto it, adopt what I brought, push, collapse.
    private static func finishJoin(claimed: HouseholdMember, host: String, context: ModelContext) async -> JoinOutcome {
        let me = TableIdentity.cached
        let outbox = HouseholdOutbox.shared

        suppressed = true
        let members = fetchAll(HouseholdMember.self, context)
        // The owner row minted at onboarding: never synced, role owner, and
        // not the seat just claimed. The host's own seat arrived from the
        // wire and carries `shareModifiedAt`, so it can never match.
        let local = members.first {
            $0 !== claimed && $0.role == "owner" && $0.shareModifiedAt == nil
                && (($0.userRecordName ?? "").isEmpty || $0.userRecordName == me)
        }
        if let local {
            for meal in local.assignedMeals ?? [] { meal.cook = claimed }
            if claimed.userRecordName == nil || claimed.userRecordName == me {
                let oldName = claimed.name
                if !local.name.isEmpty, !HouseholdIdentity.isPlaceholder(local.name) { claimed.name = local.name }
                if claimed.bio.isEmpty { claimed.bio = local.bio }
                if claimed.photoData == nil { claimed.photoData = local.photoData }
                if oldName != claimed.name { Awards.rekey(from: oldName, to: claimed.name) }
            }
            context.delete(local)
            print("PLATED HOUSEHOLD: retired the local owner row onto \(claimed.shareRecordName)")
        }
        if (claimed.userRecordName ?? "").isEmpty { claimed.userRecordName = me }
        if claimed.userRecordName == me {
            if claimed.seat != .joined { claimed.seat = .joined }
            if claimed.joinedAt == nil { claimed.joinedAt = .now }
            if claimed.role == "owner" { claimed.role = "partner" }
            if claimed.authorID.isEmpty { claimed.authorID = me }
        }
        HouseholdShare.mySeat = claimed.shareRecordName

        // 5. Adopt what I brought: my recipes, gatherings and laid places
        // are stamped mine and go to the household.
        //
        // Selected by sync state, never by a missing author: `willSave`
        // stamps `authorID` on every row this build inserts, and a leave
        // leaves every kept row stamped with me, so "authorID is empty" is
        // an empty set on any phone newer than the field. A row that came
        // from the household in the merge a moment ago carries a
        // `shareModifiedAt`; everything this person brought does not.
        var adopted = 0
        for row in fetchAll(Recipe.self, context) where row.shareModifiedAt == nil {
            if row.authorID.isEmpty { row.authorID = me }
            outbox.enqueueUpsert(.recipe, row.shareRecordName); adopted += 1
        }
        for row in fetchAll(Gathering.self, context) where row.shareModifiedAt == nil {
            if row.authorID.isEmpty { row.authorID = me }
            outbox.enqueueUpsert(.gathering, row.shareRecordName); adopted += 1
        }
        for row in fetchAll(HouseholdMember.self, context)
        where row.seat == .notOnPlated && row.shareModifiedAt == nil
            && (row.authorID.isEmpty || row.authorID == me) {
            if row.authorID.isEmpty { row.authorID = me }
            outbox.enqueueUpsert(.seat, row.shareRecordName); adopted += 1
        }
        Persist.save(context, "seat claimed")
        suppressed = false
        outbox.enqueueUpsert(.seat, claimed.shareRecordName)
        print("PLATED HOUSEHOLD: adopted \(adopted) row(s), pushing the seat")

        await outbox.drain(context: context)
        collapseDuplicates(in: context)
        // The bell says it only once the seat is real. Said before the seat
        // question, it claimed a join that a dismissed sheet never finished.
        Notifier.post(
            .householdJoined, actor: host,
            body: "You joined \(host.isEmpty ? "the" : host + "'s") household.",
            link: DeepLink.url(.plan).absoluteString, into: context
        )
        Persist.save(context, "joined")
        WidgetBridge.publish(from: context)
        Haptic.kiss()
        isJoining = false
        pendingJoinHost = ""
        return .joined
    }

    /// The second device of an Apple ID that joined somewhere else (§2).
    ///
    /// `refreshMembership` found a household this device has no local trace
    /// of joining, so `plated.household.mySeat` is empty and nothing knows
    /// which row is this person. The mirror carries the seat over on its own
    /// schedule, so this only adopts a row that is already here, and mints,
    /// renames and clears nothing: `ensureRecordNames` would stamp fresh
    /// names over the host's, and `clearBeforeFirstPull` would delete the
    /// rows the mirror is in the middle of delivering.
    static func adoptMySeat(in context: ModelContext) {
        guard HouseholdShare.mySeat == nil else { return }
        let me = TableIdentity.cached
        guard !me.isEmpty, !TableIdentity.isPlaceholder else { return }
        let mine = fetchAll(HouseholdMember.self, context).first {
            $0.userRecordName == me && !$0.shareRecordName.isEmpty
        }
        guard let mine else {
            print("PLATED HOUSEHOLD: a member with no seat row yet, waiting for the mirror")
            return
        }
        HouseholdShare.mySeat = mine.shareRecordName
        print("PLATED HOUSEHOLD: adopted seat \(mine.shareRecordName) on this device")
    }

    /// The seat this device was writing turned out to be somebody else's
    /// (§7): two people opened links naming the same seat, and the record
    /// came back carrying the other identity. Rather than fight for it,
    /// this device takes a fresh seat and brings its nights along.
    ///
    /// `freshSeat` saves under `suppressed`, so the new seat is enqueued by
    /// hand here. The nights that moved are not: they are local rows, and
    /// the plan pipe republishes what it sees on its next pass.
    static func claimFreshSeat(replacing taken: HouseholdMember, in context: ModelContext) {
        let meals = taken.assignedMeals ?? []
        guard let fresh = freshSeat(in: context), fresh !== taken else {
            print("PLATED HOUSEHOLD: that seat is somebody else's and no fresh one could be minted")
            return
        }
        suppressed = true
        for meal in meals where meal.cook === taken { meal.cook = fresh }
        Persist.save(context, "moved onto a fresh seat")
        suppressed = false
        HouseholdShare.mySeat = fresh.shareRecordName
        HouseholdOutbox.shared.enqueueUpsert(.seat, fresh.shareRecordName, at: .now)
        print("PLATED HOUSEHOLD: seat \(taken.shareRecordName) was claimed by somebody else, took \(fresh.shareRecordName)")
    }

    /// A seat made from my own owner row: the row stays, becomes a partner
    /// and takes this identity. When there is no owner row (a fresh install
    /// that skipped profile setup) one is minted from the typed name.
    private static func freshSeat(in context: ModelContext) -> HouseholdMember? {
        let me = TableIdentity.cached
        let members = fetchAll(HouseholdMember.self, context)
        if let own = members.first(where: {
            $0.role == "owner" && $0.shareModifiedAt == nil
                && (($0.userRecordName ?? "").isEmpty || $0.userRecordName == me)
        }) {
            suppressed = true
            defer { suppressed = false }
            own.role = "partner"
            own.seat = .joined
            own.joinedAt = .now
            own.userRecordName = me
            own.authorID = me
            Persist.save(context, "fresh seat")
            return own
        }
        let typed = (UserDefaults.standard.string(forKey: "userFirstName") ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return nil }
        suppressed = true
        defer { suppressed = false }
        let seat = HouseholdMember(name: typed, role: "partner", seat: .joined)
        seat.joinedAt = .now
        seat.userRecordName = me
        seat.authorID = me
        context.insert(seat)
        Persist.save(context, "fresh seat")
        return seat
    }

    /// Before the first pull, not after it (§7 step 5 says after; the order
    /// here is deliberate). The joiner's own future nights go, and this
    /// outlives the meal merge that first asked for it: the household's week
    /// now arrives in `PlanLedger` and the planner draws it BESIDE this
    /// phone's own nights (docs/plan-share.md). A joiner who kept theirs
    /// would open the Plan to every night described twice, once by the
    /// household and once by the week they planned alone before joining, and
    /// no screen could tell a reader which one dinner is. Past nights stay:
    /// they are this person's history, nobody else is describing them, and
    /// their insights are theirs. Marks are cleared here so the household's,
    /// folded by the pull, survive.
    private static func clearBeforeFirstPull(in context: ModelContext) {
        suppressed = true
        defer { suppressed = false }
        let today = Calendar.current.startOfDay(for: .now)
        var dropped = 0
        for meal in fetchAll(PlannedMeal.self, context) where meal.date >= today {
            context.delete(meal); dropped += 1
        }
        for line in fetchAll(GroceryItem.self, context) where line.shareModifiedAt == nil {
            context.delete(line); dropped += 1
        }
        GroceryMarks.shared.clear()
        HouseholdOutbox.shared.clear()
        Persist.save(context, "before first pull")
        print("PLATED HOUSEHOLD: dropped \(dropped) local plan and grocery row(s) before the first pull")
    }

    /// Why the accept was refused, in the join sheet's sentences (§7).
    /// Prefer `TableShare.Accepted.line` when the accept returned one; this
    /// is the fallback for the rare path that still only has a Bool-shaped
    /// refusal, and for re-reading a share after a transient miss.
    private static func acceptFailure(metadata: CKShare.Metadata, host: String) async -> String {
        switch await TableSync.accountState() {
        case .noAccount:
            return "Sign in to iCloud on this iPhone to join, then open the link again."
        case .restricted:
            return "iCloud is restricted on this iPhone, so Plated can't join a household."
        default:
            break
        }
        if let url = metadata.share.url {
            do {
                _ = try await TableShare.shareMetadata(for: url)
            } catch let error as CKError where error.code == .unknownItem {
                let who = host.isEmpty ? "the person who sent it" : host
                return "This link doesn't work anymore. Ask \(who) for a new one."
            } catch let error as CKError {
                let outcome = TableShare.accepted(from: error.code, account: await TableSync.accountState())
                if let line = outcome.line { return line }
            } catch {}
        }
        return "Couldn't reach iCloud. Check your connection and open the link again."
    }

    /// §7: the sentence a removed person sees, the same one the join sheet
    /// draws from `JoinPreview.State.removed`.
    private static func removedSentence(host: String) -> String {
        "\(host.isEmpty ? "They" : host) removed you from this household. Ask them for a new invitation."
    }

    /// Give back a share this phone accepted and then could not finish
    /// joining on. Without it the zone stays in the shared database and
    /// `fetchChanges` reads it on the next pull as a household nobody was
    /// ever told they were in.
    private static func discardAcceptedZone(ownedBy owner: String) async {
        #if PLATED_CLOUDKIT
        guard !owner.isEmpty else { return }
        let zoneID = CKRecordZone.ID(zoneName: HouseholdShare.zoneName, ownerName: owner)
        do {
            _ = try await CKContainer.default().sharedCloudDatabase.deleteRecordZone(withID: zoneID)
            TableShare.forgetToken(for: zoneID)
            print("PLATED HOUSEHOLD: gave the just-accepted zone back")
        } catch {
            print("PLATED HOUSEHOLD: could not give the accepted zone back: \(error.localizedDescription)")
        }
        #endif
    }

    /// The Table rides on the household root. Accepted only when this
    /// identity is not already on it; a failure is logged and retried by
    /// `ensureTableJoined` on every pull.
    private static func acceptTableIfNeeded(url: URL?) async {
        guard let url else {
            print("PLATED HOUSEHOLD: the root carries no table link yet")
            return
        }
        do {
            let table = try await TableShare.shareMetadata(for: url)
            // The already-a-participant check lives in `TableShare.accept`
            // now, so both roads into a Table get it from one place.
            let outcome = await TableShare.accept(table)
            print("PLATED HOUSEHOLD: table accept \(outcome)"
                  + (outcome.seated ? "" : ", will retry on the next pull"))
        } catch {
            print("PLATED HOUSEHOLD: could not read the table share: \(error.localizedDescription)")
        }
    }

    /// The standing step of every pull (§7 step 1): a member whose Table
    /// accept failed at join is seated at the household's Table the next
    /// time iCloud answers.
    static func ensureTableJoined() async {
        #if PLATED_CLOUDKIT
        guard case .member(let owner) = HouseholdShare.membership,
              let url = HouseholdShare.cachedTableShareURL else { return }
        guard await TableSync.accountAvailable() else { return }
        if await TableShare.zone(ownedBy: owner) != nil { return }
        print("PLATED HOUSEHOLD: the household's table is not in the shared database yet")
        await acceptTableIfNeeded(url: url)
        #endif
    }

    // MARK: Leave (§8)

    /// Steps 1 to 7, in order. Only a member leaves; a host has nobody to
    /// leave.
    static func leave(context: ModelContext) async -> Bool {
        guard case .member(let owner) = HouseholdShare.membership else { return false }
        let me = TableIdentity.cached
        let host = HouseholdShare.cachedOwnerName
        let mySeat = HouseholdShare.mySeat
        let members = fetchAll(HouseholdMember.self, context)
        let mine = members.first { $0.userRecordName == me } ?? members.first { $0.shareRecordName == mySeat }

        // 1. My seat goes out as left, and the push is waited for. A
        // refusal ends the leave: the row goes back to what it was and
        // Settings says "Couldn't leave". Tearing the household down here
        // while the zone still says I am joined is the household keeping a
        // person it was never told about (§8).
        if let mine {
            let priorSeat = mine.seat
            let priorLeftAt = mine.leftAt
            suppressed = true
            mine.seat = .left
            if mine.leftAt == nil { mine.leftAt = .now }
            Persist.save(context, "seat left")
            suppressed = false
            let entry = HouseholdOutbox.Entry(id: mine.shareRecordName, kind: .seat, isDelete: false, at: .now)
            let outcome = await HouseholdShare.push(entries: [entry], context: context)
            print("PLATED HOUSEHOLD: pushed my seat as left: \(outcome[mine.shareRecordName].map { "\($0)" } ?? "no answer")")
            switch outcome[mine.shareRecordName] {
            case .saved, .gone:
                break
            default:
                suppressed = true
                mine.seat = priorSeat
                mine.leftAt = priorLeftAt
                Persist.save(context, "leave refused")
                suppressed = false
                print("PLATED HOUSEHOLD: the seat never went out, so nothing was left")
                return false
            }
        }

        // 2. Both zones out of the shared database. A zone that stays is a
        // household that keeps arriving: `fetchChanges` reads every
        // household zone in the shared database, so the next pull with
        // network merges back every row step 4 is about to delete, and
        // re-derives this phone into the household it thinks it left.
        // Membership is set to solo between the two because `leaveTable`
        // refuses the household's owner while this phone is still a member
        // of it.
        guard await HouseholdShare.leave() else {
            print("PLATED HOUSEHOLD: the household zone is still there, so this phone has not left")
            return false
        }
        HouseholdShare.setMembership(.solo)
        let leftTable = await TableShare.leaveTable(owner: owner)
        print("PLATED HOUSEHOLD: left the household's table: \(leftTable)")

        // 3 to 6.
        forgetHousehold(in: context, me: me, mySeat: mySeat)
        WidgetBridge.publish(from: context)
        AppBadge.sync(context)

        // 7.
        Notifier.post(
            .householdLeft, actor: host,
            body: "You left \(host.isEmpty ? "the" : host + "'s") household and their Table. Your recipes stayed with you.",
            link: DeepLink.url(.home).absoluteString, into: context
        )
        Persist.save(context, "left household")
        AppBadge.sync(context)
        return true
    }

    /// Steps 3 to 6 of Leave (§8), which need no CloudKit: the books, the
    /// rows, the reset, the promotion. Pure over the store, so the test
    /// target can hold it to the deletion rule.
    ///
    /// The rule: a row that came from the household goes. Seats other than
    /// mine and the places I laid; gatherings and manual lines that were
    /// exchanged with the zone or signed by somebody else; recipes whose
    /// `authorID` is somebody else's and which were exchanged. A row with an
    /// empty `authorID` is kept, always. Auto grocery rows are derived from
    /// a plan that is gone and are dropped for the builder to rebuild.
    ///
    /// Nights are not touched. Every `PlannedMeal` on this phone was planned
    /// on it or mirrored from its owner's other device; the household's week
    /// was never here, it was in `PlanLedger`, and leaving drops it there
    /// (`PlanLedger.forget(zoneOwner:)`).
    static func forgetHousehold(in context: ModelContext, me: String, mySeat: String?) {
        suppressed = true
        defer { suppressed = false }
        if HouseholdShare.membership != .solo { HouseholdShare.setMembership(.solo) }
        HouseholdOutbox.shared.clear()
        GroceryMarks.shared.clear()
        // A night the old household took off is not this plan's business
        // any more. Left parked, it would take a dinner off a plan that no
        // longer has anything to do with the people who removed it, on
        // whatever the next drain happened to be.
        RemovedNights.clear()
        HouseholdEdits.clear()
        HouseholdShare.mySeat = nil
        HouseholdShare.forgetUnresolved()
        let defaults = groupDefaults
        for key in [HouseholdShare.Keys.name, HouseholdShare.Keys.publishedAt, HouseholdShare.Keys.removedIDs,
                    HouseholdShare.Keys.tableShareURL, HouseholdShare.Keys.lastSyncedName,
                    // A total left behind makes the next household this
                    // phone hosts open with "Sharing with your household,
                    // 0 of 360" over a queue that holds nothing.
                    HouseholdOutbox.publishTotalKey] {
            defaults.removeObject(forKey: key)
        }

        func isMine(_ author: String) -> Bool { author.isEmpty || author == me }
        var deleted = 0

        let members = fetchAll(HouseholdMember.self, context)
        // A join that stopped at the seat picker claimed nothing and carries
        // no identity on any synced row, so without the third fallback the
        // person's own onboarding row is deleted with the household's and
        // step 6 has nothing to promote.
        let mine = members.first { $0.userRecordName == me }
            ?? members.first { $0.shareRecordName == mySeat }
            ?? members.first { $0.role == "owner" && $0.shareModifiedAt == nil }
        for row in members where row !== mine {
            let keep = isMine(row.authorID) && (row.seat == .notOnPlated || row.shareModifiedAt == nil)
            if !keep {
                for meal in row.assignedMeals ?? [] { meal.cook = nil }
                context.delete(row); deleted += 1
            }
        }

        for row in fetchAll(Gathering.self, context) {
            guard !row.authorID.isEmpty else { continue }
            if row.shareModifiedAt != nil || row.authorID != me { context.delete(row); deleted += 1 }
        }
        for row in fetchAll(GroceryItem.self, context) {
            if !row.isManual { context.delete(row); deleted += 1; continue }
            guard !row.authorID.isEmpty else { continue }
            if row.shareModifiedAt != nil || row.authorID != me { context.delete(row); deleted += 1 }
        }
        for row in fetchAll(Recipe.self, context) {
            guard !row.authorID.isEmpty, row.authorID != me, row.shareModifiedAt != nil else { continue }
            CookLedger.shared.forget(row)
            context.delete(row); deleted += 1
        }

        // 5. Never synced, fresh names: the "gone from the wire" rule can
        // never fire on these in the next household.
        for row in fetchAll(HouseholdMember.self, context) where !row.isDeleted {
            row.shareModifiedAt = nil; row.shareFingerprint = ""; row.shareRecordName = HouseholdShare.mintSeatName()
        }
        for row in fetchAll(Recipe.self, context) where !row.isDeleted {
            row.shareModifiedAt = nil; row.shareFingerprint = ""; row.shareRecordName = "recipe-\(UUID().uuidString)"
        }
        for row in fetchAll(Gathering.self, context) where !row.isDeleted {
            row.shareModifiedAt = nil; row.shareFingerprint = ""; row.shareRecordName = "gathering-\(UUID().uuidString)"
        }
        for row in fetchAll(GroceryItem.self, context) where !row.isDeleted && row.isManual {
            row.shareModifiedAt = nil; row.shareFingerprint = ""; row.shareRecordName = "line-\(UUID().uuidString)"
        }

        // 6. My seat is the head of my own table again.
        if let mine {
            mine.role = "owner"
            mine.seat = .head
            mine.leftAt = nil
        }
        Persist.save(context, "forget household")
        HouseholdShare.mySeat = nil
        print("PLATED HOUSEHOLD: forgot the household, deleted \(deleted) row(s)")
    }

    /// A host leaving to join somebody else (§7, "hosting with only by-name
    /// seats"). The private zone is deleted so `fetchChanges` stops reading
    /// it back into the store; the rows themselves are all the host's own
    /// and are kept.
    /// Answers whether the zone is actually gone. A zone left behind is
    /// read by `fetchChanges` on every later pull, and its rows merge back
    /// under their old names beside the renamed ones this function keeps:
    /// duplicate recipes and a second row carrying this identity. So the caller refuses the join rather than proceeding.
    private static func abandonHosting(context: ModelContext) async -> Bool {
        #if PLATED_CLOUDKIT
        let zoneID = CKRecordZone.ID(zoneName: HouseholdShare.zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await CKContainer.default().privateCloudDatabase.deleteRecordZone(withID: zoneID)
            TableShare.forgetToken(for: zoneID)
            print("PLATED HOUSEHOLD: deleted my own household zone before joining")
        } catch let error as CKError where error.code == .zoneNotFound {
            TableShare.forgetToken(for: zoneID)
            print("PLATED HOUSEHOLD: my own household zone was already gone")
        } catch {
            print("PLATED HOUSEHOLD: could not delete my own household zone: \(error.localizedDescription)")
            return false
        }
        #endif
        let me = TableIdentity.cached
        forgetHousehold(in: context, me: me, mySeat: nil)
        WidgetBridge.publish(from: context)
        return true
    }

    /// Positive evidence says the host removed this phone (§8). Membership
    /// must still be `.member`; the shell dismisses first, then the rows go.
    static func handleRemoved(context: ModelContext) {
        guard case .member = HouseholdShare.membership else { return }
        let host = HouseholdShare.cachedOwnerName
        NotificationCenter.default.post(name: householdRemoved, object: nil)
        forgetHousehold(in: context, me: TableIdentity.cached, mySeat: HouseholdShare.mySeat)
        WidgetBridge.publish(from: context)
        let sentence = "\(host.isEmpty ? "The" : host + "'s") household is no longer on this phone. Your recipes stayed with you, and the household kept its copy."
        Notifier.post(.householdLeft, actor: host, body: sentence,
                      link: DeepLink.url(.plan).absoluteString, into: context)
        Persist.save(context, "removed from household")
        groupDefaults.set(sentence, forKey: Keys.removedNotice)
        AppBadge.sync(context)
        print("PLATED HOUSEHOLD: removed from \(host)'s household")
    }

    // MARK: Every pull (§12)

    /// Fold a household delta into the store and say what in it is news.
    static func absorb(_ changes: HouseholdShare.Changes, context: ModelContext) async {
        if changes.zoneGone {
            handleRemoved(context: context)
            return
        }
        guard !changes.isEmpty || changes.sharesChanged else { return }
        let outcome = HouseholdShare.merge(changes, into: context)
        collapseDuplicates(in: context)
        if changes.sharesChanged {
            await Seats.reconcile(in: context)
            Persist.save(context, "seats after household pull")
        }
        // The digest names the person who left, so it is composed before
        // the seat is retired out from under it.
        await TableNews.deliver(household: changes, outcome: outcome, context: context)
        if !outcome.leftSeats.isEmpty {
            for row in outcome.leftSeats { retireLeftSeat(row, in: context) }
            Persist.save(context, "seats that left")
        }
        // A `.left` row that is still in the host's roster is one an older
        // build marked and kept, or one whose delete was refused. §8 says
        // the host's roster does not hold them, and until it goes the name
        // is still in the seated line and the Chef's kiss denominator.
        if case .hosting = HouseholdShare.membership {
            let lingering = fetchAll(HouseholdMember.self, context).filter { $0.seat == .left }
            if !lingering.isEmpty {
                for row in lingering { retireLeftSeat(row, in: context) }
                Persist.save(context, "seats that had already left")
            }
        }
        // A seat is the only thing in a household delta that can move a
        // reminder: whose night it is. The week itself arrives through the
        // plan pipe, and `NotificationScheduler.rebuild` reads `PlanLedger`
        // on its own (docs/plan-share.md), so nothing here has to know that.
        if !changes.seats.isEmpty {
            await NotificationScheduler.rebuild(meals: fetchAll(PlannedMeal.self, context))
        }
        // Every household delta moves something the widget draws: a mark or
        // a manual line moves the grocery count, a recipe moves the cookbook
        // card. `absorb` has already returned unless the delta carried
        // something, so this is at most one publish per delta.
        WidgetBridge.publish(from: context)
    }

    /// A seat arriving `left` (§8): its nights go back to unplanned, and on
    /// the host's phone the row and its record go, which is what makes the
    /// digest's "Their nights are open again" true.
    ///
    /// A member's phone clears the nights but keeps the row: nothing local
    /// can delete a record in the host's zone, and the next merge would
    /// insert the seat again from a record this phone had simply not seen.
    /// The host's deletion arrives on its own through `changes.deleted`.
    static func retireLeftSeat(_ member: HouseholdMember, in context: ModelContext) {
        guard !member.isMe, member.shareRecordName != HouseholdShare.mySeat else { return }
        for meal in member.assignedMeals ?? [] { meal.cook = nil }
        member.cookWeekdays = []
        guard case .hosting = HouseholdShare.membership else { return }
        HouseholdOutbox.shared.enqueueDelete(.seat, member.shareRecordName)
        context.delete(member)
        print("PLATED HOUSEHOLD: retired the seat that left, its nights are unplanned")
    }

    // MARK: Plumbing

    private static func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    #if DEBUG
    /// `-plated-rehearse-household`: a household arriving from "Sam" on a
    /// simulator that has no second Apple ID (§11). The seeded head is
    /// stamped with this identity so the reader stays "you".
    static func rehearse(context: ModelContext) async {
        SampleData.seed(into: context)
        suppressed = true
        for row in fetchAll(HouseholdMember.self, context) where row.seat == .head && (row.userRecordName ?? "").isEmpty {
            row.userRecordName = TableIdentity.cached
        }
        Persist.save(context, "rehearsal seed")
        suppressed = false
        HouseholdShare.setMembership(.member(owner: "rehearsal-sam"), ownerName: "Sam")

        var changes = HouseholdShare.Changes()
        var root = HouseholdShare.RemoteRoot()
        root.name = "The Meadows"
        root.hostName = "Sam"
        root.publishedAt = .now
        changes.root = root

        var sam = HouseholdShare.RemoteSeat()
        sam.recordName = "seat-rehearsal-sam"
        sam.authorID = "rehearsal-sam"
        sam.modifiedBy = "rehearsal-sam"
        sam.name = "Sam Okafor"
        sam.role = "owner"
        sam.seat = HouseholdMember.Seat.head.rawValue
        sam.userRecordName = "rehearsal-sam"
        sam.colorHex = "3DA35D"
        sam.cookWeekdays = [7, 1]
        var riley = HouseholdShare.RemoteSeat()
        riley.recordName = "seat-rehearsal-riley"
        riley.authorID = "rehearsal-sam"
        riley.modifiedBy = "rehearsal-sam"
        riley.name = "Riley Okafor"
        riley.role = "kid"
        riley.colorHex = "C88A00"
        changes.seats = [sam, riley]

        // Recipes only. Sam's week is not a household record and never
        // arrives here; `-plated-fake-table-news` rehearses remote nights
        // through `PlanLedger`, which is where they land.
        for (index, title) in ["Sheet-pan chicken", "Ragù"].enumerated() {
            var recipe = HouseholdShare.RemoteRecipe()
            recipe.recordName = "recipe-rehearsal-\(index)"
            recipe.authorID = "rehearsal-sam"
            recipe.modifiedBy = "rehearsal-sam"
            recipe.title = title
            recipe.summary = "From Sam's kitchen."
            recipe.servings = 4
            recipe.cookMinutes = 35
            recipe.ingredients = [HouseholdShare.WireIngredient(name: "Chicken thighs", quantity: 6, unit: "", aisle: GroceryAisle.other.rawValue, isPantryStaple: false, sortIndex: 0)]
            changes.recipes.append(recipe)
        }
        TableNews.rehearsing = true
        defer { TableNews.rehearsing = false }
        await absorb(changes, context: context)
        print("PLATED HOUSEHOLD: rehearsal household absorbed")
    }

    /// `-plated-prime-household`: one of every household record type, so
    /// CloudKit's Development schema learns them, then retracted. Refuses
    /// unless membership is `.solo`, and leaves nothing behind: the zone is
    /// minted without a share and deleted at the end.
    static func primeSchema(context: ModelContext) async -> String {
        #if PLATED_CLOUDKIT
        guard HouseholdShare.membership == .solo else {
            return "PRIME HOUSEHOLD: refused, membership is \(HouseholdShare.membership.kind)."
        }
        guard await TableSync.accountAvailable() else {
            return "PRIME HOUSEHOLD: no iCloud account, nothing primed."
        }
        let db = CKContainer.default().privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: HouseholdShare.zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await db.save(CKRecordZone(zoneID: zoneID))
        } catch {
            return "PRIME HOUSEHOLD: could not make the zone: \(error)"
        }
        var root = HouseholdShare.RemoteRoot()
        root.name = "Prime"
        root.hostName = "Prime"
        root.hostPhoto = Data([0xFF, 0xD8, 0xFF, 0xD9])
        root.banner = root.hostPhoto
        root.tableShareURL = URL(string: "https://www.icloud.com/share/prime")
        root.publishedAt = .now
        root.removedIDs = ["prime"]
        let rootOK = await HouseholdShare.pushRoot(root)

        // A throwaway context: the rows exist only long enough to be
        // written, and a rollback takes them back before they mirror.
        let scratch = ModelContext(context.container)
        scratch.autosaveEnabled = false
        suppressed = true
        let member = HouseholdMember(name: "Prime seat", role: "kid", seat: .invited)
        member.dietaryNotes = "none"; member.avoidedIngredients = ["nuts"]; member.cookWeekdays = [2]
        member.bio = "prime"; member.photoData = root.hostPhoto; member.userRecordName = "prime"
        member.participantID = "prime"; member.invitedAt = .now; member.joinedAt = .now; member.leftAt = .now
        let recipe = Recipe(title: "Prime recipe", summary: "prime", instructions: "prime", tags: ["prime"])
        recipe.photoData = root.hostPhoto; recipe.steps = ["one"]; recipe.weatherMoods = ["prime"]
        // Every OPTIONAL field on a wire type has to be non-nil here.
        // `Wire.set` omits a nil key, an omitted key is never minted, and a
        // field that does not exist in Production fails the first real save
        // that carries it with `.invalidArguments`. The recipe is the only
        // household type with optionals: `importedAt`, which nothing else
        // in this probe sets, and `photoData`, which the line above does.
        // A field added to any of these types belongs in this probe on the
        // same commit.
        recipe.importedAt = .now
        let ingredient = Ingredient(name: "Prime", quantity: 1, unit: "cup", aisle: .other, isPantryStaple: false, sortIndex: 0)
        ingredient.recipe = recipe
        let photo = RecipePhoto(photoData: root.hostPhoto, sortIndex: 0)
        photo.recipe = recipe
        let gathering = Gathering(title: "Prime gathering", notes: "prime", guestCount: 2, location: "here")
        let line = GroceryItem(name: "Prime line", quantity: 1, unit: "cup", isManual: true)
        line.originTitle = "prime"
        for row in [member, recipe, ingredient, photo, gathering, line] as [any PersistentModel] { scratch.insert(row) }
        let mark = GroceryMarks.Mark(lineKey: "prime|cup", purchases: ["prime": 1], dismissedUntil: "2026-01-01", at: .now, by: "prime")
        _ = GroceryMarks.shared.fold(mark, into: scratch)
        suppressed = false

        let entries = [
            HouseholdOutbox.Entry(id: member.shareRecordName, kind: .seat, isDelete: false, at: .now),
            HouseholdOutbox.Entry(id: recipe.shareRecordName, kind: .recipe, isDelete: false, at: .now),
            HouseholdOutbox.Entry(id: gathering.shareRecordName, kind: .gathering, isDelete: false, at: .now),
            HouseholdOutbox.Entry(id: line.shareRecordName, kind: .line, isDelete: false, at: .now),
            HouseholdOutbox.Entry(id: GroceryMarks.recordName(for: mark.lineKey), kind: .mark, isDelete: false, at: .now),
        ]
        let outcomes = await HouseholdShare.push(entries: entries, context: scratch)
        scratch.rollback()
        GroceryMarks.shared.clear()
        HouseholdOutbox.shared.clear()
        var report = "PRIME HOUSEHOLD: root \(rootOK ? "ok" : "refused")\n"
        for entry in entries {
            report += "  \(entry.kind.rawValue): \(outcomes[entry.id].map { "\($0)" } ?? "no answer")\n"
        }
        // The night's record lives in THIS zone, and this function deletes
        // the zone on its way out, so this is the only moment in the app's
        // life when `PlatedHouseholdPlan` can be minted at all. Primed here
        // rather than from `-plated-prime-share`, which runs when there is
        // no household zone and could only ever answer "skipped".
        report += "  \(TableShare.planType): \(await TableShare.primePlan())\n"
        do {
            _ = try await db.deleteRecordZone(withID: zoneID)
            TableShare.forgetToken(for: zoneID)
            report += "  zone deleted, nothing left behind"
        } catch {
            report += "  zone NOT deleted: \(error)"
        }
        return report
        #else
        return "PRIME HOUSEHOLD: built without CloudKit."
        #endif
    }
    #endif
}
