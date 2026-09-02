import Foundation
import CloudKit

/// An invitation somebody can actually receive.
///
/// **What was wrong.** "Invite" wrote a name into a local string and stopped
/// there. The row then said "Waiting on them" — about a person who had
/// never been contacted, would never be contacted, and had no way of
/// knowing they had been invited to anything. Two people looking at two
/// phones, one of them told a comforting lie.
///
/// **What an invitation has to be.** A link the recipient can tap, in a
/// message they actually receive, that works whether or not they have the
/// app. A `CKShare` URL is all three: tapped on a phone with Plated it
/// hands the share straight to `ShareAcceptor`; tapped without it, iCloud
/// serves a web page that points at the App Store and holds the invitation
/// until they come back. That is the whole reason the invite rides a share
/// URL rather than a custom `plated://` scheme — a custom scheme is dead
/// text on a phone that doesn't have the app, which is precisely the phone
/// every invitation is sent to.
enum Invitation {

    struct Ready {
        /// Nil when CloudKit could not mint a share — no account, no
        /// network, or sharing switched off. The invite still sends; it
        /// just carries words instead of a link.
        var url: URL?
        var body: String

        var hasLink: Bool { url != nil }
    }

    /// The live share URL, minted once and reused.
    ///
    /// Reused rather than re-minted because a second `CKShare` on the same
    /// root silently invalidates the first — and the first is already
    /// sitting in somebody's Messages thread. `TableShare.invitationURL`
    /// enforces that server-side; this cache just keeps us from asking
    /// CloudKit on every keystroke.
    private static var cached: URL?

    static func prepare(hostName: String) async -> Ready {
        if cached == nil { cached = await TableShare.invitationURL(hostName: hostName) }
        return Ready(url: cached, body: body(hostName: hostName, link: cached))
    }

    /// What is already known, without waiting on the network. Lets a button
    /// render its final state immediately when the link was fetched earlier.
    static var known: URL? { cached }

    static func body(hostName: String, link: URL?) -> String {
        var text = TableSync.inviteMessage(hostName: hostName)
        if let link { text += "\n\n\(link.absoluteString)" }
        return text
    }
}
