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
    var createdAt: Date = Date.now
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
        createdAt: Date = .now,
        plateCount: Int = 0,
        photoData: Data? = nil
    ) {
        self.authorName = authorName
        self.authorColorHex = authorColorHex
        self.dishTitle = dishTitle
        self.caption = caption
        self.kind = kind
        self.createdAt = createdAt
        self.plateCount = plateCount
        self.photoData = photoData
    }

    var totalPlates: Int { plateCount + (platedByMe ? 1 : 0) }

    /// Ten plates from the table and the dish has officially made it.
    var hasChefsKiss: Bool { totalPlates >= 10 }

    var initials: String {
        let parts = authorName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var firstName: String { authorName.split(separator: " ").first.map(String.init) ?? authorName }

    var sortedComments: [TableComment] {
        (comments ?? []).sorted { $0.createdAt < $1.createdAt }
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

    var post: TablePost?

    init(authorName: String = "", text: String = "", linkURL: String = "", createdAt: Date = .now) {
        self.authorName = authorName
        self.text = text
        self.linkURL = linkURL
        self.createdAt = createdAt
    }

    /// Host shown in the link chip: "cooking.nytimes.com".
    var linkLabel: String {
        guard !linkURL.isEmpty, let url = URL(string: linkURL) else { return "" }
        return url.host ?? linkURL
    }
}
