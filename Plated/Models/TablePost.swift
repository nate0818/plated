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
    var createdAt: Date = Date.now
    /// Household members called out in the caption ("@Riley made the sauce").
    var taggedNames: [String] = []
    /// Ask posts can carry a poll: the choices, the counts, and my pick.
    /// Counts are the rest of the table; mine is tracked separately so a
    /// changed vote can't drift the totals — same trick as plates.
    var pollOptions: [String] = []
    var pollCounts: [Int] = []
    var myPollChoice: Int = -1
    /// Plates from the rest of the table. Mine is tracked separately so the
    /// toggle can't drift the count.
    var plateCount: Int = 0
    var platedByMe: Bool = false
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
    }

    var totalPlates: Int { plateCount + (platedByMe ? 1 : 0) }

    /// Ten plates from the table and the dish has officially made it.
    var hasChefsKiss: Bool { totalPlates >= 10 }

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

    /// Total votes for an option, my ballot included.
    func votes(for option: Int) -> Int {
        let base = pollCounts.indices.contains(option) ? pollCounts[option] : 0
        return base + (myPollChoice == option ? 1 : 0)
    }

    var totalPollVotes: Int {
        pollOptions.indices.reduce(0) { $0 + votes(for: $1) }
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

    var post: TablePost?

    init(
        authorName: String = "", text: String = "", linkURL: String = "",
        createdAt: Date = .now, replyToName: String = "",
        mentions: [String] = [], photoData: Data? = nil
    ) {
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
