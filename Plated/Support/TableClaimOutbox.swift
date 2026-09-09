import Foundation

/// Pending Table invitation claims that did not land on the first write.
///
/// Accept can succeed while `pushClaim` fails (transient CloudKit). Without
/// a retry the host's Invited row never settles and the joiner looks like
/// they never joined. Same app-group pattern as `TableOutbox`: a small JSON
/// book drained on every Table pull.
@MainActor
enum TableClaimOutbox {
    private struct Entry: Codable, Equatable {
        var inviteID: String
        var zoneOwner: String
    }

    private static let key = "plated.table.claimOutbox"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    static func remember(inviteID: String, zoneOwner: String) {
        guard !inviteID.isEmpty else { return }
        var book = load()
        if !book.contains(where: { $0.inviteID == inviteID }) {
            book.append(Entry(inviteID: inviteID, zoneOwner: zoneOwner))
            save(book)
            print("PLATED SHARE: queued claim for invitation \(inviteID)")
        }
    }

    static func forget(inviteID: String) {
        var book = load()
        let before = book.count
        book.removeAll { $0.inviteID == inviteID }
        guard book.count != before else { return }
        save(book)
    }

    /// Drain every pending claim. Successful writes drop; refusals stay
    /// for the next pull.
    static func drain() async {
        let book = load()
        guard !book.isEmpty else { return }
        for entry in book {
            let ok = await TableShare.pushClaim(inviteID: entry.inviteID, zoneOwner: entry.zoneOwner)
            if ok {
                forget(inviteID: entry.inviteID)
            }
        }
    }

    private static func load() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let book = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return book
    }

    private static func save(_ book: [Entry]) {
        defaults.set(try? JSONEncoder().encode(book), forKey: key)
    }
}
