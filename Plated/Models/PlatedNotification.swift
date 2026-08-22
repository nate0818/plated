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

    init(kind: PlatedNotificationKind, actorName: String = "", body: String = "") {
        self.kind = kind.rawValue
        self.actorName = actorName
        self.body = body
        self.createdAt = .now
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
    case general

    var symbolName: String {
        switch self {
        case .mealPlanned: return "calendar.badge.checkmark"
        case .turnReminder: return "frying.pan"
        case .groceriesAdded: return "basket"
        case .groceriesOrdered: return "shippingbox"
        case .plateReaction: return "circle.circle"
        case .saveReceived: return "arrow.down.heart"
        case .prongsbyReplied: return "fork.knife"
        case .commentAdded: return "bubble.right"
        case .recipeAdded: return "book.closed"
        case .askPosted: return "hand.raised"
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
