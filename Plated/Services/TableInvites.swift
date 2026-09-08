import Foundation
import Observation

/// Table invitations this phone actually sent (docs/household.md §9).
///
/// Written only when the composer reported `.sent`, which is what lets the
/// seats sheet say "Invited Tuesday" without asserting a message that never
/// went. A Table invitation creates no `HouseholdMember`: a friend at the
/// Table is not in the household, and the roster is the household. So the
/// pending invitation needs a home of its own, and it is this small book in
/// the app group beside the ledger.
///
/// Every Table link carries the entry's id. On accept the joiner writes a
/// claim naming it, the host's next Table pull settles it, and an entry
/// that never settles can always be cancelled by hand.
@MainActor
@Observable
final class TableInvites {
    static let shared = TableInvites()

    struct Entry: Codable, Identifiable, Equatable {
        var id: String
        var name: String
        var phone: String?
        var email: String?
        var sentAt: Date
    }

    private var entries: [Entry] = []

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "table-invites.json")
    }

    private init() { load() }

    /// Oldest first, so the sheet reads in the order they went.
    var pending: [Entry] { entries.sorted { $0.sentAt < $1.sentAt } }
    var isEmpty: Bool { entries.isEmpty }

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    /// Minted before the composer opens, so the link can carry the id, and
    /// deliberately not saved: nothing is recorded until the composer says
    /// the message went. `sentAt` is set now and is only ever read once
    /// `record` has made it true.
    func mint(name: String, phone: String?, email: String?) -> Entry {
        Entry(id: UUID().uuidString, name: name, phone: phone, email: email, sentAt: .now)
    }

    /// The composer reported `.sent`. Keyed on id, so a resend of the same
    /// entry updates its date rather than listing the person twice.
    func record(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        save()
        print("PLATED HOUSEHOLD: recorded table invitation \(entry.id) for \(entry.name)")
    }

    func cancel(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Claims read from the Table zone name the invitations they answer.
    func settle(claims: [TableShare.Claim]) {
        let answered = Set(claims.map(\.inviteID))
        guard entries.contains(where: { answered.contains($0.id) }) else { return }
        let settled = entries.filter { answered.contains($0.id) }
        entries.removeAll { answered.contains($0.id) }
        save()
        for entry in settled {
            print("PLATED HOUSEHOLD: table invitation \(entry.id) for \(entry.name) settled")
        }
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: Disk

    private func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
