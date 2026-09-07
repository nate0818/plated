import Foundation

/// Where a widget or a notification can drop you. A widget that doesn't land
/// you in the right place is a poster, and a notification that opens the
/// app rather than the thing it was about is a doorbell; every one of them
/// carries a URL and the shell routes it here.
///
/// The scheme is registered in config/PlatedInfo.plist. Keep the raw values
/// in step with `PlatedLink` on the widget side — they're the same contract
/// as the snapshot's JSON keys. `post` and `activity` exist only on this
/// side: the widget never links to a single post.
enum DeepLink: String {
    case plan
    case table
    case grocery
    case cookbook
    case prongsby
    case home
    /// `plated://post?id=<record name>` — one dish's thread.
    case post
    /// The bell.
    case activity
    /// `plated://invite?s=<share url>&from=<name>`, the link a push about a
    /// saved seat carries. It asks before it seats anybody: a link that
    /// accepts on tap would let any push put a person at a stranger's table.
    case invite

    static let scheme = "plated"

    static func destination(for url: URL) -> DeepLink? {
        guard url.scheme == scheme else { return nil }
        // plated://grocery — the host carries it; fall back to the path so a
        // hand-typed plated:///grocery still works.
        let name = url.host ?? url.pathComponents.first(where: { $0 != "/" }) ?? ""
        return DeepLink(rawValue: name.lowercased())
    }

    /// The record name inside a `post` link, or nil for anything else.
    static func postID(in url: URL) -> String? {
        guard destination(for: url) == .post,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty
        else { return nil }
        return id
    }

    static func url(_ destination: DeepLink) -> URL {
        URL(string: "\(scheme)://\(destination.rawValue)")!
    }

    /// The seat inside an `invite` link: who saved it, and the share.
    static func invitation(in url: URL) -> (from: String, share: URL)? {
        guard destination(for: url) == .invite,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "s" })?.value,
              let share = URL(string: raw),
              share.scheme == "https"
        else { return nil }
        let from = items.first(where: { $0.name == "from" })?.value ?? ""
        return (from, share)
    }

    static func url(post record: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = DeepLink.post.rawValue
        components.queryItems = [URLQueryItem(name: "id", value: record)]
        return components.url ?? url(.table)
    }
}
