import XCTest
import SwiftData
import CloudKit
@testable import Plated

/// Taking a night off the household plan, held to docs/household.md.
///
/// A removal is a WRITE of `removed = 1`, never a CloudKit delete, because a
/// deletion arrives as a bare record name with nobody attached: the notice
/// then had to name the night's author, and the author's own phone, which
/// drops every record it wrote, could never be told at all. These are the
/// pure pieces: the flag on the wire, the author hearing it, the reader
/// hearing it, the publisher refusing to stand the night back up, and the
/// two hold-backs that decide when the meal may actually go.
@MainActor
final class RemovedNightTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    private static let calendar = Calendar.current
    private static var today: Date { calendar.startOfDay(for: .now) }
    private static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private var savedOwner: String?

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        savedOwner = PlanLedger.shared.householdOwner
        PlanLedger.shared.clear()
        PlanShare.forgetEdits()
        RemovedNights.clear()
        HouseholdEdits.clear()
        PlanLedger.shared.householdOwner = "host"
    }

    override func tearDown() async throws {
        RemovedNights.clear()
        HouseholdEdits.clear()
        PlanShare.forgetEdits()
        PlanLedger.shared.clear()
        PlanLedger.shared.householdOwner = savedOwner
        container = nil
    }

    private func plan(
        id: String = "n1", author: String = "_riley", title: String = "Tacos",
        day offset: Int = 2, removed: Int = 0, editorID: String = "", editorName: String = ""
    ) -> TableShare.RemotePlan {
        var p = TableShare.RemotePlan()
        p.recordName = "plan-\(id)"
        p.shoppingID = id
        p.zoneOwner = "host"
        p.authorID = author
        p.authorName = author == "_riley" ? "Riley Park" : "Nate Meadows"
        p.day = PlanDay.string(Self.day(offset))
        p.slot = MealSlot.dinner.rawValue
        p.title = title
        p.removed = removed
        p.editorID = editorID
        p.editorName = editorName
        return p
    }

    private func deliver(_ plans: [TableShare.RemotePlan], me: String) -> PlanLedger.Delta {
        var changes = TableShare.Changes()
        changes.plans = plans
        return PlanLedger.shared.absorb(changes, me: me)
    }

    // MARK: The author hears it

    func testTheAuthorIsToldTheHouseholdTookTheirNightOff() {
        // The delivery the author could never hear. Their own records are
        // dropped on arrival, so an ABSENCE was the one thing that could
        // not reach them; a tombstone is a record, so it does.
        let delta = deliver([plan(author: "_me", removed: 1, editorID: "_riley", editorName: "Riley Park")], me: "_me")
        XCTAssertEqual(delta.ownRemoved.count, 1)
        XCTAssertEqual(delta.ownRemoved.first?.shoppingID, "n1")
        XCTAssertEqual(delta.ownRemoved.first?.editorName, "Riley Park")
        XCTAssertFalse(delta.isEmpty, "isEmpty gates the reminder rebuild, so a removal may not read as nothing")
    }

    func testTheAuthorsOwnLivingNightIsStillDroppedRatherThanDrawn() {
        let delta = deliver([plan(author: "_me")], me: "_me")
        XCTAssertTrue(delta.isEmpty, "a night this phone planned is a PlannedMeal, never a ledger entry")
        XCTAssertNil(PlanLedger.shared.entry("plan-n1"))
    }

    func testARecordWithNoAuthorIsNobodysOwnRemoval() {
        // The own-author guard's else fires on an EMPTY author too, and an
        // empty id is not this phone.
        let delta = deliver([plan(author: "", removed: 1)], me: "_me")
        XCTAssertTrue(delta.ownRemoved.isEmpty)
    }

    // MARK: A reader hears it

    func testATombstoneTakesSomebodyElsesNightOffThisPhone() {
        _ = deliver([plan()], me: "_me")
        XCTAssertNotNil(PlanLedger.shared.entry("plan-n1"), "the night arrived first")
        let delta = deliver([plan(removed: 1, editorID: "_sam", editorName: "Sam Okafor")], me: "_me")
        XCTAssertNil(PlanLedger.shared.entry("plan-n1"), "and the tombstone took it off")
        XCTAssertEqual(delta.removed.count, 1)
        XCTAssertTrue(delta.changed.isEmpty, "a removal is not an ordinary change")
    }

    func testTheRemoverIsNotToldAboutTheirOwnRemoval() {
        _ = deliver([plan()], me: "_sam")
        let delta = deliver([plan(removed: 1, editorID: "_sam", editorName: "Sam Okafor")], me: "_sam")
        XCTAssertNil(PlanLedger.shared.entry("plan-n1"), "it still leaves their plan")
        XCTAssertTrue(delta.removed.isEmpty, "a notice is never about your own action")
    }

    // MARK: The wire

    func testARemovalIsAWriteThatCarriesWhoDidIt() {
        let night = PlanLedger.Entry(plan())
        let edit = PlanShare.Edit(deleting: night)
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let served = CKRecord(
            recordType: TableShare.planType,
            recordID: CKRecord.ID(recordName: "plan-n1", zoneID: zone)
        )
        served["title"] = "Tacos" as CKRecordValue
        served["removed"] = 0 as CKRecordValue
        let (record, _) = PlanShare.record(for: edit, existing: served, zone: zone, now: .now)
        XCTAssertEqual(TableShare.int(record, "removed"), 1)
        XCTAssertEqual(record["title"] as? String, "Tacos", "a removal does not rewrite the night")
        XCTAssertFalse((record["editorID"] as? String ?? "").isEmpty, "and it carries who did it")
    }

    func testAChangeNeverSetsTheRemovedFlag() {
        let night = PlanLedger.Entry(plan())
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let served = CKRecord(
            recordType: TableShare.planType,
            recordID: CKRecord.ID(recordName: "plan-n1", zoneID: zone)
        )
        served["removed"] = 0 as CKRecordValue
        let (record, _) = PlanShare.record(for: edit, existing: served, zone: zone, now: .now)
        XCTAssertEqual(TableShare.int(record, "removed"), 0)
    }

    func testTheFlagSurvivesTheWire() {
        var p = plan(removed: 1)
        p.editorID = "_sam"
        let entry = PlanLedger.Entry(p)
        XCTAssertEqual(entry.editorID, "_sam")
        XCTAssertEqual(p.removed, 1)
    }

    // MARK: A fetch that overtook a write

    func testADeliveryOlderThanTheRowIsNotApplied() {
        // TablePull fetches and then folds with suspension points between,
        // and `exclusively` guards writers only, so an edit can land in the
        // gap and this fold would put the old dish back on screen.
        var first = plan(id: "n1", author: "_riley", title: "Tacos")
        first.changedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = deliver([first], me: me)
        var newer = plan(id: "n1", author: "_riley", title: "Ragu")
        newer.changedAt = Date(timeIntervalSince1970: 1_700_000_060)
        _ = deliver([newer], me: me)
        XCTAssertEqual(PlanLedger.shared.entry("plan-n1")?.title, "Ragu")

        // The stale read, fetched before the write and folded after it.
        let delta = deliver([first], me: me)
        XCTAssertEqual(PlanLedger.shared.entry("plan-n1")?.title, "Ragu", "the older read is refused")
        XCTAssertTrue(delta.changed.isEmpty, "and it is not news either")
    }

    func testTheSameVersionArrivingTwiceIsStillApplied() {
        // A date that goes to CloudKit and comes back is not a different
        // version, so the comparison is in whole seconds.
        var p = plan(id: "n1", author: "_riley", title: "Tacos")
        p.changedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = deliver([p], me: me)
        p.changedAt = Date(timeIntervalSince1970: 1_700_000_000.2)
        p.title = "Ragu"
        _ = deliver([p], me: me)
        XCTAssertEqual(PlanLedger.shared.entry("plan-n1")?.title, "Ragu")
    }

    // MARK: A night of this phone's own that somebody else changed

    func testTheAuthorHearsWhenSomebodyElseChangesTheirNight() {
        var p = plan(author: me, title: "Ragu")
        p.editorID = "_riley"
        p.editorName = "Riley Park"
        p.cookID = me
        p.cookName = "Nate Meadows"
        let delta = deliver([p], me: me)
        XCTAssertEqual(delta.ownChanged.count, 1, "the deafness this closes")
        XCTAssertEqual(delta.ownChanged.first?.title, "Ragu")
        XCTAssertEqual(delta.ownChanged.first?.cookID, me, "including being put down to cook")
        XCTAssertFalse(delta.isEmpty)
    }

    func testTheAuthorsOwnPublishIsNotAChangeToThemselves() {
        var p = plan(author: me, title: "Tacos")
        p.editorID = me
        p.editorName = "Nate Meadows"
        XCTAssertTrue(deliver([p], me: me).ownChanged.isEmpty)
    }

    func testARemovalIsNotAlsoAChange() {
        var p = plan(author: me, removed: 1)
        p.editorID = "_riley"
        p.editorName = "Riley Park"
        let delta = deliver([p], me: me)
        XCTAssertEqual(delta.ownRemoved.count, 1)
        XCTAssertTrue(delta.ownChanged.isEmpty, "a night that is gone is not a night that changed")
    }

    func testTheHouseholdsVersionIsNeverTakenWithoutSomebodyTapping() {
        // A value crossing the seam needs a human. Noting it must not move
        // a single field of the person's own night.
        let m = meal(id: "n1", title: "Tacos")
        var p = plan(author: me, title: "Ragu")
        p.editorID = "_riley"
        p.editorName = "Riley Park"
        HouseholdEdits.note(deliver([p], me: me).ownChanged)
        XCTAssertEqual(m.title, "Tacos", "the plan is untouched until a person says so")
        XCTAssertEqual(HouseholdEdits.pending(shoppingID: "n1")?.title, "Ragu")

        XCTAssertTrue(HouseholdEdits.adopt(HouseholdEdits.pending(shoppingID: "n1")!, in: context))
        XCTAssertEqual(m.title, "Ragu", "and taken only when they do")
        XCTAssertNil(HouseholdEdits.pending(shoppingID: "n1"), "and not offered twice")
    }

    func testTheNewestVersionOfANightIsTheOneOffered() {
        for title in ["Ragu", "Katsu curry"] {
            var p = plan(author: me, title: title)
            p.editorID = "_riley"
            p.editorName = "Riley Park"
            HouseholdEdits.note(deliver([p], me: me).ownChanged)
        }
        XCTAssertEqual(HouseholdEdits.all.count, 1, "one night, one answer")
        XCTAssertEqual(HouseholdEdits.pending(on: Self.day(2))?.title, "Katsu curry")
    }

    // MARK: One delivery carrying more than one kind of change

    func testARemovalAndAnUnrelatedEditInOneDeliveryDoNotDisturbEachOther() {
        // The one path where the removal arm, the drain, the retraction and
        // the reminder rebuild all run in the same pass. Everything about
        // the ordering between them has only ever been reasoned about, so
        // the part that can be pinned here is pinned here: the two nights
        // must not be able to answer for each other.
        _ = meal(id: "mine")
        _ = deliver([plan(id: "theirs", author: "_riley", title: "Ragu", day: 3)], me: me)
        XCTAssertNotNil(PlanLedger.shared.entry("plan-theirs"))

        var off = plan(id: "mine", author: me, title: "Tacos", day: 2, removed: 1)
        off.editorID = "_riley"
        off.editorName = "Riley Park"
        var edited = plan(id: "theirs", author: "_riley", title: "Katsu curry", day: 3)
        edited.editorID = "_sam"
        edited.editorName = "Sam Okafor"

        let delta = deliver([off, edited], me: me)
        XCTAssertEqual(delta.ownRemoved.map(\.shoppingID), ["mine"], "only the author's own night is removed")
        XCTAssertEqual(delta.changed.count, 1, "and the other night is an ordinary change")
        XCTAssertEqual(delta.changed.first?.after.title, "Katsu curry")
        XCTAssertNotNil(PlanLedger.shared.entry("plan-theirs"), "which stays in the ledger")

        RemovedNights.park(delta.ownRemoved)
        XCTAssertTrue(RemovedNights.drain(in: context))
        let left = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        XCTAssertTrue(left.isEmpty, "the removed night's meal went")
        XCTAssertNotNil(PlanLedger.shared.entry("plan-theirs"), "and the edited night was not touched by the drain")
    }

    // MARK: The one notice with no antecedent

    /// The digest reads `TableIdentity.cached` for "me", so the tests use
    /// this phone's own answer rather than a literal.
    private var me: String { TableIdentity.cached }

    private func digest(_ delta: PlanLedger.Delta) -> [TableNews.Notice] {
        TableNews.digest(TableShare.Changes(), newSeats: [], plans: delta, context: context)
    }

    func testTheAuthorIsToldWhenTheHouseholdTakesTheirNightOff() {
        // Every other plan notice answers a row the reader already has, and
        // the author has none for a night they planned themselves. This one
        // is sent anyway: the consequence of not hearing it is shopping for
        // or cooking a dinner that is off the plan.
        let delta = deliver(
            [plan(author: me, removed: 1, editorID: "_riley", editorName: "Riley Park")],
            me: me
        )
        let notices = digest(delta)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley took Tacos off \(Stamp.nightPhrase(Self.day(2)))")
        XCTAssertEqual(notices[0].body, "It came off your week too.")
        XCTAssertTrue(notices[0].addressed, "it is about the reader, so it is never folded into a count")
    }

    func testTheAuthorIsNotToldAboutTheirOwnRemovalOnTheirOtherDevice() {
        let delta = deliver(
            [plan(author: me, removed: 1, editorID: me, editorName: "Nate Meadows")],
            me: me
        )
        XCTAssertEqual(delta.ownRemoved.count, 1, "the meal still has to go")
        XCTAssertTrue(digest(delta).isEmpty, "but a notice is never about your own action")
    }

    func testARemovalThatNamesNobodyTellsTheAuthorNothing() {
        let delta = deliver([plan(author: me, removed: 1)], me: me)
        XCTAssertEqual(delta.ownRemoved.count, 1, "the meal still has to go")
        XCTAssertTrue(digest(delta).isEmpty, "named, or not sent")
    }

    // MARK: When the meal may actually go

    private func meal(id: String, cooked: Bool = false, title: String = "Tacos") -> PlannedMeal {
        let m = PlannedMeal(date: Self.day(2), recipe: nil, customTitle: title)
        m.shoppingID = id
        if cooked { m.cookedAt = .now }
        context.insert(m)
        return m
    }

    private func park(editorName: String = "Riley Park") {
        var p = plan(author: "_me", removed: 1)
        p.editorID = "_riley"
        p.editorName = editorName
        RemovedNights.park([PlanLedger.Entry(p)])
    }

    func testAnOrdinaryNightLeavesThePlan() {
        _ = meal(id: "n1")
        park()
        XCTAssertTrue(RemovedNights.drain(in: context))
        XCTAssertTrue(((try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []).isEmpty)
        XCTAssertEqual(RemovedNights.all.first?.settled, true, "and it stops waiting")
    }

    func testANightThatWasCookedIsNeverDeleted() {
        // cookedAt is what timesCooked, Awards and the insights all count,
        // none of it snapshotted. The zone does not get to erase what
        // happened in a kitchen.
        _ = meal(id: "n1", cooked: true)
        park()
        XCTAssertFalse(RemovedNights.drain(in: context))
        XCTAssertEqual((try? context.fetch(FetchDescriptor<PlannedMeal>()))?.count, 1)
        XCTAssertEqual(RemovedNights.all.first?.kept, true, "kept, and said so differently")
        XCTAssertEqual(RemovedNights.all.first?.settled, true, "settled, not still waiting")
    }

    func testANightWithNoRowOnThisPhoneStopsWaiting() {
        park()
        XCTAssertFalse(RemovedNights.drain(in: context))
        XCTAssertEqual(RemovedNights.all.first?.settled, true)
    }

    func testTheSameNightDoesNotQueueTwice() {
        park()
        park()
        XCTAssertEqual(RemovedNights.all.count, 1)
    }

    func testThePhoneRemembersWhoTookTheNightOffAfterTheMealHasGone() {
        // Once the meal is deleted nothing else on this phone remembers the
        // night existed, so the screens that tell the person have nowhere
        // else to read from.
        _ = meal(id: "n1")
        park()
        XCTAssertTrue(RemovedNights.drain(in: context))
        let said = RemovedNights.gone(on: Self.day(2))
        XCTAssertEqual(said?.title, "Tacos")
        XCTAssertEqual(said?.by, "Riley Park")
    }

    func testARecordThatNamedNobodyIsRememberedWithoutAName() {
        _ = meal(id: "n1")
        park(editorName: "")
        RemovedNights.drain(in: context)
        XCTAssertEqual(RemovedNights.gone(on: Self.day(2))?.by, "", "never a guessed name")
    }

    func testThePublisherMayNotDeleteATombstoneOutOfTheZone() {
        // The tombstone is the only carrier of who removed the night. The
        // author's own pass runs seconds after the meal goes, and a phone
        // that had not pulled yet would find a bare absence.
        park()
        XCTAssertTrue(RemovedNights.isTombstoned("plan-n1"))
        XCTAssertFalse(RemovedNights.isTombstoned("plan-somebody-elses"))
    }
}
