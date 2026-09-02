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
/// message they actually receive. A `CKShare` URL is that: on a phone with
/// Plated it hands the share straight to `ShareAcceptor` — which requires
/// `CKSharingSupported` in Info.plist, and without it every link went to
/// Safari instead. It also beats a custom `plated://` scheme, which is dead
/// text on a phone that doesn't have the app, and that is precisely the
/// phone most invitations are sent to.
///
/// **What it is NOT, yet.** An earlier version of this comment claimed the
/// iCloud page "points at the App Store and holds the invitation until they
/// come back." That was assumed, never verified, and is the same species of
/// comfortable fiction this file was written to delete. What is actually
/// true: somebody without the app lands on an iCloud web page, and what
/// that page offers is Apple's business, not ours.
///
/// The fix, before launch, is a Universal Link on our own domain —
/// `plated.app/join/…` wrapping the share URL, with an
/// apple-app-site-association file and a real landing page. Then a phone
/// with the app opens it directly, and a phone without it sees Plated's own
/// page and an App Store button instead of an Apple support article. Until
/// that exists, do not write copy promising the App Store.
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
        if let link { text += "\n\n\(wrapped(link, hostName: hostName).absoluteString)" }
        return text
    }

    /// The share URL, carried inside a Plated link.
    ///
    /// A phone with the app opens it directly — that is what the
    /// associated-domains entitlement and the `apple-app-site-association`
    /// file on plated.food are for. A phone without the app gets Plated's
    /// own page saying what this is and where to get it, instead of an
    /// Apple support article about a share it cannot open.
    ///
    /// Falls back to the raw iCloud link if the wrap can't be built, since
    /// a link that works for some people beats no link at all.
    static func wrapped(_ share: URL, hostName: String = "") -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "plated.food"
        components.path = "/join"
        var items = [URLQueryItem(name: "s", value: share.absoluteString)]
        // The host's first name, so the page reads as a person keeping you a
        // seat rather than a product announcing itself. Omitted rather than
        // faked when we don't have one.
        let who = hostName.trimmingCharacters(in: .whitespaces)
        if !who.isEmpty { items.append(URLQueryItem(name: "h", value: who)) }
        components.queryItems = items
        return components.url ?? share
    }
}
