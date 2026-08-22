import Foundation

extension URL {
    /// A URL safe to hand to `Link`: user-typed strings become taps only
    /// when they resolve to http(s). A stored `tel:` or `facetime:` string
    /// must never become a call prompt in a shared feed.
    static func webLink(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
