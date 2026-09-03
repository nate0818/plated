import Foundation
import SwiftData

/// Plating a dish and voting in a poll, in one place.
///
/// Both used to be written twice — once in `TableFeedView.togglePlate` and
/// once again in `PlateReactionButton`, with a third copy in `DiscoverView`
/// — and the copies had already drifted: only one of them notified, none of
/// them agreed about the haptic, and the notification the drifted copy sent
/// went into the local context so it reached nobody.
///
/// Every reaction takes the same road now: the ledger records it, the outbox
/// queues it, and the drain puts it on the table when there is a table to
/// put it on. Recording before sending is the honest order — DESIGN.md's
/// rule is that state is recorded, never asserted, and a reaction is a thing
/// that happened on this phone whether or not the network agrees yet.
@MainActor
enum TableReactions {

    /// Turn a plate on or off. Returns the state it landed in.
    @discardableResult
    static func togglePlate(_ post: TablePost) -> Bool {
        let me = TableIdentity.cached
        let now = !TableLedger.shared.platedByMe(post.shareRecordName, me: me)
        TableLedger.shared.setPlate(post.shareRecordName, author: me, active: now)
        TableOutbox.shared.enqueue(
            .plate(post: post.shareRecordName, zoneOwner: post.shareZoneOwner, active: now),
            author: me
        )
        return now
    }

    /// Cast, change or withdraw a vote. Passing the option already chosen
    /// withdraws it, which is how the poll behaved before and is the only
    /// way to un-vote without a second control.
    static func vote(_ post: TablePost, option: Int) {
        let me = TableIdentity.cached
        let current = TableLedger.shared.myVote(post.shareRecordName, me: me)
        let choice = current == option ? -1 : option
        TableLedger.shared.setBallot(post.shareRecordName, author: me, choice: choice)
        TableOutbox.shared.enqueue(
            .ballot(post: post.shareRecordName, zoneOwner: post.shareZoneOwner, choice: choice),
            author: me
        )
    }

    /// Seed the ledger from the fields that used to hold this.
    ///
    /// Runs once. `platedByMe` and `myPollChoice` were real answers a person
    /// gave, and losing them because the storage moved would be the app
    /// forgetting something it was told. `plateCount` and `pollCounts` are
    /// deliberately NOT carried across: they were only ever written by
    /// SampleData, so on a real device they are zero, and on a seeded one
    /// they are fiction about people who never tapped anything.
    static func backfill(_ posts: [TablePost], context: ModelContext) {
        let flag = "plated.ledgerBackfilled"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        let me = TableIdentity.cached
        for post in posts {
            // Every post that existed before this version was published the
            // moment it was written, or never; a non-empty name means it got
            // out. New posts mint a name at birth and set this themselves.
            if !post.isPublished, !post.shareRecordName.isEmpty {
                post.isPublished = true
            }
            if post.platedByMe {
                TableLedger.shared.setPlate(post.shareRecordName, author: me,
                                            active: true, at: post.createdAt)
            }
            if post.myPollChoice >= 0 {
                TableLedger.shared.setBallot(post.shareRecordName, author: me,
                                             choice: post.myPollChoice, at: post.createdAt)
            }
        }
        UserDefaults.standard.set(true, forKey: flag)
        Persist.save(context, "ledger backfill")
    }
}
