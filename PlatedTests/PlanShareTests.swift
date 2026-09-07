import XCTest
import SwiftData
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

    private static let calendar = Calendar.current
    private nonisolated static var today: Date { calendar.startOfDay(for: .now) }
    private nonisolated static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }

    override func tearDown() async throws {
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

    func testARecipeTravelsAsAFlagMinutesAndAnEmptyOriginKey() {
        let recipe = Recipe(title: "Sheet-pan chicken", prepMinutes: 10, cookMinutes: 25)
        context.insert(recipe)
        let with = PlanShare.plan(for: meal(title: "", recipe: recipe), me: "_me")
        XCTAssertTrue(with.hasRecipe)
        XCTAssertEqual(with.recipeMinutes, 35)
        XCTAssertEqual(with.recipeOriginKey, "", "a home-written recipe has no origin, and an empty key never matches")
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
}
