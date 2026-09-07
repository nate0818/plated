import XCTest
import SwiftData
import UserNotifications
@testable import Plated

/// The digest is pure: a delta in, a list of notices out. These hold it to
/// the rules docs/notifications.md promises, so a change that quietly
/// starts narrating your own plates, or raising a banner twice after a
/// change-token reset, fails here rather than on somebody's lock screen.
@MainActor
final class TableNewsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let me = TableIdentity.cached

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        TableNews.forgetAll()
        TableLedger.shared.clear()
        // The digest refuses to decide anything on a placeholder identity,
        // which is what a simulator without iCloud has. The rehearsal
        // switch is the same door the debug flag uses.
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
        // Never leave a development simulator's switch off.
        UserDefaults.standard.removeObject(forKey: TableNews.tableOnKey)
        container = nil
    }

    // MARK: Helpers

    private func remoteDish(
        by author: String, id: String, title: String = "Sheet-pan chicken",
        caption: String = "Crispy edges tonight.", at: Date = .now
    ) -> TableShare.RemotePost {
        var p = TableShare.RemotePost()
        p.recordName = "post-\(id)"
        p.authorID = author
        p.authorName = author == "riley" ? "Riley Park" : "Sam Okafor"
        p.dishTitle = title
        p.caption = caption
        p.createdAt = at
        return p
    }

    @discardableResult
    private func myPost(title: String = "Ragù") -> TablePost {
        let post = TablePost(authorName: "Nate Meadows", dishTitle: title)
        post.authorID = me
        post.isPublished = true
        context.insert(post)
        try? context.save()
        return post
    }

    private func note(
        on post: TablePost, by author: String, text: String,
        replyTo: String = "", mentions: [String] = []
    ) -> TableShare.RemoteNote {
        var n = TableShare.RemoteNote()
        n.recordName = "note-\(UUID().uuidString)"
        n.post = post.shareRecordName
        n.authorID = author
        n.authorName = author == "riley" ? "Riley Park" : "Sam Okafor"
        n.text = text
        n.replyToName = replyTo
        n.mentions = mentions
        return n
    }

    private func plate(on post: TablePost, by author: String, at: Date = .now) -> TableShare.RemoteReaction {
        var r = TableShare.RemoteReaction()
        r.post = post.shareRecordName
        r.author = author
        r.authorName = author == "riley" ? "Riley Park" : "Sam Okafor"
        r.value = 1
        r.at = at
        return r
    }

    // MARK: Dishes

    func testSomebodyElsesDishIsNews() {
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "1")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .dish)
        XCTAssertEqual(notices[0].title, "Riley plated Sheet-pan chicken")
        XCTAssertEqual(notices[0].body, "Crispy edges tonight.")
        XCTAssertEqual(DeepLink.postID(in: notices[0].link), "post-1")
        XCTAssertFalse(notices[0].direct)
    }

    func testMyOwnDishFromAnotherDeviceIsNotNews() {
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: me, id: "mine")]
        XCTAssertTrue(TableNews.digest(changes, newSeats: [], context: context).isEmpty)
    }

    func testAReplayedZoneIsWindowedToRecentHistory() {
        var changes = TableShare.Changes()
        changes.replayed = true
        changes.posts = [
            remoteDish(by: "riley", id: "old", at: .now.addingTimeInterval(-3 * 24 * 3600)),
            remoteDish(by: "riley", id: "recent", at: .now.addingTimeInterval(-3600))
        ]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(notices.map(\.post), ["post-recent"])
    }

    func testAnIncrementalDeltaIsTrustedWhole() {
        // Late delivery is not old news: a dish written on a plane last
        // week and uploaded today arrives in an incremental delta and is
        // told once, now.
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "late", at: .now.addingTimeInterval(-7 * 24 * 3600))]
        XCTAssertEqual(TableNews.digest(changes, newSeats: [], context: context).count, 1)
    }

    func testBeingTaggedInADishIsDirect() {
        var changes = TableShare.Changes()
        var dish = remoteDish(by: "riley", id: "tagged")
        dish.taggedNames = ["Nate Meadows"]
        changes.posts = [dish]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(notices.first?.title, "Riley tagged you in Sheet-pan chicken")
        XCTAssertTrue(notices.first?.direct ?? false)
    }

    func testAReplayedZoneRaisesNothingTwice() {
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "once")]
        let first = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(first.count, 1)
        TableNews.remember(first.map(\.key))
        XCTAssertTrue(TableNews.digest(changes, newSeats: [], context: context).isEmpty)
    }

    // MARK: Comments

    func testACommentOnMyDishIsDirect() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.notes = [note(on: post, by: "sam", text: "Saving this for Sunday.")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .comment)
        XCTAssertTrue(notices[0].direct)
        XCTAssertEqual(notices[0].title, "Sam commented on your Ragù")
        XCTAssertEqual(notices[0].body, "Saving this for Sunday.")
    }

    func testAReplyToMeOnSomebodyElsesDishIsDirect() {
        let theirs = TablePost(authorName: "Riley Park", dishTitle: "Tacos")
        theirs.authorID = "riley"
        theirs.isRemote = true
        context.insert(theirs)
        var changes = TableShare.Changes()
        changes.notes = [note(on: theirs, by: "sam", text: "Agreed.", replyTo: "Nate")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Sam replied to you")
        XCTAssertTrue(notices[0].direct)
    }

    func testACommentBetweenOtherPeopleIsNotMine() {
        let theirs = TablePost(authorName: "Riley Park", dishTitle: "Tacos")
        theirs.authorID = "riley"
        theirs.isRemote = true
        context.insert(theirs)
        var changes = TableShare.Changes()
        changes.notes = [note(on: theirs, by: "sam", text: "Looks great.")]
        XCTAssertTrue(TableNews.digest(changes, newSeats: [], context: context).isEmpty)
    }

    // MARK: Plates

    func testPlatesOnMyDishCoalesceIntoOneCountedLine() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.reactions = [
            plate(on: post, by: "riley", at: .now.addingTimeInterval(-60)),
            plate(on: post, by: "sam")
        ]
        // The digest reads the ledger, which merge has already folded, and
        // names people from what earlier deliveries taught it.
        TableShare.merge(changes, into: context)
        TableNews.learnNames(from: changes)
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].kind, .plates)
        XCTAssertEqual(notices[0].identifier, TableNews.idPrefix + "plates:\(post.shareRecordName)")
        XCTAssertEqual(notices[0].rowKey, "plates:\(post.shareRecordName)")
        XCTAssertEqual(notices[0].title, "Riley and Sam plated your Ragù")
    }

    func testASecondPlateUpdatesTheSameLineWithEveryoneSoFar() {
        let post = myPost()
        var first = TableShare.Changes()
        first.reactions = [plate(on: post, by: "riley", at: .now.addingTimeInterval(-60))]
        TableShare.merge(first, into: context)
        TableNews.learnNames(from: first)
        let one = TableNews.digest(first, newSeats: [], context: context)
        XCTAssertEqual(one.first?.title, "Riley plated your Ragù")
        TableNews.remember(one.map(\.key))

        var second = TableShare.Changes()
        second.reactions = [plate(on: post, by: "sam")]
        TableShare.merge(second, into: context)
        TableNews.learnNames(from: second)
        let two = TableNews.digest(second, newSeats: [], context: context)
        XCTAssertEqual(two.first?.title, "Riley and Sam plated your Ragù")
        XCTAssertEqual(two.first?.identifier, one.first?.identifier)
    }

    func testAPlateFromSomebodyThePhoneCannotNameIsNotASentence() {
        let post = myPost()
        var changes = TableShare.Changes()
        var nameless = plate(on: post, by: "legacy-id")
        nameless.authorName = ""
        changes.reactions = [nameless]
        TableShare.merge(changes, into: context)
        TableNews.learnNames(from: changes)
        XCTAssertTrue(TableNews.digest(changes, newSeats: [], context: context).isEmpty)
    }

    func testNamesListReadsLikeASentence() {
        XCTAssertEqual(TableNews.list(["Riley"], of: 1), "Riley")
        XCTAssertEqual(TableNews.list(["Riley", "Sam"], of: 2), "Riley and Sam")
        XCTAssertEqual(TableNews.list(["Riley", "Sam", "Jo"], of: 3), "Riley, Sam and Jo")
        XCTAssertEqual(TableNews.list(["Riley", "Sam", "Jo"], of: 4), "Riley, Sam and 2 others")
        XCTAssertEqual(TableNews.list(["Riley"], of: 2), "Riley and 1 other")
    }

    func testAJoinedSeatIsSaidOutLoudButNotWrittenTwice() {
        let joiner = HouseholdMember(name: "Jo Alvarez", role: "member", seat: .joined)
        joiner.participantID = "participant-jo"
        context.insert(joiner)
        let notices = TableNews.digest(TableShare.Changes(), newSeats: [joiner], context: context)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "Jo joined your table")
        XCTAssertEqual(notices[0].body, "They can see the Table now.")
        XCTAssertFalse(notices[0].writesRow)
    }

    func testMyOwnPlateIsNeverNarratedBackToMe() {
        let post = myPost()
        var changes = TableShare.Changes()
        var mine = plate(on: post, by: me)
        mine.authorName = "Nate Meadows"
        changes.reactions = [mine]
        TableShare.merge(changes, into: context)
        XCTAssertTrue(TableNews.digest(changes, newSeats: [], context: context).isEmpty)
    }

    // MARK: Selection

    func testSelectionCapsBannersAndFoldsTheRest() {
        var changes = TableShare.Changes()
        changes.posts = (1...6).map { remoteDish(by: "riley", id: "\($0)") }
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(notices.count, 6)
        let shown = TableNews.select(notices)
        XCTAssertEqual(shown.count, 5)
        XCTAssertEqual(shown.last?.kind, .more)
        XCTAssertEqual(shown.last?.title, "2 more from Riley")
    }

    func testDirectNewsIsShownBeforeAmbientNews() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "ambient", at: .now)]
        changes.notes = [note(on: post, by: "sam", text: "Yes please.")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(TableNews.select(notices).first?.kind, .comment)
    }

    // MARK: Time and links

    func testQuietHours() {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = 23
        XCTAssertTrue(TableNews.isQuietHour(Calendar.current.date(from: c)!))
        c.hour = 7
        XCTAssertTrue(TableNews.isQuietHour(Calendar.current.date(from: c)!))
        c.hour = 8
        XCTAssertFalse(TableNews.isQuietHour(Calendar.current.date(from: c)!))
        c.hour = 12
        XCTAssertFalse(TableNews.isQuietHour(Calendar.current.date(from: c)!))
    }

    func testPostLinksRoundTrip() {
        let url = DeepLink.url(post: "post-ABC")
        XCTAssertEqual(DeepLink.destination(for: url), .post)
        XCTAssertEqual(DeepLink.postID(in: url), "post-ABC")
        XCTAssertNil(DeepLink.postID(in: DeepLink.url(.table)))
        XCTAssertEqual(DeepLink.destination(for: URL(string: "plated://activity")!), .activity)
    }

    func testAnInviteLinkCarriesWhoAndWhereAndRefusesPlainHTTP() {
        let good = URL(string: "plated://invite?s=https%3A%2F%2Fwww.icloud.com%2Fshare%2Fabc&from=Riley")!
        let invitation = DeepLink.invitation(in: good)
        XCTAssertEqual(invitation?.from, "Riley")
        XCTAssertEqual(invitation?.share.host, "www.icloud.com")
        let bad = URL(string: "plated://invite?s=http%3A%2F%2Fevil.example%2Fshare")!
        XCTAssertNil(DeepLink.invitation(in: bad))
    }

    // MARK: Passive plates, threads, photographs

    func testAPlateNeverLightsTheScreenButTheKissDoes() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.reactions = [plate(on: post, by: "riley")]
        TableShare.merge(changes, into: context)
        TableNews.learnNames(from: changes)
        let plates = TableNews.digest(changes, newSeats: [], context: context)
        XCTAssertEqual(plates.first?.kind, .plates)
        XCTAssertTrue(plates.first?.passive ?? false)
        var noon = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        noon.hour = 12
        let content = TableNews.content(for: plates[0], at: Calendar.current.date(from: noon)!)
        XCTAssertEqual(content.interruptionLevel, .passive)
        XCTAssertNil(content.sound)

        // Everybody at a three-seat table: the kiss, which is direct and active.
        var everyone = TableShare.Changes()
        var mine = plate(on: post, by: me)
        mine.authorName = "Nate Meadows"
        everyone.reactions = [plate(on: post, by: "sam"), mine]
        TableShare.merge(everyone, into: context)
        TableNews.learnNames(from: everyone)
        let kiss = TableNews.digest(everyone, newSeats: [], context: context)
        XCTAssertEqual(kiss.first?.kind, .kiss)
        XCTAssertEqual(kiss.first?.title, "Everyone plated your Ragù")
        XCTAssertFalse(kiss.first?.passive ?? true)
        XCTAssertEqual(TableNews.content(for: kiss[0], at: Calendar.current.date(from: noon)!).interruptionLevel, .active)
    }

    func testPassiveNoticesNeverCrowdOutADish() {
        var changes = TableShare.Changes()
        for i in 1...5 {
            let post = myPost(title: "Dish \(i)")
            changes.reactions.append(plate(on: post, by: "riley"))
        }
        changes.posts = [remoteDish(by: "sam", id: "fresh")]
        TableShare.merge(changes, into: context)
        TableNews.learnNames(from: changes)
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        let shown = TableNews.select(notices)
        XCTAssertEqual(shown.filter { !$0.passive }.map(\.kind), [.dish])
        XCTAssertEqual(shown.filter(\.passive).count, 5)
        XCTAssertFalse(shown.contains { $0.kind == .more })
    }

    func testRoomNewsSharesOneThreadAndADishKeepsItsOwn() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "1")]
        changes.notes = [note(on: post, by: "sam", text: "Yes.")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        let dish = notices.first { $0.kind == .dish }!
        let comment = notices.first { $0.kind == .comment }!
        XCTAssertEqual(TableNews.thread(for: dish), "table")
        XCTAssertEqual(TableNews.thread(for: comment), post.shareRecordName)
    }

    func testDirectNewsAtNightIsActiveAndADishIsPassive() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "late")]
        changes.notes = [note(on: post, by: "sam", text: "Yes.")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        var night = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        night.hour = 23
        let when = Calendar.current.date(from: night)!
        let dish = TableNews.content(for: notices.first { $0.kind == .dish }!, at: when)
        let reply = TableNews.content(for: notices.first { $0.kind == .comment }!, at: when)
        XCTAssertEqual(dish.interruptionLevel, .passive)
        XCTAssertEqual(reply.interruptionLevel, .active)
        XCTAssertNotNil(reply.sound)
        XCTAssertEqual(reply.userInfo[NotificationRouter.Key.actor] as? String, "Sam Okafor")
        XCTAssertEqual(reply.userInfo[NotificationRouter.Key.post] as? String, post.shareRecordName)
    }

    // MARK: Retractions

    func testASecondPlaterKeepsTheLineHonestWhenTheFirstTakesItBack() async {
        let post = myPost()
        var first = TableShare.Changes()
        first.reactions = [
            plate(on: post, by: "riley", at: .now.addingTimeInterval(-120)),
            plate(on: post, by: "sam", at: .now.addingTimeInterval(-60))
        ]
        TableShare.merge(first, into: context)
        await TableNews.deliver(first, context: context)
        let row = rows(eventKey: "plates:\(post.shareRecordName)").first
        XCTAssertEqual(row?.body, "Riley and Sam plated your Ragù.")
        row?.isRead = true
        let stamped = row?.createdAt

        var back = TableShare.Changes()
        var unplate = plate(on: post, by: "riley")
        unplate.value = 0
        back.reactions = [unplate]
        TableShare.merge(back, into: context)
        await TableNews.deliver(back, context: context)
        let after = rows(eventKey: "plates:\(post.shareRecordName)").first
        XCTAssertEqual(after?.body, "Sam plated your Ragù.")
        XCTAssertEqual(after?.isRead, true)
        XCTAssertEqual(after?.createdAt, stamped)
    }

    func testAnUnplateRetiresTheLine() async {
        let post = myPost()
        var first = TableShare.Changes()
        first.reactions = [plate(on: post, by: "riley")]
        TableShare.merge(first, into: context)
        await TableNews.deliver(first, context: context)
        XCTAssertEqual(rows(eventKey: "plates:\(post.shareRecordName)").count, 1)
        var back = TableShare.Changes()
        var unplate = plate(on: post, by: "riley")
        unplate.value = 0
        back.reactions = [unplate]
        TableShare.merge(back, into: context)
        await TableNews.deliver(back, context: context)
        XCTAssertTrue(rows(eventKey: "plates:\(post.shareRecordName)").isEmpty)
    }

    func testADeletedCommentTakesItsNoticeWithIt() async {
        let post = myPost()
        var first = TableShare.Changes()
        let n = note(on: post, by: "sam", text: "Saving this.")
        first.notes = [n]
        TableShare.merge(first, into: context)
        await TableNews.deliver(first, context: context)
        XCTAssertEqual(rows(eventKey: "note:\(n.recordName)").count, 1)
        var gone = TableShare.Changes()
        gone.deleted = [n.recordName]
        await TableNews.deliver(gone, context: context)
        XCTAssertTrue(rows(eventKey: "note:\(n.recordName)").isEmpty)
    }

    func testARowKeepsTheEventsOwnTime() async {
        var changes = TableShare.Changes()
        let then = Date.now.addingTimeInterval(-3600)
        changes.posts = [remoteDish(by: "riley", id: "earlier", at: then)]
        await TableNews.deliver(changes, context: context)
        let row = rows(eventKey: "post:post-earlier").first
        XCTAssertEqual(row?.createdAt.timeIntervalSince1970 ?? 0, then.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: Read elsewhere, badges, seats, presentation

    func testABannerAboutADishReadElsewhereIsWithdrawn() {
        let stale = TableNews.staleDelivered(
            delivered: [
                (id: TableNews.idPrefix + "post:post-1", post: "post-1"),
                (id: TableNews.idPrefix + "post:post-2", post: "post-2"),
                (id: TableNews.idPrefix + "seat:x", post: "")
            ],
            unreadPosts: ["post-2"]
        )
        XCTAssertEqual(stale, [TableNews.idPrefix + "post:post-1"])
        XCTAssertTrue(TableNews.staleDelivered(delivered: [], unreadPosts: []).contains(TableNews.idPrefix + "more"))
    }

    func testBadgeCountsOnlyOtherPeoplesUnreadRows() {
        context.insert(PlatedNotification(kind: .general, actorName: "Me", body: "You posted a dish."))
        context.insert(PlatedNotification(kind: .dishPosted, actorName: "Riley Park", body: "Riley plated x.",
                                          link: DeepLink.url(post: "post-x").absoluteString, eventKey: "post:post-x"))
        XCTAssertEqual(AppBadge.count(context), 1)
        UserDefaults.standard.set(false, forKey: TableNews.tableOnKey)
        XCTAssertEqual(AppBadge.count(context), 0)
    }

    func testAJoinedSeatRowIsKeyedOpensHomeAndIsWrittenOnce() {
        Notifier.postKeyed(eventKey: "seat:p1", .seatJoined, actor: "Jo", body: "Jo joined. They can see the Table now.",
                           link: DeepLink.url(.home).absoluteString, into: context)
        Notifier.postKeyed(eventKey: "seat:p1", .seatJoined, actor: "Jo", body: "Jo joined. They can see the Table now.",
                           link: DeepLink.url(.home).absoluteString, into: context)
        let seat = rows(eventKey: "seat:p1")
        XCTAssertEqual(seat.count, 1)
        XCTAssertEqual(seat.first?.linkURL, DeepLink.url(.home))
    }

    func testAStandingMatchesByParticipantIDBeforeAddress() {
        let byLink = HouseholdMember(name: "Jo Alvarez", role: "member", seat: .joined)
        byLink.participantID = "p-jo"
        let byPhone = HouseholdMember(name: "Kim Lee", role: "member", seat: .invited, phoneE164: "+15550001111")
        let standing = TableShare.Standing(
            phone: nil, email: nil, name: "Jo", accepted: true, participantID: "p-jo"
        )
        XCTAssertEqual(Seats.match(standing, in: [byPhone, byLink])?.name, "Jo Alvarez")
        let invited = TableShare.Standing(
            phone: "+15550001111", email: nil, name: "Kim", accepted: true, participantID: "p-kim"
        )
        XCTAssertEqual(Seats.match(invited, in: [byPhone, byLink])?.name, "Kim Lee")
        let stranger = TableShare.Standing(
            phone: nil, email: nil, name: "", accepted: true, participantID: "p-new"
        )
        XCTAssertNil(Seats.match(stranger, in: [byPhone, byLink]))
    }

    func testABannerAboutWhatIsOnScreenIsKeptToTheList() {
        XCTAssertEqual(NotificationRouter.presentation(post: "post-1", kind: "comment", openPost: "post-1", feedVisible: false), [.list])
        XCTAssertEqual(NotificationRouter.presentation(post: "post-2", kind: "dish", openPost: nil, feedVisible: true), [.list])
        XCTAssertEqual(NotificationRouter.presentation(post: "post-2", kind: "comment", openPost: nil, feedVisible: true), [.banner, .list, .sound])
        XCTAssertEqual(NotificationRouter.presentation(post: "post-3", kind: "dish", openPost: "post-1", feedVisible: false), [.banner, .list, .sound])
    }

    // MARK: A person speaking

    func testAPersonSpeakingIsAMessageAndTheKissIsNot() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "spoken")]
        changes.notes = [note(on: post, by: "sam", text: "Saving this.", replyTo: "Nate")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        let dish = notices.first { $0.kind == .dish }!
        let reply = notices.first { $0.kind == .comment }!

        let dishIntent = TableNews.intent(for: dish)
        XCTAssertEqual(dishIntent?.sender?.displayName, "Riley")
        XCTAssertEqual(dishIntent?.conversationIdentifier, "table")
        XCTAssertEqual(dishIntent?.speakableGroupName?.spokenPhrase, "The Table")
        XCTAssertEqual(dish.deed, "Plated Sheet-pan chicken. Crispy edges tonight.")

        let replyIntent = TableNews.intent(for: reply)
        XCTAssertEqual(replyIntent?.sender?.displayName, "Sam")
        XCTAssertEqual(replyIntent?.conversationIdentifier, post.shareRecordName)
        XCTAssertEqual(replyIntent?.speakableGroupName?.spokenPhrase, "Your Ragù")
        XCTAssertEqual(reply.deed, "Replied to you: Saving this.")
        // No seat in setUp carries a number, an address or an identity, so
        // the handle falls back to the CloudKit id and the type is unknown.
        XCTAssertEqual(replyIntent?.sender?.personHandle?.type, .unknown)
        XCTAssertEqual(replyIntent?.sender?.personHandle?.value, "sam")
        XCTAssertNotNil(replyIntent?.sender?.image)

        var everyone = TableShare.Changes()
        var mine = plate(on: post, by: me)
        mine.authorName = "Nate Meadows"
        everyone.reactions = [plate(on: post, by: "riley"), plate(on: post, by: "sam"), mine]
        TableShare.merge(everyone, into: context)
        TableNews.learnNames(from: everyone)
        let kiss = TableNews.digest(everyone, newSeats: [], context: context).first { $0.kind == .kiss }!
        XCTAssertNil(TableNews.intent(for: kiss))
    }

    func testASinglePlateSpeaksAndTwoDoNot() {
        let post = myPost()
        var one = TableShare.Changes()
        one.reactions = [plate(on: post, by: "riley")]
        TableShare.merge(one, into: context)
        TableNews.learnNames(from: one)
        let single = TableNews.digest(one, newSeats: [], context: context).first!
        XCTAssertEqual(TableNews.intent(for: single)?.sender?.displayName, "Riley")
        XCTAssertEqual(single.deed, "Plated your Ragù.")
        TableNews.remember([single.key])

        var two = TableShare.Changes()
        two.reactions = [plate(on: post, by: "sam")]
        TableShare.merge(two, into: context)
        TableNews.learnNames(from: two)
        let pair = TableNews.digest(two, newSeats: [], context: context).first!
        XCTAssertEqual(pair.title, "Riley and Sam plated your Ragù")
        XCTAssertNil(TableNews.intent(for: pair))
    }

    func testASeatedPersonIsMatchedOnIdentityAndCarriesTheirHandle() throws {
        let members = try context.fetch(FetchDescriptor<HouseholdMember>())
        let riley = members.first { $0.name == "Riley Park" }!
        riley.participantID = "riley"
        riley.phoneE164 = "+15550002222"
        riley.photoData = Data([0x89, 0x50, 0x4E, 0x47])
        let sam = members.first { $0.name == "Sam Okafor" }!
        sam.participantID = "sam"
        sam.inviteEmail = "sam@example.com"
        // A laid place with the same name and a different face must never
        // dress Riley's banner: it has no identity and cannot post.
        let namesake = HouseholdMember(name: "Riley Park", role: "kid", seat: .notOnPlated)
        namesake.photoData = Data([0x00, 0x01])
        context.insert(namesake)
        try context.save()

        let post = myPost()
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "identified")]
        changes.notes = [note(on: post, by: "sam", text: "Yes.")]
        let notices = TableNews.digest(changes, newSeats: [], context: context)
        let dish = notices.first { $0.kind == .dish }!
        let comment = notices.first { $0.kind == .comment }!
        XCTAssertEqual(dish.face, riley.photoData)
        XCTAssertEqual(dish.handle, "+15550002222")
        XCTAssertEqual(TableNews.intent(for: dish)?.sender?.personHandle?.type, .phoneNumber)
        XCTAssertEqual(TableNews.intent(for: dish)?.sender?.personHandle?.value, "+15550002222")
        XCTAssertEqual(TableNews.intent(for: dish)?.sender?.customIdentifier, "riley")
        XCTAssertEqual(TableNews.intent(for: comment)?.sender?.personHandle?.type, .emailAddress)
        XCTAssertEqual(TableNews.intent(for: comment)?.sender?.personHandle?.value, "sam@example.com")
    }

    func testANamesakeLaidPlaceNeverDressesAStranger() throws {
        let namesake = HouseholdMember(name: "Jo Alvarez", role: "kid", seat: .notOnPlated)
        namesake.photoData = Data([0x00, 0x01])
        context.insert(namesake)
        try context.save()
        var changes = TableShare.Changes()
        var dish = remoteDish(by: "jo", id: "stranger")
        dish.authorName = "Jo Alvarez"
        changes.posts = [dish]
        let notice = TableNews.digest(changes, newSeats: [], context: context).first!
        XCTAssertNil(notice.face)
        XCTAssertNil(notice.handle)
        XCTAssertEqual(TableNews.intent(for: notice)?.sender?.personHandle?.type, .unknown)
    }

    func testTwoPlatersKeepTheLastFaceOnTheRowButDoNotSpeakAsOne() {
        let post = myPost()
        var changes = TableShare.Changes()
        changes.reactions = [
            plate(on: post, by: "riley", at: .now.addingTimeInterval(-60)),
            plate(on: post, by: "sam")
        ]
        TableShare.merge(changes, into: context)
        TableNews.learnNames(from: changes)
        let pair = TableNews.digest(changes, newSeats: [], context: context).first!
        XCTAssertEqual(pair.title, "Riley and Sam plated your Ragù")
        XCTAssertFalse(pair.actor.isEmpty)
        XCTAssertNil(TableNews.intent(for: pair))
    }

    func testOnTheSimulatorTheDressingIsCompiledOut() async {
        var changes = TableShare.Changes()
        changes.posts = [remoteDish(by: "riley", id: "plain")]
        let dish = TableNews.digest(changes, newSeats: [], context: context).first!
        let base = TableNews.content(for: dish)
        let final = await TableNews.communicationContent(for: dish, base: base)
        #if targetEnvironment(simulator)
        XCTAssertEqual(final.title, dish.title)
        XCTAssertEqual(final.body, dish.body)
        #else
        XCTAssertEqual(final.body, dish.deed)
        #endif
        XCTAssertEqual(final.threadIdentifier, "table")
        XCTAssertEqual(final.userInfo[NotificationRouter.Key.post] as? String, "post-plain")
    }

    private func rows(eventKey: String) -> [PlatedNotification] {
        (try? context.fetch(FetchDescriptor<PlatedNotification>(
            predicate: #Predicate { $0.eventKey == eventKey }
        ))) ?? []
    }
}
