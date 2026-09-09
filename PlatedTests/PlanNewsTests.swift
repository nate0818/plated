import XCTest
import SwiftData
import UserNotifications
@testable import Plated

/// The plan across Apple IDs, held to docs/plan-share.md: what the ledger
/// keeps and drops, what the digest says about a night and when it says
/// nothing, which switch governs it, and which nights earn a reminder.
/// Every one of these is pure given the store, the ledger and the seen
/// keys, which `setUp` and `tearDown` reset the way `TableNewsTests` do.
@MainActor
final class PlanNewsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let me = TableIdentity.cached
    /// The phone's real answer, put back after the tests, so running
    /// these on a simulator does not leave it drawing nobody's week.
    private var savedHouseholdOwner: String?

    // Nonisolated because `remotePlan` uses `tomorrow` as a default
    // argument, which is evaluated outside the actor.
    nonisolated private static let calendar = Calendar.current
    nonisolated private static var today: Date { calendar.startOfDay(for: .now) }
    nonisolated private static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }
    nonisolated private static var tomorrow: Date { day(1) }
    nonisolated private static var inTwoDays: Date { day(2) }
    /// A writer's clock, whole seconds apart: the dedupe key folds
    /// `changedAt` in at second precision, so two saves in one test have
    /// to be told apart on purpose.
    nonisolated private static func stamp(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970) + Double(seconds))
    }

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        TableNews.forgetAll()
        TableLedger.shared.clear()
        NewsPreferences.reset()
        savedHouseholdOwner = PlanLedger.shared.householdOwner
        PlanLedger.shared.clear()
        // Every night below is planned into "host"'s zone unless a test
        // says otherwise, so the household is that zone.
        PlanLedger.shared.householdOwner = "host"
        TableNews.rehearsing = true
        context.insert(HouseholdMember(name: "Nate Meadows", role: "owner", seat: .head))
        context.insert(HouseholdMember(name: "Riley Park", role: "partner", seat: .joined))
        context.insert(HouseholdMember(name: "Sam Okafor", role: "member", seat: .joined))
        try context.save()
    }

    override func tearDown() async throws {
        TableNews.forgetAll()
        TableLedger.shared.clear()
        TableNews.rehearsing = false
        UserDefaults.standard.removeObject(forKey: TableNews.tableOnKey)
        NewsPreferences.reset()
        PlanLedger.shared.clear()
        PlanLedger.shared.householdOwner = savedHouseholdOwner
        container = nil
    }

    // MARK: Helpers

    private func remotePlan(
        by author: String, id: String, day: Date = PlanNewsTests.tomorrow,
        title: String = "Sheet-pan chicken", cookID: String = "riley",
        cookName: String = "Riley Park", cookSeat: String = HouseholdMember.Seat.joined.rawValue,
        zoneOwner: String = "host", changedAt: Date = .now,
        editorID: String = "", editorName: String = ""
    ) -> TableShare.RemotePlan {
        var p = TableShare.RemotePlan()
        p.recordName = "plan-\(id)"
        p.shoppingID = id
        p.zoneOwner = zoneOwner
        p.authorID = author
        switch author {
        case "riley": p.authorName = "Riley Park"
        case "sam": p.authorName = "Sam Okafor"
        case me: p.authorName = "Nate Meadows"
        default: p.authorName = author
        }
        p.cookID = cookID
        p.cookName = cookName
        p.cookSeat = cookSeat
        p.day = PlanDay.string(day)
        p.title = title
        p.changedAt = changedAt
        p.createdAt = changedAt
        // "" is a record written before the editor fields existed, which is
        // every night in every test that does not ask for one.
        p.editorID = editorID
        p.editorName = editorName
        return p
    }

    private func delivery(_ plans: [TableShare.RemotePlan], deleted: Set<String> = [], replayed: Set<String> = [])
    -> (changes: TableShare.Changes, delta: PlanLedger.Delta) {
        var changes = TableShare.Changes()
        changes.plans = plans
        changes.deleted = deleted
        changes.replayedOwners = replayed
        let delta = PlanLedger.shared.absorb(changes, me: me)
        return (changes, delta)
    }

    private func digest(
        _ d: (changes: TableShare.Changes, delta: PlanLedger.Delta), at now: Date = .now
    ) -> [TableNews.Notice] {
        TableNews.digest(d.changes, newSeats: [], plans: d.delta, context: context, now: now)
    }

    private func rows(eventKey: String) -> [PlatedNotification] {
        (try? context.fetch(FetchDescriptor<PlatedNotification>(
            predicate: #Predicate { $0.eventKey == eventKey }
        ))) ?? []
    }

    // MARK: The ledger

    func testMyOwnNightsAreNeverKept() {
        let d = delivery([remotePlan(by: me, id: "mine", cookID: me, cookName: "Nate Meadows")])
        XCTAssertTrue(d.delta.isEmpty)
        XCTAssertNil(PlanLedger.shared.entry("plan-mine"))
        XCTAssertTrue(PlanLedger.shared.plans(on: Self.tomorrow).isEmpty)
    }

    func testADeletionIsByPlanNameOnly() {
        _ = delivery([remotePlan(by: "riley", id: "1")])
        XCTAssertNotNil(PlanLedger.shared.entry("plan-1"))
        // A post's name in the same delivery is somebody else's business.
        let d = delivery([], deleted: ["post-1", "plan-1"])
        XCTAssertEqual(d.delta.removed.map(\.recordName), ["plan-1"])
        XCTAssertNil(PlanLedger.shared.entry("plan-1"))
    }

    func testAReplayedOwnerKeepsOnlyWhatWasDelivered() {
        _ = delivery([
            remotePlan(by: "riley", id: "keep"),
            remotePlan(by: "riley", id: "gone", day: Self.day(2), title: "Tacos"),
            remotePlan(by: "sam", id: "elsewhere", zoneOwner: "other-host")
        ])
        let d = delivery([remotePlan(by: "riley", id: "keep")], replayed: ["host"])
        XCTAssertEqual(d.delta.removed.map(\.recordName), ["plan-gone"], "a replay carries no deletions, so absence is the deletion")
        XCTAssertNotNil(PlanLedger.shared.entry("plan-keep"))
        XCTAssertNotNil(PlanLedger.shared.entry("plan-elsewhere"), "another zone was not replayed and is left alone")
        XCTAssertTrue(d.delta.added.isEmpty, "a night the ledger already had is not added twice")
    }

    func testAPastDayDeletionIsHousekeepingNotNews() {
        _ = delivery([remotePlan(by: "riley", id: "past", day: Self.day(-1))])
        XCTAssertNotNil(PlanLedger.shared.entry("plan-past"))
        let d = delivery([], deleted: ["plan-past"])
        XCTAssertTrue(d.delta.removed.isEmpty)
        XCTAssertNil(PlanLedger.shared.entry("plan-past"))
        // And a past night arriving is not news either.
        let late = delivery([remotePlan(by: "riley", id: "late", day: Self.day(-2))])
        XCTAssertTrue(late.delta.added.isEmpty)
    }

    func testOnlyTheHouseholdsNightsAreDrawn() {
        _ = delivery([
            remotePlan(by: "riley", id: "ours"),
            remotePlan(by: "sam", id: "theirs", zoneOwner: "other-host")
        ])
        XCTAssertEqual(PlanLedger.shared.plans(on: Self.tomorrow).map(\.recordName), ["plan-ours"])
        PlanLedger.shared.householdOwner = "other-host"
        XCTAssertEqual(PlanLedger.shared.plans(on: Self.tomorrow).map(\.recordName), ["plan-theirs"])
        PlanLedger.shared.householdOwner = nil
        XCTAssertTrue(PlanLedger.shared.plans(on: Self.tomorrow).isEmpty, "unresolved draws nothing")
        XCTAssertNotNil(PlanLedger.shared.entry("plan-ours"), "the book keeps what it cannot draw")
    }

    func testTheDeltaIsComputedBeforeTheOverwrite() {
        _ = delivery([remotePlan(by: "riley", id: "1")])
        let d = delivery([remotePlan(by: "riley", id: "1", day: Self.day(2))])
        XCTAssertEqual(d.delta.changed.count, 1)
        XCTAssertEqual(d.delta.changed.first?.before.day, PlanDay.string(Self.tomorrow))
        XCTAssertEqual(d.delta.changed.first?.after.day, PlanDay.string(Self.day(2)))
        XCTAssertEqual(PlanLedger.shared.entry("plan-1")?.day, PlanDay.string(Self.day(2)))
    }

    func testARemovedAndAddedPairIsCancelled() {
        _ = delivery([remotePlan(by: "riley", id: "a")])
        // A second device backfilled a fresh shoppingID for the same night.
        let d = delivery([remotePlan(by: "riley", id: "b")], deleted: ["plan-a"])
        XCTAssertTrue(d.delta.added.isEmpty)
        XCTAssertTrue(d.delta.removed.isEmpty)
        XCTAssertNil(PlanLedger.shared.entry("plan-a"))
        XCTAssertNotNil(PlanLedger.shared.entry("plan-b"))
        XCTAssertTrue(digest(d).isEmpty)
    }

    // MARK: The digest

    func testSomebodyElsesNightIsNews() {
        let d = delivery([remotePlan(by: "riley", id: "1")])
        let notices = digest(d)
        XCTAssertEqual(notices.count, 1)
        let n = notices[0]
        XCTAssertEqual(n.kind, .plan)
        XCTAssertEqual(n.title, "Riley planned Sheet-pan chicken for tomorrow")
        XCTAssertEqual(n.body, "Riley is cooking.")
        XCTAssertEqual(n.line, "Riley planned Sheet-pan chicken for tomorrow.")
        XCTAssertEqual(n.template, "{actor} planned {object} for tomorrow.")
        XCTAssertEqual(n.objectTitle, "Sheet-pan chicken")
        XCTAssertEqual(n.actorID, "riley")
        XCTAssertEqual(n.identifier, TableNews.idPrefix + "plan:plan-1")
        XCTAssertEqual(n.rowKey, "plan:plan-1")
        XCTAssertFalse(n.key.contains("|"), "remember splits keys on the bar")
        XCTAssertTrue(n.key.hasPrefix("plan:plan-1:"))
        XCTAssertEqual(n.feedKind, .planShared)
        XCTAssertEqual(n.post, "")
        XCTAssertEqual(n.group, "The Table")
        XCTAssertEqual(n.deed, "Planned Sheet-pan chicken for tomorrow. Riley is cooking.")
        XCTAssertFalse(n.addressed)
        XCTAssertFalse(n.direct)
        XCTAssertFalse(n.passive)
        XCTAssertEqual(n.relevance, 0.6)
        XCTAssertEqual(DeepLink.planDay(in: n.link), Self.tomorrow)
        XCTAssertEqual(TableNews.thread(for: n), "table")
        XCTAssertEqual(NotificationRouter.category(for: .plan), NotificationRouter.Category.plan)
        XCTAssertEqual(TableNews.intent(for: n)?.sender?.displayName, "Riley")
    }

    func testANightStampedWithTheHostNameStillNamesTheAuthor() throws {
        let ale = HouseholdMember(name: "Alessandra", role: "partner", seat: .joined)
        ale.userRecordName = "ale"
        context.insert(ale)
        try context.save()
        var p = remotePlan(by: "ale", id: "wrap", title: "Crunch Wrap Supreme")
        p.authorName = "Nate Meadows"
        p.authorID = "ale"
        let n = try XCTUnwrap(digest(delivery([p])).first)
        XCTAssertEqual(n.title, "Alessandra planned Crunch Wrap Supreme for tomorrow")
        XCTAssertEqual(n.actor, "Alessandra")
        XCTAssertEqual(n.actorID, "ale")
    }

    func testANightWithNoRealCookNamesNobody() {
        let d = delivery([remotePlan(by: "riley", id: "1", cookID: "", cookName: "", cookSeat: "")])
        XCTAssertEqual(digest(d).first?.body, "")
        // A name typed for an invited seat is not a cook.
        let invited = delivery([remotePlan(
            by: "riley", id: "2", cookID: "", cookName: "Jo Alvarez",
            cookSeat: HouseholdMember.Seat.invited.rawValue
        )])
        XCTAssertEqual(digest(invited).first?.body, "")
    }

    func testYourOwnNightToCookSaysSoWithoutBeingAWordToYou() {
        let d = delivery([remotePlan(by: "riley", id: "1", cookID: me, cookName: "Nate Meadows",
                                     cookSeat: HouseholdMember.Seat.head.rawValue)])
        let n = digest(d)[0]
        XCTAssertEqual(n.body, "You cook.")
        XCTAssertFalse(n.addressed)
        XCTAssertFalse(n.direct)
        XCTAssertEqual(n.relevance, 0.8)
        // Never a word to you: quiet at night, never a sound.
        var night = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        night.hour = 23
        let late = TableNews.content(for: n, at: Calendar.current.date(from: night)!)
        XCTAssertEqual(late.interruptionLevel, .passive)
        XCTAssertNil(late.sound)
        night.hour = 12
        XCTAssertEqual(TableNews.content(for: n, at: Calendar.current.date(from: night)!).interruptionLevel, .active)
    }

    func testAMovedNightSaysWhere() {
        let first = delivery([remotePlan(by: "riley", id: "1")])
        TableNews.remember(digest(first).map(\.key))
        let moved = delivery([remotePlan(by: "riley", id: "1", day: Self.day(2))])
        let notices = digest(moved)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley moved Sheet-pan chicken to \(Stamp.nightPhrase(Self.day(2)))")
        XCTAssertEqual(notices[0].body, "Riley is cooking.")
        XCTAssertEqual(notices[0].rowKey, "plan:plan-1", "one night is one row")
        XCTAssertEqual(DeepLink.planDay(in: notices[0].link), Self.day(2))
    }

    func testBeingPutDownToCookIsSaidAsAFieldSet() {
        let first = delivery([remotePlan(by: "riley", id: "1")])
        TableNews.remember(digest(first).map(\.key))
        let handed = delivery([remotePlan(by: "riley", id: "1", cookID: me, cookName: "Nate Meadows",
                                          cookSeat: HouseholdMember.Seat.head.rawValue)])
        let notices = digest(handed)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley put you down to cook tomorrow: Sheet-pan chicken")
        XCTAssertEqual(notices[0].template, "{actor} put you down to cook tomorrow: {object}")
        XCTAssertEqual(notices[0].relevance, 0.8)
        XCTAssertFalse(notices[0].addressed)
        XCTAssertFalse(notices[0].direct)
    }

    func testARenamedNightSaysTheNewName() {
        let first = delivery([remotePlan(by: "riley", id: "1")])
        TableNews.remember(digest(first).map(\.key))
        let renamed = delivery([remotePlan(by: "riley", id: "1", title: "Tacos")])
        let notices = digest(renamed)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley changed tomorrow to Tacos")
        XCTAssertEqual(notices[0].objectTitle, "Tacos")
    }

    func testAnEditThatMeansNothingToTheReaderIsSilent() {
        let first = delivery([remotePlan(by: "riley", id: "1")])
        TableNews.remember(digest(first).map(\.key))
        var servings = remotePlan(by: "riley", id: "1")
        servings.servings = 6
        servings.tagline = "Extra lemons."
        let edited = delivery([servings])
        XCTAssertEqual(edited.delta.changed.count, 1, "the ledger saw the edit")
        XCTAssertTrue(digest(edited).isEmpty, "the digest did not")
    }

    func testANightTakenOffBeforeItWasReadIsARetraction() async {
        let first = delivery([remotePlan(by: "riley", id: "1")])
        await TableNews.deliver(first.changes, plans: first.delta, context: context)
        XCTAssertEqual(rows(eventKey: "plan:plan-1").count, 1)
        XCTAssertEqual(rows(eventKey: "plan:plan-1").first?.isRead, false)

        let gone = delivery([], deleted: ["plan-1"])
        XCTAssertEqual(gone.delta.removed.count, 1)
        XCTAssertTrue(digest(gone).isEmpty, "nothing is said about a night nobody read about")
        await TableNews.deliver(gone.changes, plans: gone.delta, context: context)
        XCTAssertTrue(rows(eventKey: "plan:plan-1").isEmpty, "the row went with the night")
    }

    /// A removal reaches this phone as a tombstone carrying its remover,
    /// not as a bare deletion: a deletion names nobody, and this sentence
    /// used to name the night's AUTHOR for somebody else's doing.
    func testANightTakenOffAfterItWasReadIsQuietNews() async {
        let first = delivery([remotePlan(by: "riley", id: "1")])
        await TableNews.deliver(first.changes, plans: first.delta, context: context)
        rows(eventKey: "plan:plan-1").first?.isRead = true
        try? context.save()

        var off = remotePlan(by: "riley", id: "1")
        off.removed = 1
        off.editorID = "riley"
        off.editorName = "Riley Park"
        let gone = delivery([off])
        let notices = digest(gone)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley took Sheet-pan chicken off tomorrow")
        XCTAssertTrue(notices[0].passive)
        XCTAssertNil(notices[0].photo)
        XCTAssertEqual(NewsPreferences.category(for: notices[0].kind, addressed: notices[0].addressed), .planning)
        await TableNews.deliver(gone.changes, plans: gone.delta, context: context)
        let row = rows(eventKey: "plan:plan-1").first
        XCTAssertEqual(row?.body, "Riley took Sheet-pan chicken off tomorrow.")
        XCTAssertEqual(row?.isRead, false, "news again, on the same row")
    }

    func testMyOwnNightIsIgnoredByTheDigest() {
        // The ledger drops it; and a delta that somehow carried it would
        // still be ignored, because "not mine" is decided in both places.
        var delta = PlanLedger.Delta()
        delta.added = [PlanLedger.Entry(remotePlan(by: me, id: "mine", cookID: me, cookName: "Nate Meadows"))]
        XCTAssertTrue(TableNews.digest(TableShare.Changes(), newSeats: [], plans: delta, context: context).isEmpty)
        XCTAssertTrue(digest(delivery([remotePlan(by: me, id: "again", cookID: me, cookName: "Nate Meadows")])).isEmpty)
    }

    func testAReplayWindowsPlanNoticesOnChangedAt() {
        var old = delivery([
            remotePlan(by: "riley", id: "old", changedAt: .now.addingTimeInterval(-3 * 24 * 3600)),
            remotePlan(by: "riley", id: "recent", day: Self.day(2), changedAt: .now.addingTimeInterval(-3600))
        ])
        old.changes.replayed = true
        XCTAssertEqual(digest(old).map(\.rowKey), ["plan:plan-recent"])
        // An incremental delta is trusted whole: a night planned on a plane
        // last week and uploaded today is told once, now.
        let late = delivery([remotePlan(by: "riley", id: "late", day: Self.day(3),
                                        changedAt: .now.addingTimeInterval(-7 * 24 * 3600))])
        XCTAssertEqual(digest(late).count, 1)
    }

    func testAPlanNoticeIsRaisedOnce() {
        // One record, delivered twice: a replay hands back the record as
        // the zone stores it, `changedAt` included, so the same value is
        // reused rather than minted again.
        let night = remotePlan(by: "riley", id: "once")
        let d = delivery([night])
        let first = digest(d)
        XCTAssertEqual(first.count, 1)
        TableNews.remember(first.map(\.key))
        XCTAssertTrue(digest(d).isEmpty)
        // The same night replayed from the beginning of the zone: the
        // ledger already has it, so it is not even added.
        let replay = delivery([night], replayed: ["host"])
        XCTAssertTrue(replay.delta.isEmpty)
        XCTAssertTrue(digest(replay).isEmpty)
    }

    func testLearnNamesFoldsTheAuthorAndTheCook() {
        var changes = TableShare.Changes()
        changes.plans = [remotePlan(by: "riley", id: "1", cookID: "sam", cookName: "Sam Okafor")]
        TableNews.learnNames(from: changes)
        XCTAssertEqual(TableNews.name(for: "riley"), "Riley Park")
        XCTAssertEqual(TableNews.name(for: "sam"), "Sam Okafor")
    }

    // MARK: Preferences, presentation, links, phrases

    func testPlanNoticesAnswerToThePlanningSwitchBeforeTheAddressedQuestion() {
        XCTAssertEqual(NewsPreferences.category(for: TableNews.Notice.Kind.plan, addressed: true), .planning)
        XCTAssertEqual(NewsPreferences.category(for: TableNews.Notice.Kind.plan, addressed: false), .planning)
        XCTAssertEqual(NewsPreferences.category(for: PlatedNotificationKind.planShared, addressed: true), .planning)
        XCTAssertEqual(NewsPreferences.category(for: PlatedNotificationKind.planShared, addressed: false), .planning)

        let d = delivery([remotePlan(by: "riley", id: "1")])
        let n = digest(d)[0]
        XCTAssertTrue(NewsPreferences.allows(n))
        NewsPreferences.set(.planning, on: false)
        XCTAssertFalse(NewsPreferences.allows(n), "off keeps it to the list")
        let row = PlatedNotification(
            kind: .planShared, actorName: "Riley Park", body: n.line,
            link: n.link.absoluteString, eventKey: n.rowKey
        )
        XCTAssertFalse(NewsPreferences.counts(row), "and off the icon")
        NewsPreferences.set(.planning, on: true)
        XCTAssertTrue(NewsPreferences.counts(row))
        XCTAssertTrue(PlatedNotificationKind.planShared.isAboutSomebody)
    }

    func testAPlanBannerIsKeptToTheListWhileTheWeekIsOnScreen() {
        XCTAssertEqual(
            NotificationRouter.presentation(post: "", kind: "plan", openPost: nil, feedVisible: false, planVisible: true),
            [.list]
        )
        XCTAssertEqual(
            NotificationRouter.presentation(post: "", kind: "plan", openPost: nil, feedVisible: true, planVisible: false),
            [.banner, .list, .sound]
        )
        XCTAssertEqual(
            NotificationRouter.presentation(post: "post-1", kind: "dish", openPost: nil, feedVisible: false, planVisible: true),
            [.banner, .list, .sound],
            "the week on screen says nothing about a dish"
        )
        XCTAssertEqual(TableNews.Notice.Kind.plan.rawValue, "plan", "the router matches on the raw value")
    }

    func testPlanLinksRoundTrip() {
        let noon = Self.tomorrow.addingTimeInterval(12 * 3600)
        let url = DeepLink.url(plan: noon)
        XCTAssertEqual(DeepLink.destination(for: url), .plan)
        XCTAssertEqual(DeepLink.planDay(in: url), Self.tomorrow, "a night is a day, not a moment")
        XCTAssertNil(DeepLink.planDay(in: DeepLink.url(.plan)))
        XCTAssertNil(DeepLink.planDay(in: DeepLink.url(post: "post-1")))
        XCTAssertEqual(PlanDay.date(PlanDay.string(noon)), Self.tomorrow)
    }

    func testNightPhrasesLadder() {
        XCTAssertEqual(Stamp.nightPhrase(Self.today), "tonight")
        XCTAssertEqual(Stamp.nightPhrase(Self.tomorrow), "tomorrow")
        XCTAssertEqual(Stamp.nightPhrase(Self.day(-1)), "yesterday")
        XCTAssertEqual(Stamp.nightPhrase(Self.day(3)), Stamp.weekdayFormat.string(from: Self.day(3)))
        XCTAssertEqual(Stamp.nightPhrase(Self.day(5)), Stamp.weekdayFormat.string(from: Self.day(5)))
        XCTAssertEqual(Stamp.nightPhrase(Self.day(-3)), "last \(Stamp.weekdayFormat.string(from: Self.day(-3)))")
        // Six days out a weekday names a week that is not the week it
        // means, so it becomes a date, with the year once the year turns.
        let week = Self.day(6)
        let sameYear = Calendar.current.isDate(week, equalTo: .now, toGranularity: .year)
        XCTAssertEqual(
            Stamp.nightPhrase(week),
            (sameYear ? Stamp.dateFormat : Stamp.datedYearFormat).string(from: week)
        )
        XCTAssertEqual(Stamp.nightPhrase(Self.day(400)), Stamp.datedYearFormat.string(from: Self.day(400)))
        // The sentence owns the preposition, so no rung may carry one.
        for offset in [-5, -1, 0, 1, 3, 6, 10, 400] {
            XCTAssertFalse(Stamp.nightPhrase(Self.day(offset)).hasPrefix("on "), "day \(offset)")
        }
    }

    /// A night a week or more out is the common case (the window runs
    /// ninety days ahead), and every title has to read as a sentence
    /// there, not "planned Tacos for on 12 Sep".
    func testANightAWeekOutReadsAsASentence() async {
        let far = Self.day(10), farther = Self.day(12)
        let first = delivery([remotePlan(by: "riley", id: "1", day: far, changedAt: Self.stamp(-2))])
        let planned = digest(first)
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned[0].title, "Riley planned Sheet-pan chicken for \(Stamp.nightPhrase(far))")
        TableNews.remember(planned.map(\.key))

        let moved = delivery([remotePlan(by: "riley", id: "1", day: farther, changedAt: Self.stamp(-1))])
        let movedNotices = digest(moved)
        XCTAssertEqual(movedNotices.count, 1)
        XCTAssertEqual(movedNotices[0].title, "Riley moved Sheet-pan chicken to \(Stamp.nightPhrase(farther))")
        await TableNews.deliver(moved.changes, plans: moved.delta, context: context)
        rows(eventKey: "plan:plan-1").first?.isRead = true
        try? context.save()

        // A tombstone, not a bare deletion: a deletion names nobody, and
        // this sentence used to name the night's author for it.
        var off = remotePlan(by: "riley", id: "1", day: farther, changedAt: Self.stamp(-1))
        off.removed = 1
        off.editorID = "riley"
        off.editorName = "Riley Park"
        let gone = delivery([off])
        let offNotices = digest(gone)
        XCTAssertEqual(offNotices.count, 1)
        XCTAssertEqual(offNotices[0].title, "Riley took Sheet-pan chicken off \(Stamp.nightPhrase(farther))")
        for n in planned + movedNotices + offNotices {
            XCTAssertFalse(n.title.contains(" on "), n.title)
            XCTAssertFalse(n.line.contains(" on "), n.line)
        }
    }

    /// The memory is of keys. A key that is a pure function of the
    /// night's state swallows a return to a state it has been in, and the
    /// bell keeps saying "moved to Friday" about a night the planner draws
    /// on Thursday.
    func testANightMovedBackIsSaidAgain() {
        let first = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(-2))])
        TableNews.remember(digest(first).map(\.key))
        let away = delivery([remotePlan(by: "riley", id: "1", day: Self.day(2), changedAt: Self.stamp(-1))])
        let awayNotices = digest(away)
        XCTAssertEqual(awayNotices.count, 1)
        TableNews.remember(awayNotices.map(\.key))
        let back = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        let notices = digest(back)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley moved Sheet-pan chicken to tomorrow")
    }

    func testACookHandedBackIsSaidAgain() {
        let head = HouseholdMember.Seat.head.rawValue
        let first = delivery([remotePlan(by: "riley", id: "1", cookID: me, cookName: "Nate Meadows",
                                         cookSeat: head, changedAt: Self.stamp(-2))])
        let planned = digest(first)
        XCTAssertEqual(planned.first?.body, "You cook.")
        TableNews.remember(planned.map(\.key))
        // Handed to Sam: the week looks the same from here, so nothing.
        let toSam = delivery([remotePlan(by: "riley", id: "1", cookID: "sam", cookName: "Sam Okafor",
                                         changedAt: Self.stamp(-1))])
        XCTAssertTrue(digest(toSam).isEmpty)
        let back = delivery([remotePlan(by: "riley", id: "1", cookID: me, cookName: "Nate Meadows",
                                        cookSeat: head, changedAt: Self.stamp(0))])
        let notices = digest(back)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley put you down to cook tomorrow: Sheet-pan chicken")
    }

    /// A night that is simply GONE takes its row down and says nothing.
    ///
    /// This used to say "Riley took Sheet-pan chicken off Thursday", naming
    /// the night's AUTHOR because a bare absence carries nobody. A removal
    /// is a write now and carries its remover, so the only things left on
    /// this path are an age-out, a departed member's sweep, and a record the
    /// author's own publisher cleared after acting on the removal. In every
    /// one of those, naming the author is naming the wrong person, and
    /// docs/notifications.md is explicit: if the sentence cannot name the
    /// person, nothing is sent. The row still goes.
    func testANightTakenOffOnAReplayTakesItsRowDownWithoutNamingAnybody() async {
        let first = delivery([remotePlan(by: "riley", id: "1", day: Self.day(4),
                                         changedAt: .now.addingTimeInterval(-4 * 24 * 3600))])
        await TableNews.deliver(first.changes, plans: first.delta, context: context)
        rows(eventKey: "plan:plan-1").first?.isRead = true
        try? context.save()
        var gone = delivery([], replayed: ["host"])
        gone.changes.replayed = true
        XCTAssertEqual(gone.delta.removed.count, 1, "the night still leaves the ledger")
        XCTAssertTrue(digest(gone).isEmpty, "and nothing is said, because nothing true can be")
    }

    /// A removal that carries its remover names them, which is the whole
    /// reason it is a write rather than a delete.
    func testATombstoneNamesThePersonWhoTookTheNightOff() async {
        let first = delivery([remotePlan(by: "riley", id: "1", day: Self.day(4))])
        await TableNews.deliver(first.changes, plans: first.delta, context: context)
        rows(eventKey: "plan:plan-1").first?.isRead = true
        try? context.save()
        var off = remotePlan(by: "riley", id: "1", day: Self.day(4))
        off.removed = 1
        off.editorID = "sam"
        off.editorName = "Sam Okafor"
        let gone = delivery([off])
        XCTAssertEqual(gone.delta.removed.count, 1)
        let notices = digest(gone)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(
            notices[0].title,
            "Sam took Sheet-pan chicken off \(Stamp.nightPhrase(Self.day(4)))",
            "the remover, never the night's author"
        )
    }

    // MARK: Reminders

    func testALocalNightWinsTheDayForReminders() {
        let a = PlanDay.string(Self.tomorrow)
        let b = PlanDay.string(Self.day(2))
        let nights = [
            PlanLedger.Entry(remotePlan(by: "riley", id: "a", day: Self.tomorrow, cookID: me)),
            PlanLedger.Entry(remotePlan(by: "riley", id: "b2", day: Self.day(2), title: "Tacos", cookID: me)),
            PlanLedger.Entry(remotePlan(by: "riley", id: "b1", day: Self.day(2), title: "Curry", cookID: me))
        ]
        // A local meal on day A, any slot, is that plan's night to remind.
        let chosen = NotificationScheduler.remoteTurns(nights, localDays: [a])
        XCTAssertEqual(chosen.map(\.day), [b], "one turn reminder per day, ever")
        XCTAssertEqual(chosen.map(\.title), ["Curry"], "the first by day, slot and title")
        XCTAssertTrue(NotificationScheduler.remoteTurns(nights, localDays: [a, b]).isEmpty)
        XCTAssertEqual(NotificationScheduler.remoteTurns([], localDays: []).count, 0)
        XCTAssertEqual(NotificationScheduler.remoteTurnPrefix, "plated.turn.remote.")
    }

    func testMyNightsAreTheOnesWhoseCookIsMe() {
        _ = delivery([
            remotePlan(by: "riley", id: "mine", cookID: me, cookName: "Nate Meadows",
                       cookSeat: HouseholdMember.Seat.head.rawValue),
            remotePlan(by: "riley", id: "theirs", day: Self.day(2)),
            remotePlan(by: "sam", id: "other-table", day: Self.day(3), cookID: me, cookName: "Nate Meadows",
                       cookSeat: HouseholdMember.Seat.head.rawValue, zoneOwner: "other-host")
        ])
        XCTAssertEqual(PlanLedger.shared.myNights().map(\.recordName), ["plan-mine"],
                       "by identity, and only in the household's zone")
        XCTAssertEqual(PlanLedger.shared.cookLine(for: PlanLedger.shared.entry("plan-mine")!), "You're cooking")
        XCTAssertEqual(PlanLedger.shared.cookLine(for: PlanLedger.shared.entry("plan-theirs")!), "Riley is cooking")
    }

    // MARK: A change this phone made

    func testThisPhonesOwnEditComesBackAsNothingToSay() {
        // Riley planned it; this phone changed it and the zone said yes.
        let first = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        TableNews.remember(digest(first).map(\.key))
        let night = PlanLedger.shared.entry("plan-1")!
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        PlanLedger.shared.applyLocally(edit)
        let landed = Self.stamp(60)
        PlanLedger.shared.settle(edit, .landed(landed))

        // The record comes back the way it was saved. Nothing here is news:
        // a notice about the reader's own action is the one rule
        // docs/notifications.md breaks for nothing.
        var again = remotePlan(by: "riley", id: "1", title: "Ragu", changedAt: landed)
        // The record keeps the night's own birthday; only the helper above
        // ties the two together.
        again.createdAt = night.createdAt
        let back = delivery([again])
        XCTAssertTrue(back.delta.changed.isEmpty, "the ledger already holds exactly this")
        XCTAssertTrue(digest(back).isEmpty)
    }

    // MARK: Who changed the night

    func testAnEditedNightNamesTheEditorAndNotItsAuthor() {
        // Riley planned it, Sam changed it. "Riley changed tomorrow to
        // Ragu" is a false sentence about a real person.
        let first = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        TableNews.remember(digest(first).map(\.key))
        let edited = delivery([remotePlan(
            by: "riley", id: "1", title: "Ragu", changedAt: Self.stamp(60),
            editorID: "sam", editorName: "Sam Okafor"
        )])
        let notices = digest(edited)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Sam changed tomorrow to Ragu")
        XCTAssertEqual(notices[0].actorID, "sam", "the bell row composes with the editor's name")
        XCTAssertEqual(notices[0].actor, "Sam Okafor")
    }

    func testAMovedNightNamesWhoMovedIt() {
        let first = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        TableNews.remember(digest(first).map(\.key))
        let moved = delivery([remotePlan(
            by: "riley", id: "1", day: Self.day(2), changedAt: Self.stamp(60),
            editorID: "sam", editorName: "Sam Okafor"
        )])
        XCTAssertEqual(
            digest(moved).first?.title,
            "Sam moved Sheet-pan chicken to \(Stamp.nightPhrase(Self.day(2)))"
        )
    }

    func testANightThisPhoneChangedRaisesNothingThoughItIsSomebodyElses() {
        // The author is Riley, so the old guard (`authorID != me`) let it
        // through and told this phone about its own change.
        let first = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        TableNews.remember(digest(first).map(\.key))
        let mine = delivery([remotePlan(
            by: "riley", id: "1", title: "Ragu", changedAt: Self.stamp(60),
            editorID: me, editorName: "Nate Meadows"
        )])
        XCTAssertEqual(mine.delta.changed.count, 1, "the ledger took the new version")
        XCTAssertTrue(digest(mine).isEmpty, "and said nothing about the reader's own change")
    }

    func testANightWithNoEditorStillNamesItsAuthor() {
        // Every record written before the editor fields, and every night
        // its own author republishes: the author is the only answer there
        // is, and it is the right one.
        let first = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        TableNews.remember(digest(first).map(\.key))
        let renamed = delivery([remotePlan(by: "riley", id: "1", title: "Tacos", changedAt: Self.stamp(60))])
        let notices = digest(renamed)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley changed tomorrow to Tacos")
        XCTAssertEqual(notices[0].actorID, "riley")
    }

    func testAnEditorThisPhoneCannotNameSaysNothingRatherThanSomeone() {
        let first = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        TableNews.remember(digest(first).map(\.key))
        let anonymous = delivery([remotePlan(
            by: "riley", id: "1", title: "Ragu", changedAt: Self.stamp(60),
            editorID: "_stranger", editorName: ""
        )])
        XCTAssertEqual(anonymous.delta.changed.count, 1)
        XCTAssertTrue(
            digest(anonymous).isEmpty,
            "named, or not sent: naming the author here would print the false sentence again"
        )
    }

    func testANewlyPlannedNightStillNamesItsAuthor() {
        // A night nobody has edited yet carries the author as its editor,
        // which is the same person; the sentence is about the planning.
        let d = delivery([remotePlan(
            by: "riley", id: "1", editorID: "riley", editorName: "Riley Park"
        )])
        let notices = digest(d)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Riley planned Sheet-pan chicken for tomorrow")
        XCTAssertEqual(notices[0].actorID, "riley")
    }

    func testLearnNamesFoldsTheEditor() {
        var changes = TableShare.Changes()
        changes.plans = [remotePlan(by: "riley", id: "1", editorID: "sam", editorName: "Sam Okafor")]
        TableNews.learnNames(from: changes)
        XCTAssertEqual(TableNews.name(for: "sam"), "Sam Okafor")
    }

    func testANightSomebodyElseChangedIsStillNewsWhileThisPhoneHasOneWaiting() {
        _ = delivery([remotePlan(by: "riley", id: "1", changedAt: Self.stamp(0))])
        let night = PlanLedger.shared.entry("plan-1")!
        var edit = PlanShare.Edit(changing: night)
        edit.servings = 8
        PlanLedger.shared.applyLocally(edit)
        let theirs = delivery([remotePlan(by: "riley", id: "1", title: "Katsu curry", changedAt: Self.stamp(30))])
        XCTAssertEqual(digest(theirs).first?.title, "Riley changed tomorrow to Katsu curry")
        XCTAssertNotNil(
            PlanLedger.shared.entry("plan-1")?.pendingSince,
            "a delivery does not send what this phone has still to send"
        )
    }

    // MARK: One sitting, one interruption

    /// A household enters a week in one go. Each night is its own record,
    /// its own publisher pass and its own delivery, so without a window
    /// across deliveries that is seven screen-lighting banners on every
    /// other phone. The first still speaks; the rest arrive quietly and are
    /// all still in the bell.
    func testAPlanningBurstInterruptsOnce() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = digest(delivery([remotePlan(by: "riley", id: "n1", title: "Tacos")]), at: start)
        XCTAssertEqual(first.count, 1)
        XCTAssertFalse(first[0].passive, "the first night of a sitting is the first word of something new")

        // Four minutes later, a second night, a second delivery.
        let second = digest(
            delivery([remotePlan(by: "riley", id: "n2", day: PlanNewsTests.inTwoDays, title: "Ragu")]),
            at: start.addingTimeInterval(4 * 60)
        )
        XCTAssertEqual(second.count, 1, "still news, still in the bell")
        XCTAssertTrue(second[0].passive, "a second night in the same sitting does not light the screen again")
    }

    /// The window may only be pushed forward by a night that actually
    /// spoke. Seeded from the stored value and written back unconditionally,
    /// every delivery re-stamped it, including the great majority carrying
    /// no planned night, so a household that pulls often silenced its own
    /// planning banners permanently after the first.
    func testADeliveryWithNoPlannedNightDoesNotHoldTheWindowOpen() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = digest(delivery([remotePlan(by: "riley", id: "n1", title: "Tacos")]), at: start)
        XCTAssertFalse(first[0].passive)

        // Forty minutes of ordinary deliveries carrying nothing planned.
        for minute in stride(from: 5, through: 40, by: 5) {
            _ = digest(delivery([]), at: start.addingTimeInterval(Double(minute) * 60))
        }
        // Fifty minutes after the FIRST night, the sitting is over.
        let later = digest(
            delivery([remotePlan(by: "riley", id: "n2", day: PlanNewsTests.inTwoDays, title: "Ragu")]),
            at: start.addingTimeInterval(50 * 60)
        )
        XCTAssertEqual(later.count, 1)
        XCTAssertFalse(later[0].passive, "the empty deliveries must not have held the window open")
    }

    /// Tomorrow evening is a different sitting, not a continuation of this
    /// one, so it speaks again.
    func testTheNextSittingSpeaksAgain() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        _ = digest(delivery([remotePlan(by: "riley", id: "n1", title: "Tacos")]), at: start)
        let later = digest(
            delivery([remotePlan(by: "riley", id: "n2", day: PlanNewsTests.inTwoDays, title: "Ragu")]),
            at: start.addingTimeInterval(3 * 60 * 60)
        )
        XCTAssertEqual(later.count, 1)
        XCTAssertFalse(later[0].passive)
    }

}
