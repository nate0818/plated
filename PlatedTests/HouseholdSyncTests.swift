import XCTest
import SwiftData
import UserNotifications
@testable import Plated

/// The pure half of the household glue (docs/household.md section 11): the
/// fingerprint, the duplicate collapse, re-attribution, the identity stamp,
/// the leave rule and the household digest. Everything here runs on an
/// in-memory container with no CloudKit; the membership keys and the
/// app-group books are reset around every test so a development
/// simulator's real household is never read as a fact about the fixture.
@MainActor
final class HouseholdSyncTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let me = TableIdentity.cached

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        resetBooks()
        TableNews.rehearsing = true
    }

    override func tearDown() async throws {
        resetBooks()
        TableNews.rehearsing = false
        UserDefaults.standard.removeObject(forKey: TableNews.tableOnKey)
        container = nil
    }

    private func resetBooks() {
        TableNews.forgetAll()
        TableLedger.shared.clear()
        HouseholdOutbox.shared.clear()
        GroceryMarks.shared.clear()
        let defaults = UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
        for key in [HouseholdMember.Keys.membershipKind, HouseholdMember.Keys.mySeat,
                    HouseholdShare.Keys.owner, HouseholdShare.Keys.ownerName, HouseholdShare.Keys.name,
                    HouseholdShare.Keys.epoch, HouseholdShare.Keys.publishedAt, HouseholdShare.Keys.removedIDs,
                    HouseholdShare.Keys.tableShareURL, HouseholdShare.Keys.unresolved,
                    HouseholdSync.Keys.minter, HouseholdSync.Keys.removedNotice,
                    HouseholdOutbox.publishTotalKey] {
            defaults.removeObject(forKey: key)
        }
    }

    private func setMembership(_ kind: String, owner: String = "") {
        let defaults = UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
        defaults.set(kind, forKey: HouseholdMember.Keys.membershipKind)
        if owner.isEmpty { defaults.removeObject(forKey: HouseholdShare.Keys.owner) }
        else { defaults.set(owner, forKey: HouseholdShare.Keys.owner) }
    }

    // MARK: The fingerprint

    func testTheFingerprintIsContentNotBookkeeping() throws {
        let recipe = Recipe(title: "Ragù", summary: "Slow.")
        context.insert(recipe)
        try context.save()
        let before = HouseholdSync.fingerprint(of: recipe)
        XCTAssertNotNil(before)

        recipe.shareRecordName = "recipe-other"
        recipe.shareModifiedAt = .now
        recipe.shareFingerprint = "stale"
        recipe.isFavorite = true
        recipe.isPinned = true
        XCTAssertEqual(HouseholdSync.fingerprint(of: recipe), before)

        recipe.title = "Ragù bolognese"
        let renamed = HouseholdSync.fingerprint(of: recipe)
        XCTAssertNotEqual(renamed, before)
        recipe.photoData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        XCTAssertNotEqual(HouseholdSync.fingerprint(of: recipe), renamed)

        let member = HouseholdMember(name: "Riley", role: "partner", seat: .invited)
        let plain = HouseholdSync.fingerprint(of: member)
        member.phoneE164 = "+15550001111"
        member.inviteEmail = "riley@example.com"
        XCTAssertEqual(HouseholdSync.fingerprint(of: member), plain)
        member.name = "Riley Park"
        XCTAssertNotEqual(HouseholdSync.fingerprint(of: member), plain)

        let gathering = Gathering(title: "Sunday lunch")
        let unsynced = HouseholdSync.fingerprint(of: gathering)
        gathering.calendarEventID = "event-1"
        XCTAssertEqual(HouseholdSync.fingerprint(of: gathering), unsynced)

        let line = GroceryItem(name: "Lemons", isManual: true)
        let typed = HouseholdSync.fingerprint(of: line)
        line.reminderID = "reminder-1"
        XCTAssertEqual(HouseholdSync.fingerprint(of: line), typed)
        XCTAssertNil(HouseholdSync.fingerprint(of: GroceryItem(name: "Auto", isManual: false)))
    }

    // MARK: Duplicates

    /// The night in this fixture is never collapsed: it has no household
    /// record name to collapse on, and no pass over `PlannedMeal` exists
    /// any more. It is here to prove a rehomed recipe and cook take the
    /// nights that point at them along.
    func testCollapseKeepsTheOldestAndRehomesAMealsRecipeAndCook() throws {
        let older = Recipe(title: "Ragù")
        older.shareRecordName = "recipe-1"
        older.createdAt = .now.addingTimeInterval(-600)
        let newer = Recipe(title: "Ragù")
        newer.shareRecordName = "recipe-1"
        let cookOlder = HouseholdMember(name: "Riley", role: "partner", seat: .joined, shareRecordName: "seat-1")
        cookOlder.createdAt = .now.addingTimeInterval(-600)
        let cookNewer = HouseholdMember(name: "Riley", role: "partner", seat: .joined, shareRecordName: "seat-1")
        let meal = PlannedMeal(date: .now, recipe: newer, cook: cookNewer)
        for row in [older, newer] { context.insert(row) }
        for row in [cookOlder, cookNewer] { context.insert(row) }
        context.insert(meal)
        try context.save()

        HouseholdSync.collapseDuplicates(in: context)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes.first?.createdAt, older.createdAt)
        let members = try context.fetch(FetchDescriptor<HouseholdMember>())
        XCTAssertEqual(members.count, 1)
        XCTAssertTrue(meal.recipe === older)
        XCTAssertTrue(meal.cook === cookOlder)
    }

    func testCollapseKeepsTheOldestTablePostAndRehomesComments() throws {
        let older = TablePost(authorName: "Nate", dishTitle: "Ragù")
        older.shareRecordName = "post-1"
        older.createdAt = .now.addingTimeInterval(-600)
        let newer = TablePost(authorName: "Nate", dishTitle: "Ragù")
        newer.shareRecordName = "post-1"
        let note = TableComment(authorName: "Riley", text: "Saving this.")
        note.post = newer
        for row in [older, newer] { context.insert(row) }
        context.insert(note)
        try context.save()

        HouseholdSync.collapseDuplicates(in: context)

        let posts = try context.fetch(FetchDescriptor<TablePost>())
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.createdAt, older.createdAt)
        XCTAssertTrue(note.post === older)
    }

    // MARK: Identity

    func testReattributeRewritesAuthorAndIdentity() throws {
        let placeholder = "local-abc"
        let member = HouseholdMember(name: "Nate", role: "owner", seat: .head)
        member.authorID = placeholder
        member.userRecordName = placeholder
        let recipe = Recipe(title: "Ragù")
        recipe.authorID = placeholder
        let theirs = Recipe(title: "Tacos")
        theirs.authorID = "riley"
        for row in [member] { context.insert(row) }
        for row in [recipe, theirs] { context.insert(row) }
        try context.save()

        HouseholdSync.reattribute(from: placeholder, to: "_real", in: context)

        XCTAssertEqual(member.authorID, "_real")
        XCTAssertEqual(member.userRecordName, "_real")
        XCTAssertEqual(recipe.authorID, "_real")
        XCTAssertEqual(theirs.authorID, "riley")
    }

    func testTheHeadIsStampedOnlyWhileUnshared() throws {
        let head = HouseholdMember(name: "Nate", role: "owner", seat: .head)
        context.insert(head)
        try context.save()

        setMembership("member", owner: "_host")
        HouseholdSync.stampIdentityIfUnshared(in: context, identity: "_me")
        XCTAssertNil(head.userRecordName)

        setMembership("solo")
        HouseholdSync.stampIdentityIfUnshared(in: context, identity: "local-placeholder")
        XCTAssertNil(head.userRecordName)

        HouseholdSync.stampIdentityIfUnshared(in: context, identity: "_me")
        XCTAssertEqual(head.userRecordName, "_me")
    }

    // MARK: Leaving

    func testLeavingKeepsWhatIsMineAndDropsWhatWasTheirs() throws {
        setMembership("member", owner: "_host")
        let mine = HouseholdMember(name: "Nate", role: "partner", seat: .joined, shareRecordName: "seat-me")
        mine.userRecordName = "_me"
        mine.shareModifiedAt = .now
        mine.shareFingerprint = "x"
        let host = HouseholdMember(name: "Sam", role: "owner", seat: .head, shareRecordName: "seat-host")
        host.userRecordName = "_host"
        host.shareModifiedAt = .now
        let kid = HouseholdMember(name: "Max", role: "kid", seat: .notOnPlated, shareRecordName: "seat-max")
        kid.authorID = "_me"
        kid.shareModifiedAt = .now
        let theirKid = HouseholdMember(name: "Jo", role: "kid", seat: .notOnPlated, shareRecordName: "seat-jo")
        theirKid.authorID = "_host"
        theirKid.shareModifiedAt = .now

        let unowned = Recipe(title: "Old ragù")
        let ours = Recipe(title: "My tacos")
        ours.authorID = "_me"
        ours.shareModifiedAt = .now
        ours.shareFingerprint = "y"
        let theirs = Recipe(title: "Sam's curry")
        theirs.authorID = "_host"
        theirs.shareModifiedAt = .now
        let theirsUnsent = Recipe(title: "Sam's soup")
        theirsUnsent.authorID = "_host"

        // Every night on this phone is this phone's own: the household's
        // week was never in `PlannedMeal` (docs/household.md §3.2), so a
        // leave has nothing to take out of it.
        let thisWeek = PlannedMeal(date: .now.addingTimeInterval(86400), recipe: ours, cook: mine)
        thisWeek.authorID = "_me"
        let history = PlannedMeal(date: .now.addingTimeInterval(-86400 * 30), recipe: ours, cook: mine)
        history.authorID = "_me"

        for row in [mine, host, kid, theirKid] { context.insert(row) }
        for row in [unowned, ours, theirs, theirsUnsent] { context.insert(row) }
        for row in [thisWeek, history] { context.insert(row) }
        try context.save()

        HouseholdSync.forgetHousehold(in: context, me: "_me", mySeat: "seat-me")

        let members = try context.fetch(FetchDescriptor<HouseholdMember>()).sorted { $0.name < $1.name }
        XCTAssertEqual(members.map(\.name), ["Max", "Nate"])
        XCTAssertEqual(mine.role, "owner")
        XCTAssertEqual(mine.seat, .head)
        XCTAssertNil(mine.shareModifiedAt)
        XCTAssertEqual(mine.shareFingerprint, "")
        XCTAssertNotEqual(mine.shareRecordName, "seat-me")
        XCTAssertTrue(mine.shareRecordName.hasPrefix("seat-"))

        let recipes = try context.fetch(FetchDescriptor<Recipe>()).map(\.title).sorted()
        XCTAssertEqual(recipes, ["My tacos", "Old ragù", "Sam's soup"])
        XCTAssertNil(ours.shareModifiedAt)
        XCTAssertEqual(ours.shareFingerprint, "")
        XCTAssertTrue(ours.shareRecordName.hasPrefix("recipe-"))

        let meals = try context.fetch(FetchDescriptor<PlannedMeal>())
        XCTAssertEqual(meals.count, 2, "a leave takes no night off this phone")
        XCTAssertTrue(meals.contains { $0 === thisWeek })
        XCTAssertTrue(meals.contains { $0 === history })
        XCTAssertEqual(HouseholdShare.membership, .solo)
        XCTAssertNil(HouseholdShare.mySeat)
    }

    // MARK: The household digest

    private func seat(_ name: String, id: String?, by: String, record: String = "seat-x") -> (HouseholdMember, HouseholdShare.RemoteSeat) {
        let member = HouseholdMember(name: name, role: "partner", seat: .joined, shareRecordName: record)
        member.userRecordName = id
        context.insert(member)
        var remote = HouseholdShare.RemoteSeat()
        remote.recordName = record
        remote.name = name
        remote.userRecordName = id
        remote.modifiedBy = by
        remote.seat = HouseholdMember.Seat.joined.rawValue
        return (member, remote)
    }

    func testAJoinedSeatBySomebodyElseIsOneNamedNoticeWithARow() throws {
        let (riley, remote) = seat("Riley Park", id: "riley", by: "riley")
        try context.save()
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.newSeats = [riley]

        let notices = TableNews.digest(household: changes, outcome: outcome, context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .householdSeat)
        XCTAssertEqual(notices[0].key, "household:riley")
        XCTAssertEqual(notices[0].title, "Riley joined your household")
        XCTAssertEqual(notices[0].body, "They can see the plan, the grocery list and the cookbook now.")
        XCTAssertTrue(notices[0].writesRow)
        XCTAssertTrue(notices[0].direct)
        XCTAssertTrue(notices[0].quietAtNight)
        XCTAssertEqual(notices[0].link, DeepLink.url(.home))
        XCTAssertEqual(TableNews.thread(for: notices[0]), "household")
        // The placeholder on a locked screen has to name the door the tap
        // opens, and a seat opens Home, not the plan.
        XCTAssertEqual(
            NotificationRouter.category(for: notices[0].kind), NotificationRouter.Category.householdSeat
        )
    }

    /// Two guards, held one at a time: a seat somebody else wrote that is
    /// mine, and my own seat written by me. A fixture that trips both at
    /// once passes with either one deleted.
    func testMyOwnSeatIsNeverNarratedBackToMe() throws {
        let (mine, remote) = seat("Nate Meadows", id: me, by: me)
        try context.save()
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.newSeats = [mine]
        XCTAssertTrue(TableNews.digest(household: changes, outcome: outcome, context: context).isEmpty)

        // My seat, but the host wrote it: still my seat, still not news.
        var byTheHost = remote
        byTheHost.modifiedBy = "riley"
        var theirs = HouseholdShare.Changes()
        theirs.seats = [byTheHost]
        XCTAssertTrue(TableNews.digest(household: theirs, outcome: outcome, context: context).isEmpty)

        // Somebody else's seat that my own phone wrote: my action.
        let (riley, rileyRemote) = seat("Riley Park", id: "riley", by: me, record: "seat-riley")
        try context.save()
        var byMe = HouseholdShare.Changes()
        byMe.seats = [rileyRemote]
        var rileyOutcome = HouseholdShare.MergeOutcome()
        rileyOutcome.newSeats = [riley]
        XCTAssertTrue(TableNews.digest(household: byMe, outcome: rileyOutcome, context: context).isEmpty)
    }

    func testASeatThatLeftIsOnePassiveNoticeAndNeverAboutMe() throws {
        let (riley, remote) = seat("Riley Park", id: "riley", by: "riley", record: "seat-riley")
        riley.seat = .left
        try context.save()
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.leftSeats = [riley]

        let notices = TableNews.digest(household: changes, outcome: outcome, context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .householdLeft)
        XCTAssertEqual(notices[0].key, "household-left:riley")
        XCTAssertEqual(notices[0].title, "Riley left your household")
        XCTAssertTrue(notices[0].passive)
        XCTAssertTrue(notices[0].writesRow)
        XCTAssertEqual(notices[0].link, DeepLink.url(.home))
        XCTAssertEqual(
            NotificationRouter.category(for: notices[0].kind), NotificationRouter.Category.householdSeat
        )

        // The leaver's own phone hears nothing about its own departure,
        // whichever half of the guard is asked.
        var byMe = remote
        byMe.modifiedBy = me
        var mine = HouseholdShare.Changes()
        mine.seats = [byMe]
        XCTAssertTrue(TableNews.digest(household: mine, outcome: outcome, context: context).isEmpty)

        let (leaver, leaverRemote) = seat("Nate Meadows", id: me, by: "riley", record: "seat-me")
        leaver.seat = .left
        try context.save()
        var about = HouseholdShare.Changes()
        about.seats = [leaverRemote]
        var aboutMe = HouseholdShare.MergeOutcome()
        aboutMe.leftSeats = [leaver]
        XCTAssertTrue(TableNews.digest(household: about, outcome: aboutMe, context: context).isEmpty)
    }

    // MARK: Seats that leave (§8)

    /// A seat arriving `left` for somebody this phone has never seen is
    /// history, not a person. Seeding it gave a fresh joiner a roster full
    /// of the household's leavers, each reading "Riley / Left" for ever.
    func testAWireSeatThatAlreadyLeftIsNotSeeded() throws {
        var gone = HouseholdShare.RemoteSeat()
        gone.recordName = "seat-riley"
        gone.name = "Riley Park"
        gone.userRecordName = "riley"
        gone.seat = HouseholdMember.Seat.left.rawValue
        gone.modifiedAt = .now

        var changes = HouseholdShare.Changes()
        changes.seats = [gone]
        HouseholdShare.merge(changes, into: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<HouseholdMember>())
        XCTAssertTrue(rows.isEmpty, "a leaver nobody here ever met is not a row")

        // My own leaving, pushed from another device, is how this phone
        // learns it is out, so that one IS seeded.
        var mine = gone
        mine.recordName = "seat-me"
        mine.userRecordName = me
        var about = HouseholdShare.Changes()
        about.seats = [mine]
        HouseholdShare.merge(about, into: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<HouseholdMember>()).count, 1)
    }

    /// The host's roster does not hold a seat that left, and the nights it
    /// held go back to unplanned. "Their nights are open again." is a claim
    /// about the plan, and it has to be true of the plan.
    func testRetiringASeatOpensItsNightsAndLeavesTheHostsRoster() throws {
        setMembership("hosting")
        let riley = HouseholdMember(name: "Riley Park", role: "partner", seat: .left,
                                    shareRecordName: "seat-riley")
        riley.userRecordName = "riley"
        riley.cookWeekdays = [3]
        context.insert(riley)
        let night = PlannedMeal(date: .now, slot: .dinner)
        night.cook = riley
        context.insert(night)
        try context.save()

        HouseholdSync.retireLeftSeat(riley, in: context)
        try context.save()

        XCTAssertNil(night.cook)
        XCTAssertTrue(try context.fetch(FetchDescriptor<HouseholdMember>()).isEmpty)
        XCTAssertTrue(HouseholdOutbox.shared.hasPending("seat-riley"))
    }

    /// A member's phone cannot delete a record in the host's zone, and the
    /// next merge would insert the seat again from a record it had simply
    /// not seen. It clears the nights and waits for the host's delete.
    func testAMemberKeepsTheRowAndOnlyOpensTheNights() throws {
        setMembership("member", owner: "sam")
        let riley = HouseholdMember(name: "Riley Park", role: "partner", seat: .left,
                                    shareRecordName: "seat-riley")
        riley.userRecordName = "riley"
        riley.cookWeekdays = [3]
        context.insert(riley)
        let night = PlannedMeal(date: .now, slot: .dinner)
        night.cook = riley
        context.insert(night)
        try context.save()

        HouseholdSync.retireLeftSeat(riley, in: context)
        try context.save()

        XCTAssertNil(night.cook)
        XCTAssertEqual(riley.cookWeekdays, [])
        XCTAssertEqual(try context.fetch(FetchDescriptor<HouseholdMember>()).count, 1)
        XCTAssertFalse(HouseholdOutbox.shared.hasPending("seat-riley"))
    }

    /// The seat question offers every unclaimed seat, `.joined` ones
    /// included: an already-shipped `reconcile` promoted some of those off a
    /// matching Table participant, and refusing them forces a second seat
    /// beside the one the host is looking at.
    func testTheSeatQuestionOffersEveryUnclaimedSeat() throws {
        let head = HouseholdMember(name: "Sam", role: "owner", seat: .head, shareRecordName: "seat-sam")
        let byName = HouseholdMember(name: "Max", role: "kid", seat: .notOnPlated, shareRecordName: "seat-max")
        let invited = HouseholdMember(name: "Jo", role: "partner", seat: .invited, shareRecordName: "seat-jo")
        let promoted = HouseholdMember(name: "Dan", role: "partner", seat: .joined, shareRecordName: "seat-dan")
        let taken = HouseholdMember(name: "Riley", role: "partner", seat: .joined, shareRecordName: "seat-riley")
        taken.userRecordName = "riley"
        let gone = HouseholdMember(name: "Ash", role: "partner", seat: .left, shareRecordName: "seat-ash")
        for row in [head, byName, invited, promoted, taken, gone] { context.insert(row) }
        try context.save()

        let open = HouseholdSync.openSeats(in: try context.fetch(FetchDescriptor<HouseholdMember>()))
        XCTAssertEqual(Set(open.map(\.id)), ["seat-max", "seat-jo", "seat-dan"])
    }

    // MARK: The books

    /// A fold moves purchases from a night that lost a merge onto the one
    /// that won. Nobody touched the line, so the mark keeps its own time and
    /// author: recorded as now, by me, this phone becomes the newest writer
    /// of a line it never checked off and beats a real tap made a moment ago
    /// on another phone.
    func testAFoldedMarkKeepsItsOwnTimeAndAuthor() {
        let book = GroceryMarks.shared
        book.record(lineKey: "milk", purchases: ["shop-a": 1], dismissedUntil: nil)
        let before = book.mark(for: "milk")
        XCTAssertNotNil(before)

        book.rewrite(lineKey: "milk", purchases: ["shop-b": 1])
        let after = book.mark(for: "milk")
        XCTAssertEqual(after?.purchases, ["shop-b": 1])
        XCTAssertEqual(after?.at, before?.at)
        XCTAssertEqual(after?.by, before?.by)
    }

    /// A publish total left behind opens the next household this phone
    /// hosts with "Sharing with your household, 0 of 360" over a queue that
    /// holds nothing.
    func testLeavingForgetsThePublishTotal() throws {
        let defaults = UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
        defaults.set(360, forKey: HouseholdOutbox.publishTotalKey)
        setMembership("member", owner: "sam")
        let mine = HouseholdMember(name: "Nate", role: "owner", seat: .joined, shareRecordName: "seat-me")
        mine.userRecordName = me
        context.insert(mine)
        try context.save()

        HouseholdSync.forgetHousehold(in: context, me: me, mySeat: "seat-me")
        XCTAssertNil(defaults.object(forKey: HouseholdOutbox.publishTotalKey))
    }

    func testAReplayedHouseholdDeltaRaisesNothing() throws {
        let (riley, remote) = seat("Riley Park", id: "riley", by: "riley")
        try context.save()
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        changes.replayed = true
        var outcome = HouseholdShare.MergeOutcome()
        outcome.newSeats = [riley]
        XCTAssertTrue(TableNews.digest(household: changes, outcome: outcome, context: context).isEmpty)
    }

    func testARecipeIAddedIsNeverNarratedBackToMe() throws {
        _ = seat("Nate Meadows", id: me, by: me, record: "seat-me")
        let recipe = Recipe(title: "Ragù")
        recipe.shareRecordName = "recipe-ragu"
        context.insert(recipe)
        try context.save()

        var changes = HouseholdShare.Changes()
        var remote = HouseholdShare.RemoteRecipe()
        remote.recordName = "recipe-ragu"
        remote.modifiedBy = me
        changes.recipes = [remote]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.newRecipes = [recipe]
        XCTAssertTrue(TableNews.digest(household: changes, outcome: outcome, context: context).isEmpty)

        // The same recipe from the other phone in the household is news.
        _ = seat("Riley Park", id: "riley", by: "riley", record: "seat-riley")
        try context.save()
        remote.modifiedBy = "riley"
        changes.recipes = [remote]
        let notices = TableNews.digest(household: changes, outcome: outcome, context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .recipe)
        XCTAssertEqual(notices[0].title, "Riley added Ragù")
        XCTAssertEqual(notices[0].link, DeepLink.url(.cookbook))
        XCTAssertEqual(
            NotificationRouter.category(for: notices[0].kind), NotificationRouter.Category.householdRecipe
        )
    }

    /// A joiner's phone pulls incrementally from the moment it joined, so
    /// the host's `publishAll` arrives as hundreds of fresh nights and
    /// recipes about a plan and a cookbook that were there first. While
    /// the root has no `publishedAt` the Plan and the Cookbook are already
    /// saying "Still arriving"; the bell says nothing at all about it.
    func testTheHostsFirstPublishIsNotToldAsNews() throws {
        setMembership("member", owner: "sam")
        let (sam, samSeat) = seat("Sam Okafor", id: "sam", by: "sam", record: "seat-sam")
        let recipe = Recipe(title: "Ragù")
        recipe.shareRecordName = "recipe-ragu"
        context.insert(recipe)
        try context.save()

        var changes = HouseholdShare.Changes()
        changes.seats = [samSeat]
        var remoteRecipe = HouseholdShare.RemoteRecipe()
        remoteRecipe.recordName = "recipe-ragu"
        remoteRecipe.modifiedBy = "sam"
        changes.recipes = [remoteRecipe]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.newRecipes = [recipe]

        // The back catalogue is silent, and the seat arriving beside it
        // still speaks: a person joining is an event, not history.
        outcome.newSeats = [sam]
        let arriving = TableNews.digest(household: changes, outcome: outcome, context: context)
        XCTAssertEqual(arriving.map(\.kind), [.householdSeat])

        // Once the root says the upload finished, the same delivery is news.
        outcome.newSeats = []
        var root = HouseholdShare.RemoteRoot()
        root.publishedAt = .now
        changes.root = root
        let landed = TableNews.digest(household: changes, outcome: outcome, context: context)
        XCTAssertEqual(Set(landed.map(\.kind)), [.recipe])
    }

    /// The mirror image on the host's phone: a joiner adopts and pushes
    /// everything they brought in one go, so their whole cookbook lands in
    /// the delivery that carries their seat.
    func testWhatAJoinerBringsWithThemIsNotNews() throws {
        let (riley, rileySeat) = seat("Riley Park", id: "riley", by: "riley", record: "seat-riley")
        let recipe = Recipe(title: "Ragù")
        recipe.shareRecordName = "recipe-ragu"
        context.insert(recipe)
        try context.save()

        var changes = HouseholdShare.Changes()
        changes.seats = [rileySeat]
        var remote = HouseholdShare.RemoteRecipe()
        remote.recordName = "recipe-ragu"
        remote.modifiedBy = "riley"
        changes.recipes = [remote]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.newSeats = [riley]
        outcome.newRecipes = [recipe]

        let notices = TableNews.digest(household: changes, outcome: outcome, context: context)
        XCTAssertEqual(notices.map(\.kind), [.householdSeat])
    }

    func testAConflictIsABellRowAndNeverABanner() throws {
        let (_, rileySeat) = seat("Riley Park", id: "riley", by: "riley", record: "seat-riley")
        let recipe = Recipe(title: "Ragù")
        recipe.shareRecordName = "recipe-ragu"
        context.insert(recipe)
        try context.save()

        var changes = HouseholdShare.Changes()
        changes.seats = [rileySeat]
        var remote = HouseholdShare.RemoteRecipe()
        remote.recordName = "recipe-ragu"
        remote.modifiedBy = "riley"
        changes.recipes = [remote]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.conflicts = ["recipe-ragu"]

        let notices = TableNews.digest(household: changes, outcome: outcome, context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .conflict)
        XCTAssertEqual(notices[0].key, "conflict:recipe-ragu")
        XCTAssertEqual(notices[0].title, "Riley changed Ragù after you did")
        XCTAssertEqual(notices[0].body, "Their version is showing.")
        XCTAssertTrue(notices[0].writesRow)
        XCTAssertTrue(notices[0].bellOnly)
        XCTAssertTrue(TableNews.select(notices).isEmpty)
        XCTAssertEqual(notices[0].link, DeepLink.url(.cookbook))
    }

    // MARK: A lost edit, from the push to the bell

    /// What `HouseholdOutbox.drain` hands the digest after a push: the
    /// names whose edit lost, and the server versions that won, so the row
    /// names the person who wrote them. A seat that came back newer is not a
    /// loss worth a row, and a save is not a loss at all. A night cannot
    /// appear at all: it is not a household record.
    func testALostEditReachesTheBellNamedAndOnlyForARecipe() throws {
        let (_, rileySeat) = seat("Riley Park", id: "riley", by: "riley", record: "seat-riley")
        let recipe = Recipe(title: "Ragù")
        recipe.shareRecordName = "recipe-ragu"
        context.insert(recipe)
        try context.save()

        var theirRecipe = HouseholdShare.RemoteRecipe()
        theirRecipe.recordName = "recipe-ragu"
        theirRecipe.title = "Ragù"
        theirRecipe.modifiedBy = "riley"
        var served = HouseholdShare.Changes()
        served.recipes = [theirRecipe]
        var servedSeat = HouseholdShare.Changes()
        servedSeat.seats = [rileySeat]

        let entries = [
            HouseholdOutbox.Entry(id: "recipe-ragu", kind: .recipe, isDelete: false, at: .now),
            HouseholdOutbox.Entry(id: "seat-riley", kind: .seat, isDelete: false, at: .now),
            HouseholdOutbox.Entry(id: "recipe-kept", kind: .recipe, isDelete: false, at: .now),
        ]
        let outcomes: [String: HouseholdShare.PushOutcome] = [
            "recipe-ragu": .remoteNewer(theirs: served),
            "seat-riley": .remoteNewer(theirs: servedSeat),
            "recipe-kept": .saved(modifiedAt: .now),
        ]

        let lost = HouseholdOutbox.conflicts(in: outcomes, entries: entries)
        XCTAssertEqual(lost.names, ["recipe-ragu"])
        XCTAssertEqual(lost.theirs.recipes.map(\.recordName), ["recipe-ragu"])
        XCTAssertTrue(lost.theirs.seats.isEmpty)

        let notices = TableNews.digest(
            household: lost.theirs, outcome: HouseholdShare.MergeOutcome(conflicts: lost.names), context: context
        )
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .conflict)
        XCTAssertEqual(notices[0].key, "conflict:recipe-ragu")
        XCTAssertEqual(notices[0].title, "Riley changed Ragù after you did")
        XCTAssertEqual(notices[0].body, "Their version is showing.")
        XCTAssertEqual(notices[0].actor, "Riley Park")
        XCTAssertTrue(notices[0].writesRow)
        XCTAssertTrue(notices[0].bellOnly)
        XCTAssertTrue(TableNews.select(notices).isEmpty)
    }

    /// Named or not sent. An edit that lost to an identity no seat and no
    /// earlier delivery can name raises nothing, rather than "Someone
    /// changed Ragù".
    func testALostEditToSomebodyNobodyCanNameIsNotSaid() throws {
        let recipe = Recipe(title: "Ragù")
        recipe.shareRecordName = "recipe-ragu"
        context.insert(recipe)
        try context.save()

        var theirRecipe = HouseholdShare.RemoteRecipe()
        theirRecipe.recordName = "recipe-ragu"
        theirRecipe.title = "Ragù"
        theirRecipe.modifiedBy = "stranger"
        var served = HouseholdShare.Changes()
        served.recipes = [theirRecipe]
        let entries = [HouseholdOutbox.Entry(id: "recipe-ragu", kind: .recipe, isDelete: false, at: .now)]
        let lost = HouseholdOutbox.conflicts(in: ["recipe-ragu": .remoteNewer(theirs: served)], entries: entries)
        XCTAssertEqual(lost.names, ["recipe-ragu"])

        let notices = TableNews.digest(
            household: lost.theirs, outcome: HouseholdShare.MergeOutcome(conflicts: lost.names), context: context
        )
        XCTAssertTrue(notices.isEmpty)
    }

    /// A join adopts rows across several saves before it drains at its own
    /// end; a drain asked for in between is parked, not run, so nothing
    /// half-adopted reaches the zone.
    func testTheOutboxDoesNotDrainWhileAJoinIsRunning() async throws {
        HouseholdSync.isJoining = true
        HouseholdOutbox.shared.enqueueUpsert(.recipe, "recipe-ragu")
        let ran = await HouseholdOutbox.shared.drain(context: context)
        XCTAssertFalse(ran)
        XCTAssertTrue(HouseholdOutbox.shared.hasPending("recipe-ragu"))
        // Cleared before the flag drops, so the parked drain has nothing to
        // send once the join it was waiting on is over.
        HouseholdOutbox.shared.clear()
        HouseholdSync.isJoining = false
    }

    func testTheJoinNoticeWaitsUntilMorning() throws {
        let (riley, remote) = seat("Riley Park", id: "riley", by: "riley")
        try context.save()
        var changes = HouseholdShare.Changes()
        changes.seats = [remote]
        var outcome = HouseholdShare.MergeOutcome()
        outcome.newSeats = [riley]
        let notice = TableNews.digest(household: changes, outcome: outcome, context: context)[0]

        var night = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        night.hour = 23
        XCTAssertEqual(TableNews.content(for: notice, at: Calendar.current.date(from: night)!).interruptionLevel, .passive)
        var noon = night
        noon.hour = 12
        let day = TableNews.content(for: notice, at: Calendar.current.date(from: noon)!)
        XCTAssertEqual(day.interruptionLevel, .active)
        XCTAssertNotNil(day.sound)
    }

    func testATableSeatHeldByAHouseholdMemberIsNotSaidTwice() throws {
        let riley = HouseholdMember(name: "Riley Park", role: "partner", seat: .joined)
        riley.userRecordName = "riley"
        riley.participantID = "riley"
        context.insert(riley)
        try context.save()
        XCTAssertTrue(TableNews.digest(TableShare.Changes(), newSeats: [riley], context: context).isEmpty)

        let guest = HouseholdMember(name: "Jo Alvarez", role: "member", seat: .joined)
        guest.participantID = "jo"
        context.insert(guest)
        try context.save()
        XCTAssertEqual(TableNews.digest(TableShare.Changes(), newSeats: [guest], context: context).count, 1)
    }
}
