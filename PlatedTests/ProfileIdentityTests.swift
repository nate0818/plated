import XCTest
import SwiftData
@testable import Plated

@MainActor
final class ProfileIdentityTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    override func setUp() async throws {
        container = try ModelContainer(for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        HouseholdShare.setMembership(.solo)
    }
    override func tearDown() async throws {
        HouseholdShare.setMembership(.solo)
        container = nil
    }
    private func person(_ name: String, id: String, role: String = "partner") -> HouseholdMember {
        let member = HouseholdMember(name: name, role: role, seat: role == "owner" ? .head : .joined)
        member.userRecordName = id
        context.insert(member)
        return member
    }
    func testRenamedAuthorRetainsPhotoAndProfileByAccountIdentity() {
        let sam = person("Sam Rivera", id: "sam-id")
        sam.photoData = Data([1, 2, 3])
        let roster = [sam]
        XCTAssertEqual(roster.photo(forAuthor: "Sam Meadows", authorID: "sam-id"), sam.photoData)
        let ref = PersonRef.author("Sam Meadows", colorHex: "", authorID: "sam-id", in: roster)
        XCTAssertEqual(ref.memberID, sam.persistentModelID)
        XCTAssertTrue(ProfileIdentity.matches(authorID: "sam-id", authorName: "Sam Meadows",
            member: sam, profileName: sam.name, roster: roster))
    }
    func testSameNameWithDifferentAccountNeverBorrowsPhotoOrPosts() {
        let sam = person("Sam Meadows", id: "sam-id")
        sam.photoData = Data([1, 2, 3])
        XCTAssertNil([sam].photo(forAuthor: "Sam Meadows", authorID: "different-id"))
        XCTAssertFalse(ProfileIdentity.matches(authorID: "different-id", authorName: "Sam Meadows",
            member: sam, profileName: sam.name, roster: [sam]))
        let other = person("Sam Rivera", id: "other-id")
        XCTAssertNil(ProfileIdentity.member(authorID: "", name: "Sam", in: [sam, other]))
        XCTAssertNotNil(ProfileIdentity.member(authorID: "", name: "Sam", in: [sam]))
        sam.seat = .invited
        XCTAssertNil(ProfileIdentity.member(authorID: "", name: "Sam Meadows", in: [sam]))
    }
    func testOwnUnclaimedOfflineSeatStillFindsPostsUnderCachedIdentity() {
        let owner = HouseholdMember(name: "Nate", role: "owner", seat: .head)
        context.insert(owner)
        XCTAssertTrue(owner.isMe)
        XCTAssertEqual(ProfileIdentity.member(authorID: TableIdentity.cached, name: "Nate Meadows", in: [owner])?.persistentModelID, owner.persistentModelID)
        XCTAssertTrue(ProfileIdentity.matches(authorID: TableIdentity.cached, authorName: "Nate Meadows",
            member: owner, profileName: owner.name, roster: [owner]))
    }
    func testOrganizerPhotoRemainsVisibleToAnotherHouseholdMember() {
        HouseholdShare.setMembership(.member(owner: "host-id"), ownerName: "Nate")
        let host = person("Nate Meadows", id: "host-id", role: "owner")
        host.photoData = Data([4, 5, 6])
        let reader = person("Sam", id: TableIdentity.cached)
        let display = Seats.resolvedDisplay(for: host, among: [host, reader], reader: reader)
        XCTAssertFalse(host.isMe)
        XCTAssertEqual(display.name, "Nate Meadows")
        XCTAssertEqual(display.photo, host.photoData)
    }
    func testJoinerStillDoesNotBorrowAnAccidentallyClonedHostPhoto() {
        let host = person("Nate Meadows", id: TableIdentity.cached, role: "owner")
        host.photoData = Data([4, 5, 6])
        let joiner = person("Sam", id: "sam-id")
        joiner.photoData = host.photoData
        XCTAssertNil(Seats.resolvedDisplay(for: joiner, among: [host, joiner]).photo)
    }
    func testOrganizerCookKeepsOwnIdentityWhenAnotherMemberPlans() {
        HouseholdShare.setMembership(.member(owner: "host-id"), ownerName: "Nate")
        let host = person("Nate Meadows", id: "host-id", role: "owner")
        let meal = PlannedMeal(date: .now, customTitle: "Pasta", cook: host)
        context.insert(meal)
        let plan = PlanShare.plan(for: meal, me: "reader-id")
        XCTAssertEqual(plan.cookID, "host-id")
        var remote = TableShare.RemotePlan()
        remote.cookID = plan.cookID; remote.cookName = host.name
        XCTAssertEqual(RemoteCookFace.member(for: PlanLedger.Entry(remote), in: [host])?.persistentModelID, host.persistentModelID)
    }
    func testActivityCreditsCookAndStableAuthorDeduplicatingSharedEchoes() {
        let sam = person("Sam Rivera", id: "sam-id")
        let other = person("Sam Meadows", id: "other-id")
        let now = Date.now
        let date = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let meal = PlannedMeal(date: date, customTitle: "Pasta", cook: sam)
        meal.cookedAt = date; context.insert(meal)
        var echo = TableShare.RemotePlan()
        echo.shoppingID = meal.shoppingID!; echo.recordName = "plan-" + echo.shoppingID
        echo.day = PlanDay.string(date); echo.slot = "dinner"; echo.cooked = true
        echo.cookID = "sam-id"; echo.cookName = "Sam Meadows"
        var shared = echo; shared.shoppingID = "other-night"; shared.recordName = "plan-other-night"
        let own = TablePost(authorName: "Sam Meadows", dishTitle: "Pasta", createdAt: date)
        own.authorID = "sam-id"; context.insert(own)
        let wrong = TablePost(authorName: "Sam Rivera", dishTitle: "Not Sam’s", createdAt: date)
        wrong.authorID = "other-id"; context.insert(wrong)
        let activity = MemberDinnerActivity(member: sam, roster: [sam, other], meals: [meal],
            remote: [PlanLedger.Entry(echo), PlanLedger.Entry(shared)], posts: [own, wrong], now: now)
        XCTAssertEqual(activity.cooked, 2)
        XCTAssertEqual(activity.shared, 1)
        meal.cookedAt = nil
        XCTAssertEqual(MemberDinnerActivity(member: sam, roster: [sam, other], meals: [meal],
            remote: [PlanLedger.Entry(echo)], posts: [], now: now).cooked, 0)
    }
    func testActivityExcludesPlansEatingOutOtherCooksAndOldOrFutureDates() {
        let sam = person("Sam", id: "sam-id")
        let other = person("Riley", id: "riley-id")
        let now = Date.now
        var meals: [PlannedMeal] = []
        for (offset, title, cook, complete) in [(-8, "Old", sam, true), (1, "Future", sam, true),
            (-1, "Eating out", sam, true), (0, "Planned", sam, false), (-1, "Other cook", other, true)] {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: now)!
            let meal = PlannedMeal(date: date, customTitle: title, cook: cook)
            if complete { meal.cookedAt = date }; context.insert(meal); meals.append(meal)
        }
        let activity = MemberDinnerActivity(member: sam, roster: [sam, other], meals: meals, remote: [], posts: [], now: now)
        XCTAssertEqual(activity.cooked, 0)
        XCTAssertEqual(activity.shared, 0)
    }
}
