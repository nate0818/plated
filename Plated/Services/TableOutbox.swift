import Foundation

/// Writes that have not reached the table yet.
///
/// Deliberately **not** a SwiftData entity. A mirrored outbox is a
/// distributed queue with no lease: two of one person's devices both see the
/// same pending row and both drain it, and a stale `.pending` export
/// overwrites a `.landed` written seconds earlier on the other phone. The
/// queue is per-device work, so it lives per-device, in the app group beside
/// the ledger and the change tokens.
///
/// Every entry carries the identity it was minted under, not a reference to
/// "me". An Apple ID can change between a tap and a drain, and a plate
/// written by the previous account must never be replayed into the new one's
/// zone — `TableIdentity.reset()` empties this for exactly that reason.
@MainActor
final class TableOutbox {
    static let shared = TableOutbox()

    enum Work: Codable, Equatable {
        case plate(post: String, zoneOwner: String, active: Bool)
        case ballot(post: String, zoneOwner: String, choice: Int)
        case note(post: String, zoneOwner: String, id: String)
    }

    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var work: Work
        var author: String
        var at: Date
        /// Failed attempts. A write that keeps being refused backs off
        /// rather than hammering the network on every pull.
        var tries: Int = 0
    }

    private var entries: [Entry] = []

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "table-outbox.json")
    }

    private init() { load() }

    var pending: [Entry] { entries }
    var isEmpty: Bool { entries.isEmpty }

    /// Queue a write, replacing any earlier one for the same thing.
    ///
    /// Keyed rather than appended: plate, un-plate, plate again while offline
    /// is one final state, not three writes. The key deliberately excludes
    /// the value, so the newest intent wins and the queue cannot grow with
    /// somebody fidgeting.
    func enqueue(_ work: Work, author: String, at: Date = .now) {
        let key = Self.key(for: work)
        entries.removeAll { Self.key(for: $0.work) == key }
        entries.append(Entry(id: key, work: work, author: author, at: at))
        save()
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// This attempt failed. Kept, so it goes out on the next pull.
    func failed(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].tries += 1
        // Twenty refusals is not a network blip, it is a write that will
        // never land — a post deleted at the far end, most likely. Dropping
        // it is honest; retrying forever is a queue that never drains and a
        // battery that never rests.
        if entries[i].tries > 20 { entries.remove(at: i) }
        save()
    }

    /// The identity that minted these turned out to be a real one.
    func reattribute(from old: String, to new: String) {
        guard old != new else { return }
        for i in entries.indices where entries[i].author == old {
            entries[i].author = new
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private static func key(for work: Work) -> String {
        switch work {
        case let .plate(post, _, _):  return "plate:\(post)"
        case let .ballot(post, _, _): return "ballot:\(post)"
        case let .note(_, _, id):     return "note:\(id)"
        }
    }

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
