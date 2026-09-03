import Foundation
import SwiftData

/// One moment shared to the Table — a plated dish (photo + caption) or an
/// open ask ("what should we plate Thursday?"). Feed mechanics are
/// Instagram's, but the reaction is a plate and ten plates earn the kiss.
@Model
final class TablePost {
    var authorName: String = ""
    var authorColorHex: String = "FF5A3C"
    var dishTitle: String = ""
    var caption: String = ""
    /// "dish" (photo moment) or "ask" (open request for ideas).
    var kind: String = "dish"
    /// True for posts from open tables shown in Discover, never in your feed.
    var isDiscover: Bool = false
    /// The CloudKit record this post is, once it has left the device.
    ///
    /// Empty means "mine and not yet published". Non-empty is the identity
    /// a merge keys on — without it, every fetch would insert a second copy
    /// of every post, since nothing else about a dish is reliably unique
    /// (two people can plate the same title on the same evening).
    var shareRecordName: String = ""
    /// True when this arrived from somebody else's table. Guests may plate
    /// and comment; they may not edit or delete what isn't theirs.
    var isRemote: Bool = false
    /// Which table's zone this post lives in. "" always means my own.
    ///
    /// Without it, writing back to a post is routed by asking "do I host a
    /// zone?", which is a question about the person rather than about the
    /// post. Anyone who has tapped Invite once hosts forever, so deleting a
    /// post on a table they JOINED aimed the delete at their own zone, hit
    /// `.unknownItem`, and read that as "already gone" — which removes the
    /// local row and lets the next pull bring the post back as a stranger's,
    /// undeletable. Verbatim the bug that made deleting a post a lie, down a
    /// second road.
    ///
    /// Defaulted rather than optional so the mirror stays CloudKit-safe, and
    /// "" is correct for every post that already exists: before tables could
    /// be joined, every post was on your own.
    var shareZoneOwner: String = ""
    var createdAt: Date = Date.now
    /// Household members called out in the caption ("@Riley made the sauce").
    var taggedNames: [String] = []
    /// Ask posts can carry a poll: the choices, the counts, and my pick.
    /// Counts are the rest of the table; mine is tracked separately so a
    /// changed vote can't drift the totals — same trick as plates.
    var pollOptions: [String] = []
    var pollCounts: [Int] = []
    var myPollChoice: Int = -1
    /// Plates and votes as they were before `TableLedger` existed.
    ///
    /// Never written again. A count is a lost update the moment two devices
    /// hold one — an Int incremented in two places has no way to detect that
    /// it was — so the truth moved to one entry per person per post in the
    /// ledger, which merges by construction. These stay because removing a
    /// mirrored property is a migration nobody needs, and because the
    /// backfill reads them exactly once to seed the ledger.
    var plateCount: Int = 0
    var platedByMe: Bool = false
    /// Whether this has actually reached the table.
    ///
    /// `shareRecordName` used to carry two meanings at once — the record's
    /// name AND whether it had ever been published — so a post could not
    /// have a stable identity before it went out. It gets one at birth now,
    /// which is what lets the ledger file reactions against a post that has
    /// never left the phone.
    var isPublished: Bool = false
    @Attribute(.externalStorage) var photoData: Data?

    @Relationship(deleteRule: .cascade, inverse: \TableComment.post)
    var comments: [TableComment]? = []

    init(
        authorName: String = "",
        authorColorHex: String = "FF5A3C",
        dishTitle: String = "",
        caption: String = "",
        kind: String = "dish",
        isDiscover: Bool = false,
        createdAt: Date = .now,
        plateCount: Int = 0,
        photoData: Data? = nil
    ) {
        self.authorName = authorName
        self.authorColorHex = authorColorHex
        self.dishTitle = dishTitle
        self.caption = caption
        self.kind = kind
        self.isDiscover = isDiscover
        self.createdAt = createdAt
        self.plateCount = plateCount
        self.photoData = photoData
        // Minted here, not at publish. Identity is not something a post
        // earns by reaching the network.
        self.shareRecordName = "post-\(UUID().uuidString)"
    }

    /// A post with nobody behind it and nothing in it.
    ///
    /// Nothing a person can do makes one: the composer refuses to post
    /// without a photo or a name, and every path through it stamps an
    /// author. These arrive on their own — see `TableShare.postType` for
    /// how — and they render as a card with a blank byline, no dish and
    /// no words. The feed, the widget and every count skip them.
    var isBlank: Bool {
        authorName.isEmpty && dishTitle.isEmpty && caption.isEmpty
            && photoData == nil && pollOptions.isEmpty
    }

    /// How many people plated this, from the ledger.
    ///
    /// Was `plateCount + (platedByMe ? 1 : 0)`, and `plateCount` was written
    /// by exactly one file in the whole app: SampleData. So on a real device
    /// this was 0 or 1 for the life of every post, and the Chef's kiss below
    /// — which needs ten — could never once fire for a real dinner.
    @MainActor
    var totalPlates: Int {
        TableLedger.shared.plateCount(shareRecordName, me: TableIdentity.cached)
    }

    @MainActor
    var platedByMeNow: Bool {
        TableLedger.shared.platedByMe(shareRecordName, me: TableIdentity.cached)
    }

    /// Everyone at the table plated it.
    ///
    /// Ten was unreachable by arithmetic, and it would have been unreachable
    /// by product too: this is a household, not an audience. "Everybody who
    /// could plate this did" is a thing that can actually happen at a table
    /// of four, and it means more there than ten ever meant anywhere.
    @MainActor
    func hasChefsKiss(seats: Int) -> Bool {
        seats >= 2 && totalPlates >= seats
    }

    var initials: String {
        let parts = authorName.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var firstName: String { authorName.split(separator: " ").first.map(String.init) ?? authorName }

    /// Stable identity for "saved to cookbook" bookkeeping.
    var originKey: String {
        // A title is optional in the composer, so keying on it alone made
        // every untitled post by one person the same post: save one of
        // Sam's photo-only dishes and every future one answers "already in
        // your cookbook". Titled posts keep the old key so the legacy
        // Discover repair still matches them.
        dishTitle.isEmpty
            ? "post:\(authorName)|\(Int(createdAt.timeIntervalSince1970))"
            : "post:\(authorName)|\(dishTitle)"
    }

    var sortedComments: [TableComment] {
        (comments ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var hasPoll: Bool { !pollOptions.isEmpty }

    /// Votes for an option, from the ledger. `pollCounts` was only ever
    /// `Array(repeating: 0, …)` — one phone's ballot printed as the table's.
    @MainActor
    func votes(for option: Int) -> Int {
        let tally = TableLedger.shared.votes(shareRecordName, options: pollOptions.count)
        return tally.indices.contains(option) ? tally[option] : 0
    }

    @MainActor
    var totalPollVotes: Int {
        TableLedger.shared.totalVotes(shareRecordName)
    }

    @MainActor
    var myVote: Int {
        TableLedger.shared.myVote(shareRecordName, me: TableIdentity.cached)
    }
}

/// Comments allow URLs on purpose — recipes live all over the internet and
/// Grandma should be able to point at one.
@Model
final class TableComment {
    var authorName: String = ""
    var text: String = ""
    var linkURL: String = ""
    var createdAt: Date = Date.now
    /// Name of the person this comment answers — threads stay flat, replies
    /// read as "↩︎ Grandma" the way IG keeps one level.
    var replyToName: String = ""
    /// Household members @-mentioned in the text.
    var mentions: [String] = []
    /// A photo in the comments — the "I made it and here's proof" move.
    @Attribute(.externalStorage) var photoData: Data?
    /// This comment's name on the wire, minted at compose time.
    ///
    /// A UUID rather than anything derived, because two people commenting in
    /// the same instant must not contend for a name — and because a save
    /// whose response was lost has to replay as a no-op rather than as a
    /// duplicate. It is the key a merge from the wire matches on, so nothing
    /// else about a comment needs to be unique.
    var shareRecordName: String = ""
    /// Who wrote it, in CloudKit's terms rather than in first names.
    var authorID: String = ""

    var post: TablePost?

    init(
        authorName: String = "", text: String = "", linkURL: String = "",
        createdAt: Date = .now, replyToName: String = "",
        mentions: [String] = [], photoData: Data? = nil,
        authorID: String = ""
    ) {
        self.shareRecordName = "note-\(UUID().uuidString)"
        self.authorID = authorID
        self.authorName = authorName
        self.text = text
        self.linkURL = linkURL
        self.createdAt = createdAt
        self.replyToName = replyToName
        self.mentions = mentions
        self.photoData = photoData
    }

    /// Host shown in the link chip: "cooking.nytimes.com".
    var linkLabel: String {
        guard !linkURL.isEmpty, let url = URL(string: linkURL) else { return "" }
        return url.host ?? linkURL
    }
}
