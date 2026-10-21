import XCTest
import SwiftData
import CloudKit
@testable import Plated

/// The publisher's pure pieces, held to docs/plan-share.md: the
/// fingerprint that decides whether a night goes out again, the wire
/// fields read off a `PlannedMeal`, the Save and Delete rules, and the
/// candidate rules that say which table is the household's. None of these
/// touch CloudKit; the store is in memory and the book is a value passed
/// in, so a rule broken here fails on a Mac rather than in somebody's
/// shared zone.
@MainActor
final class PlanShareTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    private nonisolated static var today: Date {
        Calendar.current.startOfDay(for: .now)
    }
    private nonisolated static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// The phone's real answer, put back afterwards, so running these on a
    /// simulator does not leave it drawing nobody's week.
    private var savedHouseholdOwner: String?
    private var conversionAssetURLs: [URL] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        savedHouseholdOwner = PlanLedger.shared.householdOwner
        PlanLedger.shared.clear()
        PlanShare.forgetEdits()
        PlanLedger.shared.householdOwner = "host"
    }

    override func tearDown() async throws {
        PlanShare.forgetEdits()
        PlanLedger.shared.clear()
        PlanLedger.shared.householdOwner = savedHouseholdOwner
        for url in conversionAssetURLs { try? FileManager.default.removeItem(at: url) }
        conversionAssetURLs.removeAll()
        container = nil
    }

    // MARK: Fingerprint

    private func fingerprint(
        title: String = "Tacos", cookedAt: Date? = nil, minutes: Int = 35, cookID: String = "riley"
    ) -> String {
        PlanShare.fingerprint(
            day: "2026-09-10", slot: "dinner", title: title, servings: 4,
            cookID: cookID, cookName: "Riley Park", cookSeat: "joined", tagline: "Kids pick",
            cooked: cookedAt != nil, cookedAt: cookedAt, hasRecipe: true,
            recipeMinutes: minutes, recipeOriginKey: ""
        )
    }

    func testTheFingerprintIsStableAndCarriesNoPipe() {
        let a = fingerprint(title: "Tacos | al pastor")
        XCTAssertEqual(a, fingerprint(title: "Tacos | al pastor"), "the same night hashes the same")
        XCTAssertFalse(a.isEmpty)
        XCTAssertFalse(a.contains("|"), "the news splits its keys on a pipe")
        XCTAssertTrue(a.allSatisfy(\.isHexDigit))
    }

    func testEveryFingerprintedFieldMoves() {
        let base = fingerprint()
        XCTAssertNotEqual(base, fingerprint(title: "Ragu"))
        XCTAssertNotEqual(base, fingerprint(minutes: 40))
        XCTAssertNotEqual(base, fingerprint(cookID: "sam"))
        XCTAssertNotEqual(base, fingerprint(cookedAt: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    // MARK: The night off a PlannedMeal

    private func member(
        _ name: String, role: String = "member", seat: HouseholdMember.Seat, participant: String? = nil
    ) -> HouseholdMember {
        let m = HouseholdMember(name: name, colorHex: "3DA35D", role: role, seat: seat)
        m.participantID = participant
        context.insert(m)
        return m
    }

    private func meal(
        on date: Date = day(2), title: String = "Tacos", recipe: Recipe? = nil, cook: HouseholdMember? = nil
    ) -> PlannedMeal {
        let m = PlannedMeal(date: date, recipe: recipe, customTitle: title, cook: cook, tagline: "Kids pick")
        context.insert(m)
        return m
    }

    func testTheCookTravelsByParticipantID() {
        let riley = member("Riley Park", role: "partner", seat: .joined, participant: "_riley")
        let night = meal(cook: riley)
        let plan = PlanShare.plan(for: night, me: "_me", authorName: "Nate Meadows", authorColorHex: "FF5A3C")
        XCTAssertEqual(plan.cookID, "_riley")
        XCTAssertEqual(plan.cookName, "Riley Park")
        XCTAssertEqual(plan.cookSeat, HouseholdMember.Seat.joined.rawValue)
        XCTAssertEqual(plan.cookColorHex, "3DA35D")
        XCTAssertEqual(plan.authorID, "_me")
        XCTAssertEqual(plan.authorName, "Nate Meadows")
        XCTAssertEqual(plan.recordName, "plan-\(night.shoppingID ?? "")")
        XCTAssertEqual(plan.shoppingID, night.shoppingID)
        XCTAssertEqual(plan.title, "Tacos")
        XCTAssertEqual(plan.tagline, "Kids pick")
        XCTAssertEqual(plan.servings, 4)
        XCTAssertFalse(plan.cooked)
        XCTAssertNil(plan.cookedAt)
    }

    func testTheOwnerCookingIsThisPhonesOwnID() {
        let nate = member("Nate Meadows", role: "owner", seat: .head)
        let plan = PlanShare.plan(for: meal(cook: nate), me: "_me")
        XCTAssertEqual(plan.cookID, "_me", "the head has no participant row; the phone's own id stands in")
        XCTAssertEqual(plan.cookName, "Nate Meadows")
        XCTAssertEqual(plan.cookSeat, HouseholdMember.Seat.head.rawValue)
    }

    func testAnInvitedSeatIsNotACook() {
        let sam = member("Sam Okafor", seat: .invited)
        let plan = PlanShare.plan(for: meal(cook: sam), me: "_me")
        XCTAssertEqual(plan.cookName, "", "a name typed five seconds ago is not a cook")
        XCTAssertEqual(plan.cookID, "")
        XCTAssertEqual(plan.cookSeat, HouseholdMember.Seat.invited.rawValue)
    }

    func testAMemberWithNoIdentityAndNoOwnershipNamesNobodyByID() {
        let kid = member("Ada", seat: .notOnPlated)
        let plan = PlanShare.plan(for: meal(cook: kid), me: "_me")
        XCTAssertEqual(plan.cookID, "", "a reader never guesses who a kid is")
        XCTAssertEqual(plan.cookName, "Ada")
        XCTAssertEqual(plan.cookSeat, HouseholdMember.Seat.notOnPlated.rawValue)
    }

    func testANightWithNoCookIsBlankAboutIt() {
        let plan = PlanShare.plan(for: meal(), me: "_me")
        XCTAssertEqual(plan.cookID, "")
        XCTAssertEqual(plan.cookName, "")
        XCTAssertEqual(plan.cookSeat, "")
        XCTAssertEqual(plan.cookColorHex, "")
    }

    func testTheDayIsACalendarStringNotAMoment() {
        let date = Self.day(3)
        let plan = PlanShare.plan(for: meal(on: date), me: "_me")
        XCTAssertEqual(plan.day, PlanDay.string(date))
        XCTAssertEqual(PlanDay.date(plan.day), date, "the string names the same night on the way back")
        XCTAssertEqual(plan.slot, MealSlot.dinner.rawValue)
    }

    func testARecipeTravelsWithAStableHouseholdCookingKey() {
        let recipe = Recipe(title: "Sheet-pan chicken", prepMinutes: 10, cookMinutes: 25)
        context.insert(recipe)
        let with = PlanShare.plan(for: meal(title: "", recipe: recipe), me: "_me")
        XCTAssertTrue(with.hasRecipe)
        XCTAssertEqual(with.recipeMinutes, 35)
        XCTAssertEqual(with.recipeOriginKey, recipe.planningKey, "a home-written household recipe has a stable cooking link")
        XCTAssertEqual(with.title, "Sheet-pan chicken", "the recipe's title when the night has no name of its own")
        let without = PlanShare.plan(for: meal(), me: "_me")
        XCTAssertFalse(without.hasRecipe)
        XCTAssertEqual(without.recipeMinutes, 0)
        XCTAssertNil(without.photoData)
    }

    func testASavedRecipeCarriesItsOriginAndItsPhotoBytes() {
        let recipe = Recipe(title: "Ragu")
        recipe.originID = "post-abc"
        recipe.photoData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        context.insert(recipe)
        let plan = PlanShare.plan(for: meal(recipe: recipe), me: "_me")
        XCTAssertEqual(plan.recipeOriginKey, "post-abc")
        XCTAssertEqual(plan.photoCount, 4, "fingerprinted on the source bytes, never decoded here")
    }

    func testACookedNightSaysSo() {
        let night = meal(on: Self.day(-1))
        night.cookedAt = Self.day(-1)
        let plan = PlanShare.plan(for: night, me: "_me")
        XCTAssertTrue(plan.cooked)
        XCTAssertEqual(plan.cookedAt, Self.day(-1))
    }

    // MARK: Diff

    private func night(
        _ name: String, day: Date, title: String = "Tacos", photo: Data? = nil
    ) -> PlanShare.Plan {
        PlanShare.Plan(
            recordName: "plan-\(name)", shoppingID: name,
            authorID: "_me", authorName: "Nate", authorColorHex: "FF5A3C",
            cookID: "", cookName: "", cookColorHex: "", cookSeat: "",
            day: PlanDay.string(day), slot: MealSlot.dinner.rawValue, title: title,
            servings: 4, tagline: "", cooked: false, cookedAt: nil,
            hasRecipe: false, recipeMinutes: 0, recipeOriginKey: "",
            createdAt: .now, photoData: photo
        )
    }

    private func entry(_ plan: PlanShare.Plan, zone: String = "host") -> PlanShare.BookEntry {
        PlanShare.BookEntry(
            fingerprint: plan.fingerprint, photoCount: plan.photoCount,
            zoneOwner: zone, day: plan.day, slot: plan.slot
        )
    }

    func testANightTheBookHasNeverSeenIsCreatedOutright() {
        let tacos = night("a", day: Self.day(2))
        let work = PlanShare.diff(book: [:], meals: [tacos], target: "host")
        XCTAssertEqual(work.save.map(\.plan.recordName), ["plan-a"])
        XCTAssertFalse(work.save[0].known)
        XCTAssertTrue(work.save[0].sendPhoto)
        XCTAssertTrue(work.delete.isEmpty)
        XCTAssertTrue(work.ageOut.isEmpty)
    }

    func testAnUnchangedNightIsLeftAlone() {
        let tacos = night("a", day: Self.day(2), photo: Data([1, 2, 3]))
        let book = ["plan-a": entry(tacos)]
        XCTAssertTrue(PlanShare.diff(book: book, meals: [tacos], target: "host").isEmpty)
    }

    func testAChangedNightIsFetchedFirstAndKeepsItsPhoto() {
        let before = night("a", day: Self.day(2), title: "Tacos", photo: Data([1, 2, 3]))
        let after = night("a", day: Self.day(2), title: "Ragu", photo: Data([1, 2, 3]))
        let work = PlanShare.diff(book: ["plan-a": entry(before)], meals: [after], target: "host")
        XCTAssertEqual(work.save.count, 1)
        XCTAssertTrue(work.save[0].known, "a known name is fetched by name before it is saved")
        XCTAssertFalse(work.save[0].sendPhoto, "the photo did not change, so readers keep what they have")
    }

    func testAChangedPhotoGoesOutAgain() {
        let before = night("a", day: Self.day(2), photo: Data([1, 2, 3]))
        let after = night("a", day: Self.day(2), photo: Data([1, 2, 3, 4]))
        let work = PlanShare.diff(book: ["plan-a": entry(before)], meals: [after], target: "host")
        XCTAssertEqual(work.save.count, 1)
        XCTAssertTrue(work.save[0].sendPhoto)
        let removed = night("a", day: Self.day(2), photo: nil)
        let cleared = PlanShare.diff(book: ["plan-a": entry(before)], meals: [removed], target: "host")
        XCTAssertTrue(cleared.save[0].sendPhoto, "a photo taken off the recipe is cleared on the wire too")
    }

    func testANightTakenOffIsDeleted() {
        let gone = night("a", day: Self.day(1))
        let kept = night("b", day: Self.day(3))
        let book = ["plan-a": entry(gone), "plan-b": entry(kept)]
        let work = PlanShare.diff(book: book, meals: [kept], target: "host")
        XCTAssertEqual(work.delete, ["plan-a"])
        XCTAssertTrue(work.save.isEmpty)
        XCTAssertTrue(work.ageOut.isEmpty)
    }

    func testANightTakenOffInsideTheWeekBehindIsStillADelete() {
        let recent = night("a", day: Self.day(-6))
        let work = PlanShare.diff(book: ["plan-a": entry(recent)], meals: [], target: "host")
        XCTAssertEqual(work.delete, ["plan-a"], "seven days back is inside the window, so its absence means taken off")
    }

    func testAnOldNightAgesOutAndAMiddleAgedOneWaits() {
        let ancient = night("a", day: Self.day(-31))
        let middle = night("b", day: Self.day(-15))
        let book = ["plan-a": entry(ancient), "plan-b": entry(middle)]
        let work = PlanShare.diff(book: book, meals: [], target: "host")
        XCTAssertEqual(work.ageOut, ["plan-a"], "more than thirty days past leaves the zone")
        XCTAssertTrue(work.delete.isEmpty, "out of the window but not yet old is nobody's business")
    }

    func testAFlippedZoneRepublishesIntoTheNewTable() {
        let tacos = night("a", day: Self.day(2), photo: Data([1, 2, 3]))
        let work = PlanShare.diff(book: ["plan-a": entry(tacos, zone: "old-host")], meals: [tacos], target: "new-host")
        XCTAssertEqual(work.save.count, 1)
        XCTAssertTrue(work.save[0].known)
        XCTAssertTrue(work.save[0].sendPhoto, "the new table has never seen the photo")
    }

    func testSavesComeNearestNightFirst() {
        let later = night("z", day: Self.day(5))
        let sooner = night("a", day: Self.day(1))
        let work = PlanShare.diff(book: [:], meals: [later, sooner], target: "host")
        XCTAssertEqual(work.save.map(\.plan.recordName), ["plan-a", "plan-z"], "a capped pass sends what matters")
    }

    // MARK: Which zone is the household's

    func testAnEmptyOwnShareYieldsToTheJoinedTable() {
        let choice = TableShare.chooseHousehold(
            ownShareAccepted: false, ownAcceptedParticipantIDs: [],
            joinedOwners: ["_host"], stored: nil, me: "_me"
        )
        XCTAssertEqual(choice, .resolved("_host"), "a zone minted by onboarding is not a table")
    }

    func testAnAcceptedOwnShareWithNoJoinedTableIsTheHousehold() {
        let choice = TableShare.chooseHousehold(
            ownShareAccepted: true, ownAcceptedParticipantIDs: ["_riley"],
            joinedOwners: [], stored: nil, me: "_me"
        )
        XCTAssertEqual(choice, .resolved(""))
    }

    func testNoCandidateIsNone() {
        let choice = TableShare.chooseHousehold(
            ownShareAccepted: false, ownAcceptedParticipantIDs: [],
            joinedOwners: [], stored: "", me: "_me"
        )
        XCTAssertEqual(choice, .none)
    }

    func testAStoredChoiceStillACandidateWins() {
        let choice = TableShare.chooseHousehold(
            ownShareAccepted: true, ownAcceptedParticipantIDs: ["_riley"],
            joinedOwners: ["_host"], stored: "_host", me: "_me"
        )
        XCTAssertEqual(choice, .resolved("_host"))
        let own = TableShare.chooseHousehold(
            ownShareAccepted: true, ownAcceptedParticipantIDs: ["_riley"],
            joinedOwners: ["_host"], stored: "", me: "_me"
        )
        XCTAssertEqual(own, .resolved(""))
    }

    func testAStoredChoiceThatIsNoLongerACandidateDoesNotCount() {
        let choice = TableShare.chooseHousehold(
            ownShareAccepted: true, ownAcceptedParticipantIDs: ["_riley"],
            joinedOwners: ["_host"], stored: "_gone", me: "_me"
        )
        XCTAssertEqual(choice, .unresolved(["", "_host"]))
    }

    func testMutualInvitesPickTheSmallestOwnerOnBothPhones() {
        // A and B each accepted the other's share. On A's phone the own
        // zone is "" and B is joined; on B's, the reverse. Both must land
        // on A's table.
        let onA = TableShare.chooseHousehold(
            ownShareAccepted: true, ownAcceptedParticipantIDs: ["_b"],
            joinedOwners: ["_b"], stored: nil, me: "_a"
        )
        XCTAssertEqual(onA, .resolved(""), "A's own table is the smaller id")
        let onB = TableShare.chooseHousehold(
            ownShareAccepted: true, ownAcceptedParticipantIDs: ["_a"],
            joinedOwners: ["_a"], stored: nil, me: "_b"
        )
        XCTAssertEqual(onB, .resolved("_a"))
    }

    func testAJoinedTableWhoseHostIsNotAtMineIsNotMutual() {
        let choice = TableShare.chooseHousehold(
            ownShareAccepted: true, ownAcceptedParticipantIDs: ["_riley"],
            joinedOwners: ["_host"], stored: nil, me: "_me"
        )
        XCTAssertEqual(choice, .unresolved(["", "_host"]), "two rooms and no rule that picks one")
    }

    func testSeveralJoinedTablesWithNoChoiceAreUnresolved() {
        let choice = TableShare.chooseHousehold(
            ownShareAccepted: false, ownAcceptedParticipantIDs: [],
            joinedOwners: ["_host", "_other"], stored: nil, me: "_me"
        )
        XCTAssertEqual(choice, .unresolved(["_host", "_other"]))
    }

    // MARK: Changing a night somebody else planned

    /// A night in the household ledger, planned by somebody else, exactly as
    /// a delivery would leave it.
    @discardableResult
    private func remoteNight(
        id: String = "n1", author: String = "_riley", authorName: String = "Riley Park",
        day: Date = day(2), title: String = "Tacos", changedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> PlanLedger.Entry {
        var plan = TableShare.RemotePlan()
        plan.recordName = "plan-\(id)"
        plan.shoppingID = id
        plan.zoneOwner = "host"
        plan.authorID = author
        plan.authorName = authorName
        plan.day = PlanDay.string(day)
        plan.slot = MealSlot.dinner.rawValue
        plan.title = title
        plan.servings = 4
        plan.createdAt = changedAt
        plan.changedAt = changedAt
        var changes = TableShare.Changes()
        changes.plans = [plan]
        PlanLedger.shared.absorb(changes, me: "_me")
        return PlanLedger.shared.entry("plan-\(id)")!
    }

    func testSharedCookingCompletionKeepsIdentityAndSurvivesQueuedFolds() throws {
        let night = remoteNight()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        var completion = PlanShare.Edit(changing: night)
        completion.cooked = true; completion.cookedAt = stamp
        PlanShare.enqueue(completion)
        var later = PlanShare.Edit(changing: night); later.tagline = "Together"
        PlanShare.enqueue(later)
        PlanShare.reloadEdits()
        let edit = try XCTUnwrap(PlanShare.queuedEdits().first)
        XCTAssertEqual(edit.cooked, true); XCTAssertEqual(edit.cookedAt, stamp)
        let applied = PlanLedger.edited(night, by: edit)
        XCTAssertTrue(applied.cooked); XCTAssertEqual(applied.recordName, night.recordName)
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let (record, _) = PlanShare.record(for: edit, existing: nil, zone: zone, now: stamp)
        XCTAssertEqual(TableShare.int(record, "cooked"), 1)
        XCTAssertEqual(record["cookedAt"] as? Date, stamp)
    }

    func testAuthorCanAdoptHouseholdCookingCompletionWithoutAnAutomaticModelWrite() throws {
        defer { HouseholdEdits.clear() }
        HouseholdEdits.clear()
        let local = meal(on: Self.day(2)); local.shoppingID = "n1"
        var remote = remoteNight()
        remote.cooked = true; remote.cookedAt = Date(timeIntervalSince1970: 1_800_000_000)
        HouseholdEdits.note([remote])
        XCTAssertNil(local.cookedAt, "A delivery cannot silently overwrite the author's model")
        let change = try XCTUnwrap(HouseholdEdits.pending(shoppingID: "n1"))
        XCTAssertTrue(HouseholdEdits.adopt(change, in: context))
        XCTAssertEqual(local.cookedAt, remote.cookedAt)
    }

    func testDragCannotMoveOrSwapIntoARemoteOccupiedNight() throws {
        let source = meal(on: Self.day(1))
        let target = meal(on: Self.day(2))
        try context.save()
        remoteNight(day: Self.day(2))
        XCTAssertFalse(MealPlanMove.perform(MealPlanTransfer.token(for: source), to: Self.day(2), meals: [source, target], context: context))
        XCTAssertEqual(source.date, Self.day(1))
        XCTAssertEqual(target.date, Self.day(2))
    }

    func testSharedOccupancyAndCookedCountsUseBothAuthoritiesWithoutDuplicates() {
        let date = Self.day(2)
        var remote = remoteNight(day: date)
        XCTAssertNotNil(PlanOccupancy.shared(on: date, slot: .dinner, entries: [remote]))
        XCTAssertNil(PlanOccupancy.shared(on: date, slot: .lunch, entries: [remote]))
        let local = meal(on: date)
        local.shoppingID = "n1"
        let past = meal(on: Self.day(-2))
        XCTAssertEqual(HouseholdDinnerMetrics(local: [local, past], shared: [remote]).cookedCount, 0)
        remote.cooked = true
        let metrics = HouseholdDinnerMetrics(local: [local, past], shared: [remote])
        XCTAssertEqual(metrics.cookedCount, 1)
        XCTAssertEqual(metrics.plannedDates.count, 2)
        local.cookedAt = .now
        XCTAssertEqual(HouseholdDinnerMetrics(local: [local, past], shared: [remote]).cookedCount, 1)
    }

    func testAnEditMintsTheRecordForANightTheZoneNoLongerHolds() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        edit.servings = 6
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        let (record, temp) = PlanShare.record(for: edit, existing: nil, zone: zone, now: now)
        XCTAssertNil(temp, "no photo went with this edit")
        XCTAssertEqual(record.recordType, TableShare.planType)
        XCTAssertEqual(record.recordID.recordName, "plan-n1")
        XCTAssertEqual(record["title"] as? String, "Ragu")
        XCTAssertEqual(TableShare.int(record, "servings"), 6)
        XCTAssertEqual(record["day"] as? String, night.day)
        XCTAssertEqual(record["slot"] as? String, MealSlot.dinner.rawValue)
        XCTAssertEqual(record["shoppingID"] as? String, "n1", "the name carries the id; nothing mints a second one")
        XCTAssertEqual(record["modifiedAt"] as? Date, now)
        XCTAssertEqual(
            record["authorID"] as? String, "_riley",
            "the night keeps its author: a record authored by the editor is dropped by the editor's own ledger"
        )
        XCTAssertEqual(record["authorName"] as? String, "Riley Park")
        // Both links, or a member cannot see it at all.
        XCTAssertEqual(record.parent?.recordID.recordName, TableShare.householdRootName)
        XCTAssertEqual((record["parent"] as? CKRecord.Reference)?.action, .deleteSelf)
        // Every key primed, so none of them is first minted from nothing.
        XCTAssertEqual(record["cookID"] as? String, "")
        XCTAssertEqual(TableShare.int(record, "cooked"), 0)
        XCTAssertEqual(TableShare.int(record, "hasRecipe"), 0)
    }

    func testAnEditOnlyTouchesTheFieldsThePersonChanged() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.cookID = "_sam"
        edit.cookName = "Sam Okafor"
        edit.cookSeat = HouseholdMember.Seat.joined.rawValue
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let served = CKRecord(
            recordType: TableShare.planType,
            recordID: CKRecord.ID(recordName: "plan-n1", zoneID: zone)
        )
        served["title"] = "Tacos" as CKRecordValue
        served["tagline"] = "Kids pick" as CKRecordValue
        let (record, _) = PlanShare.record(for: edit, existing: served, zone: zone, now: .now)
        XCTAssertEqual(record["cookID"] as? String, "_sam")
        XCTAssertEqual(record["title"] as? String, "Tacos", "a field nobody touched is left as the zone has it")
        XCTAssertEqual(record["tagline"] as? String, "Kids pick")
    }

    func testAnUnreadableIngredientListIsClearedRatherThanLeftUnderNewServings() {
        // Leaving it stands the old servings' quantities under the new
        // servings: a list that is confidently wrong, which is worse than
        // one that is short.
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.servings = 8
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let served = CKRecord(
            recordType: TableShare.planType,
            recordID: CKRecord.ID(recordName: "plan-n1", zoneID: zone)
        )
        served["servings"] = 4 as CKRecordValue
        served["lines"] = "{ not json" as CKRecordValue
        let (record, _) = PlanShare.record(for: edit, existing: served, zone: zone, now: .now)
        XCTAssertEqual(record["lines"] as? String, "[]")
    }

    func testARescaleRoundTripDoesNotLookLikeAChangedNight() {
        // 4 to 6 to 4 does not return the original bytes, and at full
        // precision that drift republishes a window nobody touched.
        let meal = PlannedMeal(date: Self.day(1), recipe: nil, customTitle: "Ragu")
        context.insert(meal)
        var plan = PlanShare.plan(for: meal, me: "_me")
        plan.lines = [PlanShare.Line(name: "Beef mince", normalizedName: "beef mince",
                                     unit: "oz", quantity: 16, aisle: "Meat & Seafood",
                                     isPantryStaple: false)]
        let before = plan.linesKey
        plan.lines[0].quantity = plan.lines[0].quantity * 1.5 / 1.5
        XCTAssertEqual(before, plan.linesKey)
    }

    // MARK: A phone that has never published this night before

    func testAContestOnAPhoneWithNoBookIsRecordedRatherThanSwallowed() {
        // The publisher stands down when the fetched record names an editor
        // that is not this phone, and on a reinstall or a second device the
        // book is silent about EVERY night, so that is when it fires most.
        // Recording it is what makes the difference between a night that
        // waits and a week that silently never leaves the phone.
        PlanShare.forgetBook()
        XCTAssertNil(PlanShare.contest(for: "plan-n1"))
        PlanShare.recordContestForTesting(
            recordName: "plan-n1", day: PlanDay.string(Self.day(2)),
            slot: MealSlot.dinner.rawValue, zoneOwner: "host",
            by: "Riley Park", theirTitle: "Ragu", mineTitle: "Tacos"
        )
        let contest = PlanShare.contest(for: "plan-n1")
        XCTAssertNotNil(contest, "a fresh device records the stand-down")
        XCTAssertEqual(contest?.by, "Riley Park")
        XCTAssertEqual(contest?.theirTitle, "Ragu")
        XCTAssertEqual(contest?.mineTitle, "Tacos")
        PlanShare.forgetBook()
    }

    // MARK: A fold that arrives while the edit is on the wire

    func testAFoldDuringASendIsNotDroppedUnsentAndIsNotCalledASuccess() {
        // The drain used to drop the queue entry by record name after its
        // send, which deleted a change made while that send was in flight
        // and then handed its author the drain's own `.landed`. The sheet
        // closed on a success that never left the phone.
        let night = remoteNight()
        var first = PlanShare.Edit(changing: night)
        first.title = "Ragu"
        first.revision = PlanShare.enqueue(first)

        var second = PlanShare.Edit(changing: night)
        second.cookID = "_sam"
        second.cookName = "Sam Okafor"
        let folded = PlanShare.enqueue(second)
        XCTAssertEqual(folded, first.revision + 1, "a fold is a new version of the entry")

        let answer = PlanShare.settle(first, .landed(.now))
        guard case .queued = answer else {
            return XCTFail("the fold has not been sent, so this is not a success")
        }
        let queued = PlanShare.queuedEdits()
        XCTAssertEqual(queued.count, 1, "the fold stays queued rather than being dropped unsent")
        XCTAssertEqual(queued.first?.cookID, "_sam")
        XCTAssertEqual(queued.first?.title, "Ragu", "and still carries the version that did go out")
    }

    func testAnEditNothingFoldedOntoStillLeavesTheQueueOnLanding() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        edit.revision = PlanShare.enqueue(edit)
        let answer = PlanShare.settle(edit, .landed(.now))
        guard case .landed = answer else { return XCTFail("nothing folded, so it landed") }
        XCTAssertTrue(PlanShare.queuedEdits().isEmpty, "and the entry is gone")
    }

    func testTwoVersionsOfOneNightAreAnsweredSeparately() {
        // The reason `answers` is keyed by revision: a caller must never be
        // able to read a different version's outcome as its own.
        let night = remoteNight()
        var first = PlanShare.Edit(changing: night)
        first.revision = 0
        var second = first
        second.revision = 1
        XCTAssertNotEqual(PlanShare.answerKey(first), PlanShare.answerKey(second))
    }

    func testChangingTheServingsRescalesTheNightsIngredients() {
        // The edit path does not write `lines`, and the editor's phone does
        // not have the author's recipe, so without this a member doubling a
        // night left the household shopping for the old quantities: a list
        // quietly disagreeing with a change the person watched land.
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.servings = 8
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let served = CKRecord(
            recordType: TableShare.planType,
            recordID: CKRecord.ID(recordName: "plan-n1", zoneID: zone)
        )
        served["servings"] = 4 as CKRecordValue
        served["lines"] = (TableShare.encodeLines([
            PlanShare.Line(name: "Beef mince", normalizedName: "beef mince", unit: "oz",
                           quantity: 16, aisle: "Meat & Seafood", isPantryStaple: false)
        ]) ?? "[]") as CKRecordValue
        let (record, _) = PlanShare.record(for: edit, existing: served, zone: zone, now: .now)
        let lines = TableShare.decodeLines(record["lines"] as? String)
        XCTAssertEqual(lines.first?.quantity, 32, "doubling the servings doubles the mince")
        XCTAssertEqual(lines.first?.unit, "oz", "and does not change what it is measured in")
    }

    func testAnEditThatLeavesTheServingsAloneLeavesTheIngredientsAlone() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: "host")
        let served = CKRecord(
            recordType: TableShare.planType,
            recordID: CKRecord.ID(recordName: "plan-n1", zoneID: zone)
        )
        served["servings"] = 4 as CKRecordValue
        let json = TableShare.encodeLines([
            PlanShare.Line(name: "Beef mince", normalizedName: "beef mince", unit: "oz",
                           quantity: 16, aisle: "Meat & Seafood", isPantryStaple: false)
        ]) ?? "[]"
        served["lines"] = json as CKRecordValue
        let (record, _) = PlanShare.record(for: edit, existing: served, zone: zone, now: .now)
        XCTAssertEqual(record["lines"] as? String, json)
    }

    func testAServerVersionThisEditDidNotDescendFromWins() {
        let night = remoteNight()
        let edit = PlanShare.Edit(changing: night)
        XCTAssertFalse(
            PlanShare.movedOn(night.changedAt, since: edit.seenAt),
            "the version this edit was made against is not a conflict"
        )
        XCTAssertFalse(
            PlanShare.movedOn(night.changedAt.addingTimeInterval(0.2), since: edit.seenAt),
            "a date that went to CloudKit and came back is not a different version"
        )
        XCTAssertTrue(PlanShare.movedOn(night.changedAt.addingTimeInterval(90), since: edit.seenAt))
        XCTAssertTrue(PlanShare.movedOn(.now, since: nil), "an edit that expected no record, on a record that is there")

        // What the write does with that answer: their version, and the row
        // this phone was holding is gone.
        var theirs = TableShare.RemotePlan()
        theirs.recordName = night.recordName
        theirs.zoneOwner = "host"
        theirs.authorID = "_riley"
        theirs.authorName = "Riley Park"
        theirs.day = night.day
        theirs.slot = night.slot
        theirs.title = "Ragu"
        theirs.changedAt = night.changedAt.addingTimeInterval(90)
        var mine = edit
        mine.title = "Katsu"
        PlanLedger.shared.applyLocally(mine)
        XCTAssertEqual(PlanLedger.shared.entry(night.recordName)?.title, "Katsu")
        PlanLedger.shared.fold(theirs)
        PlanLedger.shared.settle(mine, .theirs)
        XCTAssertEqual(PlanLedger.shared.entry(night.recordName)?.title, "Ragu")
        XCTAssertNil(
            PlanLedger.shared.entry(night.recordName)?.pendingSince,
            "nothing of this phone's is still on its way"
        )
    }

    func testTakingANightOffKeepsTheRowUntilTheDeleteLands() {
        let night = remoteNight()
        let edit = PlanShare.Edit(deleting: night)
        PlanShare.enqueue(edit)
        let going = PlanLedger.shared.applyLocally(edit)
        // The row stays, saying what is true: the night is still on every
        // other phone until this delete goes.
        XCTAssertNotNil(going, "an offline delete that removes the row tells nobody")
        XCTAssertTrue(going?.isGoing == true)
        XCTAssertEqual(going?.pendingSince, edit.at)
        XCTAssertEqual(going?.pendingLine, "Still on the other phones")
        XCTAssertEqual(
            PlanLedger.shared.plans(on: Self.day(2)).map(\.recordName), [night.recordName],
            "a night still on the plan is still counted by everything that counts nights"
        )
        XCTAssertEqual(PlanShare.queuedEdits().map(\.kind), [.delete])
        // A later change cannot resurrect it: a night taken off is off.
        var later = PlanShare.Edit(changing: night)
        later.title = "Ragu"
        PlanShare.enqueue(later)
        XCTAssertEqual(PlanShare.queuedEdits().count, 1)
        XCTAssertEqual(PlanShare.queuedEdits().first?.kind, .delete)
        PlanLedger.shared.settle(edit, .landed(.now))
        XCTAssertNil(PlanLedger.shared.entry(night.recordName), "now it has really gone, so now the row goes")
    }

    func testARefusedDeletePutsTheNightBackWithNothingClaimed() {
        let night = remoteNight()
        let edit = PlanShare.Edit(deleting: night)
        PlanLedger.shared.applyLocally(edit)
        PlanLedger.shared.settle(edit, .refused("This change could not reach your household."))
        let after = PlanLedger.shared.entry(night.recordName)
        XCTAssertEqual(after?.title, "Tacos", "the night is what it was")
        XCTAssertNil(after?.pendingSince)
        XCTAssertFalse(after?.isGoing == true)
    }

    func testARowGoingOffWithNothingQueuedStopsSayingSo() {
        let night = remoteNight()
        let edit = PlanShare.Edit(deleting: night)
        PlanLedger.shared.applyLocally(edit)
        // A kill between the ledger write and the queue write: the mark is
        // there with nothing to send it, and the night is simply on.
        PlanLedger.shared.clearPending(except: [])
        let after = PlanLedger.shared.entry(night.recordName)
        XCTAssertNotNil(after)
        XCTAssertFalse(after?.isGoing == true)
        XCTAssertNil(after?.pendingLine)
    }

    func testAQueuedEditSurvivesTheAppBeingKilled() throws {
        try XCTSkipIf(
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID) == nil,
            "no app group container on this host, so nothing here can persist"
        )
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        edit.servings = 6
        PlanShare.enqueue(edit)
        // The relaunch: nothing in memory, everything off the disk.
        PlanShare.reloadEdits()
        let waiting = PlanShare.queuedEdits()
        XCTAssertEqual(waiting.count, 1)
        XCTAssertEqual(waiting.first?.title, "Ragu")
        XCTAssertEqual(waiting.first?.servings, 6)
        XCTAssertEqual(waiting.first?.seenAt, night.changedAt, "the version it was made against travels with it")
    }

    func testTwoEditsOfOneNightFoldAndKeepTheVersionThePersonStartedFrom() {
        let night = remoteNight()
        var first = PlanShare.Edit(changing: night)
        first.title = "Ragu"
        PlanShare.enqueue(first)
        var second = PlanShare.Edit(changing: night)
        second.seenAt = night.changedAt.addingTimeInterval(600)
        second.servings = 8
        PlanShare.enqueue(second)
        let waiting = PlanShare.queuedEdits()
        XCTAssertEqual(waiting.count, 1, "one night is one entry")
        XCTAssertEqual(waiting.first?.title, "Ragu", "the earlier field is still going out")
        XCTAssertEqual(waiting.first?.servings, 8)
        XCTAssertEqual(waiting.first?.seenAt, night.changedAt, "the version the person started from is the one to compare")
    }

    func testTheRowMovesAtOnceAndSaysItHasNotLandedUntilItHas() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        edit.servings = 6
        edit.at = Date(timeIntervalSince1970: 1_700_050_000)
        PlanShare.enqueue(edit)
        let applied = PlanLedger.shared.applyLocally(edit)
        XCTAssertEqual(applied?.title, "Ragu")
        XCTAssertEqual(applied?.servings, 6)
        XCTAssertEqual(applied?.pendingSince, edit.at, "a queued write is not a landed write")

        let landed = Date(timeIntervalSince1970: 1_700_050_030)
        PlanLedger.shared.settle(edit, .landed(landed))
        let after = PlanLedger.shared.entry(night.recordName)
        XCTAssertNil(after?.pendingSince)
        XCTAssertEqual(
            after?.changedAt, landed,
            "the ledger takes the record's own clock, or this phone's own edit comes back reading as news"
        )
    }

    /// The row moving under the finger may not move the clock the next edit
    /// is compared against. `Edit.seenAt` is the entry's `changedAt`, so an
    /// optimistic stamp there made the write read the record's real
    /// `modifiedAt` as somebody else's version: the person was told "This
    /// night changed on another phone first" about their own previous tap,
    /// and the servings stepper, which applies locally and then writes,
    /// said it on the first tap every time.
    func testAnOptimisticRowDoesNotMoveTheVersionTheNextEditComparesAgainst() {
        let night = remoteNight()
        var first = PlanShare.Edit(changing: night)
        first.title = "Ragu"
        first.at = Date(timeIntervalSince1970: 1_700_050_000)
        PlanLedger.shared.applyLocally(first)

        guard let moved = PlanLedger.shared.entry(night.recordName) else {
            return XCTFail("the row is still in the ledger while its change is queued")
        }
        XCTAssertEqual(moved.title, "Ragu", "the row moved")
        XCTAssertEqual(moved.changedAt, night.changedAt, "the record's clock did not")

        let second = PlanShare.Edit(changing: moved)
        XCTAssertEqual(second.seenAt, night.changedAt)
        XCTAssertFalse(
            PlanShare.movedOn(night.changedAt, since: second.seenAt),
            "nobody else touched this night, so nothing may tell the person they did"
        )
    }

    func testARefusedEditPutsTheNightBack() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        PlanLedger.shared.applyLocally(edit)
        XCTAssertEqual(PlanLedger.shared.entry(night.recordName)?.title, "Ragu")
        PlanLedger.shared.settle(edit, .refused("This night is at a household this phone has left."))
        let after = PlanLedger.shared.entry(night.recordName)
        XCTAssertEqual(after?.title, "Tacos", "the night is what it was")
        XCTAssertNil(after?.pendingSince)
    }

    /// The delete is on this phone's queue, so the record is still in the
    /// zone; the delivery that carries it back must not be read as somebody
    /// planning the night the reader just took off.
    func testANightOnItsWayOffIsNotDeliveredBackAsNews() {
        let night = remoteNight()
        let edit = PlanShare.Edit(deleting: night)
        PlanShare.enqueue(edit)
        PlanLedger.shared.applyLocally(edit)
        XCTAssertTrue(PlanLedger.shared.entry(night.recordName)?.isGoing == true)

        var plan = TableShare.RemotePlan()
        plan.recordName = night.recordName
        plan.shoppingID = "n1"
        plan.zoneOwner = "host"
        plan.authorID = night.authorID
        plan.authorName = night.authorName
        plan.day = night.day
        plan.slot = night.slot
        plan.title = night.title
        plan.servings = night.servings
        plan.createdAt = night.createdAt
        plan.changedAt = night.changedAt
        var changes = TableShare.Changes()
        changes.plans = [plan]
        let delta = PlanLedger.shared.absorb(changes, me: "_me")

        XCTAssertTrue(delta.added.isEmpty, "a notice about the reader's own action is the rule that never bends")
        XCTAssertTrue(delta.changed.isEmpty)
        XCTAssertEqual(
            PlanLedger.shared.entry(night.recordName)?.pendingSince, edit.at,
            "the row comes back saying the change has not gone yet, which is what is true"
        )
        XCTAssertTrue(
            PlanLedger.shared.entry(night.recordName)?.isGoing == true,
            "and it still says it is the delete that has not gone"
        )
    }

    /// The night was taken off on another phone while this edit was being
    /// made. Minting the record back stands a ghost on every phone but the
    /// author's, because the mint carries the author and their publish book
    /// no longer holds the name.
    func testAnEditToANightSomebodyElseTookOffIsNotAMint() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        XCTAssertTrue(
            PlanShare.wasTakenOffElsewhere(edit),
            "a ledger entry exists only because the record was delivered, so an absent record was deleted"
        )
        var fresh = PlanShare.Edit(changing: night)
        fresh.seenAt = nil
        XCTAssertFalse(
            PlanShare.wasTakenOffElsewhere(fresh),
            "a night that never had a record is still a mint"
        )

        // What the write does with that answer: the night goes, and the
        // refusal that carries the sentence cannot put it back.
        PlanLedger.shared.applyLocally(edit)
        PlanLedger.shared.nightIsGone(night.recordName)
        PlanLedger.shared.settle(edit, .refused("That night was taken off the plan on another phone."))
        XCTAssertNil(
            PlanLedger.shared.entry(night.recordName),
            "the other person won: the deletion is their version and it stands"
        )
    }

    /// The publisher's pass and a person's edit write the same records in the
    /// same zone. Overlapping them let a pass land this phone's own edit while
    /// the write was on the wire, and the write then called its own drain
    /// somebody else.
    func testTheHouseholdZoneHasOneWriterAtATime() async {
        Self.writersInside = 0
        Self.mostAtOnce = 0
        async let first: Void = PlanShare.exclusively { await Self.pretendToWrite() }
        async let second: Void = PlanShare.exclusively { await Self.pretendToWrite() }
        async let third: Void = PlanShare.exclusively { await Self.pretendToWrite() }
        _ = await (first, second, third)
        XCTAssertEqual(Self.mostAtOnce, 1, "two writers in the zone is the false sentence being fixed")
        XCTAssertEqual(Self.writersInside, 0)
    }

    private static var writersInside = 0
    private static var mostAtOnce = 0

    /// Enters, gives every other task a turn, leaves.
    private static func pretendToWrite() async {
        writersInside += 1
        mostAtOnce = max(mostAtOnce, writersInside)
        for _ in 0..<5 { await Task.yield() }
        writersInside -= 1
    }

    func testAnEditDroppedAfterTwentyRefusalsIsNotReportedAsQueued() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        edit.tries = 20
        PlanShare.enqueue(edit)
        PlanLedger.shared.applyLocally(edit)
        let answer = PlanShare.settle(edit, .queued("Your household could not be reached. It goes out on the next try."))
        XCTAssertEqual(
            answer, .refused("This change could not reach your household."),
            "the person may not be told it goes out later while the row snaps back"
        )
        XCTAssertTrue(PlanShare.queuedEdits().isEmpty)
        XCTAssertEqual(PlanLedger.shared.entry(night.recordName)?.title, "Tacos")

        // One more refusal is still one refusal, and it says which.
        var again = PlanShare.Edit(changing: night)
        again.title = "Katsu"
        PlanShare.enqueue(again)
        let queued = PlanShare.settle(again, .queued("This night could not be read just now. It goes out on the next try."))
        XCTAssertEqual(queued, .queued("This night could not be read just now. It goes out on the next try."))
        XCTAssertEqual(PlanShare.queuedEdits().first?.tries, 1)
    }

    func testARefusalDoesNotPutANightBackIntoAHouseholdThisPhoneHasLeft() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        PlanLedger.shared.applyLocally(edit)
        // The re-home: this phone's household is somebody else's now and the
        // old table's nights are gone from the book.
        PlanLedger.shared.householdOwner = "other-host"
        PlanLedger.shared.forget(zoneOwner: "host")
        PlanLedger.shared.settle(edit, .refused("This night is at a household this phone has left."))
        XCTAssertNil(
            PlanLedger.shared.entry(night.recordName),
            "a night put back into a household this phone has left is dead data nothing will ever correct"
        )
    }

    func testARowThatSaysItIsOnItsWayWithNothingQueuedIsCorrected() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        PlanLedger.shared.applyLocally(edit)
        XCTAssertNotNil(PlanLedger.shared.entry(night.recordName)?.pendingSince)
        // A kill between the ledger write and the queue write leaves exactly
        // this: a row claiming a change is on its way with nothing to send it.
        PlanLedger.shared.clearPending(except: [])
        XCTAssertNil(PlanLedger.shared.entry(night.recordName)?.pendingSince)
    }

    // MARK: No-cooking choices preserve the night, not the old recipe

    private func completedRecipeNight() -> PlanLedger.Entry {
        var night = remoteNight()
        night.hasRecipe = true
        night.recipeMinutes = 35
        night.recipeOriginKey = "recipe-tacos"
        night.hasPhoto = true
        night.lines = [.init(name: "Beef", normalizedName: "beef", unit: "oz",
                             quantity: 16, aisle: "Meat & Seafood", isPantryStaple: false)]
        night.cookID = "_sam"
        night.cookName = "Sam Okafor"
        night.cookColorHex = "3DA35D"
        night.cookSeat = HouseholdMember.Seat.joined.rawValue
        night.cooked = true
        night.cookedAt = Date(timeIntervalSince1970: 1_800_000_000)
        night.tagline = "Kids pick"
        return night
    }

    private func recipeRecord(_ night: PlanLedger.Entry) throws -> CKRecord {
        let zone = CKRecordZone.ID(zoneName: TableShare.householdZoneName, ownerName: night.zoneOwner)
        let record = CKRecord(recordType: TableShare.planType,
                              recordID: CKRecord.ID(recordName: night.recordName, zoneID: zone))
        record["authorID"] = night.authorID as CKRecordValue
        record["authorName"] = night.authorName as CKRecordValue
        record["shoppingID"] = night.shoppingID as CKRecordValue
        record["day"] = night.day as CKRecordValue
        record["slot"] = night.slot as CKRecordValue
        record["title"] = night.title as CKRecordValue
        record["servings"] = night.servings as CKRecordValue
        record["tagline"] = night.tagline as CKRecordValue
        record["cookID"] = night.cookID as CKRecordValue
        record["cookName"] = night.cookName as CKRecordValue
        record["hasRecipe"] = (night.hasRecipe ? 1 : 0) as CKRecordValue
        record["recipeMinutes"] = night.recipeMinutes as CKRecordValue
        record["recipeOriginKey"] = night.recipeOriginKey as CKRecordValue
        record["lines"] = (TableShare.encodeLines(night.lines ?? []) ?? "[]") as CKRecordValue
        record["cooked"] = (night.cooked ? 1 : 0) as CKRecordValue
        record["cookedAt"] = night.cookedAt as CKRecordValue?
        record["createdAt"] = night.createdAt as CKRecordValue
        // record(for:) only manipulates the asset reference; no upload or
        // network access occurs in these tests.
        let photoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)
        conversionAssetURLs.append(photoURL)
        record["photo"] = CKAsset(fileURL: photoURL)
        return record
    }

    func testNoCookingChoiceEditPreservesTheNightAndClearsCookAndRecipeIntent() {
        let night = completedRecipeNight()
        for choice in [PlanMealChoice.leftovers, .eatingOut] {
            let edit = PlanShare.Edit(changing: night, mealChoice: choice)
            XCTAssertEqual(edit.recordName, night.recordName)
            XCTAssertEqual(edit.zoneOwner, night.zoneOwner)
            XCTAssertEqual(edit.day, night.day)
            XCTAssertEqual(edit.slot, night.slot)
            XCTAssertEqual(edit.seenAt, night.changedAt)
            XCTAssertEqual(edit.authorID, night.authorID)
            XCTAssertNil(edit.servings, "Choosing leftovers does not change how many people are eating")
            XCTAssertEqual(edit.title, choice.title)
            XCTAssertEqual(edit.tagline, choice.tagline)
            XCTAssertEqual(edit.cookID, "")
            XCTAssertEqual(edit.cookName, "")
            XCTAssertEqual(edit.cookColorHex, "")
            XCTAssertEqual(edit.cookSeat, "")
            XCTAssertEqual(edit.cooked, false)
            XCTAssertNil(edit.cookedAt)
            XCTAssertEqual(edit.hasRecipe, false)
            XCTAssertEqual(edit.photo, .clear)
        }
    }

    func testRemovingRecipeClearsOptimisticIngredientsArtworkAndMetadataWithoutTouchingOtherFields() {
        let night = completedRecipeNight()
        var edit = PlanShare.Edit(changing: night)
        edit.hasRecipe = false
        // Old queued recipe details may still be present; explicit removal wins.
        edit.recipeMinutes = 99
        edit.recipeOriginKey = "stale-recipe"
        edit.photo = .send
        edit.lines = night.lines
        let actual = PlanLedger.edited(night, by: edit)
        var expected = night
        expected.hasRecipe = false
        expected.lines = []
        expected.recipeMinutes = 0
        expected.recipeOriginKey = ""
        expected.hasPhoto = false
        XCTAssertEqual(actual, expected, "The removal must leave the author, cook, clock, date and completion alone unless explicitly changed")
    }

    func testRemovingRecipeClearsWireIngredientsArtworkAndMetadataButPreservesIdentity() throws {
        let night = completedRecipeNight()
        var edit = PlanShare.Edit(changing: night)
        edit.hasRecipe = false
        edit.recipeMinutes = 99
        edit.recipeOriginKey = "stale-recipe"
        edit.photo = .send
        edit.lines = night.lines
        let original = try recipeRecord(night)
        let (record, temp) = PlanShare.record(for: edit, existing: original,
                                             zone: original.recordID.zoneID, now: .now)
        XCTAssertTrue(record === original)
        XCTAssertNil(temp)
        XCTAssertEqual(TableShare.int(record, "hasRecipe"), 0)
        XCTAssertEqual(record["lines"] as? String, "[]")
        XCTAssertEqual(TableShare.int(record, "recipeMinutes"), 0)
        XCTAssertEqual(record["recipeOriginKey"] as? String, "")
        XCTAssertNil(record["photo"])
        XCTAssertEqual(record.recordID.recordName, night.recordName)
        XCTAssertEqual(record["shoppingID"] as? String, night.shoppingID)
        XCTAssertEqual(record["authorID"] as? String, night.authorID)
        XCTAssertEqual(record["authorName"] as? String, night.authorName)
        XCTAssertEqual(record["day"] as? String, night.day)
        XCTAssertEqual(record["slot"] as? String, night.slot)
        XCTAssertEqual(record["createdAt"] as? Date, night.createdAt)
        XCTAssertEqual(record["title"] as? String, night.title)
        XCTAssertEqual(TableShare.int(record, "servings"), night.servings)
        XCTAssertEqual(record["cookID"] as? String, night.cookID)
        XCTAssertEqual(record["tagline"] as? String, night.tagline)
        XCTAssertEqual(TableShare.int(record, "cooked"), 1)
        XCTAssertEqual(record["cookedAt"] as? Date, night.cookedAt)
    }

    func testExplicitNotCookedClearsTimestampInLedgerAndWireEvenWhenStaleTimestampTravelsWithIt() throws {
        let night = completedRecipeNight()
        var edit = PlanShare.Edit(changing: night)
        edit.cooked = false
        edit.cookedAt = night.cookedAt
        let actual = PlanLedger.edited(night, by: edit)
        var expected = night
        expected.cooked = false
        expected.cookedAt = nil
        XCTAssertEqual(actual, expected)
        let original = try recipeRecord(night)
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        XCTAssertEqual(TableShare.int(record, "cooked"), 0)
        XCTAssertNil(record["cookedAt"])
        XCTAssertEqual(TableShare.decodeLines(record["lines"] as? String), night.lines ?? [])
        XCTAssertEqual(record["recipeOriginKey"] as? String, night.recipeOriginKey)
        XCTAssertNotNil(record["photo"])
    }

    func testUnrelatedEditKeepsExistingRecipeAndCompletionInLedgerAndWire() throws {
        let night = completedRecipeNight()
        var edit = PlanShare.Edit(changing: night)
        edit.tagline = "Together"
        let actual = PlanLedger.edited(night, by: edit)
        var expected = night
        expected.tagline = "Together"
        XCTAssertEqual(actual, expected)
        let original = try recipeRecord(night)
        let photo = original["photo"] as? CKAsset
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        XCTAssertEqual(record["tagline"] as? String, "Together")
        XCTAssertEqual(TableShare.int(record, "cooked"), 1)
        XCTAssertEqual(record["cookedAt"] as? Date, night.cookedAt)
        XCTAssertEqual(TableShare.int(record, "hasRecipe"), 1)
        XCTAssertEqual(TableShare.decodeLines(record["lines"] as? String), night.lines ?? [])
        XCTAssertEqual(TableShare.int(record, "recipeMinutes"), night.recipeMinutes)
        XCTAssertEqual(record["recipeOriginKey"] as? String, night.recipeOriginKey)
        XCTAssertEqual((record["photo"] as? CKAsset)?.fileURL, photo?.fileURL)
    }

    func testExplicitRecipeAndCookedTrueKeepIngredientsAndAcceptNewCompletion() throws {
        var night = completedRecipeNight()
        night.cooked = false
        night.cookedAt = nil
        var edit = PlanShare.Edit(changing: night)
        edit.hasRecipe = true
        edit.recipeMinutes = 40
        edit.recipeOriginKey = "new-origin"
        edit.cooked = true
        let completion = Date(timeIntervalSince1970: 1_900_000_000)
        edit.cookedAt = completion
        let actual = PlanLedger.edited(night, by: edit)
        XCTAssertTrue(actual.hasRecipe)
        XCTAssertEqual(actual.lines, night.lines)
        XCTAssertTrue(actual.hasPhoto)
        XCTAssertEqual(actual.recipeMinutes, 40)
        XCTAssertEqual(actual.recipeOriginKey, "new-origin")
        XCTAssertTrue(actual.cooked)
        XCTAssertEqual(actual.cookedAt, completion)
        let original = try recipeRecord(night)
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        XCTAssertEqual(TableShare.int(record, "cooked"), 1)
        XCTAssertEqual(record["cookedAt"] as? Date, completion)
        XCTAssertEqual(TableShare.int(record, "hasRecipe"), 1)
        XCTAssertEqual(TableShare.int(record, "recipeMinutes"), 40)
        XCTAssertEqual(record["recipeOriginKey"] as? String, "new-origin")
        XCTAssertEqual(TableShare.decodeLines(record["lines"] as? String), night.lines ?? [])
        XCTAssertNotNil(record["photo"])
    }

    func testLeftoversConversionSurvivesQueuedRecipeAndCompletionFoldsAndRelaunch() throws {
        let night = completedRecipeNight()
        var first = PlanShare.Edit(changing: night)
        first.hasRecipe = true
        first.recipeMinutes = 50
        first.recipeOriginKey = "queued-old-recipe"
        first.photo = .send
        first.cooked = true
        first.cookedAt = night.cookedAt
        PlanShare.enqueue(first)
        PlanShare.enqueue(PlanShare.Edit(changing: night, mealChoice: .leftovers))
        var later = PlanShare.Edit(changing: night)
        later.servings = 6
        PlanShare.enqueue(later)
        PlanShare.reloadEdits()
        let edit = try XCTUnwrap(PlanShare.queuedEdits().first)
        XCTAssertEqual(edit.title, PlanMealChoice.leftovers.title)
        XCTAssertEqual(edit.hasRecipe, false)
        XCTAssertEqual(edit.recipeMinutes, 0)
        XCTAssertEqual(edit.recipeOriginKey, "")
        XCTAssertEqual(edit.photo, .clear)
        XCTAssertEqual(edit.cooked, false)
        XCTAssertNil(edit.cookedAt)
        XCTAssertEqual(edit.servings, 6)
        XCTAssertEqual(edit.seenAt, night.changedAt)
        let actual = PlanLedger.edited(night, by: edit)
        XCTAssertEqual(actual.lines, [])
        XCTAssertFalse(actual.hasPhoto)
        XCTAssertFalse(actual.cooked)
        XCTAssertNil(actual.cookedAt)
        XCTAssertFalse(actual.hasCook)
        let original = try recipeRecord(night)
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        XCTAssertEqual(record["lines"] as? String, "[]")
        XCTAssertNil(record["cookedAt"])
        XCTAssertNil(record["photo"])
        XCTAssertEqual(TableShare.int(record, "servings"), 6)
        XCTAssertEqual(record["cookID"] as? String, "")
    }

    func testLaterRecipeAndCompletionCanReplaceQueuedLeftovers() throws {
        let night = completedRecipeNight()
        PlanShare.enqueue(PlanShare.Edit(changing: night, mealChoice: .leftovers))
        var later = PlanShare.Edit(changing: night)
        later.title = "Fresh soup"
        later.hasRecipe = true
        later.recipeMinutes = 25
        later.recipeOriginKey = "recipe-soup"
        later.cooked = true
        later.cookedAt = Date(timeIntervalSince1970: 1_900_000_000)
        PlanShare.enqueue(later)
        PlanShare.reloadEdits()
        let edit = try XCTUnwrap(PlanShare.queuedEdits().first)
        XCTAssertEqual(edit.hasRecipe, true)
        XCTAssertEqual(edit.recipeMinutes, 25)
        XCTAssertEqual(edit.recipeOriginKey, "recipe-soup")
        XCTAssertEqual(edit.cooked, true)
        XCTAssertEqual(edit.cookedAt, later.cookedAt)
        XCTAssertEqual(edit.photo, .clear, "The old recipe's photo must not return")
    }

    func testStoredLeftoversCannotClaimCookingThroughStaleAssignment() {
        var night = completedRecipeNight()
        night.title = "Leftovers"
        night.hasRecipe = false
        night.cookID = TableIdentity.cached
        XCTAssertTrue(night.isLeftovers)
        XCTAssertFalse(night.hasCook)
        XCTAssertFalse(PlanLedger.shared.isMine(cook: night))
        XCTAssertNil(PlanLedger.shared.cookLine(for: night))
        XCTAssertEqual(PlanLedger.shared.whoLine(for: night), "Riley planned this night")
        night.hasRecipe = true
        XCTAssertFalse(night.isLeftovers, "A recipe genuinely named Leftovers remains a recipe")
        XCTAssertTrue(night.hasCook)
    }

    private func soupRecipe() -> Recipe {
        let recipe = Recipe(title: "Soup")
        recipe.servings = 4
        let beans = Ingredient(name: "Beans", quantity: 16, unit: "oz", aisle: .pantry)
        context.insert(recipe)
        context.insert(beans)
        beans.recipe = recipe
        return recipe
    }

    func testSharedRecipeReplacementUsesSameScaledIngredientsAsLocalMeal() throws {
        let recipe = soupRecipe()
        let night = completedRecipeNight()
        let leftovers = PlanLedger.edited(night, by: PlanShare.Edit(changing: night, mealChoice: .leftovers))
        var edit = PlanShare.Edit(changing: leftovers)
        edit.title = recipe.title
        edit.hasRecipe = true
        edit.servings = 6
        edit.lines = PlanShare.groceryLines(recipe: recipe, servings: 6)
        edit.recipeOriginKey = recipe.planningKey
        let local = meal(title: recipe.title, recipe: recipe)
        local.servings = 6
        XCTAssertEqual(edit.lines, PlanShare.groceryLines(for: local))
        XCTAssertEqual(edit.lines?.first?.quantity ?? 0, 24, accuracy: 0.0001)
        let actual = PlanLedger.edited(leftovers, by: edit)
        XCTAssertEqual(actual.lines, edit.lines)
        XCTAssertEqual(actual.servings, 6)
        XCTAssertTrue(actual.hasRecipe)
        let original = try recipeRecord(leftovers)
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        XCTAssertEqual(TableShare.decodeLines(record["lines"] as? String), edit.lines)
        XCTAssertEqual(TableShare.int(record, "servings"), 6)
        XCTAssertEqual(record["shoppingID"] as? String, night.shoppingID)
        XCTAssertEqual(record["authorID"] as? String, night.authorID)
    }

    func testQueuedReplacementThenServingChangeRescalesNewIngredientsExactlyOnce() throws {
        let night = completedRecipeNight()
        PlanShare.enqueue(PlanShare.Edit(changing: night, mealChoice: .leftovers))
        var replacement = PlanShare.Edit(changing: night)
        replacement.title = "Soup"
        replacement.hasRecipe = true
        replacement.servings = 6
        replacement.lines = PlanShare.groceryLines(recipe: soupRecipe(), servings: 6)
        PlanShare.enqueue(replacement)
        var more = PlanShare.Edit(changing: night)
        more.servings = 8
        PlanShare.enqueue(more)
        PlanShare.reloadEdits()
        let edit = try XCTUnwrap(PlanShare.queuedEdits().first)
        XCTAssertEqual(edit.servings, 8)
        XCTAssertEqual(edit.lines?.first?.normalizedName, "beans")
        XCTAssertEqual(edit.lines?.first?.quantity ?? 0, 32, accuracy: 0.0001)
        XCTAssertEqual(PlanLedger.edited(night, by: edit).lines, edit.lines)
        let original = try recipeRecord(night)
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        let wireLines = TableShare.decodeLines(record["lines"] as? String)
        XCTAssertEqual(wireLines, edit.lines, "Already-scaled replacement ingredients must not be multiplied by the old record's serving ratio again")
        XCTAssertEqual(wireLines.first?.quantity ?? 0, 32, accuracy: 0.0001)
    }

    func testServingOnlyChangeMatchesOptimisticAndWireIngredientQuantities() throws {
        let night = completedRecipeNight()
        var edit = PlanShare.Edit(changing: night)
        edit.servings = 6
        let actual = PlanLedger.edited(night, by: edit)
        XCTAssertEqual(actual.lines?.first?.quantity ?? 0, 24, accuracy: 0.0001)
        let original = try recipeRecord(night)
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        XCTAssertEqual(actual.lines, TableShare.decodeLines(record["lines"] as? String))
    }

    func testExplicitEmptyIngredientsClearWithoutPretendingTheRecipeWasRemoved() throws {
        let night = completedRecipeNight()
        var edit = PlanShare.Edit(changing: night)
        edit.lines = []
        let actual = PlanLedger.edited(night, by: edit)
        XCTAssertTrue(actual.hasRecipe)
        XCTAssertTrue(actual.hasPhoto)
        XCTAssertEqual(actual.lines, [])
        let original = try recipeRecord(night)
        let (record, _) = PlanShare.record(for: edit, existing: original,
                                          zone: original.recordID.zoneID, now: .now)
        XCTAssertEqual(TableShare.int(record, "hasRecipe"), 1)
        XCTAssertEqual(record["lines"] as? String, "[]")
        XCTAssertNotNil(record["photo"])
    }

    func testLegacyQueuedEditWithoutIngredientsStillDecodesAndPreservesItsIntent() throws {
        var edit = PlanShare.Edit(changing: completedRecipeNight())
        edit.servings = 6
        let data = try JSONEncoder().encode(edit)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "lines")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PlanShare.Edit.self, from: legacy)
        XCTAssertNil(decoded.lines)
        XCTAssertEqual(decoded.recordName, edit.recordName)
        XCTAssertEqual(decoded.zoneOwner, edit.zoneOwner)
        XCTAssertEqual(decoded.servings, 6)
        XCTAssertEqual(decoded.seenAt, edit.seenAt)
    }

    func testLegacyLocalLeftoversCannotRepublishAStaleCookOrCompletion() {
        let sam = member("Sam Okafor", seat: .joined, participant: "_sam")
        let leftovers = meal(title: "Leftovers", cook: sam)
        leftovers.cookedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = PlanShare.plan(for: leftovers, me: "_me")
        XCTAssertEqual(plan.title, "Leftovers")
        XCTAssertEqual(plan.recordName, "plan-" + (leftovers.shoppingID ?? ""))
        XCTAssertEqual(plan.cookID, "")
        XCTAssertEqual(plan.cookName, "")
        XCTAssertEqual(plan.cookSeat, "")
        XCTAssertEqual(plan.cookColorHex, "")
        XCTAssertFalse(plan.cooked)
        XCTAssertNil(plan.cookedAt)
        XCTAssertFalse(plan.hasRecipe)
        XCTAssertTrue(plan.lines.isEmpty)
        XCTAssertNil(plan.photoData)
        XCTAssertNotNil(leftovers.cookedAt, "Publication normalizes its payload without silently editing a private model")
        XCTAssertNotNil(leftovers.cook)
    }

    func testRealRecipeNamedLeftoversKeepsItsCookAndCompletionWhenPublished() {
        let recipe = Recipe(title: "Leftovers")
        context.insert(recipe)
        let sam = member("Sam Okafor", seat: .joined, participant: "_sam")
        let dinner = meal(title: "", recipe: recipe, cook: sam)
        dinner.cookedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = PlanShare.plan(for: dinner, me: "_me")
        XCTAssertEqual(plan.title, "Leftovers")
        XCTAssertTrue(plan.hasRecipe)
        XCTAssertEqual(plan.cookID, "_sam")
        XCTAssertTrue(plan.cooked)
        XCTAssertEqual(plan.cookedAt, dinner.cookedAt)
    }
}
