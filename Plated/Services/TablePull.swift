import Foundation

/// One pull at a time.
///
/// `TableShare.fetchChanges` ran from four places at once: the push
/// delegate, the feed's refresh, the share-accepted handler and a tapped
/// notice, each starting from the same stored change token. The loser could
/// store an older token over the winner's, or forget the zone's token after
/// the winner had stored a good one and force a full replay next time; and
/// two overlapping `absorb`s of one delta could raise the same banner twice,
/// because each remembers its keys only after it has shown them.
///
/// So every road goes through here. A pull that arrives while one is in
/// flight joins it and runs once more after, which is the right shape for a
/// push that lands mid-refresh: the second pass picks up what the first
/// fetch was too early for.
@MainActor
enum TablePull {
    private static var inFlight: Task<Void, Never>?
    private static var again = false
    private static var lastPull: Date?

    /// Foreground pulls are throttled: `.active` fires after every
    /// permission sheet and every tab flip, and a table does not change
    /// that often.
    private static let foregroundGap: TimeInterval = 60

    static func pull(reason: String) async {
        if reason == "foreground", let last = lastPull,
           Date.now.timeIntervalSince(last) < foregroundGap {
            return
        }
        if let running = inFlight {
            again = true
            print("[Pull] \(reason) joined an in-flight pull")
            await running.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                again = false
                let changes = await TableShare.fetchChanges()
                await ShareAcceptor.absorb(changes)
                lastPull = .now
                print("[Pull] \(reason): \(changes.posts.count) posts, \(changes.notes.count) notes, \(changes.reactions.count) reactions\(changes.sharesChanged ? ", seats" : "")")
            } while again
        }
        inFlight = task
        await task.value
        if inFlight == task { inFlight = nil }
    }
}
