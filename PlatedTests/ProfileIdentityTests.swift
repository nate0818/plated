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
        XCTAssertNotNil(activity.latest)
        XCTAssertFalse(activity.latest?.line.contains("Not Sam’s") ?? true)
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
        XCTAssertNil(activity.latest)
    }

    func testPlanEventNamesThePlannerWithoutCreditingTheAssignedCook() {
        let sam = person("Sam Rivera", id: "sam-id")
        let nate = person("Nate", id: "nate-id", role: "owner")
        let now = Date.now
        let meal = PlannedMeal(date: now.addingTimeInterval(86400), customTitle: "Pizza Night", cook: nate)
        meal.authorID = "sam-id"; meal.createdAt = now.addingTimeInterval(-60); context.insert(meal)
        let event = PlanMemberEvent.latest(member: sam, roster: [sam, nate], meals: [meal], remote: [], recorded: nil, now: now)
        XCTAssertEqual(event?.line, "Planned Pizza Night")
        XCTAssertEqual(event?.dinnerDate, meal.date)
        XCTAssertNil(PlanMemberEvent.latest(member: nate, roster: [sam, nate], meals: [meal], remote: [], recorded: nil, now: now))
        XCTAssertEqual(MemberDinnerActivity(member: sam, roster: [sam, nate], meals: [meal], remote: [], posts: [], now: now).cooked, 0)
    }

    func testPlanEventUsesEditorIdentityAndExcludesPendingOrEchoedChanges() {
        let sam = person("Sam", id: "sam-id")
        let now = Date.now
        var plan = TableShare.RemotePlan()
        plan.title = "Pasta"; plan.authorID = "someone-else"; plan.editorID = "sam-id"
        plan.recordName = "plan-test"; plan.shoppingID = "test"; plan.day = PlanDay.string(now)
        plan.createdAt = now.addingTimeInterval(-3600); plan.changedAt = now.addingTimeInterval(-60)
        var entry = PlanLedger.Entry(plan)
        XCTAssertEqual(PlanMemberEvent.latest(member: sam, roster: [sam], meals: [], remote: [entry], recorded: nil, now: now)?.line, "Updated Pasta")
        entry.pendingSince = now
        XCTAssertNil(PlanMemberEvent.latest(member: sam, roster: [sam], meals: [], remote: [entry], recorded: nil, now: now))
        entry.pendingSince = nil
        let local = PlannedMeal(customTitle: "New local title"); local.shoppingID = "test"; context.insert(local)
        XCTAssertNil(PlanMemberEvent.latest(member: sam, roster: [sam], meals: [local], remote: [entry], recorded: nil, now: now))
    }

    func testPrivateUnstampedPlanBelongsToTheCurrentAccountNotTheCook() {
        let owner = person("Nate", id: TableIdentity.cached, role: "owner")
        let sam = person("Sam", id: "sam-id")
        let now = Date.now
        let meal = PlannedMeal(customTitle: "Pizza", cook: sam)
        meal.createdAt = now.addingTimeInterval(-60); context.insert(meal)
        XCTAssertEqual(PlanMemberEvent.latest(member: owner, roster: [owner, sam], meals: [meal], remote: [], recorded: nil, now: now)?.line, "Planned Pizza")
        XCTAssertNil(PlanMemberEvent.latest(member: sam, roster: [owner, sam], meals: [meal], remote: [], recorded: nil, now: now))
    }
    func testRecipeContributionsUseAccountIdentityAndProtectPrivateRecipes() {
        let owner = person("Nate", id: TableIdentity.cached, role: "owner")
        let sam = person("Sam Rivera", id: "sam-id")
        let recipe = Recipe(title: "Pasta"); context.insert(recipe)
        func owns(_ member: HouseholdMember) -> Bool {
            ProfileIdentity.owns(recipe: recipe, member: member, profileID: "",
                profileName: member.name, roster: [owner, sam], isMe: member.isMe)
        }
        XCTAssertTrue(owns(owner), "Legacy unstamped recipe belongs only to this account")
        XCTAssertFalse(owns(sam))
        recipe.authorID = "sam-id"
        XCTAssertTrue(owns(sam))
        XCTAssertFalse(owns(owner))
        sam.name = "Sam Newname"
        XCTAssertTrue(owns(sam), "Renaming cannot move recipe ownership")
        recipe.visibility = "private"
        XCTAssertFalse(owns(sam), "Another member's private recipe must not appear on their profile")
        recipe.authorID = TableIdentity.cached
        XCTAssertTrue(owns(owner), "Own private recipes remain available on own profile")
    }

    func testProfileLifetimeDinnerCountKeepsWeeklyHistoryAndSharedEchoRules() {
        let sam = person("Sam", id: "sam-id")
        let now = Date.now, old = now.addingTimeInterval(-30 * 86400)
        let meal = PlannedMeal(date: old, customTitle: "Pasta", cook: sam)
        meal.cookedAt = old; context.insert(meal)
        var shared = TableShare.RemotePlan()
        shared.shoppingID = meal.shoppingID!; shared.recordName = "plan-" + shared.shoppingID
        shared.day = PlanDay.string(old); shared.slot = "dinner"; shared.cooked = true; shared.cookID = "sam-id"
        let remote = [PlanLedger.Entry(shared)]
        XCTAssertEqual(MemberDinnerActivity(member: sam, roster: [sam], meals: [meal], remote: remote,
            posts: [], now: now).cooked, 0)
        XCTAssertEqual(MemberDinnerActivity(member: sam, roster: [sam], meals: [meal], remote: remote,
            posts: [], now: now, lookbackDays: nil).cooked, 1)
        meal.cookedAt = nil
        XCTAssertEqual(MemberDinnerActivity(member: sam, roster: [sam], meals: [meal], remote: remote,
            posts: [], now: now, lookbackDays: nil).cooked, 0)
    }

}
