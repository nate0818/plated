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
    private static let namesKey = "plated.news.names"
    private static let window: TimeInterval = 36 * 3600
    private static let visibleCap = 4

    struct Notice {
        enum Kind: String { case dish, ask, comment, plates, kiss, votes, seat, more }
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
        /// A seat's row is written by `Seats.reconcile`, which is the thing
        /// that knows; the notice only says it out loud.
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
    }

    // MARK: Deciding

    /// Fold a delivery: bell rows for everything, banners for the few.
    static func deliver(
        _ changes: TableShare.Changes,
        newSeats: [HouseholdMember] = [],
        context: ModelContext
    ) async {
        // Even a delta that raises nothing teaches who is who.
        learnNames(from: changes)
        // Taken off the table, or taken back: nothing about it should
        // remain anywhere, and a line that names fewer people than it did
        // is not fresh news.
        if !changes.deleted.isEmpty {
            await forget(posts: changes.deleted, context: context)
        }
        retract(changes, context: context)
        // Without a confirmed identity "not mine" is a guess, and the guess
        // that goes wrong narrates a person's own dinner back to them.
        guard !TableIdentity.isPlaceholder || rehearsing else {
            print("[TableNews] identity unconfirmed, nothing decided")
            return
        }
        let notices = digest(changes, newSeats: newSeats, context: context)
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
        context: ModelContext
    ) -> [Notice] {
        let me = TableIdentity.cached
        let members = Seats.all(in: context)
        let owner = members.first(where: \.isOwner)
        // Names are how replies, mentions and tags are addressed on the
        // wire, so a reply is "to me" when it names either thing I am
        // called. Identity would be better; the wire does not carry it yet.
        var myNames = Set<String>()
        if let owner { myNames.insert(owner.name); myNames.insert(owner.firstName) }
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

        // A seat that just became real. `Seats.reconcile` decided that from
        // what CloudKit reported and wrote the bell row; this only says so
        // out loud.
        for member in newSeats {
            let key = "seat:\(member.participantID ?? member.name)"
            guard !seen.contains(key), !HouseholdIdentity.isPlaceholder(member.name),
                  member.name != "Someone new" else { continue }
            notices.append(Notice(
                kind: .seat, key: key, identifier: idPrefix + key,
                title: "\(member.firstName) joined your table",
                body: "They can see the Table now.",
                line: "\(member.firstName) joined. They can see the Table now.",
                link: DeepLink.url(.home), post: "",
                direct: true, photo: nil, feedKind: .seatJoined,
                actor: member.name, at: .now, rowKey: key, writesRow: false,
                relevance: 0.8, actorID: member.participantID ?? "",
                deed: "Joined your table.", group: "The Table",
                template: "{actor} joined. They can see the Table now."
            ))
        }

        return notices.map { dress($0, members: members) }
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
        let member = members.first { !n.actorID.isEmpty && $0.participantID == n.actorID }
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
        case .dish, .ask, .comment, .plates: break
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
        // for it: four plates cannot crowd a dish out of the four.
        let quiet = notices.filter(\.passive)
        let ordered = notices.filter { !$0.passive }.sorted {
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
        case .dish, .ask, .seat, .more: return "table"
        default: return n.post.isEmpty ? "table" : n.post
        }
    }

    /// What the system is handed for one notice. Pure, given the clock.
    static func content(for n: Notice, at now: Date = .now) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = n.direct ? .default : nil
        content.threadIdentifier = thread(for: n)
        content.categoryIdentifier = NotificationRouter.category(for: n.kind)
        content.relevanceScore = n.relevance
        // The room can wait until morning. A word to you cannot: that is
        // what a person's Focus is for, and second-guessing it with a
        // clock is how a reply from your partner goes unheard.
        content.interruptionLevel = (n.passive || (!n.direct && isQuietHour(now))) ? .passive : .active
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
        Seats.all(in: context).first(where: \.isOwner)?.name ?? ""
    }

    // MARK: Memory

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
        TableShare.merge(changes, into: context)
        await deliver(changes, context: context)
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
