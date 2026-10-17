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
        HouseholdShare.groupDefaults.removeObject(forKey: HouseholdShare.Keys.accessEdits)
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

    func testSameVersionRecoveryHydratesTheOtherPersonsProfileWithoutRevertingHouseholdEdits() {
        let at = Date.now
        let riley = HouseholdMember(name: "Riley", role: "partner", seat: .joined, shareRecordName: "seat-riley")
        riley.userRecordName = "riley"
        riley.shareModifiedAt = at
        riley.cookWeekdays = [2, 4]
        context.insert(riley)
        var remote = seat("Riley Park", record: "seat-riley", user: "riley", at: at)
        remote.modifiedBy = me // host's acknowledgement preserved these server fields
        remote.photo = Data([1, 2, 3])
        remote.bio = "Loves pasta"
        remote.cookWeekdays = [1]
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(riley.name, "Riley Park")
        XCTAssertEqual(riley.bio, "Loves pasta")
        XCTAssertEqual(riley.photoData, remote.photo)
        XCTAssertEqual(riley.cookWeekdays, [2, 4])
    }

    func testSameVersionProfileRepairRejectsASeatLinkedToADifferentAccount() {
        let at = Date.now
        let riley = HouseholdMember(name: "Riley", seat: .joined, shareRecordName: "seat-riley")
        riley.userRecordName = "riley"
        riley.shareModifiedAt = at
        context.insert(riley)
        var remote = seat("Sam", record: "seat-riley", user: "sam", at: at)
        remote.photo = Data([9])
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(riley.name, "Riley")
        XCTAssertNil(riley.photoData)
    }

    func testParticipantOnlyProfileCanClearItsOwnPhotoAndBio() {
        let riley = HouseholdMember(name: "Riley", seat: .joined, shareRecordName: "seat-riley")
        riley.userRecordName = ""
        riley.participantID = "riley"
        riley.photoData = Data([1])
        riley.bio = "Old bio"
        context.insert(riley)
        var remote = seat("Riley", record: "seat-riley")
        remote.participantID = "riley"
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        HouseholdShare.merge(changes, into: context)
        XCTAssertNil(riley.photoData)
        XCTAssertEqual(riley.bio, "")
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

    func testOrganizerRoleEditPreservesLinkedPersonsPublishedProfile() {
        var published = seat("Alessandra", record: "seat-guest", user: "guest-account")
        published.photo = Data([1, 2, 3]); published.bio = "Sunday cooking"
        let wire = record(HouseholdShare.seatType, published.recordName)
        HouseholdShare.write(published, onto: wire)
        defer { HouseholdShare.Wire.removeTemporaryAssets(on: [wire]) }
        var stale = published
        stale.name = "Old contact name"; stale.photo = nil; stale.bio = ""
        stale.userRecordName = ""; stale.participantID = nil
        stale.cookWeekdays = [2, 4]; stale.modifiedBy = me
        HouseholdShare.writeSeatEdit(stale, onto: wire, editor: me)
        let received = HouseholdShare.remoteSeat(from: wire)
        XCTAssertEqual(received.name, "Alessandra")
        XCTAssertEqual(received.photo, published.photo)
        XCTAssertEqual(received.bio, published.bio)
        XCTAssertEqual(received.userRecordName, "guest-account")
        XCTAssertEqual(received.cookWeekdays, [2, 4])
    }

    func testParticipantOnlyProfileIsProtectedFromAnotherEditorsEmptyPhoto() {
        var published = seat("Sam", record: "seat-guest", user: "")
        published.participantID = "guest-account"; published.photo = Data([7, 8])
        let wire = record(HouseholdShare.seatType, published.recordName)
        HouseholdShare.write(published, onto: wire)
        defer { HouseholdShare.Wire.removeTemporaryAssets(on: [wire]) }
        var stale = published; stale.photo = nil
        HouseholdShare.writeSeatEdit(stale, onto: wire, editor: me)
        XCTAssertEqual(HouseholdShare.remoteSeat(from: wire).photo, published.photo)
    }

    func testPersonCanPublishAndClearTheirOwnProfile() throws {
        var own = seat("Sam", record: "seat-person", user: "guest-account")
        own.modifiedBy = "guest-account"; own.photo = Data([2, 3]); own.bio = "Cook"
        let wire = record(HouseholdShare.seatType, own.recordName)
        HouseholdShare.writeSeatEdit(own, onto: wire, editor: "guest-account")
        var changes = HouseholdShare.Changes(); changes.add(wire)
        HouseholdShare.merge(changes, into: context)
        HouseholdShare.Wire.removeTemporaryAssets(on: [wire])
        let person = try XCTUnwrap(members().first)
        XCTAssertEqual(person.photoData, own.photo)
        own.photo = nil; own.bio = ""; own.modifiedAt = own.modifiedAt.addingTimeInterval(1)
        HouseholdShare.writeSeatEdit(own, onto: wire, editor: "guest-account")
        changes = .init(); changes.add(wire)
        HouseholdShare.merge(changes, into: context)
        XCTAssertNil(person.photoData); XCTAssertEqual(person.bio, "")
    }

    func testOwnProfileReceivesSameAccountSecondDeviceUpdateWithoutLosingPendingEdit() {
        let person = HouseholdMember(name: "Sam", role: "partner", seat: .joined, shareRecordName: "seat-me")
        person.userRecordName = me; context.insert(person)
        HouseholdShare.mySeat = person.shareRecordName
        var own = seat("Sam Rivera", record: person.shareRecordName, user: me)
        own.modifiedBy = me; own.photo = Data([1, 2]); own.bio = "Updated on my other phone"
        var changes = HouseholdShare.Changes(); changes.seats = [own]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(person.photoData, own.photo)
        XCTAssertEqual(person.name, "Sam Rivera")
        person.photoData = Data([9, 8])
        HouseholdOutbox.shared.enqueueUpsert(.seat, person.shareRecordName)
        own.modifiedAt = own.modifiedAt.addingTimeInterval(1); own.photo = Data([3, 4])
        changes.seats = [own]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(person.photoData, Data([9, 8]))
        XCTAssertTrue(HouseholdOutbox.shared.hasPending(person.shareRecordName))
    }

    func testUpgradeRequeuesOwnPhotoEvenIfOlderReaderAcknowledgedClobberedVersion() {
        let person = HouseholdMember(name: "Sam", role: "partner", seat: .joined, shareRecordName: "seat-me")
        person.userRecordName = me; person.photoData = Data([1, 2, 3])
        person.shareModifiedAt = Date.now; context.insert(person)
        HouseholdShare.mySeat = person.shareRecordName
        var stale = seat("Sam", record: person.shareRecordName, user: me, at: person.shareModifiedAt!)
        stale.modifiedBy = "organizer"; stale.photo = nil
        var changes = HouseholdShare.Changes(); changes.seats = [stale]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(person.photoData, Data([1, 2, 3]))
        XCTAssertTrue(HouseholdOutbox.shared.hasPending(person.shareRecordName))
    }

    func testGuestProfileAndActivityCrossTheWireToTheHost() throws {
        try assertProfileDelivery(senderIsHost: false)
    }

    func testHostProfileAndActivityCrossTheWireToAGuest() throws {
        try assertProfileDelivery(senderIsHost: true)
    }

    func testProfileDeliveryStillRejectsHostIdentityClonedOntoGuest() throws {
        HouseholdShare.setMembership(.hosting)
        let host = HouseholdMember(name: "Alex Rivera", role: "owner", seat: .head,
            shareRecordName: "seat-host")
        host.userRecordName = me
        host.photoData = Data([1, 2, 3])
        context.insert(host)
        let guest = HouseholdMember(name: "Sam", role: "partner", seat: .joined,
            shareRecordName: "seat-guest")
        guest.userRecordName = "guest-id"
        guest.photoData = Data([4, 5, 6])
        context.insert(guest)
        var cloned = seat("Alex", record: guest.shareRecordName, user: "guest-id")
        cloned.photo = host.photoData
        var changes = HouseholdShare.Changes()
        changes.seats = [cloned]
        HouseholdShare.merge(changes, into: context)
        XCTAssertEqual(guest.name, "Sam")
        XCTAssertEqual(guest.photoData, Data([4, 5, 6]))
    }

    /// Two isolated stores with different account identities. Exercises the
    /// actual serializers, receiver merge and UI projections; no CloudKit
    /// service or account session is involved in this regression test.
    private func assertProfileDelivery(senderIsHost: Bool) throws {
        let senderStore = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let senderID = "other-account"
        let sender = HouseholdMember(name: "Alex", role: senderIsHost ? "owner" : "partner",
            seat: senderIsHost ? .head : .joined, shareRecordName: "seat-sender")
        sender.userRecordName = senderID
        sender.authorID = senderID
        sender.photoData = Data([1, 2, 3])
        sender.bio = "Weeknight cooking"
        senderStore.mainContext.insert(sender)
        HouseholdShare.setMembership(senderIsHost ? .member(owner: senderID) : .hosting)
        let reader = HouseholdMember(name: "Reader", role: senderIsHost ? "partner" : "owner",
            seat: senderIsHost ? .joined : .head, shareRecordName: "seat-reader")
        reader.userRecordName = me
        reader.photoData = Data([7, 8, 9])
        context.insert(reader)
        HouseholdShare.mySeat = reader.shareRecordName

        func deliver(at time: Date) {
            var outgoing = HouseholdShare.remote(from: sender)
            outgoing.modifiedBy = senderID
            outgoing.modifiedAt = time
            let wire = record(HouseholdShare.seatType, sender.shareRecordName)
            HouseholdShare.write(outgoing, onto: wire)
            defer { HouseholdShare.Wire.removeTemporaryAssets(on: [wire]) }
            var incoming = HouseholdShare.Changes()
            incoming.add(wire)
            HouseholdShare.merge(incoming, into: context)
        }

        let now = Date.now
        deliver(at: now.addingTimeInterval(-1))
        let received = try XCTUnwrap(members().first { $0.userRecordName == senderID })
        XCTAssertEqual(received.photoData, sender.photoData)
        XCTAssertEqual(Seats.resolvedDisplay(for: received, among: members()).photo, sender.photoData)
        XCTAssertFalse(received.isMe)

        // A later photo and a fuller name must reach the existing seat.
        sender.name = "Alex Rivera"
        sender.photoData = Data([4, 5, 6])
        sender.bio = "Sunday roasts"
        deliver(at: now)
        XCTAssertEqual(members().count, 2)
        XCTAssertEqual(received.name, "Alex Rivera")
        XCTAssertEqual(received.photoData, sender.photoData)
        XCTAssertEqual(received.bio, sender.bio)
        XCTAssertEqual(members().photo(forAuthor: "Alex", authorID: senderID), sender.photoData)

        let dinner = PlannedMeal(date: now, customTitle: "Pasta", cook: sender)
        dinner.authorID = senderID
        dinner.cookedAt = now
        senderStore.mainContext.insert(dinner)
        let plan = PlanShare.plan(for: dinner, me: senderID)
        let wirePlan = TableShare.planRecord(plan, existing: nil, zone: zoneID, photo: .clear, now: now).record
        let receivedPlan = PlanLedger.Entry(TableShare.remotePlan(from: wirePlan))
        var post = TableShare.RemotePost()
        post.recordName = "post-sender"
        post.authorID = senderID
        post.authorName = "Alex" // the name when the dish was shared
        post.dishTitle = "Pasta"
        post.kind = "dish"
        post.createdAt = now.addingTimeInterval(-1)
        var posts = TableShare.Changes()
        posts.posts = [post]
        TableShare.merge(posts, into: context)
        let activity = MemberDinnerActivity(member: received, roster: members(), meals: [],
            remote: [receivedPlan], posts: try context.fetch(FetchDescriptor<TablePost>()), now: now)
        XCTAssertEqual(activity.cooked, 1)
        XCTAssertEqual(activity.shared, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedMeal>()).count, 0,
            "Shared activity is derived without copying a household dinner into SwiftData")
    }

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
        l.recipeOrigins = [.init(id: "recipe-a", title: "Lemon chicken")]
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
