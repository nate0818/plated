import Foundation
import SwiftData

/// One line in the activity feed — someone plated a dish, liked yours,
/// answered your ask. Instagram mechanics, dinner-table content. Generated
/// locally today; the network delivers the cross-device versions later.
@Model
final class PlatedNotification {
    /// One of `PlatedNotificationKind`'s raw values.
    var kind: String = ""
    /// Who did the thing.
    var actorName: String = ""
    /// The line shown in the feed: "Sam plated Pizza Night for Saturday".
    var body: String = ""
    var createdAt: Date = Date.now
    var isRead: Bool = false
    /// Where a tap on this row goes, as a `plated://` link. Empty on rows
    /// written before the feed could open anything, which the row renders
    /// as a plain line rather than a dead button. Defaulted, not optional,
    /// so the CloudKit mirror accepts it without a migration.
    var link: String = ""
    /// Which event this row is about, for rows other people caused. The
    /// model is mirrored, so a person's two devices each write one row per
    /// event and the mirror hands each the other's; `TableNews.dedupeRows`
    /// keeps one per key. Empty on rows about your own actions, which are
    /// written once and never coalesce. Defaulted for the mirror.
    var eventKey: String = ""

    init(
        kind: PlatedNotificationKind, actorName: String = "", body: String = "",
        link: String = "", eventKey: String = "", at: Date = .now
    ) {
        self.kind = kind.rawValue
        self.actorName = actorName
        self.body = body
        self.link = link
        self.eventKey = eventKey
        // The event's own time, when the caller knows it. A comment written
        // at 22:14 and fetched at 07:00 is not "Just now".
        self.createdAt = at
    }

    var linkURL: URL? {
        link.isEmpty ? nil : URL(string: link)
    }

    var kindValue: PlatedNotificationKind {
        PlatedNotificationKind(rawValue: kind) ?? .general
    }
}

enum PlatedNotificationKind: String, Codable, CaseIterable {
    case mealPlanned      // someone put dinner on the plan
    case turnReminder     // it's your night and nothing is plated
    case groceriesAdded   // items landed on the list
    case groceriesOrdered // someone kicked off a delivery
    case plateReaction    // someone plated your post
    case saveReceived     // someone saved your dish to their cookbook
    case commentAdded     // comment or reply on a post
    case recipeAdded      // a new recipe joined the cookbook
    case askPosted        // someone asked the table for ideas
    case prongsbyReplied  // the fork answered while you were elsewhere
    case dishPosted       // somebody else put a dish on the table
    case voteCast         // a ballot landed on your ask
    case seatJoined       // an invitation was accepted
    case general

    /// Whether the row's actor is a person to show, rather than a thing.
    var isAboutSomebody: Bool {
        switch self {
        case .plateReaction, .commentAdded, .askPosted, .dishPosted, .voteCast, .seatJoined:
            return true
        default:
            return false
        }
    }

    var symbolName: String {
        switch self {
        case .mealPlanned: return "calendar.badge.checkmark"
        case .turnReminder: return "frying.pan"
        case .groceriesAdded: return "basket"
        // A list was copied, not shipped. The raw value stays put because
        // it is stored, but the icon does not have to keep overstating it.
        case .groceriesOrdered: return "list.clipboard"
        case .plateReaction: return "circle.circle"
        case .saveReceived: return "arrow.down.heart"
        case .prongsbyReplied: return "fork.knife"
        case .commentAdded: return "bubble.right"
        case .recipeAdded: return "book.closed"
        case .askPosted: return "bubble.and.pencil"
        case .dishPosted: return "photo"
        case .voteCast: return "checkmark.circle"
        case .seatJoined: return "person.badge.plus"
        case .general: return "bell"
        }
    }
}

/// The household's own face — banner photo and anything else that makes
/// Home feel like *their* kitchen instead of a template. One row, ever.
@Model
final class HouseholdProfile {
    @Attribute(.externalStorage) var bannerPhotoData: Data?
    var createdAt: Date = Date.now

    init(bannerPhotoData: Data? = nil) {
        self.bannerPhotoData = bannerPhotoData
        self.createdAt = .now
    }
}
