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
/// A calendar day as `yyyy-MM-dd`, the way a night travels between phones.
/// A `Date` at midnight is a moment, and the same moment is a different day
/// two time zones over; "2026-09-10" is Thursday everywhere.
enum PlanDay {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String {
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Start of that day in the reader's own calendar.
    static func date(_ string: String) -> Date? {
        formatter.timeZone = .current
        guard let parsed = formatter.date(from: string) else { return nil }
        return Calendar.current.startOfDay(for: parsed)
    }
}

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

    /// `plated://plan?day=2026-09-10`: one night on the plan. The day is a
    /// calendar string, not a timestamp, so it names the same night on
    /// every phone whatever its clock says. `PlanDay` is the one formatter
    /// for it, shared with the plan records on the wire.
    static func url(plan date: Date) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = DeepLink.plan.rawValue
        components.queryItems = [URLQueryItem(name: "day", value: PlanDay.string(date))]
        return components.url ?? url(.plan)
    }

    /// The night inside a `plan` link, or nil for a bare one.
    static func planDay(in url: URL) -> Date? {
        guard destination(for: url) == .plan,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "day" })?.value
        else { return nil }
        return PlanDay.date(raw)
    }

    static func url(post record: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = DeepLink.post.rawValue
        components.queryItems = [URLQueryItem(name: "id", value: record)]
        return components.url ?? url(.table)
    }
}
