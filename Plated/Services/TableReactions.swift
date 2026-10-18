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
    static func togglePlate(
        _ post: TablePost,
        context: ModelContext? = nil,
        authorName: String? = nil
    ) -> Bool {
        let me = TableIdentity.cached
        let now = !TableLedger.shared.platedByMe(post.shareRecordName, me: me)
        let at = Date.now
        TableLedger.shared.setPlate(post.shareRecordName, author: me, active: now, at: at)
        // A post composed moments ago may still be live only in its context.
        // Put it on disk before a reaction referring to its record name can
        // enter the durable queue or leave the device.
        Persist.save(context ?? PlatedStore.shared.mainContext, "plate reaction")
        TableOutbox.shared.enqueue(
            .plate(post: post.shareRecordName, zoneOwner: post.shareZoneOwner, active: now),
            author: me,
            at: at
        )
        TableOutbox.shared.kickReactionDrain(authorName: resolvedName(authorName))
        return now
    }

    /// Comments use the deployed binary reaction wire format. A note's stable
    /// record name is the target, so its likes cannot change its post's plates.
    /// `postRef` then cascades from the note; the share parent remains table-root.
    @discardableResult
    static func toggleLike(
        _ comment: TableComment,
        context: ModelContext,
        authorName: String? = nil
    ) -> Bool {
        guard comment.deletedAt == nil, !comment.shareRecordName.isEmpty,
              let post = comment.post else { return false }
        guard Persist.save(context, "comment before reaction") else { return comment.likedByMeNow }
        let me = TableIdentity.cached
        let active = !comment.likedByMeNow
        let at = Date.now
        TableLedger.shared.setPlate(comment.shareRecordName, author: me, active: active, at: at)
        // Review fixtures must never become writes to a real shared zone.
        guard !PlatedApp.usesPreviewContainer else { return active }
        TableOutbox.shared.enqueue(
            .plate(post: comment.shareRecordName, zoneOwner: post.shareZoneOwner, active: active),
            author: me, at: at
        )
        TableOutbox.shared.kickReactionDrain(authorName: resolvedName(authorName))
        return active
    }

    static func forgetComments(_ records: Set<String>) {
        for record in records {
            TableLedger.shared.forget(post: record)
            TableOutbox.shared.remove("plate:\(record)")
        }
    }

    /// Cast, change or withdraw a vote. Passing the option already chosen
    /// withdraws it, which is how the poll behaved before and is the only
    /// way to un-vote without a second control.
    static func vote(
        _ post: TablePost,
        option: Int,
        context: ModelContext? = nil,
        authorName: String? = nil
    ) {
        let me = TableIdentity.cached
        let current = TableLedger.shared.myVote(post.shareRecordName, me: me)
        let choice = current == option ? -1 : option
        let at = Date.now
        TableLedger.shared.setBallot(post.shareRecordName, author: me, choice: choice, at: at)
        Persist.save(context ?? PlatedStore.shared.mainContext, "poll reaction")
        TableOutbox.shared.enqueue(
            .ballot(post: post.shareRecordName, zoneOwner: post.shareZoneOwner, choice: choice),
            author: me,
            at: at
        )
        TableOutbox.shared.kickReactionDrain(authorName: resolvedName(authorName))
    }

    private static func resolvedName(_ explicit: String?) -> String {
        let named = explicit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !named.isEmpty { return named }
        return (UserDefaults.standard.string(forKey: "userFirstName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

/// Ownership rules for destructive Table actions.
///
/// CloudKit identity is authoritative whenever the row carries one. A name
/// is only migration glue for an unstamped row that this device can still
/// establish lives on its own table. This keeps two people named Sam from
/// inheriting one another's Delete menu while preserving pre-identity local
/// posts and comments.
enum TableMutationAuthorization {
    static func owns(
        post: TablePost,
        identityIDs: [String],
        displayNames: [String]
    ) -> Bool {
        let ids = Set(identityIDs.filter { !$0.isEmpty })
        if !post.authorID.isEmpty { return ids.contains(post.authorID) }
        guard isLegacyLocal(post) else { return false }
        return legacyNameMatches(post.authorName, firstName: post.firstName, names: displayNames)
    }

    /// Your own comment, or any comment on a post you own.
    static func canDelete(
        comment: TableComment,
        on post: TablePost,
        identityIDs: [String],
        displayNames: [String]
    ) -> Bool {
        if owns(post: post, identityIDs: identityIDs, displayNames: displayNames) {
            return true
        }

        let ids = Set(identityIDs.filter { !$0.isEmpty })
        if !comment.authorID.isEmpty { return ids.contains(comment.authorID) }

        // An unstamped note on somebody else's/shared-zone post cannot be
        // proven local. Withhold Delete rather than authorize by a colliding
        // display name. On a genuinely local legacy post, name fallback is
        // the only ownership fact old builds left behind.
        guard post.authorID.isEmpty, isLegacyLocal(post) else { return false }
        return legacyNameMatches(comment.authorName, firstName: nil, names: displayNames)
    }

    private static func isLegacyLocal(_ post: TablePost) -> Bool {
        !post.isRemote && post.shareZoneOwner.isEmpty
    }

    private static func legacyNameMatches(
        _ fullName: String,
        firstName: String?,
        names: [String]
    ) -> Bool {
        let mine = Set(names.map(normalized).filter { !$0.isEmpty })
        guard !mine.isEmpty else { return false }
        if mine.contains(normalized(fullName)) { return true }
        if let firstName, mine.contains(normalized(firstName)) { return true }
        return false
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
