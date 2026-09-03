import Foundation
import Observation

/// Plates and ballots. Deliberately **not** SwiftData.
///
/// This state has exactly one authority — the shared CloudKit zone — and the
/// share already replicates it to every one of this person's devices. Putting
/// it in a `@Model` would add the SwiftData mirror as a SECOND writer to the
/// same fact, with its own clock and last-writer-wins per property. Two
/// devices mid-propagation then ping-pong: A has folded three plate records
/// and writes 3, B has folded five and writes 5, A imports 5 and recomputes 3
/// from its own set, writes 3. The `platedByMe` variant of that makes a
/// person's own plate flicker on and off in front of them.
///
/// Keeping it out of the schema also means `PlatedStore.schema` does not
/// change at all: no new mirrored type, `probeUserData`'s table list stays
/// valid, and the store migration CLAUDE.md calls precious is not touched or
/// even approached.
///
/// Counters cannot merge; sets can. `TablePost.plateCount` is an Int, and an
/// integer incremented on two devices is a lost update with no way to detect
/// it. One entry per person per post is idempotent under replay and
/// commutative under reordering, so there is no conflict left to resolve.
@MainActor
@Observable
final class TableLedger {
    static let shared = TableLedger()

    struct Plate: Codable, Equatable {
        var active: Bool
        var at: Date
    }

    struct Ballot: Codable, Equatable {
        var choice: Int
        var at: Date
    }

    private struct Book: Codable {
        /// post record name -> author id -> plate
        var plates: [String: [String: Plate]] = [:]
        var ballots: [String: [String: Ballot]] = [:]
    }

    private var book = Book()

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID)?
            .appending(path: "table-ledger.json")
    }

    private init() { load() }

    // MARK: Reading
    //
    // Synchronous, and touching `book` inside a SwiftUI body registers with
    // Observation, so the feed invalidates the moment a fold lands.

    /// How many people have plated this, me included.
    ///
    /// Mine counts whether or not it has reached anybody else yet: it is a
    /// thing that happened, and the honest report of it is "one person
    /// plated this, and it was you".
    func plateCount(_ post: String, me: String) -> Int {
        (book.plates[post] ?? [:]).values.filter(\.active).count
    }

    func platedByMe(_ post: String, me: String) -> Bool {
        book.plates[post]?[me]?.active ?? false
    }

    /// Who plated it, so the bell can name them instead of counting them.
    func platers(_ post: String) -> [String] {
        (book.plates[post] ?? [:]).filter { $0.value.active }.map(\.key)
    }

    func myVote(_ post: String, me: String) -> Int {
        book.ballots[post]?[me]?.choice ?? -1
    }

    /// Votes per option index, sized to the poll it belongs to.
    func votes(_ post: String, options: Int) -> [Int] {
        var tally = [Int](repeating: 0, count: max(options, 0))
        for ballot in (book.ballots[post] ?? [:]).values {
            guard ballot.choice >= 0, ballot.choice < tally.count else { continue }
            tally[ballot.choice] += 1
        }
        return tally
    }

    func totalVotes(_ post: String) -> Int {
        (book.ballots[post] ?? [:]).values.filter { $0.choice >= 0 }.count
    }

    // MARK: Writing
    //
    // Last-writer-wins on `at`, which is total and identical on every
    // device. A fold from the wire that is older than what we hold is
    // dropped rather than applied, so a slow page cannot undo a newer tap.

    @discardableResult
    func setPlate(_ post: String, author: String, active: Bool, at: Date = .now) -> Bool {
        if let existing = book.plates[post]?[author], existing.at > at { return false }
        book.plates[post, default: [:]][author] = Plate(active: active, at: at)
        save()
        return true
    }

    @discardableResult
    func setBallot(_ post: String, author: String, choice: Int, at: Date = .now) -> Bool {
        if let existing = book.ballots[post]?[author], existing.at > at { return false }
        book.ballots[post, default: [:]][author] = Ballot(choice: choice, at: at)
        save()
        return true
    }

    /// The post is gone, so its reactions are too. Nothing on the wire tells
    /// us this: a cascade delete removes the child records, and the fold that
    /// would have noticed never runs because the post is not there to fold
    /// against.
    func forget(post: String) {
        book.plates[post] = nil
        book.ballots[post] = nil
        save()
    }

    /// A placeholder identity became a real one. Everything written while
    /// offline was attributed to `local-…`; it is the same person.
    func reattribute(from old: String, to new: String) {
        guard old != new else { return }
        for (post, byAuthor) in book.plates where byAuthor[old] != nil {
            book.plates[post]?[new] = byAuthor[old]
            book.plates[post]?[old] = nil
        }
        for (post, byAuthor) in book.ballots where byAuthor[old] != nil {
            book.ballots[post]?[new] = byAuthor[old]
            book.ballots[post]?[old] = nil
        }
        save()
    }

    func clear() {
        book = Book()
        save()
    }

    // MARK: Disk

    private func load() {
        guard let url = Self.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Book.self, from: data) else { return }
        book = decoded
    }

    private func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(book) else { return }
        // Atomic: a force-quit mid-tap must not leave a half-written book,
        // which would decode as nothing and silently drop every plate at
        // the table.
        try? data.write(to: url, options: .atomic)
    }
}
