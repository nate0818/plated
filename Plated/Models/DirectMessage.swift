import Foundation
import SwiftData

/// One line of a direct conversation with a seat at your table. Stored
/// locally (and in your iCloud container) today; when Plated grows a real
/// social backend these become the send queue.
@Model
final class DirectMessage {
    /// The other person's name — the thread key until real user IDs exist.
    var peerName: String = ""
    var text: String = ""
    var isMine: Bool = true
    var createdAt: Date = Date.now

    init(peerName: String = "", text: String = "", isMine: Bool = true, createdAt: Date = .now) {
        self.peerName = peerName
        self.text = text
        self.isMine = isMine
        self.createdAt = createdAt
    }
}
