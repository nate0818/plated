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

    struct Settled: Equatable {
        var entry: Entry
        var claim: TableShare.Claim
    }

    private var entries: [Entry] = []
    /// A public CKShare often exposes an accepted identity without a name.
    /// The person who used a link might not be its intended recipient, so
    /// this is an invitation hint, never their verified profile name.
    private var invitationRecipients: [String: String] = [:]

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "table-invites.json")
    }

    private static var acceptedURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "table-accepted-names.json")
    }

    private init() { load() }

    /// Oldest first, so the sheet reads in the order they went.
    var pending: [Entry] { entries.sorted { $0.sentAt < $1.sentAt } }
    var isEmpty: Bool { entries.isEmpty }

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }
    func invitationRecipient(for identity: String) -> String? { invitationRecipients[identity] }

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
    @discardableResult
    func settle(claims: [TableShare.Claim]) -> [Settled] {
        let byID = Dictionary(claims.map { ($0.inviteID, $0) }, uniquingKeysWith: { first, _ in first })
        let settled = entries.compactMap { entry -> Settled? in
            guard let claim = byID[entry.id] else { return nil }
            return Settled(entry: entry, claim: claim)
        }
        guard !settled.isEmpty else { return [] }
        let answered = Set(settled.map { $0.entry.id })
        entries.removeAll { answered.contains($0.id) }
        for answer in settled where !answer.claim.userRecordName.isEmpty {
            invitationRecipients[answer.claim.userRecordName] = answer.entry.name
        }
        save()
        for answer in settled {
            print("PLATED HOUSEHOLD: table invitation \(answer.entry.id) for \(answer.entry.name) settled")
        }
        return settled
    }

    func clear() {
        entries = []
        invitationRecipients = [:]
        save()
    }

    // MARK: Disk

    private func load() {
        if let url = Self.url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        if let acceptedURL = Self.acceptedURL,
           let acceptedData = try? Data(contentsOf: acceptedURL),
           let names = try? JSONDecoder().decode([String: String].self, from: acceptedData) {
            invitationRecipients = names
        }
    }

    private func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
        if let acceptedURL = Self.acceptedURL,
           let acceptedData = try? JSONEncoder().encode(invitationRecipients) {
            try? acceptedData.write(to: acceptedURL, options: .atomic)
        }
    }
}
