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
    /// One short-lived sender for a burst of plate / ballot taps.
    ///
    /// Reactions used to sit in the durable queue until an unrelated pull
    /// happened. The queue remains the source of truth, but a tap now also
    /// wakes a coalesced sender so the other seats see it promptly. Notes are
    /// deliberately excluded: resolving one requires a ModelContext-owned
    /// row, and treating a missing resolver as a deleted note loses words.
    private var reactionDrainTask: Task<Void, Never>?
    private var reactionDrainRequested = false
    private var reactionAuthorName = ""

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
    @discardableResult
    func enqueue(_ work: Work, author: String, at: Date = .now) -> Entry {
        let key = Self.key(for: work)
        entries.removeAll { Self.key(for: $0.work) == key }
        let entry = Entry(id: key, work: work, author: author, at: at)
        entries.append(entry)
        save()
        return entry
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// This attempt failed. Kept, so it goes out on the next pull.
    func failed(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        recordFailure(at: i)
    }

    /// Settle exactly the entry that was sent, never merely the entry with
    /// the same key.
    ///
    /// A plate, un-plate and plate again all share one key. While the first
    /// write is awaiting CloudKit, a later tap replaces its queue row. The
    /// old completion must not remove or penalize that newer intent.
    func finish(_ sent: Entry, succeeded: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == sent.id }),
              entries[i] == sent else { return }
        if succeeded {
            entries.remove(at: i)
            save()
        } else {
            recordFailure(at: i)
        }
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
        reactionDrainRequested = false
        reactionAuthorName = ""
        entries = []
        save()
    }

    /// Wake a single sender for a burst of reaction changes.
    ///
    /// The 140 ms window collapses a quick correction into the final state.
    /// If another tap lands while CloudKit is answering, the loop makes one
    /// more pass. Failures remain in the on-disk queue for the normal pull
    /// drain; this is an eager attempt, never an alternate source of truth.
    func kickReactionDrain(authorName: String) {
        let name = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        reactionAuthorName = name
        reactionDrainRequested = true
        guard reactionDrainTask == nil else { return }

        reactionDrainTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                self?.reactionDrainTask = nil
                return
            }
            guard let self else { return }
            while self.reactionDrainRequested {
                self.reactionDrainRequested = false
                await self.drainReactions(authorName: self.reactionAuthorName)
            }
            self.reactionDrainTask = nil
        }
    }

    /// Put everything queued on the table.
    ///
    /// Ordered oldest first, and an entry is only removed once the write is
    /// confirmed. A refusal keeps it, so it goes out on the next pull rather
    /// than vanishing — the whole point of a queue is that "later" is a real
    /// answer and "never, silently" is not.
    ///
    /// Entries minted under a placeholder identity are held back rather than
    /// sent: a plate attributed to `local-<uuid>` would arrive at the table
    /// as a stranger, and the re-attribution that fixes it happens the
    /// moment CloudKit answers who this is.
    /// Finds a queued comment again by its wire name. Set by the view that
    /// owns a ModelContext; the outbox has none and should not.
    var resolveNote: ((String) -> TableComment?)?

    func drain(authorName: String) async {
        let work = entries.sorted { $0.at < $1.at }
        for entry in work {
            guard !entry.author.hasPrefix("local-") else { continue }
            let ok: Bool
            switch entry.work {
            case let .plate(post, owner, active):
                ok = await TableShare.pushPlate(
                    post: post, zoneOwner: owner, author: entry.author,
                    authorName: authorName, active: active, at: entry.at
                )
            case let .ballot(post, owner, choice):
                ok = await TableShare.pushBallot(
                    post: post, zoneOwner: owner, author: entry.author,
                    authorName: authorName, choice: choice, at: entry.at
                )
            case let .note(post, owner, id):
                // The comment row is the payload, so it has to be found
                // again rather than carried in the queue: a queue that holds
                // a copy of the text is a second place for the text to be
                // wrong.
                guard let resolveNote else {
                    // No ModelContext was installed, so nil cannot tell us
                    // "the row was deleted". Hold the durable entry until a
                    // normal pull supplies a resolver.
                    continue
                }
                if let comment = resolveNote(id) {
                    ok = await TableShare.pushNote(comment, post: post, zoneOwner: owner)
                } else {
                    // Deleted before it ever went out. Nothing to send, and
                    // that is a success rather than a failure to retry.
                    ok = true
                }
            }
            finish(entry, succeeded: ok)
        }
    }

    /// Eagerly send only work whose complete payload is in the outbox.
    /// Notes point at SwiftData instead and wait for `drain`, whose caller
    /// installs `resolveNote` first.
    private func drainReactions(authorName: String) async {
        let work = entries.sorted { $0.at < $1.at }.filter { entry in
            switch entry.work {
            case .plate, .ballot: return true
            case .note: return false
            }
        }
        for entry in work {
            guard !entry.author.hasPrefix("local-") else { continue }
            let ok: Bool
            switch entry.work {
            case let .plate(post, owner, active):
                ok = await TableShare.pushPlate(
                    post: post, zoneOwner: owner, author: entry.author,
                    authorName: authorName, active: active, at: entry.at
                )
            case let .ballot(post, owner, choice):
                ok = await TableShare.pushBallot(
                    post: post, zoneOwner: owner, author: entry.author,
                    authorName: authorName, choice: choice, at: entry.at
                )
            case .note:
                continue
            }
            finish(entry, succeeded: ok)
        }
    }

    private func recordFailure(at index: Int) {
        entries[index].tries += 1
        // Twenty refusals is not a network blip, it is a write that will
        // never land — a post deleted at the far end, most likely. Dropping
        // it is honest; retrying forever is a queue that never drains and a
        // battery that never rests.
        if entries[index].tries > 20 { entries.remove(at: index) }
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
