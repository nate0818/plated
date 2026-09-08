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
        /// Who made the version of this night that is on the record, which
        /// is not always its author: any member may change any household
        /// night. Without it the digest reads the author and tells a
        /// household "Nate changed Thursday to Ragu" about something Riley
        /// did, and never recognises the reader's own change coming back
        /// off the zone as their own.
        ///
        /// Optional rather than defaulted, for the reason `pendingRemoval`
        /// is: a synthesised `init(from:)` throws on a missing key, so a
        /// book written before these two fields would decode as no nights
        /// at all. Nil and "" mean the same thing here, an old record, and
        /// the reader falls back to the author.
        var editorID: String?
        var editorName: String?
        /// The night's ingredients, so this phone's grocery list can cover
        /// a night it did not plan. Optional for the same decode reason as
        /// the two above: a book written before groceries were shared must
        /// still read, and nil means "this record predates the field", not
        /// "this night has no ingredients". See `PlanShare.Line`.
        var lines: [PlanShare.Line]?
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
        /// When this phone changed the night without the zone having said
        /// yes yet. A queued write is not a landed write, so the row says
        /// so until `settle` clears this. Absent on every entry that came
        /// off the wire, which is every entry until somebody edits one.
        var pendingSince: Date?
        /// Set beside `pendingSince` when the change on its way is taking the
        /// night off the plan for everybody. The entry STAYS while that is
        /// true: a delete that has not landed is a night still standing on
        /// every other phone, and a row that vanishes here says it went when
        /// it did not, with nothing on any screen to correct it.
        ///
        /// Optional rather than a `Bool` with a default, because a book
        /// written before this key existed has to keep decoding: a
        /// synthesised `init(from:)` throws on a missing key rather than
        /// falling back to a property's default value.
        var pendingRemoval: Bool?

        var id: String { recordName }
        /// This night is on its way off the plan and has not gone yet.
        var isGoing: Bool { pendingSince != nil && pendingRemoval == true }

        /// The caption clause while this phone's change has not reached the
        /// household. Two sentences, not one: "Not sent yet" on a night the
        /// person took off does not say the thing they need to know, which
        /// is that everybody else still has it.
        var pendingLine: String? {
            guard pendingSince != nil else { return nil }
            return isGoing ? "Still on the other phones" : "Not sent yet"
        }

        /// The same fact with room to breathe, for the hero under the card.
        var pendingSentence: String? {
            guard pendingSince != nil else { return nil }
            return isGoing
                ? "You took this night off. It has not reached the other phones yet."
                : "Your change has not been sent yet."
        }

        /// The same fact as a clause inside a spoken sentence.
        var pendingSpoken: String? {
            guard pendingSince != nil else { return nil }
            return isGoing
                ? "you took this night off and it has not reached the other phones yet"
                : "your change has not been sent yet"
        }

        /// Start of the night's day in the reader's own calendar.
        var date: Date { PlanDay.date(day) ?? .distantPast }
        var slotValue: MealSlot { MealSlot(rawValue: slot) ?? .dinner }
        var authorFirstName: String { Entry.firstName(authorName) }
        /// The identity behind this version of the night: the editor when
        /// the record names one, the author otherwise. This is the id an
        /// own-action guard has to compare, or Riley is told about Riley's
        /// own change to Nate's night.
        var changedByID: String {
            let editor = editorID ?? ""
            return editor.isEmpty ? authorID : editor
        }
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
            editorID = r.editorID
            editorName = r.editorName
            lines = r.lines
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
        /// Nights THIS phone planned that the household has taken off.
        ///
        /// The one delivery the author was never able to hear. `absorb`
        /// drops every record whose author is this phone, and a removal used
        /// to be a CloudKit deletion, so the night stood on the author's
        /// plan forever under a control that said it had gone for everybody.
        /// A tombstone is a record, so it arrives, and this is what the app
        /// acts on: the `PlannedMeal` goes, once.
        ///
        /// Defaulted, so every existing `Delta()` still compiles, and in
        /// `isEmpty`, because that is what gates the reminder rebuild: a
        /// delivery that only removes a night still has to take its 19:00
        /// reminder down with it.
        var ownRemoved: [Entry] = []
        /// Nights THIS phone planned that somebody else has CHANGED.
        ///
        /// The other half of the same deafness. `absorb` drops every record
        /// this phone authored, so a member setting the author down to cook,
        /// or changing the dish, reached every phone except the one whose
        /// plan it was: no banner, no bell row, no reminder, and a household
        /// believing somebody had an obligation nobody had told them about.
        ///
        /// Unlike `ownRemoved` this may NOT be acted on by itself. A removal
        /// is an absence and converges on nothing; a cook or a title is a
        /// VALUE, and writing it into the author's `PlannedMeal` from a
        /// delivery is the two-writer shape the mirror law forbids outright.
        /// So this is shown, and a person decides. See CLAUDE.md, "A value
        /// crossing the seam needs a human. An absence does not."
        var ownChanged: [Entry] = []
        var isEmpty: Bool {
            added.isEmpty && changed.isEmpty && removed.isEmpty
                && ownRemoved.isEmpty && ownChanged.isEmpty
        }
    }

    private struct Book: Codable {
        var entries: [String: Entry] = [:]
        /// The night as the zone last delivered it, kept only while this
        /// phone has an edit it has not landed. It is what a delivery must
        /// be compared against: comparing against the row on screen means
        /// comparing against this phone's own optimistic change, and the
        /// digest then reports the reader's edit back to them as somebody
        /// else's. Persisted rather than held in memory like `beforeEdit`,
        /// because a queued edit survives a relaunch and the comparison has
        /// to survive with it. Defaulted, so a book written before this
        /// decodes as having none.
        var serverImages: [String: Entry] = [:]
    }

    private var book = Book()
    private var photos: [String: Data] = [:]
    /// The night as it stood before an edit this phone has not landed yet,
    /// so a refusal can put it back. In memory on purpose: it is worth
    /// nothing after a relaunch, where the zone is the thing to be corrected
    /// by (see `revert`).
    private var beforeEdit: [String: Entry] = [:]

    /// The photograph that was on the night before this phone's un-landed
    /// edit replaced it. `beforeEdit` restores the words on a refusal and
    /// used to leave the picture, so a reverted dish put the old title back
    /// over the new dish's photograph and nothing ever corrected it. The
    /// outer optional is "we have a before image", the inner one is "and it
    /// was no photograph at all", which are different restorations.
    private var beforePhoto: [String: Data?] = [:]

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
    ///
    /// A night whose delete is still queued is IN here, so the widget, the
    /// grocery window and every "N planned" count keep counting it. That is
    /// the honest half of `pendingRemoval`: the night is still on the plan
    /// until the zone says otherwise, and dropping it from the counts would
    /// be this phone claiming a delete that has not happened, which is the
    /// same lie as the vanished row in the other direction. The row says
    /// what is going on; nothing else has to pretend it already went.
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

    /// The entry decides, then the cache. The other way round, a writer that
    /// forgets one `removePhoto` leaves a picture that is still reachable
    /// and still drawn: the winning dish's title over the losing dish's
    /// photograph. Asking the entry first makes that unreachable rather
    /// than merely unlikely, whatever a future writer forgets.
    func photo(for recordName: String) -> Data? {
        guard let entry = book.entries[recordName], entry.hasPhoto else {
            // Only when there is something to clear. `photos[x] = nil` is a
            // mutation of an observed property even when the key is already
            // absent, and this is read from `RemotePlanRow`'s body, so an
            // unconditional write invalidated the view that had just read it
            // and spun the render loop at 99% of a core until the test host
            // was killed. Guarded, a night with no photograph is a pure
            // read, and a stale entry is still cleared once and then
            // converges.
            if photos[recordName] != nil { photos[recordName] = nil }
            return nil
        }
        if let cached = photos[recordName] { return cached }
        guard let url = Self.photoDirectory?.appending(path: "\(recordName).jpg"),
              let data = try? Data(contentsOf: url) else { return nil }
        photos[recordName] = data
        return data
    }

    // MARK: Folding

    /// Fold a delivery. Nights this person planned are never kept: their
    /// own phones hold them as `PlannedMeal` rows already. A replayed zone
    /// carries no deletions, so for each replayed owner the delivered set
    /// is the whole truth.
    /// The night as the zone sees it: this phone's own un-landed marks are
    /// not facts about the household and must never be the difference that
    /// makes a delivery into news.
    private static func zoneFacing(_ entry: Entry) -> Entry {
        var e = entry
        e.pendingSince = nil
        e.pendingRemoval = nil
        return e
    }

    @discardableResult
    func absorb(_ changes: TableShare.Changes, me: String) -> Delta {
        prune()
        var delta = Delta()
        let today = PlanDay.string(.now)
        func isNews(_ e: Entry) -> Bool { e.day >= today }

        // Nights this phone has taken off and not yet sent. `applyLocally`
        // keeps the entry and marks it, so the ordinary carry below holds
        // the mark; this map is what puts it back when the entry itself has
        // gone (a prune, a `forget`, a book that never had it). Without it a
        // delivery of a record still in the zone precisely because the
        // delete has not landed would raise "Nate planned Tacos for
        // Thursday" about the night the reader themself just took off.
        var leaving: [String: Date] = [:]
        for edit in PlanShare.queuedEdits() where edit.kind == .delete {
            leaving[edit.recordName] = edit.at
        }

        // Deletions by name. Only `plan-` names are nights.
        //
        // The entry loses its editor on the way out. A bare deletion carries
        // NOBODY: the record is gone, so the only editor available is the one
        // stamped on the last copy this phone happened to hold, which is
        // whoever last CHANGED the night rather than whoever removed it.
        // Left on, Riley editing Nate's servings and Nate then deleting his
        // own night announced to the household that Riley took it off.
        //
        // This is the same bug the tombstone was introduced to fix, running
        // in the other direction, and the honest answer is the same one the
        // digest already reaches for elsewhere: with no name to give, give
        // none. `changer(_:)` then falls back to the author, who for a bare
        // deletion is the only person the record can honestly be said to
        // belong to.
        for name in changes.deleted where name.hasPrefix("plan-") {
            if var old = book.entries.removeValue(forKey: name) {
                removePhoto(name)
                old.editorID = nil
                old.editorName = nil
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
                // A record that is simply GONE says nothing about who took
                // it off, which is why a removal is a write now. What is
                // left on this path is the age-out, a departed member's
                // sweep, and a reader who never saw the tombstone because
                // the author's publisher cleared the record first. The
                // entry still belongs in `removed`, because that is what
                // takes the night's bell row and its banner down. Whether
                // anything is SAID about it is decided in `planNotices`,
                // which will not name a remover it does not have.
                if isNews(old) { delta.removed.append(old) }
            }
        }

        for remote in changes.plans {
            var entry = Entry(remote)
            guard !entry.authorID.isEmpty, entry.authorID != me else {
                // The one thing a phone needs to hear about a night it
                // planned itself. Tested with `==` rather than leaning on
                // the guard, because the guard's else also catches a record
                // with an EMPTY author, and an empty id is not this phone.
                // `me` being a placeholder cannot match a real author id, so
                // an unconfirmed identity yields nothing rather than
                // everything.
                if !entry.authorID.isEmpty, entry.authorID == me {
                    let editor = entry.editorID ?? ""
                    if remote.removed == 1 {
                        delta.ownRemoved.append(entry)
                    } else if !editor.isEmpty, editor != me {
                        // Somebody else wrote this version of a night this
                        // phone planned. The publisher stamps its own author
                        // into `editorID` on every pass, so an editor that
                        // is neither empty nor this phone is the only signal
                        // there is, and it is enough.
                        delta.ownChanged.append(entry)
                    }
                }
                // Mine, echoed back. If a stale copy was kept under a
                // placeholder identity, let it go.
                if book.entries.removeValue(forKey: entry.recordName) != nil { removePhoto(entry.recordName) }
                continue
            }
            // Somebody else's night, taken off. It used to arrive as a name
            // in `changes.deleted`; a tombstone is a record, so it comes
            // through here instead and has to be turned back into a removal
            // rather than folded as an ordinary change, or the night stands
            // on every phone but the remover's with its dish unchanged.
            if remote.removed == 1 {
                if let old = book.entries.removeValue(forKey: entry.recordName) {
                    removePhoto(entry.recordName)
                    book.serverImages[entry.recordName] = nil
                    beforeEdit[entry.recordName] = nil
                    beforePhoto[entry.recordName] = nil
                    // The DELIVERED entry, not the book copy. `old` is the
                    // night as it stood before the removal, so its editor
                    // is whoever last changed it or nobody, and the notice
                    // built from it fell straight back to naming the
                    // author: the exact sentence this whole change exists
                    // to stop. `entry` carries the tombstone's editor, and
                    // every other field is the night as it was.
                    //
                    // A removal this phone asked for is not news to it. The
                    // reader who did it is told by the sheet closing, and a
                    // notice is never about your own action, on any of your
                    // devices.
                    if isNews(entry), remote.editorID != me { delta.removed.append(entry) }
                }
                // Nothing to remove is not an error: `prune` runs at the top
                // of this function and may have taken the entry already.
                continue
            }
            let before = book.entries[entry.recordName]
            // A delivery OLDER than what this phone already holds is not a
            // delivery, it is a stale read.
            //
            // `TablePull` fetches and then folds, with main-actor
            // suspension points between the two, and `exclusively` guards
            // writers only. So an edit can land in that gap: it saves the
            // new version to the zone and settles the row, and then this
            // fold applies the record fetched BEFORE that write and puts the
            // old dish back on screen. Serialising the fold does not fix it,
            // because the staleness is in the fetch rather than in the fold.
            // The record's own clock does: whole seconds, the same rounding
            // `movedOn` uses, because a date that goes to CloudKit and comes
            // back is not a different version. It also covers deliveries
            // that arrive out of order for any other reason.
            if let before, before.pendingSince == nil,
               entry.changedAt.timeIntervalSince(before.changedAt) <= -1 {
                continue
            }
            // An edit still waiting in the queue keeps its mark through a
            // delivery: the row is showing what the zone says now and what
            // this phone has still to send, and only `settle` or the drain's
            // sweep may say that is over. Carried before the comparison, so
            // a local mark can never be the difference that makes news.
            if let mark = before?.pendingSince {
                entry.pendingSince = mark
                entry.pendingRemoval = before?.pendingRemoval
            } else if let leavingAt = leaving[entry.recordName] {
                entry.pendingSince = leavingAt
                entry.pendingRemoval = true
            }
            if let before {
                // Compared against the night as the ZONE last delivered it,
                // not against the row on screen. While this phone holds an
                // un-landed edit those two are different, and `before` is the
                // optimistic one, so the zone's version differed from it by
                // exactly the change the reader had just made and the digest
                // announced their own edit back to them as somebody else's.
                //
                // Suppressing the comparison outright was the first fix and
                // it was too broad: somebody else changing the dish while
                // this phone has a servings edit waiting is real news and has
                // to survive. Comparing against the server image keeps it,
                // and drops only the reader's own change.
                // Both sides stripped of this phone's own marks before the
                // comparison. The baseline is stored mark-free and `entry`
                // carries the mark forward from the row, so comparing them
                // raw made the MARK itself the difference: a night on its
                // way off the plan was delivered back as news about itself.
                let against = book.serverImages[entry.recordName] ?? before
                if Self.zoneFacing(against) != Self.zoneFacing(entry),
                   isNews(entry) || isNews(against) {
                    delta.changed.append((against, entry))
                }
                // This delivery is the new baseline while the edit is still
                // waiting, or the next one re-announces the same change.
                // Stored without the local marks, which are this phone's and
                // not the zone's.
                if entry.pendingSince != nil {
                    var image = entry
                    image.pendingSince = nil
                    image.pendingRemoval = nil
                    book.serverImages[entry.recordName] = image
                }
            } else if isNews(entry), leaving[entry.recordName] == nil {
                delta.added.append(entry)
            }
            book.entries[entry.recordName] = entry
            if let data = remote.photoData {
                writePhoto(entry.recordName, data)
            } else {
                removePhoto(entry.recordName)
            }
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

    // MARK: Editing

    /// The night as an edit would leave it.
    ///
    /// Pure, and the one place an edit's fields are folded onto an entry, so
    /// the row that moves under the finger and the record `PlanShare` saves
    /// can never come to mean different things. `PlanShare.record(for:)`
    /// writes the same list onto the wire; a field added to one belongs in
    /// both.
    static func edited(_ entry: Entry, by edit: PlanShare.Edit) -> Entry {
        var e = entry
        if let title = edit.title { e.title = title }
        if let servings = edit.servings { e.servings = servings }
        if let tagline = edit.tagline { e.tagline = tagline }
        if let cookID = edit.cookID { e.cookID = cookID }
        if let cookName = edit.cookName { e.cookName = cookName }
        if let hex = edit.cookColorHex { e.cookColorHex = hex }
        if let seat = edit.cookSeat { e.cookSeat = seat }
        if let hasRecipe = edit.hasRecipe { e.hasRecipe = hasRecipe }
        if let minutes = edit.recipeMinutes { e.recipeMinutes = minutes }
        if let key = edit.recipeOriginKey { e.recipeOriginKey = key }
        switch edit.photo {
        case .keep: break
        case .clear: e.hasPhoto = false
        case .send: e.hasPhoto = true
        }
        // `editorID` and `editorName` are deliberately NOT moved either,
        // for the same reason and with the same shape: they are the
        // record's stamp for who made the version the zone is holding, not
        // a field the person touched, and `PlanShare.record(for:)` writes
        // them the way it writes `modifiedAt`. Stamping the optimistic row
        // with this phone would make the zone's own delivery of that same
        // edit look like no change at all on one path and a change on
        // another; what keeps a reader quiet about their own edit is the
        // digest's guard on `changedByID`, which reads the record, not
        // this row.
        //
        // `changedAt` is deliberately NOT moved. It is the record's own
        // clock as this phone last saw it, and `PlanShare.Edit(changing:)`
        // reads it straight into `seenAt`, the version the write compares
        // the server's against. Stamping it with this phone's optimistic
        // clock made the next edit on the night claim to descend from a
        // version that exists on no server, so the write read the real
        // server clock as somebody else's change and told the person
        // "This night changed on another phone first" about their own tap.
        // A landed write takes the clock the record was actually saved
        // with, in `settle`, which is the only place it may move.
        return e
    }

    /// Change the night before the zone has answered, so the row moves under
    /// the finger. What keeps that honest is `pendingSince`: the row says
    /// the change has not reached the household until `settle` says it has.
    ///
    /// The before image is held in memory only. A kill loses it, and the
    /// zone's next delivery is what corrects the row then, which is the
    /// right authority to be corrected by.
    @discardableResult
    func applyLocally(_ edit: PlanShare.Edit) -> Entry? {
        guard let before = book.entries[edit.recordName] else { return nil }
        if beforeEdit[edit.recordName] == nil {
            beforeEdit[edit.recordName] = before
            // Taken before the edit writes over it, and only on the first
            // edit of a run, so a second change folded onto the first still
            // reverts to the night as it was before either.
            beforePhoto[edit.recordName] = photo(for: edit.recordName)
        }
        // The same image, kept in the book so it outlives a relaunch. A
        // delivery arriving on top of an un-landed edit is compared against
        // this, never against the optimistic row.
        if book.serverImages[edit.recordName] == nil {
            book.serverImages[edit.recordName] = before
        }
        var after: Entry?
        if edit.kind == .delete {
            // The row stays, marked as going. Removing it here made an
            // offline delete a night that vanished from the deleter's
            // planner while it stood on every other phone, with no surface
            // anywhere saying so: the honesty rule, and the one edit on this
            // path that was not already answered by `pendingSince`.
            var entry = before
            entry.pendingSince = edit.at
            entry.pendingRemoval = true
            book.entries[edit.recordName] = entry
            after = entry
        } else {
            var entry = Self.edited(before, by: edit)
            entry.pendingSince = edit.at
            book.entries[edit.recordName] = entry
            if case .send = edit.photo, let data = PlanShare.editPhoto(edit.recordName) {
                writePhoto(edit.recordName, data)
            }
            if case .clear = edit.photo { removePhoto(edit.recordName) }
            after = entry
        }
        save()
        return after
    }

    /// The zone answered. A landed edit takes the record's own clock, or the
    /// delivery that brings this phone's own change back reads as a change
    /// somebody made and the digest raises a notice about the reader's own
    /// action, which the law forbids outright.
    /// Returns the night this settled off the plan, so the caller can take
    /// its bell row and its banner down. A delete that landed left both
    /// standing on the phone that did the deleting: every other phone had
    /// the retraction through the delivery's delta, and the one person who
    /// knew it was gone was the one still being told about it.
    @discardableResult
    func settle(_ edit: PlanShare.Edit, _ outcome: PlanShare.WriteOutcome) -> Entry? {
        var removed: Entry?
        switch outcome {
        case .landed(let at):
            if edit.kind == .delete {
                // Now it has really gone off everybody's plan, so now the
                // row goes. Until this line the night was still standing in
                // the zone and the entry said so.
                removed = book.entries.removeValue(forKey: edit.recordName)
                book.serverImages[edit.recordName] = nil
                removePhoto(edit.recordName)
                // The reminder is scheduled off myNights(), so the night has
                // to announce that it left or "Your night tomorrow" fires
                // for a dinner nobody is cooking. forget(zoneOwner:) already
                // posts this for the same reason.
                if removed != nil {
                    NotificationCenter.default.post(name: Self.nightsDropped, object: nil)
                }
            } else if var entry = book.entries[edit.recordName] {
                entry.changedAt = at
                entry.pendingSince = nil
                entry.pendingRemoval = nil
                book.entries[edit.recordName] = entry
            }
            beforeEdit[edit.recordName] = nil
            beforePhoto[edit.recordName] = nil
            // The waiting window is over, so the baseline goes with it.
            book.serverImages[edit.recordName] = nil
            save()
        case .queued:
            // The row keeps saying it has not gone yet, because it has not.
            break
        case .theirs:
            // `fold` already wrote the server's version over it, photograph
            // included, so the before image has nothing left to restore.
            beforeEdit[edit.recordName] = nil
            beforePhoto[edit.recordName] = nil
            book.serverImages[edit.recordName] = nil
        case .refused:
            revert(edit)
        }
        return removed
    }

    /// Put the night back the way it was. Nothing to put back after a
    /// relaunch, and nothing to invent either: the row stops claiming it is
    /// on its way and the zone says what it is on the next delivery.
    private func revert(_ edit: PlanShare.Edit) {
        let restore = beforePhoto.removeValue(forKey: edit.recordName)
        book.serverImages[edit.recordName] = nil
        guard let before = beforeEdit.removeValue(forKey: edit.recordName) else {
            // No before image, which after a relaunch is every refusal:
            // `beforeEdit` is memory only. Clearing the mark and stopping
            // left this phone's un-sent fields standing as settled fact, on
            // a night the household never heard of, captioned as though the
            // author had planned it. The entry goes instead, so the row says
            // nothing until the next delivery says what the night really is.
            // A night the zone still holds comes straight back; one it does
            // not was never there to draw.
            if book.entries.removeValue(forKey: edit.recordName) != nil {
                removePhoto(edit.recordName)
            }
            save()
            return
        }
        // The picture goes back with the words, or the old title lands over
        // the new dish's photograph and stays there.
        if let restore {
            if let data = restore {
                writePhoto(edit.recordName, data)
            } else {
                removePhoto(edit.recordName)
            }
        }
        // Not into a household this phone has left. `rehome` empties that
        // zone's nights from the book and only then does the drain settle
        // its strays with `.refused`, so writing the before image back here
        // would put a night nobody can draw into a book that was just
        // cleared of it: dead data that outlives the household.
        if let owner = householdOwner, before.zoneOwner != owner {
            save()
            return
        }
        book.entries[edit.recordName] = before
        save()
    }

    /// The zone does not hold this night any more, and no refusal may put it
    /// back. The before image goes with it: an edit answered by "somebody
    /// took this off" is not an edit to undo, it is a night that is gone.
    @discardableResult
    func nightIsGone(_ recordName: String) -> Entry? {
        beforeEdit[recordName] = nil
        beforePhoto[recordName] = nil
        book.serverImages[recordName] = nil
        guard let removed = book.entries.removeValue(forKey: recordName) else { return nil }
        removePhoto(recordName)
        save()
        // Same reason as the landed delete: a night that has left has to say
        // so, or its reminder outlives it.
        NotificationCenter.default.post(name: Self.nightsDropped, object: nil)
        return removed
    }

    /// One record read outside a delivery: the version that beat an edit.
    /// Written straight in with no delta, because the person is being told
    /// by the sheet in front of them, not by the bell.
    func fold(_ remote: TableShare.RemotePlan) {
        var entry = Entry(remote)
        guard !entry.authorID.isEmpty, entry.authorID != TableIdentity.cached else { return }
        entry.pendingSince = nil
        entry.pendingRemoval = nil
        book.entries[entry.recordName] = entry
        // Both directions, the way `applyLocally` does it. Writing only when
        // the winner carries bytes left the loser's photograph on disk under
        // the winner's title: the person picked a dish, lost the race, and
        // watched the other dish's name settle over their picture.
        if let data = remote.photoData {
            writePhoto(entry.recordName, data)
        } else {
            removePhoto(entry.recordName)
        }
        beforeEdit[entry.recordName] = nil
        beforePhoto[entry.recordName] = nil
        book.serverImages[entry.recordName] = nil
        save()
    }

    /// Nights marked as not landed with nothing queued behind them. A kill
    /// between the ledger write and the queue write leaves exactly one of
    /// those, and a row that says it is on its way when nothing is going to
    /// send it is the honesty rule broken quietly.
    func clearPending(except queued: Set<String>) {
        var touched = false
        for (name, entry) in book.entries where entry.pendingSince != nil && !queued.contains(name) {
            book.entries[name]?.pendingSince = nil
            // A night marked as going with no delete behind it is a night
            // that is staying, and the row has to stop saying otherwise.
            book.entries[name]?.pendingRemoval = nil
            touched = true
        }
        if touched { save() }
    }

    /// A leave, a flip, or a rehearsal ending: that table's nights go.
    func forget(zoneOwner: String) {
        let names = book.entries.filter { $0.value.zoneOwner == zoneOwner }.map(\.key)
        for name in names {
            book.entries.removeValue(forKey: name)
            book.serverImages.removeValue(forKey: name)
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
        beforeEdit = [:]
        beforePhoto = [:]
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
            book.serverImages.removeValue(forKey: name)
            removePhoto(name)
        }
        // A baseline whose night has gone is dead weight that would otherwise
        // sit in the book for the life of the install.
        book.serverImages = book.serverImages.filter { book.entries[$0.key] != nil }
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
