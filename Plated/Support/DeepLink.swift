import Foundation

/// Where a widget can drop you. A widget that doesn't land you in the right
/// place is a poster, so every one of them carries a `widgetURL` and the
/// shell routes it here.
///
/// The scheme is registered in config/PlatedInfo.plist. Keep the raw values
/// in step with `PlatedLink` on the widget side — they're the same contract
/// as the snapshot's JSON keys.
enum DeepLink: String {
    case plan
    case table
    case grocery
    case cookbook
    case prongsby
    case home

    static let scheme = "plated"

    static func destination(for url: URL) -> DeepLink? {
        guard url.scheme == scheme else { return nil }
        // plated://grocery — the host carries it; fall back to the path so a
        // hand-typed plated:///grocery still works.
        let name = url.host ?? url.pathComponents.first(where: { $0 != "/" }) ?? ""
        return DeepLink(rawValue: name.lowercased())
    }
}
