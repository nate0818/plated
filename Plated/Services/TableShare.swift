import Foundation
import CloudKit
import UIKit
import SwiftData

/// Real seats at a real table: CloudKit sharing for `TablePost`, and for
/// nothing else.
///
/// **Why this exists at all.** SwiftData mirrors only the PRIVATE CloudKit
/// database — it has no CKShare, no shared database, no public database, and
/// that is still true on iOS 26. So the Table, the one thing in Plated that
/// must cross households, cannot ride the mirror that carries everything
/// else. The alternative was migrating the whole store to Core Data to gain
/// sharing on a single entity, which would have put every working, debugged
/// model in the app at risk for one feature. This layer is the narrower
/// trade: recipes, weeks, grocery and household stay exactly where they are,
/// and only posts learn to travel.
///
/// **The shape.** The host owns one custom zone holding one root record; a
/// CKShare on that root is the invitation. Guests accept the share, which
/// puts that zone in their shared database, and both sides read and write
/// posts as children of the root. One zone per table, so a guest leaving is
/// a participant removal rather than a data migration.
///
/// Everything here is best-effort and non-throwing at the edges. A table
/// that cannot reach CloudKit is a local table, which is a state Plated has
/// always supported and must never treat as an error.
enum TableShare {

    static let zoneName = "PlatedTable"
    private static let rootType = "Table"
    /// The record type a shared dish is written as. Deliberately NOT
    /// "TablePost", and the difference is load-bearing.
    ///
    /// The SwiftData mirror syncs the same private database this zone
    /// lives in, walks every zone it finds there, and adopts any record
    /// whose type matches one of its own entity names. A record typed
    /// "TablePost" therefore came back through the mirror as a TablePost
    /// row with every field at its default — no author, no dish, no photo
    /// — because the mirror reads `CD_`-prefixed fields and this record
    /// carries none. That was the blank card in the feed. The root record
    /// was never adopted for exactly the reason this rename works: no
    /// entity is called "Table". The collision was the entity name, not
    /// the zone.
    private static let postType = "PlatedDish"
    /// What `postType` used to be. Read, never written — tables shared
    /// before the rename still carry it, and their dishes are real.
    private static let legacyPostType = "TablePost"
    /// Reactions, in the same reserved namespace as `PlatedDish`.
    ///
    /// The prefix is load-bearing, not decorative. The SwiftData mirror
    /// adopts any private-database record whose type matches one of its
    /// entity names — that is the ghost post in MEMORY.md, where blank cards
    /// appeared in the feed — so a hand-written type may never be named
    /// after a @Model. `assertNoEntityCollision` makes that a check rather
    /// than a thing somebody has to remember.
    private static let plateType = "PlatedDishPlate"
    private static let ballotType = "PlatedDishBallot"
    private static let noteType = "PlatedDishNote"
    /// The household's own zone, minted and shared by the household invite
    /// (docs/household.md): roster, plan, recipes. The plan record below
    /// lives here, never under the Table share, because a Table guest must
    /// not be able to read the week. See docs/plan-share.md.
    static let householdZoneName = "PlatedHousehold"
    static let householdRootName = "household-root"
    static let householdRootType = "PlatedHousehold"
    /// A night on the plan, `plan-<shoppingID>`, in the household zone.
    static let planType = "PlatedHouseholdPlan"
    /// Written by the household invite on join and on the head's first
    /// mint, read here as the one answer to "which household is this
    /// phone in": "" for the head's own zone, the host's user record name
    /// for a member, absent for none. App-group suite.
    static let householdOwnerKey = "plated.household.owner"

    #if DEBUG
    /// The ghost post, made unrepeatable.
    ///
    /// `legacyPostType` is deliberately excluded: "TablePost" IS the
    /// collision, it is read-only, and asserting on it would fire on the one
    /// type that can never be renamed. The reserved prefix closes the class
    /// going forward, not retroactively.
    static func assertNoEntityCollision() {
        let entities = Set(PlatedStore.schema.entities.map(\.name))
        let written: Set<String> = [rootType, postType, plateType, ballotType, noteType, householdRootType, planType]
        let clash = entities.intersection(written)
        assert(clash.isEmpty, "CloudKit types collide with SwiftData entities: \(clash)")
    }
    #endif

    /// CloudKit has no boolean type. A Bool field is stored as an INT64 and
    /// `record[key] as? Bool` is a bridging coin flip.
    static func int(_ record: CKRecord, _ key: String) -> Int {
        if let n = record[key] as? Int { return n }
        if let n = record[key] as? Int64 { return Int(n) }
        if let n = record[key] as? NSNumber { return n.intValue }
        return 0
    }

    // MARK: Which zone is the household's

    /// Three states, never a guess. `unresolved` carries the candidates,
    /// "" for this phone's own table, so Settings can offer the choice.
    enum Choice: Equatable {
        case none
        case unresolved([String])
        case resolved(String)
    }

    /// The candidate rules from docs/plan-share.md, pure so a test can hold
    /// them. A zone never counts because it exists: onboarding mints a
    /// private table for nearly everyone, so the own zone is a candidate
    /// only when somebody has actually accepted its share.
    ///
    /// `me` is this phone's own record name. The mutual-invite tie-break
    /// compares owner ids, and the own zone is "" here but my real id on
    /// every other phone, so the comparison has to use the real one or two
    /// partners who invited each other would each pick their own table.
    static func chooseHousehold(
        ownShareAccepted: Bool,
        ownAcceptedParticipantIDs: Set<String>,
        joinedOwners: [String],
        stored: String?,
        me: String
    ) -> Choice {
        var candidates: [String] = ownShareAccepted ? [""] : []
        for owner in joinedOwners where !owner.isEmpty && !candidates.contains(owner) {
            candidates.append(owner)
        }
        guard !candidates.isEmpty else { return .none }
        if candidates.count == 1 { return .resolved(candidates[0]) }
        if let stored, candidates.contains(stored) { return .resolved(stored) }
        // Two partners who invited each other: every joined table's owner
        // sits accepted at my own, so both phones hold the same pair and
        // the smallest id is the same answer on each.
        let joined = candidates.filter { !$0.isEmpty }
        if ownShareAccepted, !me.isEmpty,
           joined.allSatisfy({ ownAcceptedParticipantIDs.contains($0) }) {
            let smallest = (joined + [me]).min() ?? me
            return .resolved(smallest == me ? "" : smallest)
        }
        return .unresolved(candidates)
    }

    #if PLATED_CLOUDKIT
    private static var container: CKContainer { .default() }

    // MARK: The host's share

    /// The invitation URL, creating the zone, the root and the share the
    /// first time it is asked for. Nil whenever CloudKit can't help, which
    /// the caller shows as "your table is local for now" rather than an error.
    static func invitationURL(hostName: String) async -> URL? {
        guard await TableSync.accountAvailable() else { return nil }
        do {
            let db = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            // Creating a zone that exists is not an error worth surfacing;
            // CloudKit returns the existing one.
            _ = try? await db.save(CKRecordZone(zoneID: zoneID))

            let rootID = CKRecord.ID(recordName: "table-root", zoneID: zoneID)
            let root: CKRecord
            if let existing = try? await db.record(for: rootID) {
                root = existing
            } else {
                root = CKRecord(recordType: rootType, recordID: rootID)
            }
            let tableTitle: String = hostName.isEmpty ? "Our table" : "\(hostName)'s table"
            root["title"] = tableTitle as CKRecordValue

            // An existing share is reused: minting a second one would
            // silently invalidate the link already sitting in somebody's
            // messages.
            if let ref = root.share,
               let existing = try? await db.record(for: ref.recordID) as? CKShare,
               let url = existing.url {
                // A table minted before the mark existed still carries the
                // generic iCloud card on every link it has ever sent. Fill
                // it in once, here, rather than only on brand-new shares.
                if existing[CKShare.SystemFieldKey.thumbnailImageData] == nil,
                   let icon = shareThumbnail() {
                    existing[CKShare.SystemFieldKey.title] = tableTitle as CKRecordValue
                    existing[CKShare.SystemFieldKey.thumbnailImageData] = icon as CKRecordValue
                    _ = try? await db.modifyRecords(saving: [existing], deleting: [])
                }
                return url
            }

            let share = CKShare(rootRecord: root)
            let shareTitle: String = "\(tableTitle) on Plated"
            share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
            // Messages renders an iCloud share link from the share's own
            // title and thumbnail. With no thumbnail it falls back to a
            // generic iCloud card, so a personal invitation to somebody's
            // dinner table arrived looking like a system file transfer.
            if let icon = shareThumbnail() {
                share[CKShare.SystemFieldKey.thumbnailImageData] = icon as CKRecordValue
            }
            // The link is the credential: whoever holds it can take a seat.
            //
            // This was `.none` — participant-only — which sounds safer and
            // in practice meant almost nobody could accept. A CloudKit
            // participant can only be looked up by the address on someone's
            // iCloud account, and the number in your Contacts for a person
            // is very often not that address. Every one of those invitations
            // failed. An unlisted link, sent by hand in a message the user
            // wrote, is the same trade Notes and Reminders make, and it is
            // the difference between an invite that works and one that
            // doesn't. Anyone we CAN resolve is still added as a
            // participant, which pre-authorises them.
            share.publicPermission = .readWrite

            // The URL is server-assigned, so it exists on the record that
            // comes BACK, never on the instance we sent. Returning
            // `share.url` here handed out nil for the first invitation
            // anybody ever sent from a table.
            let saved = try await db.modifyRecords(saving: [root, share], deleting: [])
            for (_, result) in saved.saveResults {
                if case .success(let record) = result, let share = record as? CKShare {
                    return share.url
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    /// The app's own mark, small enough to ride on a share record.
    ///
    /// Read from the bundled icon file rather than `UIImage(named:)`: an
    /// app icon is not a normal asset at runtime and often will not resolve
    /// by name, which would silently put us back on the iCloud card.
    private static func shareThumbnail() -> Data? {
        let names = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons")
            .flatMap { ($0 as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any] }
            .flatMap { $0["CFBundleIconFiles"] as? [String] } ?? []
        let candidates = names.reversed() + ["AppIcon60x60", "AppIcon"]
        for name in candidates {
            guard let image = UIImage(named: name) else { continue }
            // CloudKit keeps share metadata small; a 256pt mark is plenty
            // for a link preview and stays well inside the record limit.
            let side: CGFloat = 256
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            let scaled = renderer.image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            if let data = scaled.jpegData(compressionQuality: 0.9) { return data }
        }
        print("PLATED SHARE: no app icon found for the link preview")
        return nil
    }

    /// What happened when we tried to make a real seat for somebody.
    enum InviteOutcome {
        /// A link bound to them. Send it.
        case ready(URL)
        /// No iCloud account answers to that number or address, so a link
        /// sent there would not open the door.
        case noAccount
        /// No iCloud on this device at all, or CloudKit refused.
        case noCloud
    }

    /// Add one person to the table's share and hand back their link.
    ///
    /// This is the step that was missing entirely. The share is created
    /// with `publicPermission = .none` — correct, an invite-only table —
    /// but with no participants ever added, that share admits literally
    /// nobody. Every invitation the app had ever "sent" carried a link
    /// that could not have worked for the person holding it.
    static func invite(phone: String?, email: String?, hostName: String) async -> InviteOutcome {
        guard await TableSync.accountAvailable() else { return .noCloud }
        guard let url = await invitationURL(hostName: hostName),
              let share = await currentShare() else { return .noCloud }

        // Tables minted before the link became the credential are still
        // participant-only; open them so their links start working.
        if share.publicPermission != .readWrite {
            share.publicPermission = .readWrite
            _ = try? await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        }

        // Look them up by the address the invitation is going to. A number
        // that isn't the one on their iCloud account finds nobody, which is
        // a thing to say out loud rather than fail silently on.
        var identity: CKShare.Participant?
        if let phone, !phone.isEmpty {
            identity = try? await container.shareParticipant(forPhoneNumber: phone)
        }
        if identity == nil, let email, !email.isEmpty {
            identity = try? await container.shareParticipant(forEmailAddress: email)
        }
        // Not finding them is no longer fatal: the link works regardless,
        // and resolving them is a bonus that pre-authorises their seat.
        guard let participant = identity else {
            print("PLATED SHARE: no iCloud identity for that address — sending the open link")
            return .ready(url)
        }

        // Already on it — reuse rather than adding them twice.
        let known = share.participants.contains { existing in
            existing.userIdentity.lookupInfo?.phoneNumber == phone
                || existing.userIdentity.lookupInfo?.emailAddress == email
        }
        if known { return .ready(url) }

        participant.permission = .readWrite
        share.addParticipant(participant)
        do {
            _ = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
            return .ready(url)
        } catch {
            print("PLATED SHARE: could not add participant — \(error)")
            return .noCloud
        }
    }

    /// Undo `invite` when the message was never sent. A participant left on
    /// the share for a person who was never told is a door standing open
    /// for somebody who does not know it exists.
    static func revokeInvite(phone: String?, email: String?) async {
        guard let share = await currentShare() else { return }
        guard let victim = share.participants.first(where: { existing in
            (phone != nil && existing.userIdentity.lookupInfo?.phoneNumber == phone)
                || (email != nil && existing.userIdentity.lookupInfo?.emailAddress == email)
        }), victim.role != .owner else { return }
        share.removeParticipant(victim)
        _ = try? await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
    }

    /// Everyone on the share and how far along they are, keyed by the
    /// address they were invited at — the only thing a *pending*
    /// participant carries, since it has no user record until it accepts.
    struct Standing {
        var phone: String?
        var email: String?
        var name: String
        var accepted: Bool
        var participantID: String?
    }

    static func standings() async -> [Standing] {
        guard await TableSync.accountAvailable() else { return [] }
        guard let share = await currentShare() else { return [] }
        return share.participants.compactMap { p in
            guard p.role != .owner else { return nil }
            let name = [p.userIdentity.nameComponents?.givenName,
                        p.userIdentity.nameComponents?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            return Standing(
                phone: p.userIdentity.lookupInfo?.phoneNumber,
                email: p.userIdentity.lookupInfo?.emailAddress,
                name: name,
                accepted: p.acceptanceStatus == .accepted,
                participantID: p.userIdentity.userRecordID?.recordName
            )
        }
    }

    /// Read a share's metadata from its URL.
    ///
    /// The system does this for you when it routes an `icloud.com/share`
    /// link, but a link that arrives through our own domain is just a URL —
    /// so the metadata has to be fetched by hand before it can be accepted.
    static func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = false
            var found: CKShare.Metadata?
            operation.perShareMetadataResultBlock = { _, result in
                if case .success(let metadata) = result { found = metadata }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let found { continuation.resume(returning: found) }
                    else { continuation.resume(throwing: CKError(.unknownItem)) }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    /// Someone tapped an invitation. Accepting puts the host's zone into
    /// this user's shared database; the next refresh reads it.
    static func accept(_ metadata: CKShare.Metadata) async -> Bool {
        do {
            _ = try await container.accept(metadata)
            return true
        } catch {
            return false
        }
    }

    // MARK: Posts across the wire

    /// Publish one local post into the table's zone.
    ///
    /// Guests write into the shared database and hosts into their own
    /// private one — same zone, different database handle, which is the
    /// single thing that most often goes wrong in a CKShare implementation.
    static func publish(_ post: TablePost, hostName: String) async -> String? {
        guard await TableSync.accountAvailable() else { return nil }
        // A post that has already been published goes back to the table it
        // is on. Only a brand new one gets to ask where it should live.
        let target: (CKDatabase, CKRecordZone.ID, String)?
        if post.shareRecordName.isEmpty {
            target = await myWritableZone()
        } else if let (db, id) = await zone(ownedBy: post.shareZoneOwner) {
            target = (db, id, post.shareZoneOwner)
        } else {
            target = nil
        }
        guard let (db, zoneID, owner) = target else { return nil }
        await MainActor.run { post.shareZoneOwner = owner }
        do {
            let name = post.shareRecordName.isEmpty
                ? "post-\(UUID().uuidString)" : post.shareRecordName
            let record = CKRecord(
                recordType: postType,
                recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
            )
            record["authorName"] = post.authorName as CKRecordValue
            record["authorID"] = TableIdentity.cached as CKRecordValue
            // An ask's poll never crossed the wire at all, so a guest saw
            // the question with no answers under it and no way to vote —
            // "Ask the Table" reaching everybody except the table.
            //
            // Omitted rather than written empty: a CloudKit list field
            // minted from an empty array is minted as the WRONG TYPE and
            // stays that way, and every later save carrying a real list
            // then fails .invalidArguments. From a person's seat that looks
            // exactly like "my post just didn't appear".
            if !post.pollOptions.isEmpty {
                record["pollOptions"] = post.pollOptions as CKRecordValue
            }
            if !post.taggedNames.isEmpty {
                record["taggedNames"] = post.taggedNames as CKRecordValue
            }
            record["authorColorHex"] = post.authorColorHex as CKRecordValue
            record["dishTitle"] = post.dishTitle as CKRecordValue
            record["caption"] = post.caption as CKRecordValue
            record["kind"] = post.kind as CKRecordValue
            record["createdAt"] = post.createdAt as CKRecordValue
            record["parent"] = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: "table-root", zoneID: zoneID),
                action: .deleteSelf
            )
            // The share's root must be the parent, or the record is private
            // to its writer and no participant ever sees it.
            record.setParent(CKRecord.ID(recordName: "table-root", zoneID: zoneID))

            if let data = post.photoData, let asset = asset(from: data) {
                record["photo"] = asset
                defer { try? FileManager.default.removeItem(at: asset.fileURL!) }
                _ = try await db.save(record)
                return name
            }
            _ = try await db.save(record)
            return name
        } catch {
            return nil
        }
    }

    /// Take a post back off the table. The inverse of `publish`.
    ///
    /// **Deleting locally is not deleting.** `merge` keys on
    /// `shareRecordName`, so a row removed from this device while its record
    /// still sits in the zone comes back on the very next pull — and comes
    /// back as somebody ELSE's post, because the merge path that handles an
    /// unmatched record stamps `isRemote = true`. It arrives stripped of its
    /// plates and comments, attributed to "another table", and `isMine`
    /// refuses remote posts, so the overflow no longer offers Delete and the
    /// author can never remove it again. The confirmation said "The photo
    /// and comments go too" and meant it about this phone only.
    ///
    /// Returns false only when the record exists and could not be reached.
    /// A post that never published has an empty name and is already gone
    /// everywhere, which is a success, not a no-op.
    static func retract(recordName: String, zoneOwner: String) async -> Bool {
        guard !recordName.isEmpty else { return true }
        guard await TableSync.accountAvailable() else { return false }
        // The post's own table, not "wherever I write". Routed through the
        // old global answer, a host who had also joined a table deleted
        // into their OWN zone, got `.unknownItem` from a record that was
        // never there, and the catch below read that as "already gone" — so
        // the local row went and the next pull brought the post back as a
        // stranger's. That is the bug this function exists to fix, arriving
        // by a second road.
        guard let (db, zoneID) = await zone(ownedBy: zoneOwner) else { return false }
        do {
            _ = try await db.deleteRecord(
                withID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
            )
            return true
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone: deleted from another device, or it never landed.
            // Either way the caller's local delete is now honest.
            return true
        } catch {
            return false
        }
    }

    // MARK: Being told, instead of asking

    /// Subscribe to both databases so a change wakes the app.
    ///
    /// Without this the Table is a pull: Riley cooks, photographs it, posts
    /// it, and nobody's phone does anything until somebody else happens to
    /// open the app and drag down. Every craft improvement in the feed sits
    /// on top of that, and a social product where posting produces no event
    /// on anybody else's device is a diary several people can read.
    ///
    /// A DATABASE subscription rather than one per zone: a guest's zone
    /// appears only after they accept, and a per-zone subscription would
    /// have to be created at exactly that moment on exactly that device.
    /// One per database covers every table this person can see, now and
    /// later.
    ///
    /// `shouldSendContentAvailable` with no alert body is the silent kind.
    /// It asks for no permission, shows nothing, and simply gives the app a
    /// moment to fetch — which is right here, because the notification a
    /// person should see is the one the app decides to raise after it knows
    /// what actually arrived, not "something changed in a database".
    static func subscribe() async {
        for (db, id) in [(container.privateCloudDatabase, "plated-private-v1"),
                         (container.sharedCloudDatabase, "plated-shared-v1")] {
            // Already there is the common case, and CKError.serverRejectedRequest
            // is what a duplicate looks like. Asking every launch is cheap
            // and means a subscription lost to a signed-out account comes
            // back on its own.
            if (try? await db.subscription(for: id)) != nil { continue }
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try? await db.save(subscription)
        }
    }

    // MARK: Reactions on the wire

    /// One person's plate on one dish.
    ///
    /// The record name is **deterministic** — `plate-<post>-<author>` — and
    /// that is what makes the whole thing idempotent. A retry after a lost
    /// response overwrites itself rather than adding a second plate, and two
    /// devices of one person converge on one record instead of racing.
    ///
    /// Un-plating writes `active = 0`; it never deletes the record. A
    /// deletion arrives with no timestamp and no ordering against a
    /// concurrent write, so a delete-versus-write race has no defensible
    /// resolution. A tombstone does: last-writer-wins on `changedAt` is
    /// total, and identical on every device.
    static func pushPlate(
        post: String, zoneOwner: String, author: String, authorName: String,
        active: Bool, at: Date
    ) async -> Bool {
        await push(
            type: plateType, name: "plate-\(post)-\(author)",
            post: post, zoneOwner: zoneOwner
        ) { record in
            record["authorID"] = author as CKRecordValue
            record["authorName"] = authorName as CKRecordValue
            record["active"] = (active ? 1 : 0) as CKRecordValue
            record["changedAt"] = at as CKRecordValue
        }
    }

    /// One person's vote in one poll. A `choice` of -1 is a withdrawn vote,
    /// which is a value rather than an absence for the same reason a plate is
    /// tombstoned rather than deleted.
    static func pushBallot(
        post: String, zoneOwner: String, author: String, authorName: String,
        choice: Int, at: Date
    ) async -> Bool {
        await push(
            type: ballotType, name: "ballot-\(post)-\(author)",
            post: post, zoneOwner: zoneOwner
        ) { record in
            record["authorID"] = author as CKRecordValue
            // Named, like a plate. A ballot used to carry only an id, so
            // nothing downstream could say who voted, and a notice that
            // cannot name a person is a notice this app does not send.
            record["authorName"] = authorName as CKRecordValue
            record["choice"] = choice as CKRecordValue
            record["changedAt"] = at as CKRecordValue
        }
    }

    /// The shape both reactions share.
    ///
    /// Two parent links, doing two different jobs. `setParent(table-root)` is
    /// the SHARE hierarchy: CloudKit walks it to find the CKShare, and
    /// without it the record is private to whoever wrote it and no
    /// participant ever sees it. The `.deleteSelf` reference to the post is a
    /// referential constraint: it is what makes a deleted dish take its
    /// reactions with it. Neither substitutes for the other, and the comment
    /// on `publish` only half says so.
    private static func push(
        type: String, name: String, post: String, zoneOwner: String,
        fill: (CKRecord) -> Void
    ) async -> Bool {
        guard await TableSync.accountAvailable() else { return false }
        guard let (db, zoneID) = await zone(ownedBy: zoneOwner) else { return false }
        let record = CKRecord(
            recordType: type,
            recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
        )
        record["postRecordName"] = post as CKRecordValue
        record["postRef"] = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: post, zoneID: zoneID),
            action: .deleteSelf
        )
        record.setParent(CKRecord.ID(recordName: "table-root", zoneID: zoneID))
        fill(record)
        do {
            _ = try await db.save(record)
            return true
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Somebody's copy of this exact record won. With a deterministic
            // name that means one of this person's own devices got there
            // first, and last-writer-wins has already settled it.
            return true
        } catch {
            return false
        }
    }

    /// One comment on the table.
    ///
    /// Named `note-<UUID>`, minted when the comment is composed and reused
    /// across every retry and every drain. Globally unique by construction,
    /// so two people commenting in the same instant never contend, and a
    /// save whose response was lost replays as a no-op instead of a
    /// duplicate — which is the whole reason not to mint it at send time.
    static func pushNote(_ comment: TableComment, post: String, zoneOwner: String) async -> Bool {
        guard await TableSync.accountAvailable() else { return false }
        guard let (db, zoneID) = await zone(ownedBy: zoneOwner) else { return false }
        let recordID = CKRecord.ID(recordName: comment.shareRecordName, zoneID: zoneID)
        let record: CKRecord
        do { record = try await db.record(for: recordID) }
        catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: noteType, recordID: recordID)
        } catch { return false }
        // A delayed retry from another device cannot restore a deleted
        // comment. Deletion is permanent; its replies remain in place.
        if let deleted = record["deletedAt"] as? Date, comment.deletedAt == nil {
            comment.deletedAt = deleted
            comment.text = ""
            comment.linkURL = ""
            comment.photoData = nil
            comment.mentions = []
            return true
        }
        record["postRecordName"] = post as CKRecordValue
        record["authorID"] = comment.authorID as CKRecordValue
        record["authorName"] = comment.authorName as CKRecordValue
        record["text"] = comment.text as CKRecordValue
        record["linkURL"] = comment.linkURL as CKRecordValue
        record["replyToName"] = comment.replyToName as CKRecordValue
        record["parentCommentID"] = comment.parentCommentID as CKRecordValue?
        record["deletedAt"] = comment.deletedAt as CKRecordValue?
        record["createdAt"] = comment.createdAt as CKRecordValue
        // A list field minted empty is minted as the wrong type and stays
        // that way, so the key is omitted rather than written empty.
        if !comment.mentions.isEmpty {
            record["mentions"] = comment.mentions as CKRecordValue
        }
        record["postRef"] = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: post, zoneID: zoneID),
            action: .deleteSelf
        )
        record.setParent(CKRecord.ID(recordName: "table-root", zoneID: zoneID))

        if comment.mentions.isEmpty { record["mentions"] = nil }
        record["photo"] = nil
        var temp: URL?
        if let data = comment.photoData, let asset = asset(from: data) {
            record["photo"] = asset
            temp = asset.fileURL
        }
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }

        do {
            _ = try await db.save(record)
            return true
        } catch { return false }
    }

    /// A comment as it exists on the wire.
    struct RemoteNote {
        var recordName = ""
        var post = ""
        var authorID = ""
        var authorName = ""
        var text = ""
        var linkURL = ""
        var replyToName = ""
        var parentCommentID: String?
        var deletedAt: Date?
        var mentions: [String] = []
        var createdAt = Date.now
        var photoData: Data?
    }

    private static func remoteNote(from record: CKRecord) -> RemoteNote {
        var n = RemoteNote()
        n.recordName = record.recordID.recordName
        n.post = record["postRecordName"] as? String ?? ""
        n.authorID = record["authorID"] as? String ?? ""
        n.authorName = record["authorName"] as? String ?? ""
        n.text = record["text"] as? String ?? ""
        n.linkURL = record["linkURL"] as? String ?? ""
        n.replyToName = record["replyToName"] as? String ?? ""
        n.parentCommentID = record["parentCommentID"] as? String
        n.deletedAt = record["deletedAt"] as? Date
        n.mentions = record["mentions"] as? [String] ?? []
        n.createdAt = record["createdAt"] as? Date ?? .now
        if let asset = record["photo"] as? CKAsset, let url = asset.fileURL {
            n.photoData = try? Data(contentsOf: url)
        }
        return n
    }

    /// A reaction as it exists on the wire.
    struct RemoteReaction {
        var post = ""
        var author = ""
        var authorName = ""
        /// A plate's on/off, or a ballot's option index.
        var value = 0
        var at = Date.now
        var isBallot = false
    }

    /// A post as it exists on the wire.
    ///
    /// Plain values, never model objects: the caller merges on the main
    /// actor, and nothing here should touch a `ModelContext` from a
    /// background task.
    struct RemotePost {
        var recordName = ""
        /// Which table this arrived from. "" is my own.
        var zoneOwner = ""
        var authorID = ""
        var authorName = ""
        var authorColorHex = "FF5A3C"
        var dishTitle = ""
        var caption = ""
        var kind = "dish"
        var createdAt = Date.now
        var photoData: Data?
        var pollOptions: [String] = []
        var taggedNames: [String] = []
    }

    /// A night as it travels. Every field mirrors the record in
    /// docs/plan-share.md; `day` is a `PlanDay` string, never a Date.
    struct RemotePlan: Equatable {
        var recordName = ""
        /// Which table this arrived from. "" is my own.
        var zoneOwner = ""
        var authorID = ""
        var authorName = ""
        var authorColorHex = "FF5A3C"
        var cookID = ""
        var cookName = ""
        var cookColorHex = ""
        var cookSeat = ""
        var day = ""
        var slot = MealSlot.dinner.rawValue
        var title = ""
        var servings = 4
        var tagline = ""
        var cooked = false
        var cookedAt: Date?
        var hasRecipe = false
        var recipeMinutes = 0
        var recipeOriginKey = ""
        var shoppingID = ""
        var photoData: Data?
        var createdAt = Date.now
        var changedAt = Date.now
    }

    /// Everything other people have put on tables this user can see.
    ///
    /// Zone CHANGES, not a CKQuery, and that is the whole point. A query
    /// needs its record type marked Queryable and every sorted field marked
    /// Sortable in the CloudKit dashboard — none of which Development
    /// creates for you. Get it wrong and `records(matching:)` returns an
    /// empty set with no error, which is the worst possible failure: it
    /// looks exactly like "nobody has posted". `recordZoneChanges` needs no
    /// index at all, and is incremental into the bargain — the change token
    /// means the second pull costs the delta rather than the whole table.
    /// **Both databases, deliberately.**
    ///
    /// The zone lives in the HOST's private database and appears in a
    /// GUEST's shared database. This read the shared database alone, so
    /// `allRecordZones()` came back empty for every host and the loop never
    /// ran once: a guest's post never reached the person whose table it was.
    /// The Table was one-directional and nothing on screen said so, because
    /// an empty fetch is indistinguishable from a quiet table.
    ///
    /// Scanning the private database costs a host nothing they were not
    /// already paying — the zone filter skips the SwiftData mirror's own
    /// zone — and a host's own posts come back matching on
    /// `shareRecordName`, so `merge` updates them rather than duplicating.
    static func fetchRemote() async -> [RemotePost] {
        await fetchChanges().posts
    }

    /// What the tables have said since we last asked: what changed, and what
    /// was taken away.
    ///
    /// `deletions` used to be dropped on the floor, so a post the author
    /// removed stayed on every other phone until that phone was reinstalled.
    /// Now that deleting genuinely removes the record, ignoring the deletion
    /// half of the same conversation would be the same lie from the other
    /// end.
    struct Changes {
        var posts: [RemotePost] = []
        var reactions: [RemoteReaction] = []
        var notes: [RemoteNote] = []
        /// Nights other phones planned. Folded by `PlanLedger`, never merged.
        var plans: [RemotePlan] = []
        var deleted: Set<String> = []
        /// The CKShare itself came back changed: somebody accepted, or was
        /// removed. Which one is `Seats.reconcile`'s to say; this only
        /// notes that the question is worth asking now rather than at the
        /// next launch.
        var sharesChanged = false
        /// Zones read from the beginning this pull, by canonical owner. A
        /// replay carries no deletions, so for these owners the delivered
        /// plan set is the whole truth and the ledger reconciles against it.
        var replayedOwners: Set<String> = []
        /// The household share itself came back changed: somebody joined
        /// or was removed. The head sweeps departed members' nights on it.
        var householdShareChanged = false
        /// At least one zone was read from the beginning: a fresh install,
        /// or a change token CloudKit refused. The news treats such a
        /// delta as history to be windowed, not as a day's events.
        var replayed = false
    }

    static func fetchChanges() async -> Changes {
        guard await TableSync.accountAvailable() else { return Changes() }
        var all = Changes()
        for (db, isPrivate) in [(container.privateCloudDatabase, true),
                                (container.sharedCloudDatabase, false)] {
            let part = await postChanges(in: db, isPrivate: isPrivate)
            all.posts += part.posts
            all.reactions += part.reactions
            all.notes += part.notes
            all.plans += part.plans
            all.deleted.formUnion(part.deleted)
            all.replayedOwners.formUnion(part.replayedOwners)
            // The flags too. `sharesChanged` was set per database and then
            // dropped right here, so a seat accepted was never announced.
            all.sharesChanged = all.sharesChanged || part.sharesChanged
            all.replayed = all.replayed || part.replayed
        }
        return all
    }

    /// One database's worth of post changes, incrementally.
    ///
    /// A failure in one database must not cost the other its change token,
    /// which is why the catch is scoped to a zone rather than to the whole
    /// fetch: a host whose shared database throws should not re-read its
    /// own table from the beginning on every pull.
    private static func postChanges(in db: CKDatabase, isPrivate: Bool) async -> Changes {
        var found = Changes()
        guard let zones = try? await db.allRecordZones() else { return found }
        for zone in zones where zone.zoneID.zoneName == zoneName || zone.zoneID.zoneName == householdZoneName {
            let owner = canonicalOwner(zone.zoneID, isPrivate: isPrivate)
            // The Table zone carries dishes; the household zone carries the
            // plan. A replay of the Table zone must never read as "the
            // household's nights are gone", so the ledger's reconciliation
            // hears only about household zones.
            let isHousehold = zone.zoneID.zoneName == householdZoneName
            // A zone's read is all or nothing. Its records gather here and
            // join `found` only once every page has come and the token is
            // stored: a replayed owner whose read threw halfway would
            // otherwise hand the plan ledger one page as "the whole
            // truth", and the ledger would drop every other night at that
            // table, retract their rows and announce them taken off.
            var part = Changes()
            do {
                // Asked to read this table again from the beginning (the
                // household moved here): decided at the start of the read,
                // inside the one pull that is running, so no fetch that
                // began earlier can store a fresh token over the request.
                if takeReplayRequest(for: zone.zoneID) {
                    forgetToken(for: zone.zoneID)
                }
                // A page at a time until the server says there is no more.
                // One call returns one page, so a table with more posts than
                // a page holds used to arrive permanently truncated — and
                // the token still advanced, so the rest never came at all.
                var cursor = token(for: zone.zoneID)
                if cursor == nil {
                    part.replayed = true
                    // A zone read from nothing delivers every live record
                    // and no deletion, so for this owner what arrives is
                    // the whole truth and the plan ledger reconciles to it.
                    if isHousehold { part.replayedOwners.insert(owner) }
                }
                var more = true
                while more {
                    let changes = try await db.recordZoneChanges(
                        inZoneWith: zone.zoneID, since: cursor
                    )
                    for (_, result) in changes.modificationResultsByID {
                        guard let record = try? result.get().record else { continue }
                        switch record.recordType {
                        case postType, legacyPostType:
                            var post = remotePost(from: record)
                            post.zoneOwner = owner
                            part.posts.append(post)
                        case plateType, ballotType:
                            part.reactions.append(remoteReaction(from: record))
                        case noteType:
                            part.notes.append(remoteNote(from: record))
                        case planType:
                            var plan = remotePlan(from: record)
                            plan.zoneOwner = owner
                            part.plans.append(plan)
                        default:
                            if record is CKShare {
                                if isHousehold { part.householdShareChanged = true }
                                else { part.sharesChanged = true }
                            }
                            continue
                        }
                    }
                    for deleted in changes.deletions {
                        part.deleted.insert(deleted.recordID.recordName)
                    }
                    cursor = changes.changeToken
                    more = changes.moreComing
                }
                store(cursor, for: zone.zoneID)
                found.posts += part.posts
                found.reactions += part.reactions
                found.notes += part.notes
                found.plans += part.plans
                found.deleted.formUnion(part.deleted)
                found.replayedOwners.formUnion(part.replayedOwners)
                found.sharesChanged = found.sharesChanged || part.sharesChanged
                found.householdShareChanged = found.householdShareChanged || part.householdShareChanged
                found.replayed = found.replayed || part.replayed
            } catch {
                // A stale token after a zone is re-shared is the common
                // case. Forget this zone's and the next pull re-reads it
                // whole; the other zone's token survives, and so does
                // what this zone had already delivered: none of it, so
                // nothing partial is folded anywhere.
                forgetToken(for: zone.zoneID)
            }
        }
        return found
    }

    // MARK: Who is at the table

    struct Seat: Identifiable {
        var id: String
        var name: String
        var isOwner: Bool
        var isMe: Bool
    }

    /// The people on the share. Empty for a table that has never been
    /// shared, which is not an error — it is most tables, most of the time.
    static func participants() async -> [Seat] {
        guard await TableSync.accountAvailable() else { return [] }
        guard let share = await currentShare() else { return [] }
        let me = share.currentUserParticipant
        return share.participants.map { p in
            let name = [p.userIdentity.nameComponents?.givenName,
                        p.userIdentity.nameComponents?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            return Seat(
                id: p.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                name: name.isEmpty ? "Someone" : name,
                isOwner: p.role == .owner,
                isMe: p == me
            )
        }
    }

    /// Host removes a seat. The guest keeps nothing: CloudKit drops the zone
    /// from their shared database on their next sync.
    static func remove(seatID: String) async -> Bool {
        guard let share = await currentShare(),
              let victim = share.participants.first(where: {
                  $0.userIdentity.userRecordID?.recordName == seatID
              }), victim.role != .owner else { return false }
        share.removeParticipant(victim)
        do {
            _ = try await container.privateCloudDatabase.modifyRecords(
                saving: [share], deleting: []
            )
            return true
        } catch { return false }
    }

    /// A guest leaves. Deleting the zone from one's OWN shared database
    /// removes only this user's copy — it cannot touch the host's table,
    /// which is why leaving is safe to offer without a scary warning.
    static func leaveTable() async -> Bool {
        let db = container.sharedCloudDatabase
        guard let zones = try? await db.allRecordZones(),
              let zone = zones.first(where: { $0.zoneID.zoneName == zoneName })
        else { return false }
        do {
            _ = try await db.deleteRecordZone(withID: zone.zoneID)
            forgetTokens()
            // The plan is not here: it lives in the household zone, which
            // has its own leave (docs/household.md), and that leave clears
            // the household key the plan ledger reads.
            return true
        } catch { return false }
    }

    /// True when this user is a guest somewhere rather than a host.
    static func isGuest() async -> Bool {
        let mine = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        if (try? await container.privateCloudDatabase.recordZone(for: mine)) != nil { return false }
        let zones = try? await container.sharedCloudDatabase.allRecordZones()
        return zones?.contains { $0.zoneID.zoneName == zoneName } ?? false
    }

    private static func currentShare() async -> CKShare? {
        let db = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        guard let root = try? await db.record(
            for: CKRecord.ID(recordName: "table-root", zoneID: zoneID)
        ), let ref = root.share else { return nil }
        return try? await db.record(for: ref.recordID) as? CKShare
    }

    #if DEBUG
    /// Write one of everything so CloudKit's Development schema learns the
    /// record types, then read it back and say whether the round trip
    /// worked. Run before deploying the schema to Production: CloudKit
    /// cannot mint a type there on demand, so a type never exercised in
    /// Development is a feature that silently fails for everyone.
    ///
    /// Same reasoning as SchemaPrimer, which primes the SwiftData mirror's
    /// types — these are different types on a different path, and that
    /// primer does not cover them.
    static func primeSchema() async -> String {
        guard await TableSync.accountAvailable() else {
            return "PRIME SHARE: no iCloud account, nothing primed."
        }
        guard let url = await invitationURL(hostName: "Prime") else {
            return "PRIME SHARE FAILED: could not create the zone, root or share."
        }
        assertNoEntityCollision()

        // Every field on every type, populated. A field that is nil while
        // priming does not exist in Production, and the first real save
        // carrying it fails `.invalidArguments` — which, from a person's
        // seat, looks exactly like "my comment just didn't appear". Lists
        // must be NON-EMPTY here or the field is minted as the wrong type,
        // permanently.
        let probe = TablePost(
            authorName: "Prime", authorColorHex: "FF5A3C",
            dishTitle: "Schema probe", caption: "Written to teach CloudKit the type.",
            kind: "ask", createdAt: .now
        )
        probe.pollOptions = ["a", "b"]
        probe.taggedNames = ["Prime"]
        guard let name = await publish(probe, hostName: "Prime") else {
            return "PRIME SHARE FAILED: zone exists, but the post would not save.\nShare URL: \(url)"
        }

        let owner = probe.shareZoneOwner
        let note = TableComment(
            authorName: "Prime", text: "Schema probe.", linkURL: "https://plated.food",
            replyToName: "Prime", mentions: ["Prime"], authorID: "prime"
        )
        let noteOK = await pushNote(note, post: name, zoneOwner: owner)
        let plateOK = await pushPlate(
            post: name, zoneOwner: owner, author: "prime",
            authorName: "Prime", active: true, at: .now
        )
        let ballotOK = await pushBallot(
            post: name, zoneOwner: owner, author: "prime", authorName: "Primer", choice: 0, at: .now
        )
        // The plan record too: every field set and a photo on it, then
        // taken back. Its own path, not the post's, because it is parented
        // to the root rather than to a dish.
        let planLine = await primePlan()

        // And it takes back what it wrote. The old primer left "Schema
        // probe" sitting in a real household's real table forever.
        let removed = await retract(recordName: name, zoneOwner: owner)

        return """
        PRIME SHARE
          share URL  : \(url)
          PlatedDish : ok (\(name))
          Note       : \(noteOK ? "ok" : "FAILED")
          Plate      : \(plateOK ? "ok" : "FAILED")
          Ballot     : \(ballotOK ? "ok" : "FAILED")
          Plan       : \(planLine)
        Probe cleanup: \(removed ? "removed; children cascade with it" : "FAILED: cleanup must be retried").
        Every record type now exists in Development. Deploy the schema to \
        Production in the CloudKit console before shipping.
        """
    }

    /// One `PlatedHouseholdPlan` with every field non-nil and a photo, saved
    /// into the own zone and deleted again. Dated `2000-01-01`, so a
    /// reader that pulls between the save and the delete prunes it before
    /// it can be news. Nil fields are the trap: a field nil while priming
    /// does not exist in Production, and the first real save carrying it
    /// fails `.invalidArguments`.
    private static func primePlan() async -> String {
        // The plan lives in the household zone, which the household invite
        // mints. No zone, nothing to teach yet: say so rather than fail.
        guard let (db, zoneID) = await householdZone(ownedBy: "") else {
            print("[PlanShare] prime: no household zone yet; run -plated-prime-household first")
            return "skipped: no household zone yet (run -plated-prime-household first)"
        }
        let probe = PlanShare.Plan(
            recordName: "plan-prime-probe", shoppingID: "prime-probe",
            authorID: "prime", authorName: "Prime", authorColorHex: "FF5A3C",
            cookID: "prime", cookName: "Prime", cookColorHex: "3DA35D",
            cookSeat: HouseholdMember.Seat.head.rawValue,
            day: "2000-01-01", slot: MealSlot.dinner.rawValue,
            title: "Schema probe", servings: 4,
            tagline: "Written to teach CloudKit the type.",
            cooked: true, cookedAt: .now, hasRecipe: true, recipeMinutes: 35,
            recipeOriginKey: "prime", createdAt: .now, photoData: nil
        )
        // A few grey pixels: enough to mint the asset field, small enough
        // to cost nothing.
        let side: CGFloat = 8
        let pixels = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            ctx.cgContext.setFillColor(gray: 0.5, alpha: 1)
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let jpeg = pixels.jpegData(compressionQuality: 0.7) else { return "FAILED: no probe image" }
        let (record, temp) = planRecord(probe, existing: nil, zone: zoneID, photo: .set(jpeg), now: .now)
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        let saved = await savePlans([record], in: db)
        guard saved.contains(probe.recordName) else {
            print("[PlanShare] prime: the plan probe would not save")
            return "FAILED: the probe would not save"
        }
        let gone = await deletePlans(names: [probe.recordName], in: db, zone: zoneID)
        print("[PlanShare] prime: plan probe saved and \(gone.isEmpty ? "NOT " : "")deleted")
        return gone.contains(probe.recordName) ? "ok, saved with a photo and deleted again" : "FAILED: cleanup must be retried"
    }
    #endif

    // MARK: The plan across the wire

    /// One look at the shares, answered. Nil means CloudKit could not be
    /// asked, which is not "no candidate": a pass that cannot ask leaves
    /// the book and the ledger exactly as they were, because a flaky
    /// network must never read as a household that changed.
    struct HouseholdResolution {
        var choice: Choice
        /// Every candidate, titled from its root record.
        var tables: [PlanShare.Table]
        /// The resolved table's home, for the publisher. Nil unless resolved.
        var database: CKDatabase?
        var zoneID: CKRecordZone.ID?
    }

    /// Resolve the household from the shares (docs/plan-share.md, "Which
    /// zone is the household's"). `stored` is the owner already written
    /// down; `me` this phone's own record name.
    static func resolveHousehold(stored: String?, me: String) async -> HouseholdResolution? {
        guard await TableSync.accountAvailable() else {
            print("[PlanShare] no iCloud account, household not resolved")
            return nil
        }
        // The household invite wrote the answer down; it is the authority
        // (docs/household.md, one household per Apple ID). The zone has to
        // be reachable too: a key written a breath before the zone shows in
        // the shared database is "could not ask yet", never "none".
        if let written = householdStore.string(forKey: householdOwnerKey) {
            if let (db, zoneID) = await householdZone(ownedBy: written) {
                let title = await rootTitle(in: db, zone: zoneID)
                var resolution = HouseholdResolution(
                    choice: .resolved(written), tables: [PlanShare.Table(owner: written, title: title)]
                )
                resolution.database = db
                resolution.zoneID = zoneID
                print("[PlanShare] household from the invite's key: \(written.isEmpty ? "own" : written)")
                return resolution
            }
            print("[PlanShare] the household key names a zone that is not here yet")
            return nil
        }
        // No key: an install from before the household invite, or a phone
        // between households. Answer from the household zones' shares.
        // The own share's accepted seats. "Not a host" is an answer; a
        // share that could not be read is not, and must never be taken as
        // one: that is how a flaky network flips a household.
        var accepted: Set<String> = []
        do {
            if let share = try await ownHouseholdShare() {
                for p in share.participants
                where p.role != .owner && p.acceptanceStatus == .accepted {
                    if let id = p.userIdentity.userRecordID?.recordName, !id.isEmpty {
                        accepted.insert(id)
                    }
                }
            }
        } catch {
            print("[PlanShare] could not read the own share: \(error.localizedDescription)")
            return nil
        }
        let joined: [CKRecordZone]
        do {
            joined = try await container.sharedCloudDatabase.allRecordZones()
                .filter { $0.zoneID.zoneName == householdZoneName }
        } catch {
            print("[PlanShare] could not list joined households: \(error.localizedDescription)")
            return nil
        }
        let choice = chooseHousehold(
            ownShareAccepted: !accepted.isEmpty,
            ownAcceptedParticipantIDs: accepted,
            joinedOwners: joined.map(\.zoneID.ownerName),
            stored: stored, me: me
        )
        let ownID = CKRecordZone.ID(zoneName: householdZoneName, ownerName: CKCurrentUserDefaultName)
        var tables: [PlanShare.Table] = []
        if !accepted.isEmpty {
            let title = await rootTitle(in: container.privateCloudDatabase, zone: ownID)
            tables.append(PlanShare.Table(owner: "", title: title))
        }
        for zone in joined {
            let title = await rootTitle(in: container.sharedCloudDatabase, zone: zone.zoneID)
            tables.append(PlanShare.Table(owner: zone.zoneID.ownerName, title: title))
        }
        var resolution = HouseholdResolution(choice: choice, tables: tables)
        if case .resolved(let owner) = choice {
            if owner.isEmpty {
                resolution.database = container.privateCloudDatabase
                resolution.zoneID = ownID
            } else if let zone = joined.first(where: { $0.zoneID.ownerName == owner }) {
                resolution.database = container.sharedCloudDatabase
                resolution.zoneID = zone.zoneID
            }
        }
        print("[PlanShare] household: \(choice) from \(tables.count) candidate(s)")
        return resolution
    }

    /// The app-group suite the household invite writes its key into.
    static var householdStore: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    /// A household zone by canonical owner: "" is the own zone in the
    /// private database, anything else a joined zone in the shared one.
    /// Nil when it is not there or CloudKit could not say.
    static func householdZone(ownedBy owner: String) async -> (CKDatabase, CKRecordZone.ID)? {
        if owner.isEmpty {
            let id = CKRecordZone.ID(zoneName: householdZoneName, ownerName: CKCurrentUserDefaultName)
            do {
                _ = try await container.privateCloudDatabase.recordZone(for: id)
                return (container.privateCloudDatabase, id)
            } catch {
                return nil
            }
        }
        guard let zones = try? await container.sharedCloudDatabase.allRecordZones(),
              let z = zones.first(where: {
                  $0.zoneID.zoneName == householdZoneName && $0.zoneID.ownerName == owner
              })
        else { return nil }
        return (container.sharedCloudDatabase, z.zoneID)
    }

    /// The own household's share, nil when this phone hosts none. Throws
    /// when CloudKit could not say, which a `try?` would hide.
    private static func ownHouseholdShare() async throws -> CKShare? {
        let db = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: householdZoneName, ownerName: CKCurrentUserDefaultName)
        let root: CKRecord
        do {
            root = try await db.record(for: CKRecord.ID(recordName: householdRootName, zoneID: zoneID))
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
        guard let ref = root.share else { return nil }
        do {
            return try await db.record(for: ref.recordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// The household's name off its root record, "" when it has none.
    /// `name` is the household invite's field; `title` the Table's.
    private static func rootTitle(in db: CKDatabase, zone: CKRecordZone.ID) async -> String {
        let root = try? await db.record(for: CKRecord.ID(recordName: householdRootName, zoneID: zone))
        return root?["name"] as? String ?? root?["title"] as? String ?? ""
    }

    /// Where this phone's plan goes: the resolved household's database,
    /// zone and canonical owner, or nil when there is none or CloudKit
    /// could not be asked.
    @MainActor
    static func householdZone() async -> (CKDatabase, CKRecordZone.ID, owner: String)? {
        let stored = PlanLedger.shared.householdOwner
        guard let r = await resolveHousehold(stored: stored, me: TableIdentity.cached),
              case .resolved(let owner) = r.choice,
              let db = r.database, let zoneID = r.zoneID else { return nil }
        return (db, zoneID, owner)
    }

    /// Every table this phone's plan could belong to, titled.
    @MainActor
    static func tables() async -> [PlanShare.Table] {
        let stored = PlanLedger.shared.householdOwner
        return await resolveHousehold(stored: stored, me: TableIdentity.cached)?.tables ?? []
    }

    /// What one save does with the photo. A pass that already sent these
    /// bytes leaves the field alone, so readers do not download it again.
    enum PlanPhoto {
        case keep
        case set(Data)
        case clear
    }

    /// Build or update the record for one night: every field in the table
    /// in docs/plan-share.md, no lists and no Bools. The temp file behind
    /// a `.set` asset is the caller's to remove once the save is done.
    static func planRecord(
        _ plan: PlanShare.Plan, existing: CKRecord?, zone: CKRecordZone.ID,
        photo: PlanPhoto, now: Date
    ) -> (record: CKRecord, temp: URL?) {
        let record = existing ?? CKRecord(
            recordType: planType,
            recordID: CKRecord.ID(recordName: plan.recordName, zoneID: zone)
        )
        record["authorID"] = plan.authorID as CKRecordValue
        record["authorName"] = plan.authorName as CKRecordValue
        record["authorColorHex"] = plan.authorColorHex as CKRecordValue
        record["cookID"] = plan.cookID as CKRecordValue
        record["cookName"] = plan.cookName as CKRecordValue
        record["cookColorHex"] = plan.cookColorHex as CKRecordValue
        record["cookSeat"] = plan.cookSeat as CKRecordValue
        record["day"] = plan.day as CKRecordValue
        record["slot"] = plan.slot as CKRecordValue
        record["title"] = plan.title as CKRecordValue
        record["servings"] = plan.servings as CKRecordValue
        record["tagline"] = plan.tagline as CKRecordValue
        record["cooked"] = (plan.cooked ? 1 : 0) as CKRecordValue
        record["cookedAt"] = plan.cookedAt as CKRecordValue?
        record["hasRecipe"] = (plan.hasRecipe ? 1 : 0) as CKRecordValue
        record["recipeMinutes"] = plan.recipeMinutes as CKRecordValue
        record["recipeOriginKey"] = plan.recipeOriginKey as CKRecordValue
        record["shoppingID"] = plan.shoppingID as CKRecordValue
        record["createdAt"] = plan.createdAt as CKRecordValue
        // The household contract's name for the writer's clock.
        record["modifiedAt"] = now as CKRecordValue
        // Both links, exactly as `PlatedDish` carries them: the reference
        // is the cascade, the parent is what puts the record under the
        // share so a participant can see it at all.
        let rootID = CKRecord.ID(recordName: householdRootName, zoneID: zone)
        record["parent"] = CKRecord.Reference(recordID: rootID, action: .deleteSelf)
        record.setParent(rootID)
        var temp: URL?
        switch photo {
        case .keep:
            break
        case .clear:
            record["photo"] = nil
        case .set(let data):
            if let asset = asset(from: data) {
                record["photo"] = asset
                temp = asset.fileURL
            }
        }
        return (record, temp)
    }

    /// The records the zone already holds, by name, so a known night is
    /// updated rather than raced. A name the zone lacks is simply absent
    /// and the caller creates it outright.
    static func fetchPlanRecords(
        named names: [String], in db: CKDatabase, zone: CKRecordZone.ID
    ) async -> [String: CKRecord] {
        var found: [String: CKRecord] = [:]
        for batch in batches(names) {
            let ids = batch.map { CKRecord.ID(recordName: $0, zoneID: zone) }
            do {
                for (id, result) in try await db.records(for: ids) {
                    if case .success(let record) = result { found[id.recordName] = record }
                }
            } catch {
                print("[PlanShare] fetch of \(batch.count) night(s) failed: \(error.localizedDescription)")
            }
        }
        return found
    }

    /// Save nights twenty at a time, each on its own so one refusal does
    /// not fail the batch. Returns the names that landed.
    ///
    /// `.serverRecordChanged` means the zone already holds a record of this
    /// name that this one did not descend from: a flip back to a table
    /// that still has last month's copy, or one of this person's own
    /// devices saving first. Fetch it once, put these fields on it and
    /// save again; a second refusal waits for the next pass.
    static func savePlans(_ records: [CKRecord], in db: CKDatabase) async -> Set<String> {
        var saved: Set<String> = []
        for batch in batches(records) {
            saved.formUnion(await saveBatch(batch, in: db))
        }
        return saved
    }

    /// One batch, halved and retried when CloudKit says it was too big.
    ///
    /// `.limitExceeded` is a refusal of the operation's size, not of its
    /// contents, and the documented remedy is to split and try again.
    /// Treating it as a failure stalls forever rather than once: the book
    /// only records what saved, so the next pass rebuilds the same
    /// oversized batch and is refused identically. Twenty nights is well
    /// under the count limit but each one can carry a photograph, so the
    /// size limit is the one that bites.
    private static func saveBatch(_ batch: [CKRecord], in db: CKDatabase) async -> Set<String> {
        var saved: Set<String> = []
        let results: [CKRecord.ID: Result<CKRecord, Error>]
        do {
            results = try await db.modifyRecords(
                saving: batch, deleting: [], atomically: false
            ).saveResults
        } catch let error as CKError where error.code == .limitExceeded && batch.count > 1 {
            print("[PlanShare] save of \(batch.count) night(s) was too big, splitting")
            let half = batch.count / 2
            saved.formUnion(await saveBatch(Array(batch[..<half]), in: db))
            saved.formUnion(await saveBatch(Array(batch[half...]), in: db))
            return saved
        } catch {
            print("[PlanShare] save of \(batch.count) night(s) failed: \(error.localizedDescription)")
            return saved
        }
        for (id, result) in results {
            switch result {
            case .success:
                saved.insert(id.recordName)
            case .failure(let error as CKError) where error.code == .serverRecordChanged:
                guard let mine = batch.first(where: { $0.recordID == id }) else { continue }
                if await saveOverServerCopy(mine, in: db) {
                    saved.insert(id.recordName)
                } else {
                    print("[PlanShare] \(id.recordName) changed on the server twice, next pass")
                }
            case .failure(let error):
                print("[PlanShare] \(id.recordName) would not save: \(error.localizedDescription)")
            }
        }
        return saved
    }

    private static func saveOverServerCopy(_ mine: CKRecord, in db: CKDatabase) async -> Bool {
        do {
            let server = try await db.record(for: mine.recordID)
            for key in mine.changedKeys() { server[key] = mine[key] }
            server.parent = mine.parent
            let results = try await db.modifyRecords(
                saving: [server], deleting: [], atomically: false
            ).saveResults
            if case .success = results[mine.recordID] { return true }
            return false
        } catch {
            print("[PlanShare] retry of \(mine.recordID.recordName) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Delete nights by name, twenty at a time. `.unknownItem` is success:
    /// the night is not in the zone, which is what a delete is for.
    /// Returns the names now absent.
    static func deletePlans(names: [String], in db: CKDatabase, zone: CKRecordZone.ID) async -> Set<String> {
        var gone: Set<String> = []
        for batch in batches(names) {
            gone.formUnion(await deleteBatch(batch, in: db, zone: zone))
        }
        return gone
    }

    /// One batch of deletions, halved and retried on `.limitExceeded` for
    /// the same reason as `saveBatch`: the refusal is about the size of the
    /// operation, and a batch that is skipped is rebuilt identically next
    /// pass. A retraction that never lands leaves a night on other phones
    /// after it was taken off this one.
    private static func deleteBatch(
        _ batch: [String], in db: CKDatabase, zone: CKRecordZone.ID
    ) async -> Set<String> {
        var gone: Set<String> = []
        let ids = batch.map { CKRecord.ID(recordName: $0, zoneID: zone) }
        let results: [CKRecord.ID: Result<Void, Error>]
        do {
            results = try await db.modifyRecords(
                saving: [], deleting: ids, atomically: false
            ).deleteResults
        } catch let error as CKError where error.code == .limitExceeded && batch.count > 1 {
            print("[PlanShare] delete of \(batch.count) night(s) was too big, splitting")
            let half = batch.count / 2
            gone.formUnion(await deleteBatch(Array(batch[..<half]), in: db, zone: zone))
            gone.formUnion(await deleteBatch(Array(batch[half...]), in: db, zone: zone))
            return gone
        } catch {
            print("[PlanShare] delete of \(batch.count) night(s) failed: \(error.localizedDescription)")
            return gone
        }
        for (id, result) in results {
            switch result {
            case .success:
                gone.insert(id.recordName)
            case .failure(let error as CKError) where error.code == .unknownItem:
                gone.insert(id.recordName)
            case .failure(let error):
                print("[PlanShare] \(id.recordName) would not delete: \(error.localizedDescription)")
            }
        }
        return gone
    }

    /// The same, aimed at a table by its canonical owner: the re-home
    /// path, which deletes from a zone this phone no longer publishes into.
    /// A zone out of reach returns nothing; the caller treats those nights
    /// as unpublished either way.
    static func deletePlans(names: [String], zoneOwner: String) async -> Set<String> {
        guard !names.isEmpty, await TableSync.accountAvailable() else { return [] }
        guard let (db, zoneID) = await householdZone(ownedBy: zoneOwner) else {
            print("[PlanShare] \(zoneOwner.isEmpty ? "own household" : zoneOwner) is out of reach, \(names.count) night(s) left behind")
            return []
        }
        return await deletePlans(names: names, in: db, zone: zoneID)
    }

    /// The head's housekeeping after a seat changed. Nothing cascades when
    /// a member leaves: the `.deleteSelf` reference fires only when the
    /// root goes, which nothing does. So plan records in the own zone whose
    /// author no longer sits accepted on the share are deleted, and the
    /// ledger drops them through the same fold a wire deletion takes, so
    /// no notice is raised about a night this phone took off itself.
    ///
    /// Returns what the ledger dropped, so the caller can withdraw the
    /// rows and banners about those nights the way a wire deletion does.
    /// It is not handed to the digest: "Sam took Tacos off Thursday" would
    /// be a claim about Sam, and Sam left; this phone took it off.
    @MainActor
    static func sweepDepartedPlans() async -> PlanLedger.Delta {
        guard await TableSync.accountAvailable() else { return PlanLedger.Delta() }
        let share: CKShare?
        do { share = try await ownHouseholdShare() } catch { return PlanLedger.Delta() }
        guard let share else { return PlanLedger.Delta() }
        var accepted: Set<String> = [TableIdentity.cached]
        for p in share.participants where p.acceptanceStatus == .accepted {
            if let id = p.userIdentity.userRecordID?.recordName { accepted.insert(id) }
        }
        // The ledger shows the own zone's nights only while the household
        // is the own table, which is the head's ordinary state.
        guard PlanLedger.shared.householdOwner == "" else { return PlanLedger.Delta() }
        let departed = PlanLedger.shared.all
            .filter { $0.zoneOwner.isEmpty && !accepted.contains($0.authorID) }
            .map(\.recordName)
        guard !departed.isEmpty else { return PlanLedger.Delta() }
        let zoneID = CKRecordZone.ID(zoneName: householdZoneName, ownerName: CKCurrentUserDefaultName)
        let gone = await deletePlans(names: departed, in: container.privateCloudDatabase, zone: zoneID)
        var housekeeping = Changes()
        housekeeping.deleted = gone
        let delta = PlanLedger.shared.absorb(housekeeping, me: TableIdentity.cached)
        print("[PlanShare] swept \(gone.count) of \(departed.count) night(s) by people no longer at the table")
        return delta
    }

    /// A table to be read again from the beginning. The ledger drops a
    /// table's nights when the household moves away from it; when it moves
    /// back, only a full read brings them home.
    ///
    /// Written down rather than done here: a pull may be mid-fetch, and a
    /// token forgotten now would be stored over by the page that fetch is
    /// on. `postChanges` consumes the request at the start of that zone's
    /// next read, where nothing can interleave. The flag is written beside
    /// the tokens so a request survives the app dying before the next pull.
    static func requestReplay(zoneOwner: String) {
        let ownerName = zoneOwner.isEmpty ? CKCurrentUserDefaultName : zoneOwner
        let id = CKRecordZone.ID(zoneName: householdZoneName, ownerName: ownerName)
        UserDefaults.standard.set(true, forKey: replayKey(id))
    }

    private static func replayKey(_ id: CKRecordZone.ID) -> String {
        "plated.zonereplay.\(id.zoneName).\(id.ownerName)"
    }

    /// True once per request, and the request is spent.
    private static func takeReplayRequest(for id: CKRecordZone.ID) -> Bool {
        guard UserDefaults.standard.bool(forKey: replayKey(id)) else { return false }
        UserDefaults.standard.removeObject(forKey: replayKey(id))
        return true
    }

    private static func batches<T>(_ items: [T], of size: Int = 20) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }

    // MARK: Change tokens

    private static func tokenKey(_ id: CKRecordZone.ID) -> String {
        "plated.zonetoken.\(id.zoneName).\(id.ownerName)"
    }

    private static func token(for id: CKRecordZone.ID) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenKey(id)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self, from: data
        )
    }

    private static func store(_ token: CKServerChangeToken?, for id: CKRecordZone.ID) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(
                withRootObject: token, requiringSecureCoding: true
              ) else { return }
        UserDefaults.standard.set(data, forKey: tokenKey(id))
    }

    private static func forgetToken(for id: CKRecordZone.ID) {
        UserDefaults.standard.removeObject(forKey: tokenKey(id))
    }

    private static func forgetTokens() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("plated.zonetoken.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func remoteReaction(from record: CKRecord) -> RemoteReaction {
        var r = RemoteReaction()
        r.post = record["postRecordName"] as? String ?? ""
        r.author = record["authorID"] as? String ?? ""
        r.authorName = record["authorName"] as? String ?? ""
        r.at = record["changedAt"] as? Date ?? .now
        r.isBallot = record.recordType == ballotType
        // `active` and `choice` are both INT64 on the wire; CloudKit has no
        // boolean type and `as? Bool` on one is a bridging coin flip.
        r.value = r.isBallot ? int(record, "choice") : int(record, "active")
        return r
    }

    private static func remotePost(from record: CKRecord) -> RemotePost {
        var p = RemotePost()
        p.recordName = record.recordID.recordName
        p.authorID = record["authorID"] as? String ?? ""
        p.pollOptions = record["pollOptions"] as? [String] ?? []
        p.taggedNames = record["taggedNames"] as? [String] ?? []
        p.authorName = record["authorName"] as? String ?? ""
        p.authorColorHex = record["authorColorHex"] as? String ?? "FF5A3C"
        p.dishTitle = record["dishTitle"] as? String ?? ""
        p.caption = record["caption"] as? String ?? ""
        p.kind = record["kind"] as? String ?? "dish"
        p.createdAt = record["createdAt"] as? Date ?? .now
        if let asset = record["photo"] as? CKAsset, let url = asset.fileURL {
            p.photoData = try? Data(contentsOf: url)
        }
        return p
    }

    private static func remotePlan(from record: CKRecord) -> RemotePlan {
        var p = RemotePlan()
        p.recordName = record.recordID.recordName
        p.authorID = record["authorID"] as? String ?? ""
        p.authorName = record["authorName"] as? String ?? ""
        p.authorColorHex = record["authorColorHex"] as? String ?? "FF5A3C"
        p.cookID = record["cookID"] as? String ?? ""
        p.cookName = record["cookName"] as? String ?? ""
        p.cookColorHex = record["cookColorHex"] as? String ?? ""
        p.cookSeat = record["cookSeat"] as? String ?? ""
        p.day = record["day"] as? String ?? ""
        p.slot = record["slot"] as? String ?? MealSlot.dinner.rawValue
        p.title = record["title"] as? String ?? ""
        p.servings = int(record, "servings")
        p.tagline = record["tagline"] as? String ?? ""
        // INT64 on the wire, both of them; `as? Bool` on one is a coin flip.
        p.cooked = int(record, "cooked") == 1
        p.cookedAt = record["cookedAt"] as? Date
        p.hasRecipe = int(record, "hasRecipe") == 1
        p.recipeMinutes = int(record, "recipeMinutes")
        p.recipeOriginKey = record["recipeOriginKey"] as? String ?? ""
        p.shoppingID = record["shoppingID"] as? String ?? ""
        p.createdAt = record["createdAt"] as? Date ?? .now
        p.changedAt = record["modifiedAt"] as? Date ?? record["changedAt"] as? Date ?? .now
        if let asset = record["photo"] as? CKAsset, let url = asset.fileURL {
            p.photoData = try? Data(contentsOf: url)
        }
        return p
    }

    /// Which database and zone this user may write posts into: their own
    /// table if they host one, otherwise the first table they've joined.
    /// Canonical zone owner. "" always means MY OWN table.
    ///
    /// `zoneID.ownerName` is observer-relative: `__defaultOwner__` for the
    /// host reading their private database, the host's real record name for
    /// a guest reading the shared one. Canonicalising at the boundary keeps
    /// the value stored on a TablePost stable across one person's devices,
    /// and it is never compared across people.
    static func canonicalOwner(_ zoneID: CKRecordZone.ID, isPrivate: Bool) -> String {
        isPrivate ? "" : zoneID.ownerName
    }

    /// Where THIS post lives. Never "wherever I happen to write".
    ///
    /// This replaces a `writableZone()` that answered a question about the
    /// PERSON — do I host a table? — and let hosting always win. Anyone who
    /// has tapped Invite once hosts forever, so every write to a post on a
    /// table they had JOINED was aimed at their own zone instead.
    private static func zone(ownedBy owner: String) async -> (CKDatabase, CKRecordZone.ID)? {
        if owner.isEmpty {
            let id = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            // `.zoneNotFound` means there is genuinely no table here. Any
            // other error means we could not ask, and must never be read as
            // "not a host": that is how a flaky network routes a host's own
            // write into somebody else's zone.
            do {
                _ = try await container.privateCloudDatabase.recordZone(for: id)
                return (container.privateCloudDatabase, id)
            } catch {
                return nil
            }
        }
        guard let zones = try? await container.sharedCloudDatabase.allRecordZones(),
              let z = zones.first(where: {
                  $0.zoneID.zoneName == zoneName && $0.zoneID.ownerName == owner
              })
        else { return nil }
        return (container.sharedCloudDatabase, z.zoneID)
    }

    /// Where a NEW post goes: my own table if I host one, otherwise the
    /// table I have joined.
    private static func myWritableZone() async -> (CKDatabase, CKRecordZone.ID, String)? {
        if let (db, id) = await zone(ownedBy: "") { return (db, id, "") }
        guard let zones = try? await container.sharedCloudDatabase.allRecordZones(),
              let z = zones.first(where: { $0.zoneID.zoneName == zoneName })
        else { return nil }
        return (container.sharedCloudDatabase, z.zoneID, z.zoneID.ownerName)
    }

    private static func asset(from data: Data) -> CKAsset? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "share-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url)
            return CKAsset(fileURL: url)
        } catch {
            return nil
        }
    }

    #else
    static func invitationURL(hostName: String) async -> URL? { nil }
    static func accept(_ metadata: CKShare.Metadata) async -> Bool { false }
    static func publish(_ post: TablePost, hostName: String) async -> String? { nil }
    static func retract(recordName: String, zoneOwner: String) async -> Bool { true }
    struct RemotePost { var recordName = ""; var zoneOwner = ""; var authorID = ""
                        var pollOptions: [String] = []; var taggedNames: [String] = []
                        var authorName = ""
                        var authorColorHex = "FF5A3C"
                        var dishTitle = ""; var caption = ""; var kind = "dish"
                        var createdAt = Date.now; var photoData: Data? }
    struct RemoteReaction { var post = ""; var author = ""; var authorName = ""
                            var value = 0; var at = Date.now; var isBallot = false }
    struct RemoteNote { var recordName = ""; var post = ""; var authorID = ""
                        var authorName = ""; var text = ""; var linkURL = ""
                        var replyToName = ""; var parentCommentID: String?; var deletedAt: Date?; var mentions: [String] = []
                        var createdAt = Date.now; var photoData: Data? }
    struct RemotePlan: Equatable { var recordName = ""; var zoneOwner = ""; var authorID = ""
                        var authorName = ""; var authorColorHex = "FF5A3C"
                        var cookID = ""; var cookName = ""; var cookColorHex = ""; var cookSeat = ""
                        var day = ""; var slot = MealSlot.dinner.rawValue; var title = ""
                        var servings = 4; var tagline = ""; var cooked = false; var cookedAt: Date?
                        var hasRecipe = false; var recipeMinutes = 0; var recipeOriginKey = ""
                        var shoppingID = ""; var photoData: Data?
                        var createdAt = Date.now; var changedAt = Date.now }
    struct Changes { var posts: [RemotePost] = []; var reactions: [RemoteReaction] = []
                     var notes: [RemoteNote] = []; var plans: [RemotePlan] = []
                     var deleted: Set<String> = []
                     var sharesChanged = false; var replayed = false
                     var replayedOwners: Set<String> = []; var householdShareChanged = false }
    static func pushNote(_ comment: TableComment, post: String, zoneOwner: String) async -> Bool { false }
    static func subscribe() async {}
    static func pushPlate(post: String, zoneOwner: String, author: String,
                          authorName: String, active: Bool, at: Date) async -> Bool { false }
    static func pushBallot(post: String, zoneOwner: String, author: String,
                           authorName: String, choice: Int, at: Date) async -> Bool { false }
    static func fetchRemote() async -> [RemotePost] { [] }
    static func fetchChanges() async -> Changes { Changes() }
    struct Seat: Identifiable { var id = ""; var name = ""; var isOwner = false; var isMe = false }
    static func participants() async -> [Seat] { [] }
    static func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        throw CKError(.unknownItem)
    }
    static func remove(seatID: String) async -> Bool { false }
    static func leaveTable() async -> Bool { false }
    enum InviteOutcome { case ready(URL), noAccount, noCloud }
    static func invite(phone: String?, email: String?, hostName: String) async -> InviteOutcome { .noCloud }
    static func revokeInvite(phone: String?, email: String?) async {}
    struct Standing { var phone: String?; var email: String?; var name = ""
                      var accepted = false; var participantID: String? }
    static func standings() async -> [Standing] { [] }
    static func isGuest() async -> Bool { false }
    struct HouseholdResolution { var choice: Choice = .none; var tables: [PlanShare.Table] = []
                                 var database: CKDatabase?; var zoneID: CKRecordZone.ID? }
    static func resolveHousehold(stored: String?, me: String) async -> HouseholdResolution? { nil }
    @MainActor static func householdZone() async -> (CKDatabase, CKRecordZone.ID, owner: String)? { nil }
    static func householdZone(ownedBy owner: String) async -> (CKDatabase, CKRecordZone.ID)? { nil }
    static var householdStore: UserDefaults { UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard }
    @MainActor static func tables() async -> [PlanShare.Table] { [] }
    enum PlanPhoto { case keep, set(Data), clear }
    static func planRecord(_ plan: PlanShare.Plan, existing: CKRecord?, zone: CKRecordZone.ID,
                           photo: PlanPhoto, now: Date) -> (record: CKRecord, temp: URL?) {
        (existing ?? CKRecord(recordType: planType,
                              recordID: CKRecord.ID(recordName: plan.recordName, zoneID: zone)), nil)
    }
    static func fetchPlanRecords(named names: [String], in db: CKDatabase,
                                 zone: CKRecordZone.ID) async -> [String: CKRecord] { [:] }
    static func savePlans(_ records: [CKRecord], in db: CKDatabase) async -> Set<String> { [] }
    static func deletePlans(names: [String], in db: CKDatabase, zone: CKRecordZone.ID) async -> Set<String> { [] }
    static func deletePlans(names: [String], zoneOwner: String) async -> Set<String> { [] }
    @MainActor static func sweepDepartedPlans() async -> PlanLedger.Delta { PlanLedger.Delta() }
    static func requestReplay(zoneOwner: String) {}
    #endif

    /// Fold what came back into the local store, keyed on the record name so
    /// a second fetch updates rather than duplicates.
    @MainActor
    static func merge(_ changes: Changes, into context: ModelContext) {
        // Every kind of change counts. This used to return unless a POST
        // changed, so a delta carrying only plates or comments, which is
        // what arrives when somebody reacts to a dish that is already on
        // every phone, was dropped whole: the plate never reached the
        // ledger and the comment never reached the thread until some
        // unrelated post happened to change. A unit test on the news
        // digest found it; nothing on screen ever could, because a missing
        // plate looks exactly like a dish nobody plated.
        guard !changes.posts.isEmpty || !changes.deleted.isEmpty
            || !changes.reactions.isEmpty || !changes.notes.isEmpty
            || !changes.plans.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<TablePost>())) ?? []
        var byRecord: [String: TablePost] = [:]
        for post in existing where !post.shareRecordName.isEmpty {
            byRecord[post.shareRecordName] = post
        }

        // A `plan-` name is a night, not a post: `PlanLedger` folds those,
        // and the plate ledger has nothing to forget about one.
        let deletedPosts = changes.deleted.filter { !$0.hasPrefix("plan-") }

        // Taken off the table by whoever wrote it. Dropping these on the
        // floor meant a post its author had deleted stayed on every other
        // phone until that phone was reinstalled — the same lie as a delete
        // that does not delete, told from the receiving end.
        for name in deletedPosts {
            if let post = byRecord[name] {
                context.delete(post)
                byRecord[name] = nil
            }
        }

        // Fold what other people did into the ledger. Last-writer-wins on
        // `changedAt` is applied inside `setPlate`/`setBallot`, so a page
        // that arrives late cannot undo a newer tap.
        for r in changes.reactions where !r.post.isEmpty && !r.author.isEmpty {
            if r.isBallot {
                TableLedger.shared.setBallot(r.post, author: r.author,
                                             choice: r.value, at: r.at)
            } else {
                TableLedger.shared.setPlate(r.post, author: r.author,
                                            active: r.value == 1, at: r.at)
            }
        }

        // A post that is gone takes its reactions with it. The cascade
        // removes the child records on the server, but the fold that would
        // have noticed never runs — there is no post left to fold against.
        for name in deletedPosts {
            TableLedger.shared.forget(post: name)
        }

        for r in changes.posts {
            if let post = byRecord[r.recordName] {
                // Someone edited their caption; plates and comments are ours
                // and are deliberately not overwritten from the wire.
                post.caption = r.caption
                post.dishTitle = r.dishTitle
                post.shareZoneOwner = r.zoneOwner
                if !r.authorID.isEmpty { post.authorID = r.authorID }
                if !r.pollOptions.isEmpty { post.pollOptions = r.pollOptions }
                if !r.taggedNames.isEmpty { post.taggedNames = r.taggedNames }
            } else {
                let post = TablePost(
                    authorName: r.authorName, authorColorHex: r.authorColorHex,
                    dishTitle: r.dishTitle, caption: r.caption, kind: r.kind,
                    isDiscover: false, createdAt: r.createdAt, photoData: r.photoData
                )
                post.shareRecordName = r.recordName
                post.shareZoneOwner = r.zoneOwner
                post.authorID = r.authorID
                post.pollOptions = r.pollOptions
                post.taggedNames = r.taggedNames
                // Remote only when the wire actually named somebody else.
                // An unstamped record — one written before authorID existed
                // — is left alone rather than assumed to be a stranger's,
                // because that assumption is permanent and takes Delete with
                // it. Better to offer Delete on somebody else's old post,
                // which CloudKit will refuse, than to withhold it forever on
                // your own.
                post.isRemote = !r.authorID.isEmpty && r.authorID != TableIdentity.cached
                context.insert(post)
            }
        }
        // Comments, after the posts they belong to exist to hang them on.
        //
        // Keyed on the note's own record name, so a comment that arrives
        // twice — two of one person's devices folding the same thread, or a
        // page replayed after a token reset — updates rather than
        // duplicating. That is the one race a mirrored TableComment brings
        // with it, and it is answered here rather than discovered later.
        if !changes.notes.isEmpty {
            let posts = (try? context.fetch(FetchDescriptor<TablePost>())) ?? []
            var postByRecord: [String: TablePost] = [:]
            for post in posts where !post.shareRecordName.isEmpty {
                postByRecord[post.shareRecordName] = post
            }
            let comments = (try? context.fetch(FetchDescriptor<TableComment>())) ?? []
            var byRecord: [String: TableComment] = [:]
            for c in comments where !c.shareRecordName.isEmpty {
                byRecord[c.shareRecordName] = c
            }
            let pendingNotes = Set(TableOutbox.shared.pending.compactMap { entry -> String? in
                if case let .note(_, _, id) = entry.work { return id }
                return nil
            })
            for n in changes.notes {
                // A stale pull must not resurrect text awaiting deletion.
                guard !pendingNotes.contains(n.recordName) else { continue }
                guard let parent = postByRecord[n.post] else { continue }
                if let existing = byRecord[n.recordName] {
                    guard existing.deletedAt == nil || n.deletedAt != nil else { continue }
                    existing.text = n.text
                    existing.linkURL = n.linkURL
                    existing.mentions = n.mentions
                    existing.replyToName = n.replyToName
                    existing.parentCommentID = n.parentCommentID
                    existing.deletedAt = n.deletedAt
                    existing.photoData = n.photoData
                    continue
                }
                let comment = TableComment(
                    authorName: n.authorName, text: n.text, linkURL: n.linkURL,
                    createdAt: n.createdAt, replyToName: n.replyToName,
                    mentions: n.mentions, photoData: n.photoData,
                    authorID: n.authorID
                )
                comment.parentCommentID = n.parentCommentID
                comment.deletedAt = n.deletedAt
                comment.shareRecordName = n.recordName
                comment.post = parent
                context.insert(comment)
                byRecord[n.recordName] = comment
            }
        }

        Persist.save(context, "table share merge")
    }

    @MainActor private static var cleaningSchemaProbes = false

    /// Remove the known development artifacts from both authorities. Keep
    /// a hidden local copy on network failure so a later foreground or pull
    /// can retry; deleting it first would lose the cloud record's address.
    @MainActor
    static func removeSchemaProbes(
        from context: ModelContext,
        retractRecord: (String, String) async -> Bool = { name, owner in
            await retract(recordName: name, zoneOwner: owner)
        }
    ) async {
        guard !cleaningSchemaProbes else { return }
        cleaningSchemaProbes = true
        defer { cleaningSchemaProbes = false }
        do {
            let probes = try context.fetch(FetchDescriptor<TablePost>()).filter(\.isSchemaProbe)
            guard !probes.isEmpty else { return }
            var removed = 0
            for post in probes {
                guard !post.isDeleted else { continue }
                let name = post.shareRecordName
                let mirroredPrimer = post.authorName == "Schema primer"
                let cloudRemoved = name.isEmpty || mirroredPrimer ? true : await retractRecord(name, post.shareZoneOwner)
                guard cloudRemoved else {
                    print("PLATED PROBE CLEANUP: remote deletion pending; retry on next refresh")
                    continue
                }
                guard !post.isDeleted else { continue }
                context.delete(post)
                TableLedger.shared.forget(post: name)
                removed += 1
            }
            if removed > 0 {
                try context.save()
                print("PLATED PROBE CLEANUP: removed \(removed) development posts")
            }
        } catch {
            print("PLATED PROBE CLEANUP FAILED: \(error)")
        }
    }
}
