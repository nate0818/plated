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

    #if DEBUG
    /// The ghost post, made unrepeatable.
    ///
    /// `legacyPostType` is deliberately excluded: "TablePost" IS the
    /// collision, it is read-only, and asserting on it would fire on the one
    /// type that can never be renamed. The reserved prefix closes the class
    /// going forward, not retroactively.
    static func assertNoEntityCollision() {
        let entities = Set(PlatedStore.schema.entities.map(\.name))
        let written: Set<String> = [rootType, postType, plateType, ballotType, noteType]
        let clash = entities.intersection(written)
        assert(clash.isEmpty, "CloudKit types collide with SwiftData entities: \(clash)")
    }
    #endif

    /// CloudKit has no boolean type. A Bool field is stored as an INT64 and
    /// `record[key] as? Bool` is a bridging coin flip.
    private static func int(_ record: CKRecord, _ key: String) -> Int {
        if let n = record[key] as? Int { return n }
        if let n = record[key] as? Int64 { return Int(n) }
        if let n = record[key] as? NSNumber { return n.intValue }
        return 0
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
        post: String, zoneOwner: String, author: String, choice: Int, at: Date
    ) async -> Bool {
        await push(
            type: ballotType, name: "ballot-\(post)-\(author)",
            post: post, zoneOwner: zoneOwner
        ) { record in
            record["authorID"] = author as CKRecordValue
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
        var deleted: Set<String> = []
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
            all.deleted.formUnion(part.deleted)
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
        for zone in zones where zone.zoneID.zoneName == zoneName {
            let owner = canonicalOwner(zone.zoneID, isPrivate: isPrivate)
            do {
                // A page at a time until the server says there is no more.
                // One call returns one page, so a table with more posts than
                // a page holds used to arrive permanently truncated — and
                // the token still advanced, so the rest never came at all.
                var cursor = token(for: zone.zoneID)
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
                            found.posts.append(post)
                        case plateType, ballotType:
                            found.reactions.append(remoteReaction(from: record))
                        case noteType:
                            found.notes.append(remoteNote(from: record))
                        default:
                            continue
                        }
                    }
                    for deleted in changes.deletions {
                        found.deleted.insert(deleted.recordID.recordName)
                    }
                    cursor = changes.changeToken
                    more = changes.moreComing
                }
                store(cursor, for: zone.zoneID)
            } catch {
                // A stale token after a zone is re-shared is the common
                // case. Forget this zone's and the next pull re-reads it
                // whole; the other zone's token survives.
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
            post: name, zoneOwner: owner, author: "prime", choice: 0, at: .now
        )

        // And it takes back what it wrote. The old primer left "Schema
        // probe" sitting in a real household's real table forever.
        _ = await retract(recordName: name, zoneOwner: owner)

        return """
        PRIME SHARE
          share URL  : \(url)
          PlatedDish : ok (\(name))
          Note       : \(noteOK ? "ok" : "FAILED")
          Plate      : \(plateOK ? "ok" : "FAILED")
          Ballot     : \(ballotOK ? "ok" : "FAILED")
        The probe post was retracted; its children cascade with it.
        Every record type now exists in Development. Deploy the schema to \
        Production in the CloudKit console before shipping.
        """
    }
    #endif

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
    struct Changes { var posts: [RemotePost] = []; var reactions: [RemoteReaction] = []
                     var notes: [RemoteNote] = []; var deleted: Set<String> = [] }
    static func pushNote(_ comment: TableComment, post: String, zoneOwner: String) async -> Bool { false }
    static func subscribe() async {}
    static func pushPlate(post: String, zoneOwner: String, author: String,
                          authorName: String, active: Bool, at: Date) async -> Bool { false }
    static func pushBallot(post: String, zoneOwner: String, author: String,
                           choice: Int, at: Date) async -> Bool { false }
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
    #endif

    /// Fold what came back into the local store, keyed on the record name so
    /// a second fetch updates rather than duplicates.
    @MainActor
    static func merge(_ changes: Changes, into context: ModelContext) {
        guard !changes.posts.isEmpty || !changes.deleted.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<TablePost>())) ?? []
        var byRecord: [String: TablePost] = [:]
        for post in existing where !post.shareRecordName.isEmpty {
            byRecord[post.shareRecordName] = post
        }

        // Taken off the table by whoever wrote it. Dropping these on the
        // floor meant a post its author had deleted stayed on every other
        // phone until that phone was reinstalled — the same lie as a delete
        // that does not delete, told from the receiving end.
        for name in changes.deleted {
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
        for name in changes.deleted {
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
}
