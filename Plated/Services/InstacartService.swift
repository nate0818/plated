import Foundation
import CryptoKit

/// The partner API key never ships in the app. Plated's edge function verifies
/// this device's existing Apple-backed session before creating a shopping link.
actor InstacartService {
    static let shared = InstacartService()
    struct Line: Codable, Sendable {
        var name: String
        var quantity: Double
        var unit: String
    }
    private struct Receipt: Codable { var products_link_url: URL }
    private struct Cached { var fingerprint: String; var url: URL; var expires: Date }
    private var cached: Cached?
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func shoppingURL(lines: [Line]) async throws -> URL {
        guard !lines.isEmpty else { throw ShoppingError.empty }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(lines)
        var request = try Directory.authenticatedRequest(path: "instacart-shopping-list")
        // A cached shopping link belongs to the signed-in session. Reconnecting
        // or changing accounts must never reveal the previous account's list.
        let scope = Data((request.value(forHTTPHeaderField: "X-Plated-Session") ?? "").utf8)
        let fingerprint = SHA256.hash(data: scope + body).map { String(format: "%02x", $0) }.joined()
        if let cached, cached.fingerprint == fingerprint, cached.expires > .now { return cached.url }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": "Your Plated groceries", "items": JSONSerialization.jsonObject(with: body)])
        request.timeoutInterval = 30
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw ShoppingError.offline }
        guard let http = response as? HTTPURLResponse else { throw ShoppingError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw ShoppingError.signIn }
            if http.statusCode == 503 { throw ShoppingError.unavailable }
            if http.statusCode == 429 { throw ShoppingError.rateLimited }
            throw ShoppingError.invalidResponse
        }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        let url = receipt.products_link_url
        guard url.scheme == "https", let host = url.host,
              host == "instacart.com" || host.hasSuffix(".instacart.com") || host == "instacart.tools" || host.hasSuffix(".instacart.tools")
        else { throw ShoppingError.invalidResponse }
        cached = Cached(fingerprint: fingerprint, url: url, expires: .now.addingTimeInterval(6 * 86400))
        return url
    }
    enum ShoppingError: LocalizedError {
        case empty, offline, signIn, unavailable, rateLimited, invalidResponse
        var errorDescription: String? {
            switch self {
            case .empty: return "Everything in this selection is already checked off."
            case .offline: return "Couldn't connect. Your list is saved; try again when you're online."
            case .signIn: return "Sign in with Apple again to reconnect grocery shopping. Your list is saved."
            case .unavailable: return "Instacart shopping isn't available yet. You can send this list to Reminders."
            case .rateLimited: return "You've created several shopping links recently. Please try again later."
            case .invalidResponse: return "Instacart couldn't prepare your list. Try again."
            }
        }
    }
}
