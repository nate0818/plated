import XCTest
import CloudKit
import SwiftData
@testable import Plated

/// The household wire, without a network: fixtures built from the Remote
/// structs go through `merge`, and records built with
/// `CKRecord(recordType:recordID:)` go through the codec both ways. These
/// hold the field rules docs/household.md §2 and §3 promise, which no
/// screen can show and only a second Apple ID could otherwise exercise.
@MainActor
final class HouseholdShareTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let me = TableIdentity.cached
    private let zoneID = CKRecordZone.ID(zoneName: HouseholdShare.zoneName, ownerName: "_owner")

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        resetBooks()
    }

    override func tearDown() async throws {
        resetBooks()
        container = nil
    }

    private func resetBooks() {
        HouseholdOutbox.shared.clear()
        GroceryMarks.shared.clear()
        TableInvites.shared.clear()
        TableNews.forgetAll()
        HouseholdShare.setMembership(.solo)
        HouseholdShare.mySeat = nil
        HouseholdShare.forgetUnresolved()
        UserDefaults.standard.removeObject(forKey: "householdName")
    }

    // MARK: Fixtures

    private func seat(_ name: String, record: String, seat: HouseholdMember.Seat = .joined,
                      role: String = "partner", user: String? = nil, at: Date = .now) -> HouseholdShare.RemoteSeat {
        var s = HouseholdShare.RemoteSeat()
        s.recordName = record
        s.name = name
        s.role = role
        s.seat = seat.rawValue
        s.userRecordName = user
        s.modifiedBy = "riley"
        s.modifiedAt = at
        s.authorID = "riley"
        return s
    }

    private func recipe(record: String, title: String = "Ragù", at: Date = .now,
                        createdAt: Date = .now) -> HouseholdShare.RemoteRecipe {
        var r = HouseholdShare.RemoteRecipe()
        r.recordName = record
        r.title = title
        r.createdAt = createdAt
        r.modifiedBy = "riley"
        r.modifiedAt = at
        r.ingredients = [
            HouseholdShare.WireIngredient(name: "Onion", quantity: 1, unit: "", aisle: "Produce", isPantryStaple: false, sortIndex: 0),
            HouseholdShare.WireIngredient(name: "Beef", quantity: 500, unit: "g", aisle: "Meat & Seafood", isPantryStaple: false, sortIndex: 1),
            HouseholdShare.WireIngredient(name: "Salt", quantity: 0, unit: "", aisle: "Pantry", isPantryStaple: true, sortIndex: 2)
        ]
        return r
    }

    private func members() -> [HouseholdMember] {
        (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? []
    }
    private func recipes() -> [Recipe] {
        (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
    }

    private var tonight: Date { Calendar.current.startOfDay(for: .now) }

    // MARK: Update or insert

    func testMergeInsertsThenUpdatesByRecordName() {
        var changes = HouseholdShare.Changes()
        changes.seats = [seat("Riley Park", record: "seat-1")]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(members().count, 1)
        let riley = members()[0]
        XCTAssertEqual(riley.shareRecordName, "seat-1")
        XCTAssertEqual(riley.seat, .joined)

        var again = HouseholdShare.Changes()
        var edited = seat("Riley P.", record: "seat-1", at: Date.now.addingTimeInterval(5))
        edited.dietaryNotes = "No shellfish"
        again.seats = [edited]
        HouseholdShare.merge(again, into: context)
        XCTAssertEqual(members().count, 1, "a second arrival updates, never duplicates")
        XCTAssertEqual(members()[0].name, "Riley P.")
        XCTAssertEqual(members()[0].dietaryNotes, "No shellfish")
        XCTAssertTrue(riley === members()[0], "the row keeps its identity")
    }

    func testSameVersionIsNotReapplied() {
        let at = Date.now
        var changes = HouseholdShare.Changes()
        changes.seats = [seat("Riley Park", record: "seat-1", at: at)]
        HouseholdShare.merge(changes, into: context)
        members()[0].dietaryNotes = "local edit"
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(members()[0].dietaryNotes, "local edit", "an unchanged modifiedAt is skipped")
    }

    // MARK: Nameless twins

    func testNamelessRecipeTwinAdoptsTheName() {
        let created = Date.now
        let local = Recipe(title: "Ragù")
        local.shareRecordName = ""
        local.createdAt = created
        context.insert(local)
        try? context.save()

        var changes = HouseholdShare.Changes()
        changes.recipes = [recipe(record: "recipe-a", createdAt: created)]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(recipes().count, 1)
        XCTAssertEqual(recipes()[0].shareRecordName, "recipe-a")
        XCTAssertTrue(recipes()[0] === local)
    }

    // MARK: Seat rules (§3.1)

    func testJoinedFlipsInvitedAndNeverFlipsBack() {
        let local = HouseholdMember(name: "Riley Park", role: "partner", seat: .invited,
                                    phoneE164: "+15551234567", shareRecordName: "seat-1")
        context.insert(local)
        try? context.save()

        var changes = HouseholdShare.Changes()
        changes.seats = [seat("Riley Park", record: "seat-1", seat: .joined, user: "riley-id")]
        let outcome = HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(local.seat, .joined)
        XCTAssertEqual(local.userRecordName, "riley-id")
        XCTAssertEqual(local.phoneE164, "+15551234567", "the address never travels and is never cleared")
        XCTAssertEqual(outcome.newSeats.map(\.name), ["Riley Park"])

        var back = HouseholdShare.Changes()
        back.seats = [seat("Riley Park", record: "seat-1", seat: .invited, at: Date.now.addingTimeInterval(9))]
        HouseholdShare.merge(back, into: context)
        XCTAssertEqual(local.seat, .joined, "seats only move forward")
    }

    func testOwnerRoleIsRefusedOnANonOwnerSeat() {
        var changes = HouseholdShare.Changes()
        changes.seats = [seat("Sam Okafor", record: "seat-2", seat: .head, role: "owner", user: "sam-id")]
        HouseholdShare.merge(changes, into: context)
        let sam = members()[0]
        XCTAssertEqual(sam.role, "partner")
        XCTAssertEqual(sam.seat, .joined, "head is accepted only on the zone owner's seat")
    }

    func testOwnerRoleIsAcceptedOnTheOwnersSeat() {
        HouseholdShare.setMembership(.member(owner: "host-id"), ownerName: "Nate")
        var changes = HouseholdShare.Changes()
        changes.seats = [seat("Nate Meadows", record: "seat-host", seat: .head, role: "owner", user: "host-id")]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(members()[0].role, "owner")
        XCTAssertEqual(members()[0].seat, .head)
    }

    func testUserRecordNameIsSetOnce() {
        var first = HouseholdShare.Changes()
        first.seats = [seat("Riley Park", record: "seat-1", user: "riley-id")]
        HouseholdShare.merge(first, into: context)
        var second = HouseholdShare.Changes()
        second.seats = [seat("Riley Park", record: "seat-1", user: "someone-else", at: Date.now.addingTimeInterval(4))]
        HouseholdShare.merge(second, into: context)
        XCTAssertEqual(members()[0].userRecordName, "riley-id")
    }

    func testMySeatKeepsLocalNameAndBio() {
        let mine = HouseholdMember(name: "Nate Meadows", role: "partner", seat: .joined, shareRecordName: "seat-me")
        mine.userRecordName = me
        mine.bio = "Cooks on Tuesdays"
        context.insert(mine)
        try? context.save()

        var changes = HouseholdShare.Changes()
        var wire = seat("Somebody Else", record: "seat-me", user: me)
        wire.bio = "overwritten"
        wire.colorHex = "3DA35D"
        changes.seats = [wire]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(mine.name, "Nate Meadows")
        XCTAssertEqual(mine.bio, "Cooks on Tuesdays")
        XCTAssertEqual(mine.colorHex, "3DA35D", "household-owned fields still arrive")
    }

    /// A night is not a household record, so a delta can never carry one
    /// and a local night can never be deleted by one arriving
    /// (docs/household.md §3.2). The pipe that does carry the week is held
    /// to its own rules in `PlanShareTests` and `PlanNewsTests`.
    func testAHouseholdDeltaNeverTouchesTheLocalPlan() {
        let mine = PlannedMeal(date: tonight, customTitle: "Tacos")
        context.insert(mine)
        try? context.save()

        var changes = HouseholdShare.Changes()
        changes.recipes = [recipe(record: "recipe-a", title: "Ragù")]
        changes.seats = [seat("Riley Park", record: "seat-1")]
        HouseholdShare.merge(changes, into: context)

        let nights = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        XCTAssertEqual(nights.count, 1)
        XCTAssertTrue(nights[0] === mine)
        XCTAssertEqual(nights[0].title, "Tacos")
        XCTAssertTrue(HouseholdOutbox.shared.isEmpty, "nothing about a night is ever queued")
    }

    // MARK: Pending and deleted

    func testPullSkipsARowWithAPendingOutboxEntry() {
        let local = Recipe(title: "Ragù, my way")
        local.shareRecordName = "recipe-a"
        context.insert(local)
        try? context.save()
        HouseholdOutbox.shared.enqueueUpsert(.recipe, "recipe-a")

        var changes = HouseholdShare.Changes()
        changes.recipes = [recipe(record: "recipe-a", title: "Ragù, theirs")]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(local.title, "Ragù, my way")
    }

    func testDeletionRemovesTheRow() {
        var changes = HouseholdShare.Changes()
        changes.recipes = [recipe(record: "recipe-a")]
        changes.seats = [seat("Riley Park", record: "seat-1")]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(recipes().count, 1)

        var gone = HouseholdShare.Changes()
        gone.deleted = ["recipe-a", "seat-1"]
        HouseholdShare.merge(gone, into: context)
        XCTAssertTrue(recipes().isEmpty)
        XCTAssertTrue(members().isEmpty)
    }

    // MARK: Recipes (§3.3)

    func testRecipeMergeRebuildsIngredientsInOrderAndKeepsFavorite() {
        let local = Recipe(title: "Ragù")
        local.shareRecordName = "recipe-a"
        local.isFavorite = true
        local.isPinned = true
        let stale = Ingredient(name: "Old thing", sortIndex: 0)
        stale.recipe = local
        context.insert(local)
        context.insert(stale)
        try? context.save()

        var changes = HouseholdShare.Changes()
        changes.recipes = [recipe(record: "recipe-a", title: "Ragù, slow")]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(local.title, "Ragù, slow")
        XCTAssertEqual(local.sortedIngredients.map(\.name), ["Onion", "Beef", "Salt"])
        XCTAssertEqual(local.sortedIngredients.map(\.sortIndex), [0, 1, 2])
        XCTAssertTrue(local.sortedIngredients[2].isPantryStaple)
        XCTAssertTrue(local.isFavorite)
        XCTAssertTrue(local.isPinned)
        let all = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []
        XCTAssertEqual(all.count, 3, "the stale row is gone, not orphaned")
    }

    // MARK: The root (§3.6)

    func testRootWritesNameAndBannerAndCaches() {
        var changes = HouseholdShare.Changes()
        var root = HouseholdShare.RemoteRoot()
        root.name = "The Meadows"
        root.hostName = "Nate"
        root.banner = Data([1, 2, 3])
        root.removedIDs = ["gone-id"]
        root.tableShareURL = URL(string: "https://www.icloud.com/share/abc")
        changes.root = root
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "householdName"), "The Meadows")
        let profiles = (try? context.fetch(FetchDescriptor<HouseholdProfile>())) ?? []
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].bannerPhotoData, Data([1, 2, 3]))
        XCTAssertEqual(HouseholdShare.cachedOwnerName, "Nate")
        XCTAssertEqual(HouseholdShare.cachedRemovedIDs, ["gone-id"])
        XCTAssertEqual(HouseholdShare.cachedTableShareURL?.absoluteString, "https://www.icloud.com/share/abc")
    }

    // MARK: The codec, offline

    private func record(_ type: String, _ name: String) -> CKRecord {
        CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
    }

    func testSeatRoundTripOmitsEmptyListsAndWritesBoolsAsInt() {
        var s = seat("Riley Park", record: "seat-1", user: "riley-id")
        s.isPrimaryCook = true
        s.cookWeekdays = [2, 4]
        s.avoidedIngredients = []
        s.bio = "Sunday roasts"
        s.photo = Data([9, 9, 9])
        let rec = record(HouseholdShare.seatType, s.recordName)
        HouseholdShare.write(s, onto: rec)
        XCTAssertNil(rec["avoidedIngredients"], "an empty list is omitted, never minted as []")
        XCTAssertNotNil(rec["cookWeekdays"])
        XCTAssertNotNil(rec["isPrimaryCook"] as? NSNumber, "a Bool travels as a number")
        XCTAssertEqual(TableShare.int(rec, "isPrimaryCook"), 1)
        XCTAssertEqual(HouseholdShare.remoteSeat(from: rec), s)
        HouseholdShare.Wire.removeTemporaryAssets(on: [rec])
    }

    func testRecipeRoundTripCarriesIngredientsAndPhotos() {
        var r = recipe(record: "recipe-a")
        r.tags = ["weeknight"]
        r.steps = ["Brown the beef.", "Simmer."]
        r.weatherMoods = []
        r.householdCanEdit = false
        r.photoData = Data([1, 2])
        r.extraPhotos = [Data([3]), Data([4])]
        r.photoHash = HouseholdShare.Wire.photoHash(hero: r.photoData, extras: r.extraPhotos)
        let rec = record(HouseholdShare.recipeType, r.recordName)
        HouseholdShare.write(r, onto: rec)
        XCTAssertNil(rec["weatherMoods"])
        XCTAssertEqual(TableShare.int(rec, "householdCanEdit"), 0)
        XCTAssertNotNil(rec["ingredientsJSON"] as? String)
        XCTAssertEqual((rec["extraPhotos"] as? [CKAsset])?.count, 2)
        XCTAssertEqual(HouseholdShare.remoteRecipe(from: rec), r)
        HouseholdShare.Wire.removeTemporaryAssets(on: [rec])
    }

    func testRecipeWriteCanLeavePhotosAlone() {
        var r = recipe(record: "recipe-a")
        r.photoData = Data([1, 2])
        let rec = record(HouseholdShare.recipeType, r.recordName)
        HouseholdShare.write(r, onto: rec, includingPhotos: false)
        XCTAssertNil(rec["photo"])
        XCTAssertNil(rec["photoHash"])
        XCTAssertEqual(rec["title"] as? String, "Ragù")
    }

    func testGatheringLineAndMarkRoundTrip() {
        var g = HouseholdShare.RemoteGathering()
        g.recordName = "gathering-a"
        g.title = "Birthday"
        g.guestCount = 6
        g.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        g.endDate = g.startDate.addingTimeInterval(3600)
        let grec = record(HouseholdShare.gatheringType, g.recordName)
        HouseholdShare.write(g, onto: grec)
        XCTAssertEqual(HouseholdShare.remoteGathering(from: grec), g)

        var l = HouseholdShare.RemoteLine()
        l.recordName = "line-a"
        l.name = "Dish soap"
        l.quantity = 1.5
        l.unit = "bottle"
        l.day = HouseholdShare.Wire.day(tonight)
        l.isChecked = true
        let lrec = record(HouseholdShare.lineType, l.recordName)
        HouseholdShare.write(l, onto: lrec)
        XCTAssertEqual(TableShare.int(lrec, "isChecked"), 1)
        XCTAssertEqual(HouseholdShare.remoteLine(from: lrec), l)

        var m = HouseholdShare.RemoteMark()
        m.recordName = GroceryMarks.recordName(for: "beef|g")
        m.lineKey = "beef|g"
        m.purchases = [:]
        m.dismissedUntil = "2026-09-13"
        m.at = Date(timeIntervalSince1970: 1_700_000_000)
        m.by = "riley"
        m.modifiedAt = m.at
        m.modifiedBy = m.by
        m.authorID = m.by
        let mrec = record(HouseholdShare.markType, m.recordName)
        HouseholdShare.write(m, onto: mrec)
        XCTAssertEqual(mrec["purchasesJSON"] as? String, "{}", "an empty map is a value, never a missing key")
        XCTAssertEqual(HouseholdShare.remoteMark(from: mrec), m)
    }

    func testRootRoundTrip() {
        var root = HouseholdShare.RemoteRoot()
        root.name = "The Meadows"
        root.hostName = "Nate"
        root.autoRotate = false
        root.removedIDs = []
        root.tableShareURL = URL(string: "https://www.icloud.com/share/abc")
        root.modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let rec = record(HouseholdShare.rootType, HouseholdShare.rootRecordName)
        HouseholdShare.write(root, onto: rec)
        XCTAssertNil(rec["removedIDs"])
        XCTAssertEqual(TableShare.int(rec, "autoRotateOpenNights"), 0)
        XCTAssertEqual(HouseholdShare.remoteRoot(from: rec), root)
    }

    func testChangesSortRecordsByType() {
        var changes = HouseholdShare.Changes()
        changes.add(record(HouseholdShare.seatType, "seat-1"))
        changes.add(record(HouseholdShare.recipeType, "recipe-1"))
        changes.add(record(HouseholdShare.rootType, HouseholdShare.rootRecordName))
        changes.add(record("PlatedDish", "post-1"))
        XCTAssertEqual(changes.seats.count, 1)
        XCTAssertEqual(changes.recipes.count, 1)
        XCTAssertNotNil(changes.root)
        XCTAssertFalse(changes.sharesChanged)
    }

    // MARK: Membership cache

    func testMembershipRoundTripsThroughTheAppGroup() {
        HouseholdShare.setMembership(.member(owner: "host-id"), ownerName: "Nate")
        XCTAssertEqual(HouseholdShare.membership, .member(owner: "host-id"))
        XCTAssertEqual(HouseholdShare.zoneOwnerRecordName, "host-id")
        XCTAssertTrue(HouseholdMember.isMemberElsewhere)
        HouseholdShare.mySeat = "seat-me"
        XCTAssertEqual(HouseholdMember.claimedSeatName, "seat-me")
        HouseholdShare.setMembership(.hosting)
        XCTAssertEqual(HouseholdShare.membership, .hosting)
        XCTAssertEqual(HouseholdShare.zoneOwnerRecordName, me)
    }
}
