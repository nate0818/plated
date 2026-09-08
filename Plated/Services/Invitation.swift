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
/// **The link is ours, the share is Apple's.** The share URL travels inside
/// a Universal Link on plated.food (`/join` for the Table, `/join/household`
/// for the household), with an apple-app-site-association file and a real
/// landing page. A phone with the app opens it directly; a phone without
/// it sees Plated's own page saying what this is, and the page offers a
/// `plated://join` link for the window before iOS has fetched the
/// association file. What that page promises about installing is written
/// in `web/app/join/copy.ts`, and nothing here may promise more.
///
/// **Two kinds, one grammar** (docs/household.md §6, §9). A household link
/// names the seat it was minted for; a Table link names the invitation
/// entry it answers. The kind is carried in the path and in `k=`, and the
/// app never trusts either: `ShareAcceptor.received` dispatches on the zone
/// the share actually resolves to.
enum Invitation {

    // MARK: Building a link

    /// The share URL, carried inside a Plated link.
    ///
    /// Falls back to the raw iCloud link if the wrap can't be built, since
    /// a link that works for some people beats no link at all.
    static func wrapped(
        _ share: URL, hostName: String, kind: Seats.Kind, seat: String?, invite: String?
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "plated.food"
        components.path = kind == .household ? "/join/household" : "/join"
        var items = [URLQueryItem(name: "s", value: share.absoluteString)]
        // The host's first name, so the page reads as a person keeping you a
        // seat rather than a product announcing itself. Omitted rather than
        // faked when we don't have one.
        let who = hostName.trimmingCharacters(in: .whitespaces)
        if !who.isEmpty { items.append(URLQueryItem(name: "h", value: who)) }
        // The seat this link was minted for. A seatless link is legitimate
        // (Copy link, Share a link): the joiner picks their seat on arrival.
        if kind == .household, let seat, !seat.isEmpty {
            items.append(URLQueryItem(name: "seat", value: seat))
        }
        // The TableInvites entry this link answers, so the host's sheet can
        // settle "Invited Tuesday" when the claim comes back.
        if kind == .table, let invite, !invite.isEmpty {
            items.append(URLQueryItem(name: "i", value: invite))
        }
        components.queryItems = items
        return components.url ?? share
    }

    // MARK: Reading a link

    struct Parsed: Equatable {
        var share: URL
        var kind: Seats.Kind
        var seat: String?
        var invite: String?
        var host: String
    }

    /// Every road an invitation link can take, read into one shape:
    ///
    /// - `https://plated.food/join?s=&h=&i=` and `/join/household?s=&h=&seat=`
    ///   (www. too), the kind from the path unless `k=` says otherwise;
    /// - `plated://join?s=&k=&seat=&i=&h=`, the page's own fallback;
    /// - `plated://invite?s=&from=&k=&seat=&i=`, the directory's push, with
    ///   the host under `from`.
    ///
    /// The share has to be https: a push or a page that could smuggle an
    /// arbitrary scheme into the app's accept path is not an invitation.
    static func parse(_ url: URL) -> Parsed? {
        parse(url, depth: 0)
    }

    /// One of our own links, as opposed to the iCloud share URL that
    /// normally sits under `s`.
    private static func isOurs(_ url: URL) -> Bool {
        switch (url.scheme?.lowercased(), url.host?.lowercased()) {
        case ("https", "plated.food"), ("https", "www.plated.food"):
            return url.path.split(separator: "/").first.map(String.init) == "join"
        case ("plated", "join"), ("plated", "invite"):
            return true
        default:
            return false
        }
    }

    /// `depth` bounds the unwrap below. The directory nests exactly one of
    /// our links inside another and a hand-crafted one must not nest for
    /// ever, so past the first level this answers nil.
    private static func parse(_ url: URL, depth: Int) -> Parsed? {
        guard depth <= 1 else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            let raw = items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespaces) ?? ""
            return raw.isEmpty ? nil : raw
        }

        var pathKind: Seats.Kind?
        var hostKey = "h"
        switch (url.scheme?.lowercased(), url.host?.lowercased()) {
        case ("https", "plated.food"), ("https", "www.plated.food"):
            // Trailing slashes are how a link gets pasted; they change nothing.
            let path = url.path.split(separator: "/").map(String.init)
            switch path {
            case ["join"]: pathKind = .table
            case ["join", "household"]: pathKind = .household
            default: return nil
            }
        case ("plated", "join"):
            pathKind = .table
        case ("plated", "invite"):
            pathKind = .table
            hostKey = "from"
        default:
            return nil
        }

        guard let raw = value("s"), let inner = URL(string: raw) else { return nil }

        // One of ours inside another of ours. `Seats.confirmSent` hands the
        // directory the wrapped plated.food link, and `/invite` puts it back
        // verbatim under `plated://invite?s=`, so the push's `s` is a
        // plated.food URL rather than an iCloud share. Handed on unopened it
        // reaches `CKFetchShareMetadataOperation`, which refuses it and tells
        // the person the link is dead. The inner link is the authority on the
        // share, the kind and what it names; the host stays the outer link's,
        // because that is the one the server verified.
        if isOurs(inner) {
            // A link of ours is never itself a share URL, so a nest too deep
            // to open is nothing rather than something to hand to CloudKit.
            guard let nested = parse(inner, depth: depth + 1) else { return nil }
            return Parsed(
                share: nested.share,
                kind: nested.kind,
                seat: nested.seat ?? (nested.kind == .household ? value("seat") : nil),
                invite: nested.invite ?? (nested.kind == .table ? value("i") : nil),
                host: value(hostKey) ?? nested.host
            )
        }

        guard inner.scheme == "https" else { return nil }
        let share = inner
        let kind = value("k").flatMap(Seats.Kind.init(rawValue:)) ?? pathKind ?? .table
        return Parsed(
            share: share,
            kind: kind,
            seat: kind == .household ? value("seat") : nil,
            invite: kind == .table ? value("i") : nil,
            host: value(hostKey) ?? ""
        )
    }

    // MARK: The words around it

    /// The message the composer opens with. A household invitation is its
    /// own sentence, never the Table's: the two rooms promise different
    /// things (docs/household.md §6).
    static func body(hostName: String, kind: Seats.Kind, link: URL) -> String {
        sentence(hostName: hostName, kind: kind) + "\n\n" + link.absoluteString
    }

    /// The words without the link, for a share sheet that carries the URL
    /// as its own item.
    static func sentence(hostName: String, kind: Seats.Kind) -> String {
        let host = hostName.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .household:
            return host.isEmpty
                ? "Join my household on Plated to plan dinners together."
                : "\(host) invited you to plan dinners together on Plated. Open the link to join their household."
        case .table:
            return TableSync.inviteMessage(hostName: host)
        }
    }
}
