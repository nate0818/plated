import Foundation
import SwiftData
import UserNotifications
import UIKit
import Intents
import SwiftUI

/// What the table said, turned into something a person would want to hear.
///
/// A silent push means "a database changed". Nobody wants that on a lock
/// screen. This reads the delta the fetch brought back and decides, event
/// by event, whether it is news for the person holding this phone: somebody
/// else plated a dish, somebody wrote on your dish, somebody answered you.
/// Everything else is not news, and not-news is the common answer. Silence
/// about the ordinary is what buys the right to speak about the rest, which
/// is the same rule `NotificationScheduler` applies to reminders.
///
/// The rules, in one place so they can be judged rather than rediscovered:
///
/// - **Never about you.** Your own post arriving from your own iPad is not
///   news, and a plate never appears in the plater's own activity.
/// - **Named, or not sent.** Every banner names the person. A plate or a
///   vote from somebody the phone cannot name is folded into the count on
///   the Table and never becomes a sentence.
/// - **Once.** Every event carries a key and the key is remembered, so a
///   change token reset that replays a whole zone raises nothing twice.
/// - **History is not news.** A delta read from the beginning of a zone (a
///   fresh install, a refused token) is windowed to the last day and a
///   half. An incremental delta is trusted whole: late delivery is not the
///   same thing as old news.
/// - **Few.** At most `visibleCap` banners per delivery; the rest fold into
///   one line that names who they were from. Every one still reaches the bell.
/// - **A plate or a vote is always passive.** In the list and on the icon,
///   the screen dark, at any hour: the Table already draws it as a count,
///   and one line replaced seven times in a room of eight lit the phone
///   seven times. The kiss is the exception.
/// - **Quiet at night for the room, not for you.** Between 22:00 and 08:00
///   a dish lands in the list without lighting the screen. A reply to you
///   is still a reply to you, at any hour; Focus decides.
/// - **The room is one conversation, a dish is another.** Dishes, asks and
///   seats stack under the Table; everything about one dish stacks under
///   that dish, with its photograph.
/// - **A retraction takes its notice with it.** An un-plate rewrites the
///   line to whoever still stands or removes it; a deleted comment removes
///   its banner and its row. Neither is re-dated: it is not fresh news.
/// - **Not while you are looking.** `Presence` records what is on screen and
///   `NotificationRouter` keeps a banner about the post being read to the
///   list.
/// - **Coalesced.** Three plates on one dish are one line that updates, not
///   three, and the count is the ledger's, so it cannot drift.
/// - **One row per event, on every device.** Bell rows are mirrored, so a
///   person's iPad and iPhone each write one and then keep the older.
/// - **A plan notice is about a night, never a word to you.** "Nate
///   planned Tacos for Thursday", "moved", "put you down to cook", "took
///   off": what somebody did to the week. Never addressed, never direct,
///   under the Planning switch, quiet at night; the 19:00 reminder already
///   carries the sound for the obligation. A night taken off is a
///   retraction or news, decided by the row: unread, and the row and banner
///   go; read, and "Nate took Tacos off Thursday" is said passively.
///   docs/plan-share.md, "Notices".
///
/// Every notice also lands in the activity feed, which is the first time the
/// bell has counted anything another person did.
@MainActor
enum TableNews {

    /// Every visible notice raised here wears this prefix, so the reminder
    /// scheduler's wholesale rebuilds never touch one and vice versa.
    static let idPrefix = "plated.news."
    /// The Settings switch. Defaults on; `object(forKey:) == nil` is on.
    static let tableOnKey = "tableNewsOn"

    private static let seenKey = "plated.news.seen"
    /// When this phone last let a planned night light the screen.
    ///
    /// Planning is bursty by nature: a household sits down on a Sunday and
    /// enters a week. Each night is its own record, its own publisher pass
    /// three seconds after its own save, its own delivery and its own
    /// banner, so seven nights was seven interruptions on every other
    /// phone. `select`'s four-banner cap counts within ONE delivery and
    /// cannot see the burst at all.
    ///
    /// This is the plates lesson, which this file already learned and the
    /// plan pipe reproduced. The first night still speaks, because the
    /// household starting to plan is genuinely the first word of something
    /// new; the rest of the sitting arrives quietly and is all still in the
    /// bell.
    private static let plannedSpokeKey = "plated.news.plannedSpokeAt"
    private static let namesKey = "plated.news.names"
    private static let window: TimeInterval = 36 * 3600
    private static let visibleCap = 4

    struct Notice {
        enum Kind: String {
            case dish, ask, comment, plates, kiss, votes, seat, more
            /// A night another phone planned, read from `PlanLedger`
            /// (docs/plan-share.md).
            case plan
            /// The household (docs/household.md section 10): a seat joined
            /// or left, a recipe added, an edit that lost. No night: a night
            /// is not a household record, and `plan` above is the only thing
            /// said about an evening.
            case householdSeat, householdLeft, recipe, conflict
        }
        var kind: Kind
        /// Dedupe key, remembered (for the last 400). Several keys joined
        /// with "|" when one notice covers several events.
        var key: String
        /// The system identifier. Two notices sharing one replace each
        /// other, which is how plates on a dish become one updating line.
        var identifier: String
        var title: String
        var body: String
        /// The sentence the bell shows.
        var line: String
        var link: URL
        /// Record name of the post this is about, or "" for the table.
        var post: String
        /// Addressed to this person rather than to the room: a reply, a
        /// mention, a word on their dish. Direct news makes a sound.
        var direct: Bool
        var photo: Data?
        var feedKind: PlatedNotificationKind
        /// The person, full name, so a reply can be addressed to them.
        var actor: String
        var at: Date
        /// Which bell row this is. Plates and votes share one per post, so
        /// a second delivery updates the row rather than adding a sibling.
        var rowKey: String
        /// Whether this notice lands in the bell as well as on the screen.
        /// Every notice the digest raises does: the row is the record a
        /// person still has after they swipe the banner away. It was once
        /// false for a seat, on the premise that `Seats.reconcile` wrote
        /// that row itself; the rewritten reconcile writes nothing, so the
        /// premise was a silently missing row and a bell that disagreed
        /// with the banner.
        var writesRow = true
        /// In the list and on the icon, the screen dark, at any hour. A plate
        /// or a vote: the Table already draws it as a count, and replacing
        /// one line seven times in a room of eight lit the phone seven times.
        var passive = false
        /// What iOS uses to order a summary: a reply above a plate.
        var relevance: Double
        /// The person in CloudKit's terms, for the intent's identity.
        var actorID = ""
        /// The deed as a message body, for a banner that already carries
        /// the person's name as its title: "Plated Sheet-pan chicken."
        var deed = ""
        /// The conversation line under the name: "The Table", "Your Ragù".
        var group = ""
        /// Where a message to them could go, their face, and the colour
        /// their seat has earned, when this household has a seat for them.
        /// Filled in by `dress`.
        var handle: String?
        var face: Data?
        var tone: PersonTone?
        /// A reply, a mention or a tag: addressed to this person rather
        /// than owed to them by ownership. Gets through a muted dish and
        /// is governed by the Replies switch.
        var addressed = false
        /// `line` as a pattern the bell row composes at draw time; see
        /// `PlatedNotification.template`. Empty where several people are
        /// named in one line, which keeps the composed names.
        var template = ""
        var objectTitle = ""
        /// Active with sound by day, passive between 22:00 and 08:00, even
        /// though it is direct: a household join is good news, not a word
        /// addressed to you, so it can wait until morning.
        var quietAtNight = false
        /// A bell row and nothing on the screen, at any hour: an edit that
        /// lost to somebody else's is worth knowing and not worth a banner.
        var bellOnly = false
    }

    // MARK: Deciding

    /// Fold a delivery: bell rows for everything, banners for the few.
    /// `plans` is what `PlanLedger.absorb` made of the same delivery,
    /// computed before the ledger was overwritten; the default is an empty
    /// delta so a caller with no ledger in hand still compiles.
    static func deliver(
        _ changes: TableShare.Changes,
        newSeats: [HouseholdMember] = [],
        plans: PlanLedger.Delta = PlanLedger.Delta(),
        context: ModelContext
    ) async {
        // Even a delta that raises nothing teaches who is who.
        learnNames(from: changes)
        // Taken off the table, or taken back: nothing about it should
        // remain anywhere, and a line that names fewer people than it did
        // is not fresh news. A `plan-` name is a night, not a post, and a
        // night taken off is decided by its row below.
        let deletedPosts = changes.deleted.filter { !$0.hasPrefix("plan-") }
        if !deletedPosts.isEmpty {
            await forget(posts: deletedPosts, context: context)
        }
        retract(changes, context: context)
        retract(plans: plans.removed, context: context)
        // Without a confirmed identity "not mine" is a guess, and the guess
        // that goes wrong narrates a person's own dinner back to them.
        guard !TableIdentity.isPlaceholder || rehearsing else {
            print("[TableNews] identity unconfirmed, nothing decided")
            return
        }
        let notices = digest(changes, newSeats: newSeats, plans: plans, context: context)
        guard !notices.isEmpty else { return }
        for n in notices where n.writesRow {
            writeRow(n, context: context)
        }
        remember(notices.map(\.key))
        dedupeRows(context)
        Persist.save(context, "table news")
        AppBadge.sync(context)
        print("[TableNews] \(notices.count) notice(s): \(notices.map(\.kind.rawValue))")
        await show(notices)
        await reconcileDelivered(context: context)
    }

    /// What in this delta is news for me. Reads the store and the ledger,
    /// writes nothing, so the rehearsal flag and a unit test can both ask
    /// without touching the notification centre.
    static func digest(
        _ changes: TableShare.Changes,
        newSeats: [HouseholdMember],
        plans: PlanLedger.Delta = PlanLedger.Delta(),
        context: ModelContext,
        // Injected so a test can drive the planning burst window without
        // sleeping through three quarters of an hour.
        now: Date = .now
    ) -> [Notice] {
        let me = TableIdentity.cached
        let members = Seats.all(in: context)
        let myRow = members.me
        // Names are how replies, mentions and tags are addressed on the
        // wire, so a reply is "to me" when it names either thing I am
        // called. Identity would be better; the wire does not carry it yet.
        var myNames = Set<String>()
        if let myRow { myNames.insert(myRow.name); myNames.insert(myRow.firstName) }
        let typed = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        if !typed.isEmpty { myNames.insert(typed) }
        myNames.remove("")

        let posts = (try? context.fetch(FetchDescriptor<TablePost>())) ?? []
        var byRecord: [String: TablePost] = [:]
        for post in posts where !post.shareRecordName.isEmpty {
            byRecord[post.shareRecordName] = post
        }
        // Mine by identity where the wire stamped one; by the merge's own
        // verdict where it did not (a post written before authorID existed).
        func isMine(_ post: TablePost) -> Bool {
            post.authorID.isEmpty ? !post.isRemote : post.authorID == me
        }

        let cutoff = changes.replayed ? Date.now.addingTimeInterval(-window) : Date.distantPast
        let seen = seenKeys()
        var notices: [Notice] = []

        // Somebody else's dish, or their question.
        for r in changes.posts where !r.authorID.isEmpty && r.authorID != me && r.createdAt > cutoff {
            let key = "post:\(r.recordName)"
            guard !seen.contains(key) else { continue }
            let who = firstName(r.authorName)
            guard who != "Someone" else { continue }
            let tagged = !myNames.isDisjoint(with: r.taggedNames)
            if r.kind == "ask" {
                let question = r.caption.isEmpty ? r.pollOptions.joined(separator: ", ") : r.caption
                notices.append(Notice(
                    kind: .ask, key: key, identifier: idPrefix + key,
                    title: "\(who) asked the table",
                    body: question.isEmpty ? "Open the Table to answer." : question,
                    line: "\(who) asked the table\(question.isEmpty ? "." : ": \(question)")",
                    link: DeepLink.url(post: r.recordName), post: r.recordName,
                    direct: tagged, photo: nil, feedKind: .askPosted,
                    actor: r.authorName, at: r.createdAt, rowKey: key,
                    relevance: tagged ? 0.9 : 0.7,
                    actorID: r.authorID,
                    deed: question.isEmpty ? "Asked the table." : "Asked the table: \(question)",
                    group: "The Table",
                    addressed: tagged,
                    template: question.isEmpty ? "{actor} asked the table." : "{actor} asked the table: {object}",
                    objectTitle: question
                ))
            } else {
                let dish = r.dishTitle.isEmpty ? "a dish" : r.dishTitle
                let deed = (tagged ? "Tagged you in \(dish)." : "Plated \(dish).")
                    + (r.caption.isEmpty ? "" : " \(r.caption)")
                notices.append(Notice(
                    kind: .dish, key: key, identifier: idPrefix + key,
                    title: tagged ? "\(who) tagged you in \(dish)" : "\(who) plated \(dish)",
                    body: r.caption.isEmpty ? "On the Table now." : r.caption,
                    line: tagged ? "\(who) tagged you in \(dish)." : "\(who) plated \(dish).",
                    link: DeepLink.url(post: r.recordName), post: r.recordName,
                    direct: tagged, photo: r.photoData, feedKind: .dishPosted,
                    actor: r.authorName, at: r.createdAt, rowKey: key,
                    relevance: tagged ? 0.9 : 0.6,
                    actorID: r.authorID, deed: deed, group: "The Table",
                    addressed: tagged,
                    template: tagged ? "{actor} tagged you in {object}." : "{actor} plated {object}.",
                    objectTitle: dish
                ))
            }
        }

        // A word on my dish, a reply to me, or my name in somebody's mouth.
        for n in changes.notes where !n.authorID.isEmpty && n.authorID != me && n.createdAt > cutoff {
            guard let post = byRecord[n.post] else { continue }
            let key = "note:\(n.recordName)"
            guard !seen.contains(key) else { continue }
            let mine = isMine(post)
            let toMe = myNames.contains(n.replyToName)
            let mentioned = !myNames.isDisjoint(with: n.mentions)
            guard mine || toMe || mentioned else { continue }
            let who = firstName(n.authorName)
            guard who != "Someone" else { continue }
            let dish = label(post)
            let whose = mine ? "your" : "\(post.firstName)'s"
            let title: String
            let line: String
            if toMe {
                title = "\(who) replied to you"
                line = "\(who) replied to you on \(whose) \(dish)."
            } else if mentioned {
                title = "\(who) mentioned you"
                line = "\(who) mentioned you on \(whose) \(dish)."
            } else {
                title = "\(who) commented on your \(dish)"
                line = title + "."
            }
            let body: String
            if !n.text.isEmpty { body = n.text }
            else if n.photoData != nil { body = "Sent a photo." }
            else if !n.linkURL.isEmpty { body = "Sent a link." }
            else { body = "Open the Table to read it." }
            // Under the person's name the deed is the sentence: a reply says
            // it replied, a comment on your dish is just the words, because
            // the conversation line already says which dish.
            let deed = toMe ? "Replied to you: \(body)" : (mentioned ? "Mentioned you: \(body)" : body)
            notices.append(Notice(
                kind: .comment, key: key, identifier: idPrefix + key,
                title: title, body: body, line: line,
                link: DeepLink.url(post: n.post), post: n.post,
                direct: true, photo: post.photoData, feedKind: .commentAdded,
                actor: n.authorName, at: n.createdAt, rowKey: key, relevance: 1.0,
                actorID: n.authorID, deed: deed,
                group: mine ? "Your \(dish)" : "\(post.firstName)'s \(dish)",
                addressed: toMe || mentioned,
                template: toMe ? "{actor} replied to you on \(whose) {object}."
                    : (mentioned ? "{actor} mentioned you on \(whose) {object}." : "{actor} commented on your {object}."),
                objectTitle: dish
            ))
        }

        // Plates and votes on what I put on the table. Grouped per post, so a
        // burst of plates is one line, and read back from the ledger, which
        // `TableShare.merge` has already folded these into, so the names
        // and the count are everybody's, not just this delivery's.
        var platesByPost: [String: [TableShare.RemoteReaction]] = [:]
        var ballotsByPost: [String: [TableShare.RemoteReaction]] = [:]
        for r in changes.reactions where !r.author.isEmpty && r.author != me && r.at > cutoff {
            guard let post = byRecord[r.post], isMine(post) else { continue }
            if r.isBallot {
                guard r.value >= 0 else { continue }
                ballotsByPost[r.post, default: []].append(r)
            } else {
                guard r.value == 1 else { continue }
                platesByPost[r.post, default: []].append(r)
            }
        }

        for (record, plates) in platesByPost {
            guard let post = byRecord[record] else { continue }
            let fresh = plates.filter { !seen.contains("plate:\(record):\($0.author)") }
            guard !fresh.isEmpty else { continue }
            let platers = TableLedger.shared.platers(record).filter { $0 != me }
            let named = platers.compactMap { name(for: $0) }.map(firstName)
            // Named, or not sent. A room where nobody can be named is a
            // legacy table; the count on the dish still says it.
            guard !named.isEmpty else { continue }
            let dish = label(post)
            let kiss = post.hasChefsKiss(seats: members.count)
            let title = kiss
                ? "Everyone plated your \(dish)"
                : "\(list(named, of: platers.count)) plated your \(dish)"
            let key = fresh.map { "plate:\(record):\($0.author)" }.joined(separator: "|")
            notices.append(Notice(
                kind: kiss ? .kiss : .plates, key: key,
                identifier: idPrefix + "plates:\(record)",
                title: title, body: kiss ? "The Chef's kiss." : "",
                line: title + ".",
                link: DeepLink.url(post: record), post: record,
                direct: kiss, photo: post.photoData, feedKind: .plateReaction,
                actor: fresh.first?.authorName ?? "",
                at: fresh.map(\.at).max() ?? .now,
                rowKey: "plates:\(record)", passive: !kiss, relevance: kiss ? 0.9 : 0.3,
                actorID: platers.count == 1 ? (platers.first ?? "") : "",
                deed: "Plated your \(dish).", group: "Your \(dish)"
            ))
        }

        for (record, ballots) in ballotsByPost {
            guard let post = byRecord[record], post.hasPoll else { continue }
            let fresh = ballots.filter { !seen.contains("ballot:\(record):\($0.author)") }
            guard !fresh.isEmpty else { continue }
            let voters = TableLedger.shared.voters(record).filter { $0 != me }
            let named = voters.compactMap { name(for: $0) }.map(firstName)
            guard !named.isEmpty else { continue }
            let question = label(post)
            let title = "\(list(named, of: voters.count)) voted on \(question)"
            let tally = TableLedger.shared.votes(record, options: post.pollOptions.count)
            let top = tally.max() ?? 0
            let leaders = zip(post.pollOptions, tally).filter { $0.1 == top && top > 0 }.map(\.0)
            let body = leaders.count == 1 ? "\(leaders[0]) is ahead." : (leaders.count > 1 ? "It's a tie." : "")
            let key = fresh.map { "ballot:\(record):\($0.author)" }.joined(separator: "|")
            notices.append(Notice(
                kind: .votes, key: key, identifier: idPrefix + "votes:\(record)",
                title: title, body: body, line: title + ".",
                link: DeepLink.url(post: record), post: record,
                direct: false, photo: post.photoData, feedKind: .voteCast,
                actor: fresh.first?.authorName ?? "", at: fresh.map(\.at).max() ?? .now,
                rowKey: "votes:\(record)", passive: true, relevance: 0.3
            ))
        }

        // A seat that just became real. `Seats.reconcile` decided that
        // from what CloudKit reported; the notice says it and writes the
        // row, because reconcile writes neither. A person whose identity
        // holds a household seat joined the Table by joining the
        // household, and the household digest has already said so
        // (docs/household.md section 10).
        for member in newSeats {
            let key = "seat:\(member.participantID ?? member.name)"
            guard !seen.contains(key), !HouseholdIdentity.isPlaceholder(member.name),
                  member.name != "Someone new" else { continue }
            if let id = member.participantID, !id.isEmpty,
               members.contains(where: { $0.userRecordName == id && ($0.seat == .joined || $0.seat == .head) }) {
                continue
            }
            notices.append(Notice(
                kind: .seat, key: key, identifier: idPrefix + key,
                title: "\(member.firstName) joined your table",
                body: "They can see the Table now.",
                line: "\(member.firstName) joined. They can see the Table now.",
                link: DeepLink.url(.home), post: "",
                direct: true, photo: nil, feedKind: .seatJoined,
                actor: member.name, at: .now, rowKey: key,
                relevance: 0.8, actorID: member.participantID ?? "",
                deed: "Joined your table.", group: "The Table",
                template: "{actor} joined. They can see the Table now."
            ))
        }

        notices.append(contentsOf: planNotices(plans, me: me, cutoff: cutoff, seen: seen, context: context, now: now))

        return notices.map { dress($0, members: members) }
    }

    // MARK: The week

    /// What somebody did to the week: a night planned, moved, handed to
    /// you, renamed, or taken off. The ledger already dropped this person's
    /// own nights and every past-day change, and cancelled the removed and
    /// added pair a two-device `shoppingID` backfill mints; none of that is
    /// assumed here, only relied on not to be doubled.
    private static func planNotices(
        _ plans: PlanLedger.Delta, me: String, cutoff: Date, seen: Set<String>,
        context: ModelContext, now: Date
    ) -> [Notice] {
        var notices: [Notice] = []

        /// The body under the title: whose night it is, when that is
        /// worth saying. "You cook." is the one line that changes what the
        /// reader has to do; a cook with a real seat is a fact; an empty
        /// seat says nothing rather than naming a name that is not a cook.
        func cookLine(_ e: PlanLedger.Entry) -> String {
            if PlanLedger.shared.isMine(cook: e) { return "You cook." }
            if e.hasCook { return "\(e.cookFirstName) is cooking." }
            return ""
        }

        /// The actor is passed in, never read off the night, because the
        /// person a sentence is about is not always its author: a night
        /// somebody CHANGED is the editor's deed, and the record says who
        /// that was. The id travels with the name so the bell row composes
        /// with that person's current name and the banner wears their face.
        func notice(
            _ e: PlanLedger.Entry, key: String, actor: String, actorID: String,
            title: String, body: String,
            template: String, deed: String, at: Date, passive: Bool
        ) -> Notice {
            Notice(
                kind: .plan, key: key, identifier: idPrefix + "plan:\(e.recordName)",
                title: title, body: body, line: title + ".",
                link: DeepLink.url(plan: e.date), post: "",
                direct: false, photo: passive ? nil : PlanLedger.shared.photo(for: e.recordName),
                feedKind: .planShared, actor: actor, at: at,
                rowKey: "plan:\(e.recordName)", passive: passive,
                relevance: PlanLedger.shared.isMine(cook: e) ? 0.8 : 0.6,
                actorID: actorID, deed: deed, group: "The Table",
                addressed: false, template: template, objectTitle: e.title
            )
        }

        /// Who a notice about a CHANGE names, or nobody.
        ///
        /// The record carries the identity that made this version, and a
        /// member may change any household night, so the author is the
        /// wrong person to name here: "Nate changed Thursday to Ragu" about
        /// something Riley did is the interface claiming something that did
        /// not happen. A record written before the editor fields existed
        /// carries none, and the author is then the only answer there is.
        /// An editor this phone cannot put a name to is nobody at all,
        /// which is docs/notifications.md's "named, or not sent": falling
        /// back to the author there would print the false sentence again.
        func changer(_ e: PlanLedger.Entry) -> (id: String, name: String)? {
            let editor = e.editorID ?? ""
            guard !editor.isEmpty, editor != e.authorID else {
                return e.authorID.isEmpty ? nil : (e.authorID, e.authorName)
            }
            let known = e.editorName ?? ""
            let named = known.isEmpty ? (name(for: editor) ?? "") : known
            return named.isEmpty ? nil : (editor, named)
        }

        // One sitting, one interruption. See `plannedSpokeKey`.
        var plannedSpoke = spokeRecently(plannedSpokeKey, within: plannedBurst, at: now)
        for e in plans.added where !e.authorID.isEmpty && e.authorID != me && e.changedAt > cutoff {
            let key = "plan:\(e.recordName):\(planHash(e))"
            guard !seen.contains(key) else { continue }
            let who = firstName(e.authorName)
            guard who != "Someone", !e.title.isEmpty else { continue }
            let night = Stamp.nightPhrase(e.date)
            let body = cookLine(e)
            notices.append(notice(
                e, key: key, actor: e.authorName, actorID: e.authorID,
                title: "\(who) planned \(e.title) for \(night)", body: body,
                template: "{actor} planned {object} for \(night).",
                deed: "Planned \(e.title) for \(night)." + (body.isEmpty ? "" : " \(body)"),
                at: e.changedAt, passive: plannedSpoke
            ))
            plannedSpoke = true
        }
        if plannedSpoke { store.set(now, forKey: plannedSpokeKey) }

        // `changedByID`, not `authorID`. A member may change any household
        // night, so the person whose action this is is the editor, and
        // comparing the author here told Riley about Riley's own change to
        // Nate's Thursday every time the zone handed it back. A notice
        // about the reader's own action is the one rule
        // docs/notifications.md breaks for nothing.
        for (before, after) in plans.changed
        where !after.authorID.isEmpty && after.authorID != me
            && after.changedByID != me && after.changedAt > cutoff {
            let key = "plan:\(after.recordName):\(planHash(after))"
            guard !seen.contains(key) else { continue }
            guard let by = changer(after) else { continue }
            let who = firstName(by.name)
            guard who != "Someone", !after.title.isEmpty else { continue }
            let night = Stamp.nightPhrase(after.date)
            let title: String, body: String, template: String, deed: String
            if before.day != after.day {
                title = "\(who) moved \(after.title) to \(night)"
                body = cookLine(after)
                template = "{actor} moved {object} to \(night)."
                deed = "Moved \(after.title) to \(night)." + (body.isEmpty ? "" : " \(body)")
            } else if !me.isEmpty, after.cookID == me, before.cookID != me {
                // What Nate did, a field set, nothing more: not a request,
                // not a claim about what the reader agreed to.
                title = "\(who) put you down to cook \(night): \(after.title)"
                body = ""
                template = "{actor} put you down to cook \(night): {object}"
                deed = "Put you down to cook \(night): \(after.title)."
            } else if before.title != after.title {
                title = "\(who) changed \(night) to \(after.title)"
                body = cookLine(after)
                template = "{actor} changed \(night) to {object}."
                deed = "Changed \(night) to \(after.title)." + (body.isEmpty ? "" : " \(body)")
            } else {
                // Servings, a tagline, a cook handed to somebody else, a
                // photo: the week looks the same from here.
                continue
            }
            notices.append(notice(
                after, key: key, actor: by.name, actorID: by.id,
                title: title, body: body, template: template,
                deed: deed, at: after.changedAt, passive: false
            ))
        }

        // Retraction or news, decided by the row. `retract(plans:)` has
        // already taken the unread rows and their banners; a row still
        // standing was read, and a person who read "Nate planned Tacos"
        // is owed "Nate took Tacos off", quietly. Not windowed on
        // `changedAt`: that is when the writer last saved the night, not
        // when it went, and a replay that notices a removal notices it now.
        // The author's own night, taken off by the household. The one
        // notice in this file with no antecedent: every other plan notice
        // answers a row the reader already has, and the author has none for
        // a night they planned themselves, because nothing ever told them
        // about their own record.
        //
        // It is sent anyway, and `docs/notifications.md` is why rather than
        // an exception to it. A notice has to be about you or be the first
        // word of something new, and somebody taking your dinner off the
        // plan is both: the consequence of not hearing it is shopping for
        // or cooking a night that is off the plan, and the person most
        // likely to be caught out is the one who does not open the app. It
        // is addressed, so it is never folded into a count.
        //
        // Named or not sent, as everywhere: a record that names no remover
        // says nothing, and `changedByID` keeps a person from being told
        // about their own doing on their other device.
        for e in plans.ownRemoved where e.changedAt > cutoff {
            // The replay window, which this branch alone was missing. Every
            // other arm is held either by `cutoff` or by needing a read row
            // to answer; this one had neither, and the ledger appends to it
            // with no past-day filter. A reinstall or a change-token reset
            // therefore raised one banner per tombstone still in the zone,
            // up to thirty days of them, about nights weeks past whose meals
            // are not even on this phone.
            let editor = e.editorID ?? ""
            guard !editor.isEmpty, editor != me else { continue }
            guard let by = changer(e) else { continue }
            let who = firstName(by.name)
            guard who != "Someone", !e.title.isEmpty else { continue }
            let key = "plan:\(e.recordName):\(planHash(e, removed: true))"
            guard !seen.contains(key) else { continue }
            let night = Stamp.nightPhrase(e.date)
            // What actually happened to this phone's copy, read after the
            // drain rather than assumed before it. The two hold-backs keep
            // the night, and saying it came off a week that still shows it
            // is the interface contradicting the row underneath.
            let outcome = RemovedNights.outcomeLine(for: e.shoppingID)
            var n = notice(
                e, key: key, actor: by.name, actorID: by.id,
                title: "\(who) took \(e.title) off \(night)",
                body: outcome,
                template: "{actor} took {object} off \(night).",
                deed: "Took \(e.title) off \(night). \(outcome)",
                at: .now, passive: false
            )
            n.addressed = true
            n.relevance = 1.0
            // Direct, so it makes a sound and lights a locked screen. The
            // code argued this was the highest-consequence notice in the
            // feature and then handed it to the system at the quietest level
            // iOS offers, where it cannot reach the person it is for. It IS
            // addressed to them: their night, changed by somebody else,
            // with shopping and cooking hanging on it.
            n.direct = true
            // Not at two in the morning, though. The dinner is tomorrow at
            // the earliest, so this waits for daylight like a household
            // join does.
            n.quietAtNight = true
            notices.append(n)
        }

        // A removal names the person who REMOVED it, which is only
        // possible now that a removal is a write. It used to name the
        // night's author off the last book copy, because a CloudKit
        // deletion arrives as a bare record name with nobody on it: Riley
        // taking Nate's night off told the household that Nate did it, told
        // Riley the same about her own action, and never reached Nate at
        // all. Three of the laws in docs/notifications.md in one loop.
        //
        // `changer(_:)` is the same ladder the change notices use, and it
        // answers nothing rather than a name it cannot stand behind. Nothing
        // is the right answer here: a household is eight people, so a wrong
        // "someone" is a person in the room.
        for e in plans.removed {
            // The record has to NAME the remover. `changer` falls back to
            // the night's author when no editor is recorded, which is right
            // for a change and is the whole lie for a removal: it is how
            // Riley taking Nate's night off told the household that Nate
            // did it. An entry with no editor reaches here only from a
            // record that was gone rather than tombstoned, and a deletion
            // carries nobody, so there is nothing true to say. The row is
            // still taken down; only the sentence is withheld.
            let editor = e.editorID ?? ""
            guard !editor.isEmpty, let by = changer(e), by.id != me else { continue }
            guard let row = rows(eventKey: "plan:\(e.recordName)", context: context).first, row.isRead
            else { continue }
            let key = "plan:\(e.recordName):\(planHash(e, removed: true))"
            guard !seen.contains(key) else { continue }
            let who = firstName(by.name)
            guard who != "Someone", !e.title.isEmpty else { continue }
            let night = Stamp.nightPhrase(e.date)
            notices.append(notice(
                e, key: key, actor: by.name, actorID: by.id,
                title: "\(who) took \(e.title) off \(night)", body: "",
                template: "{actor} took {object} off \(night).",
                deed: "Took \(e.title) off \(night).",
                at: .now, passive: true
            ))
        }

        return notices
    }

    /// The part of a night that means something to a reader (its day, its
    /// slot, its name and its cook) and the writer's clock at the save
    /// that produced it. The clock is there because the memory is of
    /// keys, and a key that is a pure function of the night's state
    /// swallows any return to a state it has been in: Riley moves Tacos
    /// to Friday and back to Thursday, and the second move is never said
    /// while the row still reads "moved to Friday"; a cook handed back is
    /// never said the second time. A replay hands back the record as the
    /// zone stores it, `changedAt` included, so the same publish still
    /// keys the same and is told once. Stable across launches, which
    /// `hashValue` is not (it is seeded per process), and free of "|",
    /// which `remember` splits on.
    static func planHash(_ e: PlanLedger.Entry, removed: Bool = false) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let stamp = String(Int(e.changedAt.timeIntervalSince1970))
        let parts = [removed ? "off" : "on", e.day, e.slot, e.title, e.cookID, stamp]
        for byte in parts.joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }

    /// The face, the handle and the colour, when this household has a seat
    /// for the person. Matched on identity first: `participantID` and
    /// `authorID` are the same CloudKit user record name, and a name can
    /// belong to two seats or be renamed after a post was written. The
    /// name is trusted only for a row that could be this person: one with
    /// no identity recorded yet and a seat that can post. A laid place
    /// cannot post, and a row identified as somebody else is somebody
    /// else. A guest at a table they joined has no row for the host here,
    /// so the banner shows the neutral monogram, never a stand-in face.
    private static func dress(_ n: Notice, members: [HouseholdMember]) -> Notice {
        guard !n.actor.isEmpty else { return n }
        let member = members.first {
            !n.actorID.isEmpty && ($0.participantID == n.actorID || $0.userRecordName == n.actorID)
        }
            ?? members.first {
                $0.name == n.actor && $0.participantID == nil
                    && ($0.seat == .joined || $0.seat == .invited)
            }
        guard let member else { return n }
        var dressed = n
        dressed.face = member.photoData
        let handle = member.phoneE164 ?? member.inviteEmail
        dressed.handle = (handle?.isEmpty ?? true) ? nil : handle
        dressed.tone = member.showsColor ? member.tone : .neutralPair
        return dressed
    }

    // MARK: The person on the banner

    /// The message this notice is, in the system's terms, so iOS draws it
    /// the way it draws a message: the person's face, their name as the
    /// title, the conversation under it, and a place in Focus's "allowed
    /// people". Nil for anything that is not one person speaking: the
    /// kiss, several platers, a vote, a seat, the fold.
    static func intent(for n: Notice) -> INSendMessageIntent? {
        switch n.kind {
        case .dish, .ask, .comment, .plates, .plan: break
        default: return nil
        }
        guard !n.actor.isEmpty, !n.actorID.isEmpty, !n.deed.isEmpty else { return nil }
        let first = firstName(n.actor)
        guard first != "Someone" else { return nil }

        let handleType: INPersonHandleType
        if let handle = n.handle, handle.contains("@") { handleType = .emailAddress }
        else if n.handle != nil { handleType = .phoneNumber }
        else { handleType = .unknown }
        var components = PersonNameComponents()
        let parts = n.actor.split(separator: " ")
        components.givenName = parts.first.map(String.init)
        if parts.count > 1 { components.familyName = parts.dropFirst().joined(separator: " ") }

        let sender = INPerson(
            personHandle: INPersonHandle(value: n.handle ?? n.actorID, type: handleType),
            nameComponents: components,
            displayName: first,
            image: image(for: n),
            contactIdentifier: nil,
            customIdentifier: n.actorID,
            isMe: false,
            suggestionType: .none
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: n.deed,
            speakableGroupName: INSpeakableString(spokenPhrase: n.group.isEmpty ? "The Table" : n.group),
            conversationIdentifier: thread(for: n),
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        return intent
    }

    /// Their photograph, or the same monogram the app draws for them, in
    /// the colour their seat has earned. Seats do not carry photographs
    /// yet (only the owner's row does, and the owner is never the sender),
    /// so today this is the monogram every time.
    private static func image(for n: Notice) -> INImage? {
        if let face = n.face { return INImage(imageData: face) }
        let parts = n.actor.split(separator: " ").filter { $0.first?.isLetter == true }.prefix(2)
        let initials = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        let renderer = ImageRenderer(content: AvatarCircle(
            initials: initials.isEmpty ? "?" : initials, tone: n.tone ?? .neutralPair, size: 88
        ))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { return nil }
        return INImage(imageData: data)
    }

    /// The content, dressed as a message when the notice is a person
    /// speaking.
    ///
    /// `updating(from:)` does not rewrite anything you can read: it
    /// attaches a communication context and hands back content with the
    /// same title, body and userInfo, and the SYSTEM substitutes the
    /// sender's name and the conversation line when it draws the banner.
    /// (A first version compared titles to decide whether the dressing
    /// took, and so never dressed anything.) The only refusal the API
    /// expresses is a throw, so a throw is the only road back to the plain
    /// banner. The deed moves into the body because the title will be
    /// replaced by a name on screen.
    ///
    /// Not on the simulator, which draws the dressed content as a plain
    /// banner: the title stays and the body would repeat it. A phone that
    /// runs this build is entitled, because a build whose profile lacks
    /// the capability fails at signing rather than at runtime.
    static func communicationContent(for n: Notice, base: UNMutableNotificationContent) async -> UNNotificationContent {
        #if targetEnvironment(simulator)
        return base
        #else
        guard let intent = intent(for: n),
              let attempt = base.mutableCopy() as? UNMutableNotificationContent else { return base }
        attempt.body = n.deed
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.groupIdentifier = n.post.isEmpty ? "table" : n.post
        do {
            try await interaction.donate()
        } catch {
            print("[TableNews] donation refused: \(error.localizedDescription)")
        }
        do {
            let dressed = try attempt.updating(from: intent)
            print("[TableNews] dressed \(n.kind.rawValue) as a message from \(intent.sender?.displayName ?? "?")")
            return dressed
        } catch {
            print("[TableNews] communication content refused: \(error)")
            return base
        }
        #endif
    }

    // MARK: Showing

    /// Which notices get a banner. Direct first, then newest; the cap cuts
    /// from the bottom and what it cut becomes one line that names who it
    /// was from. Pure, so a test can hold it to the count it promises.
    static func select(_ notices: [Notice]) -> [Notice] {
        // Passive notices never light the screen, so they never compete
        // for it: four plates cannot crowd a dish out of the four. A
        // bell-only notice is not handed to the system at all.
        let quiet = notices.filter { $0.passive && !$0.bellOnly }
        let ordered = notices.filter { !$0.passive && !$0.bellOnly }.sorted {
            if $0.direct != $1.direct { return $0.direct }
            return $0.at > $1.at
        }
        var visible = Array(ordered.prefix(visibleCap))
        let folded = ordered.dropFirst(visibleCap)
        if !folded.isEmpty {
            var names: [String] = []
            for n in folded {
                let first = firstName(n.actor)
                if first != "Someone", !names.contains(first) { names.append(first) }
            }
            let from = names.isEmpty ? "at the table" : "from \(list(names, of: names.count))"
            visible.append(Notice(
                kind: .more, key: "", identifier: idPrefix + "more",
                title: "\(folded.count) more \(from)",
                body: "Open the Table to catch up.",
                line: "", link: DeepLink.url(.table), post: "",
                direct: false, photo: nil, feedKind: .general, actor: "", at: .now,
                rowKey: "", relevance: 0.2
            ))
        }
        return visible + quiet
    }

    /// Where a notice stacks. The room is one conversation; each dish is
    /// its own, the way a group chat and a thread inside it are.
    static func thread(for n: Notice) -> String {
        switch n.kind {
        case .dish, .ask, .seat, .more, .plan: return "table"
        case .householdSeat, .householdLeft, .recipe, .conflict: return "household"
        default: return n.post.isEmpty ? "table" : n.post
        }
    }

    /// What the system is handed for one notice. Pure, given the clock.
    static func content(for n: Notice, at now: Date = .now) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.threadIdentifier = thread(for: n)
        content.categoryIdentifier = NotificationRouter.category(for: n.kind)
        content.relevanceScore = n.relevance
        // The room can wait until morning. A word to you cannot: that is
        // what a person's Focus is for, and second-guessing it with a
        // clock is how a reply from your partner goes unheard. A household
        // join is direct by day and waits like the room by night.
        let quiet = isQuietHour(now) && (!n.direct || n.quietAtNight)
        content.interruptionLevel = (n.passive || quiet) ? .passive : .active
        // After the quiet decision, not before it. Read from `direct` alone,
        // a notice that is both direct and quietAtNight was handed to the
        // system as passive AND with an explicit sound, so the two notices
        // that deliberately wait until morning, a household join and a night
        // the household took off yours, made a noise at two in the morning
        // while presenting silently. Passive is a claim about how loud this
        // is, and a sound contradicts it.
        content.sound = (n.direct && !quiet) ? .default : nil
        content.userInfo = [
            NotificationRouter.Key.link: n.link.absoluteString,
            NotificationRouter.Key.post: n.post,
            NotificationRouter.Key.kind: n.kind.rawValue,
            NotificationRouter.Key.actor: n.actor
        ]
        return content
    }

    private static func show(_ notices: [Notice]) async {
        let wanted = UserDefaults.standard.object(forKey: tableOnKey) as? Bool ?? true
        let allowed = await NotificationScheduler.authorized()
        guard wanted, allowed else {
            // Silence is indistinguishable from success. Say which it was.
            print("[TableNews] banners skipped: wanted=\(wanted) authorized=\(allowed)")
            return
        }

        // The person's finer answer: a category switched off, or a dish
        // they muted. Every row was already written; this is only about
        // the screen. Filtered before the fold so "3 more" counts what
        // would actually have shown.
        let heard = notices.filter(NewsPreferences.allows)
        if heard.count != notices.count {
            print("[TableNews] \(notices.count - heard.count) notice(s) kept to the list by preference")
        }
        let center = UNUserNotificationCenter.current()
        for n in select(heard) {
            let content = content(for: n)
            if let photo = n.photo, let attachment = attachment(for: photo) {
                content.attachments = [attachment]
            }
            // A person speaking wears their face; iOS takes the name as
            // the title and the deed becomes the body, if it takes it.
            let final = await communicationContent(for: n, base: content)
            do {
                try await center.add(UNNotificationRequest(
                    identifier: n.identifier, content: final, trigger: nil
                ))
            } catch {
                print("[TableNews] could not show \(n.kind.rawValue): \(error.localizedDescription)")
            }
        }
    }

    /// 22:00 to 08:00, the phone's clock. Passive delivery: in the list,
    /// no light, no sound. A table does not need to wake anyone.
    static func isQuietHour(_ date: Date = .now) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 22 || hour < 8
    }

    /// The photograph on the banner. The system takes ownership of the file,
    /// so it is written fresh each time rather than pointed at the store,
    /// and taken back if the system refuses it.
    private static func attachment(for photo: Data) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "plated-news-\(UUID().uuidString).jpg")
        guard (try? photo.write(to: url, options: .atomic)) != nil else { return nil }
        if let attachment = try? UNNotificationAttachment(identifier: "photo", url: url) {
            return attachment
        }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    // MARK: The bell

    private static func writeRow(_ n: Notice, context: ModelContext) {
        if let existing = rows(eventKey: n.rowKey, context: context).first {
            // The same dish, more plates: the row moves to the top and reads
            // as new again, rather than a second row counting the same
            // people twice.
            existing.body = n.line
            existing.actorName = n.actor
            existing.link = n.link.absoluteString
            existing.kind = n.feedKind.rawValue
            existing.createdAt = .now
            existing.isRead = false
            existing.template = n.template
            existing.actorID = n.actorID
            existing.objectTitle = n.objectTitle
            existing.addressed = n.addressed
        } else {
            context.insert(PlatedNotification(
                kind: n.feedKind, actorName: n.actor, body: n.line,
                link: n.link.absoluteString, eventKey: n.rowKey, at: n.at,
                template: n.template, actorID: n.actorID,
                objectTitle: n.objectTitle, addressed: n.addressed
            ))
        }
    }

    /// A plate taken back, a vote withdrawn, a comment deleted. The line
    /// that named them is rewritten to whoever still stands, or removed,
    /// and so is the banner. Never re-dated and never re-marked unread: a
    /// retraction is not fresh news.
    static func retract(_ changes: TableShare.Changes, context: ModelContext) {
        let me = TableIdentity.cached
        var touched = false
        var gone: [String] = []
        for r in changes.reactions where !r.author.isEmpty && r.author != me {
            let withdrawn = r.isBallot ? r.value < 0 : r.value == 0
            guard withdrawn, let post = find(r.post, in: context) else { continue }
            let mine = post.authorID.isEmpty ? !post.isRemote : post.authorID == me
            guard mine else { continue }
            let key = (r.isBallot ? "votes:" : "plates:") + r.post
            guard let row = rows(eventKey: key, context: context).first else { continue }
            let people = (r.isBallot ? TableLedger.shared.voters(r.post) : TableLedger.shared.platers(r.post))
                .filter { $0 != me }
            let named = people.compactMap { name(for: $0) }.map(firstName)
            if named.isEmpty {
                context.delete(row)
                gone.append(idPrefix + key)
            } else {
                row.body = "\(list(named, of: people.count)) \(r.isBallot ? "voted on" : "plated your") \(label(post))."
            }
            touched = true
        }
        for name in changes.deleted where name.hasPrefix("note-") {
            for row in rows(eventKey: "note:\(name)", context: context) {
                context.delete(row)
                touched = true
            }
            gone.append(idPrefix + "note:\(name)")
        }
        if touched {
            Persist.save(context, "retracted notices")
            AppBadge.sync(context)
        }
        if !gone.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: gone)
        }
    }

    /// A night taken off the week, before anybody read about it: the row
    /// and the banner go, and nothing is said. A row already read is left
    /// standing for `digest` to follow with "took it off". Runs before the
    /// identity guard, like `retract`, because withdrawing a claim needs
    /// no identity: the night is gone whoever planned it.
    static func retract(plans removed: [PlanLedger.Entry], context: ModelContext) {
        guard !removed.isEmpty else { return }
        var touched = false
        var gone: [String] = []
        for entry in removed {
            let key = "plan:\(entry.recordName)"
            let unread = rows(eventKey: key, context: context).filter { !$0.isRead }
            let standing = rows(eventKey: key, context: context).contains { $0.isRead }
            for row in unread {
                context.delete(row)
                touched = true
            }
            if !standing { gone.append(idPrefix + key) }
        }
        if touched {
            Persist.save(context, "retracted plan notices")
            AppBadge.sync(context)
        }
        if !gone.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: gone)
        }
    }

    private static func rows(eventKey: String, context: ModelContext) -> [PlatedNotification] {
        guard !eventKey.isEmpty else { return [] }
        return (try? context.fetch(FetchDescriptor<PlatedNotification>(
            predicate: #Predicate { $0.eventKey == eventKey }
        ))) ?? []
    }

    /// One row per event. `PlatedNotification` is mirrored, so a person
    /// with two devices writes the same row twice, once from each, and the
    /// mirror then hands each device the other's. Keep the older, drop the
    /// rest. Cheap, idempotent, and run whenever rows are written or read.
    static func dedupeRows(_ context: ModelContext) {
        let keyed = (try? context.fetch(FetchDescriptor<PlatedNotification>(
            predicate: #Predicate { $0.eventKey != "" },
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
        var kept = Set<String>()
        for row in keyed {
            if kept.contains(row.eventKey) {
                context.delete(row)
            } else {
                kept.insert(row.eventKey)
            }
        }
    }

    /// Opening the thing a notice pointed at reads it: the bell row, the
    /// icon, and the banner still sitting in Notification Centre.
    static func markRead(post record: String, context: ModelContext) async {
        guard !record.isEmpty else { return }
        let link = DeepLink.url(post: record).absoluteString
        let rows = (try? context.fetch(FetchDescriptor<PlatedNotification>(
            predicate: #Predicate { $0.link == link && !$0.isRead }
        ))) ?? []
        for row in rows { row.isRead = true }
        if !rows.isEmpty { Persist.save(context, "notice read") }
        await clearDelivered(about: [record])
        AppBadge.sync(context)
    }

    /// A post that was taken off the table takes its notices with it: a
    /// bell row that opens nothing and a banner offering to plate a deleted
    /// dish are both claims about something that no longer exists.
    private static func forget(posts records: Set<String>, context: ModelContext) async {
        let links = Set(records.map { DeepLink.url(post: $0).absoluteString })
        let rows = (try? context.fetch(FetchDescriptor<PlatedNotification>())) ?? []
        for row in rows where links.contains(row.link) {
            context.delete(row)
        }
        Persist.save(context, "notices for deleted posts")
        await clearDelivered(about: records)
        for record in records {
            INInteraction.delete(with: record) { _ in }
        }
        AppBadge.sync(context)
    }

    private static func clearDelivered(about records: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter {
            records.contains($0.request.content.userInfo[NotificationRouter.Key.post] as? String ?? "")
        }.map(\.request.identifier)
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }

    /// Read on one device, quiet on the other. Whatever is still sitting
    /// in Notification Centre about a dish whose rows are all read (here,
    /// or on the iPad, through the mirror) is withdrawn. Seat banners and
    /// reminders carry no post and are left alone.
    static func reconcileDelivered(context: ModelContext) async {
        let unread = (try? context.fetch(FetchDescriptor<PlatedNotification>(
            predicate: #Predicate { !$0.isRead && $0.link != "" }
        ))) ?? []
        let unreadPosts = Set(unread.compactMap { $0.linkURL.flatMap(DeepLink.postID(in:)) })
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(idPrefix) }
            .map { (id: $0.request.identifier,
                    post: $0.request.content.userInfo[NotificationRouter.Key.post] as? String ?? "") }
        let stale = staleDelivered(delivered: delivered, unreadPosts: unreadPosts)
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    /// Which delivered notices no longer have an unread row behind them.
    /// Pure, so a test can hold it to the rule.
    static func staleDelivered(
        delivered: [(id: String, post: String)], unreadPosts: Set<String>
    ) -> [String] {
        var stale = delivered.filter { !$0.post.isEmpty && !unreadPosts.contains($0.post) }.map(\.id)
        if unreadPosts.isEmpty { stale.append(idPrefix + "more") }
        return stale
    }

    // MARK: Acting from the banner

    /// "Plate it" from a dish notice. Idempotent: a second press on the
    /// same banner is not an un-plate.
    static func plate(post record: String, context: ModelContext) async {
        guard let post = find(record, in: context), !post.platedByMeNow else { return }
        TableReactions.togglePlate(post)
        Persist.save(context, "plate from notice")
        // The drain sends every queued write, comments included, and a
        // comment is looked up by name at send time. Without a resolver
        // installed the drain reads "no such comment" as "deleted before it
        // went" and discards it as sent. The feed installs the same closure.
        TableOutbox.shared.resolveNote = { [context] name in
            let all = (try? context.fetch(FetchDescriptor<TableComment>())) ?? []
            return all.first { $0.shareRecordName == name }
        }
        await TableOutbox.shared.drain(authorName: ownerName(in: context))
    }

    /// "Reply" from a comment notice: the same comment `PostThreadView`
    /// would have written, addressed to the person who wrote to you.
    static func reply(post record: String, to actor: String, text: String, context: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let post = find(record, in: context) else { return }
        let typed = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
        let author = typed.isEmpty ? ownerName(in: context) : typed
        let comment = TableComment(
            authorName: author, text: trimmed,
            replyToName: actor,
            authorID: TableIdentity.cached
        )
        comment.post = post
        context.insert(comment)
        Persist.save(context, "reply from notice")
        if await TableShare.pushNote(comment, post: record, zoneOwner: post.shareZoneOwner) == false {
            TableOutbox.shared.enqueue(
                .note(post: record, zoneOwner: post.shareZoneOwner, id: comment.shareRecordName),
                author: comment.authorID
            )
        }
    }

    static func find(_ record: String, in context: ModelContext) -> TablePost? {
        guard !record.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<TablePost>(
            predicate: #Predicate { $0.shareRecordName == record }
        ))) ?? []
        return all.first
    }

    private static func ownerName(in context: ModelContext) -> String {
        Seats.all(in: context).me?.name ?? ""
    }

    // MARK: Memory

    /// How long a sitting is taken to last. Long enough to cover a household
    /// entering a week over a cup of tea, short enough that tomorrow's first
    /// planned night still speaks.
    private static let plannedBurst: TimeInterval = 45 * 60

    /// Whether this phone spoke about this kind of thing inside the window.
    static func spokeRecently(_ key: String, within: TimeInterval, at now: Date) -> Bool {
        guard let last = store.object(forKey: key) as? Date else { return false }
        // A clock that has gone backwards is not a recent utterance.
        let gap = now.timeIntervalSince(last)
        return gap >= 0 && gap < within
    }

    private static var store: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    static func seenKeys() -> Set<String> {
        Set(store.stringArray(forKey: seenKey) ?? [])
    }

    /// For tests, and for nothing else: the memory is what keeps a replayed
    /// zone from raising the same banner twice.
    static func forgetAll() {
        store.removeObject(forKey: seenKey)
        store.removeObject(forKey: namesKey)
        // The planning burst window too. It is app-group state that outlives
        // a launch by design, so a test that did not clear it inherited the
        // previous test's sitting and watched its one planned night arrive
        // silently.
        store.removeObject(forKey: plannedSpokeKey)
    }

    /// Rolling. Old keys age out, and a notice about something months old
    /// is excluded by `window` long before its key is forgotten.
    static func remember(_ keys: [String]) {
        var all = store.stringArray(forKey: seenKey) ?? []
        for key in keys where !key.isEmpty {
            all.append(contentsOf: key.split(separator: "|").map(String.init))
        }
        if all.count > 400 { all.removeFirst(all.count - 400) }
        store.set(all, forKey: seenKey)
    }

    /// Who is who, learned from every record that carries both an id and a
    /// name. The ledger keys plates and votes by id; this is how the bell
    /// turns "three ids" into "Riley, Sam and Jo".
    static func learnNames(from changes: TableShare.Changes) {
        var learned: [String: String] = [:]
        for p in changes.posts where !p.authorID.isEmpty && !p.authorName.isEmpty {
            learned[p.authorID] = p.authorName
        }
        for n in changes.notes where !n.authorID.isEmpty && !n.authorName.isEmpty {
            learned[n.authorID] = n.authorName
        }
        for r in changes.reactions where !r.author.isEmpty && !r.authorName.isEmpty {
            learned[r.author] = r.authorName
        }
        // A night carries three people once a member can edit one: the
        // phone that planned it, whoever last changed it, and the cook it
        // names. The editor is the one the digest's sentence about a change
        // is about, so a name for that id is the difference between saying
        // it and saying nothing.
        for p in changes.plans {
            if !p.authorID.isEmpty, !p.authorName.isEmpty { learned[p.authorID] = p.authorName }
            if !p.editorID.isEmpty, !p.editorName.isEmpty { learned[p.editorID] = p.editorName }
            if !p.cookID.isEmpty, !p.cookName.isEmpty { learned[p.cookID] = p.cookName }
        }
        guard !learned.isEmpty else { return }
        var names = store.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        names.merge(learned) { _, new in new }
        store.set(names, forKey: namesKey)
    }

    /// A seat carries the identity and the name of the person it is, so
    /// the household's records can be narrated by the same book.
    static func learnNames(fromSeats seats: [HouseholdShare.RemoteSeat]) {
        var learned: [String: String] = [:]
        for s in seats {
            if let id = s.userRecordName, !id.isEmpty, !s.name.isEmpty { learned[id] = s.name }
        }
        guard !learned.isEmpty else { return }
        var names = store.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        names.merge(learned) { _, new in new }
        store.set(names, forKey: namesKey)
    }

    static func name(for id: String) -> String? {
        let names = store.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        let name = names[id] ?? ""
        return name.isEmpty ? nil : name
    }

    // MARK: The household (docs/household.md section 10)

    /// Fold a household delivery: bell rows for everything, banners for
    /// the few, through the same gate and the same cap as the Table's.
    static func deliver(
        household changes: HouseholdShare.Changes,
        outcome: HouseholdShare.MergeOutcome,
        context: ModelContext
    ) async {
        learnNames(fromSeats: changes.seats)
        guard !TableIdentity.isPlaceholder || rehearsing else {
            print("[TableNews] identity unconfirmed, nothing decided about the household")
            return
        }
        let notices = digest(household: changes, outcome: outcome, context: context)
        guard !notices.isEmpty else { return }
        for n in notices where n.writesRow {
            writeRow(n, context: context)
        }
        remember(notices.map(\.key))
        dedupeRows(context)
        Persist.save(context, "household news")
        AppBadge.sync(context)
        print("[TableNews] \(notices.count) household notice(s): \(notices.map(\.kind.rawValue))")
        await show(notices)
    }

    /// What in a household delta is news for me. Pure over the store and
    /// the names book, so the tests can hold it to the rules: never about
    /// my own action (`modifiedBy != me`), never unnamed, never twice,
    /// nothing at all from a zone read from the beginning, where the join
    /// has already written the one row that is owed, and nothing about a
    /// plan or a cookbook that is still being uploaded.
    static func digest(
        household changes: HouseholdShare.Changes,
        outcome: HouseholdShare.MergeOutcome,
        context: ModelContext
    ) -> [Notice] {
        guard !changes.replayed else { return [] }
        let me = TableIdentity.cached
        let members = Seats.all(in: context)
        let seen = seenKeys()
        var notices: [Notice] = []

        // History is not news, and the host's first publish is history.
        // A joiner's pull is incremental from the moment they joined
        // (their join stored the token), so every row `publishAll` drains
        // afterwards arrives here as a fresh night and a fresh recipe:
        // hundreds of "Nate planned 3 Mar" and "Nate added Ragu" about a
        // plan and a cookbook that were there before they were. While the
        // root carries no `publishedAt` the app is already saying so on
        // the Plan and in the Cookbook, "Still arriving from Nate's
        // phone" (docs/household.md section 7, step 6), and the root is
        // drained last precisely so that stamp means everything else has
        // landed. Seats, departures and conflicts still speak: those are
        // events, not a back catalogue.
        let stillArriving = HouseholdShare.membership.owner != nil
            && HouseholdShare.cachedPublishedAt == nil
            && changes.root?.publishedAt == nil

        // The same rule pointing the other way, on the host's phone. A
        // joiner adopts and pushes everything they brought in one go
        // (section 7, step 5), so their whole cookbook lands in the
        // delivery that carries their seat. "Riley joined your household"
        // is the news; the cookbook behind it is not.
        let arriving = Set(outcome.newSeats.compactMap(\.userRecordName).filter { !$0.isEmpty })

        // Who touched a record last, by name, from this delivery.
        var modifiedBy: [String: String] = [:]
        for s in changes.seats { modifiedBy[s.recordName] = s.modifiedBy }
        for r in changes.recipes { modifiedBy[r.recordName] = r.modifiedBy }
        var modifiedAt: [String: Date] = [:]
        for s in changes.seats { modifiedAt[s.recordName] = s.modifiedAt }
        for r in changes.recipes { modifiedAt[r.recordName] = r.modifiedAt }

        /// The person behind an identity: their seat's name first, then
        /// what earlier deliveries taught. Nil is "not sent".
        func person(_ id: String) -> (full: String, first: String)? {
            guard !id.isEmpty else { return nil }
            let name = members.first { $0.userRecordName == id }?.name ?? name(for: id) ?? ""
            guard !name.isEmpty, !HouseholdIdentity.isPlaceholder(name) else { return nil }
            let first = firstName(name)
            return first == "Someone" ? nil : (name, first)
        }

        for member in outcome.newSeats {
            let by = modifiedBy[member.shareRecordName] ?? ""
            guard by != me, member.userRecordName != me else { continue }
            let id = member.userRecordName ?? member.shareRecordName
            let key = "household:\(id)"
            guard !seen.contains(key), !HouseholdIdentity.isPlaceholder(member.name) else { continue }
            let who = firstName(member.name)
            guard who != "Someone" else { continue }
            notices.append(Notice(
                kind: .householdSeat, key: key, identifier: idPrefix + key,
                title: "\(who) joined your household",
                body: "They can see the plan, the grocery list and the cookbook now.",
                line: "\(who) joined your household. They can see the plan, the grocery list and the cookbook now.",
                link: DeepLink.url(.home), post: "",
                direct: true, photo: nil, feedKind: .householdJoined,
                actor: member.name, at: modifiedAt[member.shareRecordName] ?? .now, rowKey: key,
                relevance: 0.8, actorID: member.userRecordName ?? "",
                deed: "Joined your household.", group: "Home",
                quietAtNight: true
            ))
        }

        for member in outcome.leftSeats {
            let by = modifiedBy[member.shareRecordName] ?? ""
            guard by != me, member.userRecordName != me else { continue }
            let id = member.userRecordName ?? member.shareRecordName
            let key = "household-left:\(id)"
            guard !seen.contains(key), !HouseholdIdentity.isPlaceholder(member.name) else { continue }
            let who = firstName(member.name)
            guard who != "Someone" else { continue }
            notices.append(Notice(
                kind: .householdLeft, key: key, identifier: idPrefix + key,
                title: "\(who) left your household",
                body: "Their nights are open again.",
                line: "\(who) left your household. Their nights are open again.",
                link: DeepLink.url(.home), post: "",
                direct: false, photo: nil, feedKind: .householdLeft,
                actor: member.name, at: modifiedAt[member.shareRecordName] ?? .now, rowKey: key,
                passive: true, relevance: 0.4, actorID: member.userRecordName ?? "",
                deed: "Left your household.", group: "Home"
            ))
        }

        // No night notice here, and there must not be one again. A night is
        // not a household record: it arrives through the plan pipe, and
        // `digest(plans:)` above says "Nate planned Tacos for Thursday"
        // about it (docs/plan-share.md). Two digests narrating one evening
        // was the shape this change ended.

        for recipe in outcome.newRecipes where !stillArriving {
            let by = modifiedBy[recipe.shareRecordName] ?? ""
            guard by != me, !arriving.contains(by), let who = person(by) else { continue }
            let key = "recipe:\(recipe.shareRecordName)"
            guard !seen.contains(key), !recipe.title.isEmpty else { continue }
            notices.append(Notice(
                kind: .recipe, key: key, identifier: idPrefix + key,
                title: "\(who.first) added \(recipe.title)",
                body: "It's in the cookbook.",
                line: "\(who.first) added \(recipe.title). It's in the cookbook.",
                link: DeepLink.url(.cookbook), post: "",
                direct: false, photo: recipe.photoData, feedKind: .recipeAdded,
                actor: who.full, at: modifiedAt[recipe.shareRecordName] ?? .now, rowKey: key,
                passive: true, relevance: 0.4, actorID: by,
                deed: "Added \(recipe.title).", group: "Home"
            ))
        }

        // An edit of mine that lost to a newer version. The row already
        // shows theirs; the bell says so, and nothing lights the screen.
        // Recipes only: `HouseholdOutbox.conflicts` raises a name for no
        // other kind, and a night cannot lose an edit here because it is not
        // a household record at all.
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        for name in outcome.conflicts {
            let by = modifiedBy[name] ?? ""
            guard by != me, let who = person(by) else { continue }
            let key = "conflict:\(name)"
            guard !seen.contains(key) else { continue }
            guard let recipe = recipes.first(where: { $0.shareRecordName == name }) else { continue }
            let thing = recipe.title.isEmpty ? "a recipe" : recipe.title
            let link = DeepLink.url(.cookbook)
            notices.append(Notice(
                kind: .conflict, key: key, identifier: idPrefix + key,
                title: "\(who.first) changed \(thing) after you did",
                body: "Their version is showing.",
                line: "\(who.first) changed \(thing) after you did. Their version is showing.",
                link: link, post: "",
                direct: false, photo: nil, feedKind: .editConflict,
                actor: who.full, at: modifiedAt[name] ?? .now, rowKey: key,
                passive: true, relevance: 0.3, actorID: by,
                deed: "Changed \(thing) after you did.", group: "Home",
                bellOnly: true
            ))
        }

        return notices.map { dress($0, members: members) }
    }

    // A night as a person would say it lives in `Stamp.nightPhrase`
    // (Theme.swift), and that is the only one. The copy that stood here
    // said a bare "Tuesday" for a night three days gone, which asserts the
    // week it is not; the survivor says "last Tuesday" (DESIGN.md, a
    // relative timestamp runs only while it is unambiguous).

    private static func firstName(_ name: String) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return first.isEmpty ? "Someone" : first
    }

    /// "Riley", "Riley and Sam", "Riley, Sam and Jo", "Riley, Sam and 2
    /// others". `total` counts the people, named or not.
    static func list(_ names: [String], of total: Int) -> String {
        let unnamed = max(0, total - names.count)
        let shown = Array(names.prefix(unnamed == 0 ? 3 : 2))
        let rest = total - shown.count
        switch (shown.count, rest) {
        case (0, _): return "Someone"
        case (1, 0): return shown[0]
        case (2, 0): return "\(shown[0]) and \(shown[1])"
        case (3, 0): return "\(shown[0]), \(shown[1]) and \(shown[2])"
        case (1, _): return "\(shown[0]) and \(rest) other\(rest == 1 ? "" : "s")"
        default: return "\(shown[0]), \(shown[1]) and \(rest) other\(rest == 1 ? "" : "s")"
        }
    }

    /// What to call a post after "your": its dish, its question, or "dish".
    private static func label(_ post: TablePost) -> String {
        if !post.dishTitle.isEmpty { return post.dishTitle }
        if post.kind == "ask", !post.caption.isEmpty {
            return post.caption.count > 40
                ? String(post.caption.prefix(37)).trimmingCharacters(in: .whitespaces) + "..."
                : post.caption
        }
        return post.kind == "ask" ? "ask" : "dish"
    }

    #if DEBUG
    /// Lets the rehearsal past the identity guard on a simulator, where
    /// CloudKit never answers and the id stays a placeholder.
    static var rehearsing = false

    /// A delivery that never came from CloudKit, for looking at the banners
    /// on a simulator. `-plated-fake-table-news`. It writes a real post by
    /// "Riley" into the store, so PlatedApp only honours the flag on a
    /// simulator.
    static func rehearse(context: ModelContext) async {
        rehearsing = true
        defer { rehearsing = false }
        var changes = TableShare.Changes()
        var dish = TableShare.RemotePost()
        dish.recordName = "rehearsal-post-\(UUID().uuidString)"
        dish.authorID = "rehearsal-riley"
        dish.authorName = "Riley Park"
        dish.authorColorHex = "3DA35D"
        dish.dishTitle = "Sheet-pan chicken"
        dish.caption = "Crispy edges tonight. Lemons from the tree."
        dish.createdAt = .now
        dish.photoData = rehearsalPhoto()
        changes.posts.append(dish)

        if let mine = ((try? context.fetch(FetchDescriptor<TablePost>())) ?? [])
            .filter({ !$0.isRemote && !$0.isBlank })
            .max(by: { $0.createdAt < $1.createdAt }) {
            var note = TableShare.RemoteNote()
            note.recordName = "rehearsal-note-\(UUID().uuidString)"
            note.post = mine.shareRecordName
            note.authorID = "rehearsal-sam"
            note.authorName = "Sam Okafor"
            note.text = "Saving this for Sunday."
            changes.notes.append(note)

            var plate = TableShare.RemoteReaction()
            plate.post = mine.shareRecordName
            plate.author = "rehearsal-riley"
            plate.authorName = "Riley Park"
            plate.value = 1
            changes.reactions.append(plate)
        }

        // Two nights Riley planned: one Riley cooks, one the reader does,
        // so both bodies and the remote reminder can be looked at. They
        // live in a zone of their own so the next launch without the flag
        // can drop them without touching a real table's nights.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let owner = Seats.all(in: context).first(where: \.isOwner)?.name ?? ""
        // The name is stable per night, not a fresh UUID: a rehearsal is a
        // restatement of the same two nights, and a new name every launch
        // made the ledger keep the previous ones, so the planner grew a
        // third and a fourth "Sheet-pan chicken" on one Wednesday. That
        // reads exactly like the duplication this whole design exists to
        // prevent, on the one screen the flag is there to photograph.
        func night(_ daysAhead: Int, title: String, cookID: String, cookName: String, cookSeat: String) -> TableShare.RemotePlan {
            var plan = TableShare.RemotePlan()
            plan.recordName = "plan-rehearsal-\(daysAhead)"
            plan.zoneOwner = PlanLedger.rehearsalOwner
            plan.authorID = "rehearsal-riley"
            plan.authorName = "Riley Park"
            plan.authorColorHex = "3DA35D"
            plan.cookID = cookID
            plan.cookName = cookName
            plan.cookSeat = cookSeat
            plan.day = PlanDay.string(calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today)
            plan.title = title
            plan.hasRecipe = true
            plan.recipeMinutes = 35
            plan.shoppingID = plan.recordName
            return plan
        }
        changes.plans = [
            night(1, title: "Sheet-pan chicken", cookID: "rehearsal-riley", cookName: "Riley Park",
                  cookSeat: HouseholdMember.Seat.joined.rawValue),
            night(2, title: "Tacos", cookID: TableIdentity.cached, cookName: owner.isEmpty ? "You" : owner,
                  cookSeat: HouseholdMember.Seat.head.rawValue)
        ]
        changes.plans[0].photoData = rehearsalPhoto()
        // The household has to be the rehearsal zone BEFORE the fold, or
        // the ledger keeps the nights and the planner draws none of them.
        PlanLedger.shared.householdOwner = PlanLedger.rehearsalOwner
        let delta = PlanLedger.shared.absorb(changes, me: TableIdentity.cached)

        TableShare.merge(changes, into: context)
        await deliver(changes, plans: delta, context: context)

        // The reminder a remote night earns is scheduled by the rebuild the
        // push path runs after a fold; the rehearsal is not the push path,
        // so it runs one itself and then shows what the ledger earned.
        let meals = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        await NotificationScheduler.rebuild(meals: meals)
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(NotificationScheduler.remoteTurnPrefix) }
        print("[TableNews] rehearsal: \(pending.count) remote turn reminder(s)")
        for request in pending {
            let fire = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            print("  \(request.identifier): \(request.content.title). \(request.content.body) at \(fire.map { "\($0)" } ?? "?")")
        }
    }

    private static func rehearsalPhoto() -> Data? {
        let size = CGSize(width: 800, height: 1000)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.93, green: 0.55, blue: 0.35, alpha: 1).setFill()  // design-ok(literal-colour): a stand-in photograph, not chrome
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.6)
    }
    #else
    static let rehearsing = false
    #endif
}

/// The number on the icon counts what other people did that you have not
/// looked at, and nothing else. Your own "You posted" rows are the bell's
/// business, not the Home Screen's, and when the Table switch is off the
/// icon says nothing at all. A count is evidence: read the bell, it clears.
@MainActor
enum AppBadge {
    static func count(_ context: ModelContext) -> Int {
        guard NewsPreferences.tableOn else { return 0 }
        let unread = (try? context.fetch(FetchDescriptor<PlatedNotification>(
            predicate: #Predicate { !$0.isRead && $0.eventKey != "" }
        ))) ?? []
        return unread.filter(NewsPreferences.counts).count
    }

    static func sync(_ context: ModelContext) {
        UNUserNotificationCenter.current().setBadgeCount(count(context)) { error in
            if let error { print("[Badge] \(error.localizedDescription)") }
        }
    }
}
