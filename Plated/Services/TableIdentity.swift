import Foundation
import SwiftData
#if canImport(CloudKit)
import CloudKit
#endif

/// This user, in CloudKit's terms.
///
/// The first stable identity the app has ever had for a person. Everything
/// today keys on first names: `isMine`, `seatCount`, `members.photo(forAuthor:)`,
/// `PersonRef.author`. Two people called Sam break the app in about six
/// places, and the code already carries comments admitting it. A record name
/// is the thing that does not collide, does not change when somebody edits
/// their profile, and is the same string on every one of that person's
/// devices.
///
/// Stored in the app group beside the change tokens rather than in
/// `UserDefaults.standard`: one home for sync state, so nothing has to
/// remember which half lives where.
enum TableIdentity {
    private static let key = "plated.userRecordName"

    private static var store: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    /// The cached id, or a persisted local placeholder.
    ///
    /// Synchronous on purpose. A SwiftUI body cannot await, and a plate
    /// tapped on a plane still has to be attributed to somebody — the write
    /// goes into the outbox under this id and is re-stamped when CloudKit
    /// finally answers.
    static var cached: String {
        if let existing = store.string(forKey: key), !existing.isEmpty { return existing }
        let placeholder = "local-\(UUID().uuidString)"
        store.set(placeholder, forKey: key)
        return placeholder
    }

    static var isPlaceholder: Bool { cached.hasPrefix("local-") }

    /// Every app-group fact about which household this phone is in. The
    /// two the model reads are named on `HouseholdMember.Keys`; the rest
    /// are `HouseholdShare.Keys`, spelled through that enum so a key the
    /// wire adds shows up here as a compile error rather than as a changed
    /// Apple ID inheriting the previous one's household. The minter is the
    /// one key only the sync glue writes.
    private static let householdKeys: [String] = [
        HouseholdMember.Keys.membershipKind,
        HouseholdMember.Keys.mySeat,
        HouseholdShare.Keys.owner,
        HouseholdShare.Keys.ownerName,
        HouseholdShare.Keys.name,
        HouseholdShare.Keys.epoch,
        HouseholdShare.Keys.publishedAt,
        HouseholdShare.Keys.removedIDs,
        HouseholdShare.Keys.tableShareURL,
        HouseholdShare.Keys.autoRotate,
        HouseholdShare.Keys.lastSyncedName,
        HouseholdShare.Keys.unresolved,
        HouseholdShare.Keys.sharedDatabaseToken,
        HouseholdOutbox.publishTotalKey,
        "plated.household.minter",
    ]

    /// Ask CloudKit who this is, and remember.
    ///
    /// Returns nil when it could not ask. It never re-derives a placeholder
    /// while offline: minting a fresh `local-` id on an offline launch would
    /// orphan everything already queued under the previous one.
    @discardableResult
    static func confirm() async -> String? {
        #if canImport(CloudKit)
        guard let id = try? await CKContainer.default().userRecordID() else { return nil }
        let name = id.recordName
        guard !name.isEmpty else { return nil }
        if store.string(forKey: key) != name {
            store.set(name, forKey: key)
        }
        return name
        #else
        return nil
        #endif
    }

    /// Ask CloudKit who this is, and move everything a placeholder signed
    /// onto the answer.
    ///
    /// One door, because there were three hand-copied ones and they had
    /// already drifted. The launch pass called `confirm()` alone and threw
    /// the answer away, which wrote the real id over the placeholder with
    /// nobody told: every later `real != before` was then false, so the
    /// `local-` ids stayed on the rows forever, the outbox stopped holding
    /// them and pushed a stranger's name to the household, and Leave
    /// deleted the person's own recipes as somebody else's.
    ///
    /// Every book that stamps an author has to be listed here. Two call
    /// sites confirm identity, the share absorb and the Table's first look,
    /// and for a while only one of them carried the plan: whichever ran
    /// first spent the placeholder, so the second saw no change and the
    /// nights kept a stranger's name. `reset()` below already lists the
    /// books in one place; this is the same list for the same reason.
    ///
    /// A real id becoming a different real id is not a confirmation, it is
    /// a different Apple ID. Claiming that account's rows would drain them
    /// into this one's zone, which is the exact failure `reset` exists to
    /// prevent, so that road resets instead.
    @MainActor
    @discardableResult
    static func confirmAndReattribute(in context: ModelContext) async -> String? {
        let before = cached
        guard let real = await confirm() else { return nil }
        guard real != before else { return real }
        if before.hasPrefix("local-") {
            TableLedger.shared.reattribute(from: before, to: real)
            TableOutbox.shared.reattribute(from: before, to: real)
            PlanLedger.shared.reattribute(from: before, to: real)
            HouseholdSync.reattribute(from: before, to: real, in: context)
        } else {
            reset()
        }
        return real
    }

    /// The Apple ID changed underneath us.
    ///
    /// Without this, `cached` keeps answering with the previous account's
    /// id: the outbox drains writes minted under the old identity into the
    /// new account's zone, and plates are attributed to a stranger. The
    /// change tokens go too, because they describe a zone this account has
    /// never read.
    @MainActor
    /// `becoming` is the id CloudKit has just confirmed for the NEW account,
    /// when the caller has one.
    ///
    /// Without it this cleared the key that `confirm()` had stored seconds
    /// earlier, so the phone came out of an Apple ID change running on a
    /// fresh `local-` placeholder. `PlanShare` refuses to publish under a
    /// placeholder, deliberately, so the new account's week went nowhere at
    /// all until some later confirm happened to run. The books belong to the
    /// old account and go; the answer to "who am I" was just established and
    /// does not.
    static func reset(becoming newIdentity: String? = nil) {
        store.removeObject(forKey: key)
        TableOutbox.shared.clear()
        TableLedger.shared.clear()
        // The plan too: the ledger's nights and the household it drew
        // belong to the old account, and the book names records in a zone
        // this account cannot see. The next pass republishes from nothing.
        PlanLedger.shared.clear()
        PlanShare.forgetBook()
        // The household books and its membership describe a household the
        // previous account was in. Left behind, the outbox would push that
        // account's rows into this one's zone and `me` would answer with a
        // seat this person never claimed.
        HouseholdOutbox.shared.clear()
        GroceryMarks.shared.clear()
        TableInvites.shared.clear()
        // These name nights in a household this account is not in. Drained
        // under the new identity they would take meals off a plan that has
        // nothing to do with the household that removed them.
        RemovedNights.clear()
        HouseholdEdits.clear()
        for k in householdKeys {
            store.removeObject(forKey: k)
        }
        print("PLATED HOUSEHOLD: identity reset, household and plan books and membership cleared")
        for k in store.dictionaryRepresentation().keys
        where k.hasPrefix("plated.zonetoken.") {
            store.removeObject(forKey: k)
        }
        for k in UserDefaults.standard.dictionaryRepresentation().keys
        where k.hasPrefix("plated.zonetoken.") {
            UserDefaults.standard.removeObject(forKey: k)
        }
        // Last, so nothing above can clear it again.
        if let newIdentity, !newIdentity.isEmpty, !newIdentity.hasPrefix("local-") {
            store.set(newIdentity, forKey: key)
        }
    }
}
