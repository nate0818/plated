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
        guard let (db, zoneID) = await writableZone() else { return nil }
        do {
            let name = post.shareRecordName.isEmpty
                ? "post-\(UUID().uuidString)" : post.shareRecordName
            let record = CKRecord(
                recordType: postType,
                recordID: CKRecord.ID(recordName: name, zoneID: zoneID)
            )
            record["authorName"] = post.authorName as CKRecordValue
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

    /// Everything other people have put on tables this user can see.
    ///
    /// Returns plain values, never model objects: the caller merges on the
    /// main actor, and nothing here should touch a `ModelContext` from a
    /// background task.
    struct RemotePost {
        var recordName = ""
        var authorName = ""
        var authorColorHex = "FF5A3C"
        var dishTitle = ""
        var caption = ""
        var kind = "dish"
        var createdAt = Date.now
        var photoData: Data?
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
    static func fetchRemote() async -> [RemotePost] {
        guard await TableSync.accountAvailable() else { return [] }
        let db = container.sharedCloudDatabase
        var found: [RemotePost] = []
        do {
            let zones = try await db.allRecordZones()
            for zone in zones where zone.zoneID.zoneName == zoneName {
                let changes = try await db.recordZoneChanges(
                    inZoneWith: zone.zoneID, since: token(for: zone.zoneID)
                )
                for (_, result) in changes.modificationResultsByID {
                    guard let record = try? result.get().record,
                          record.recordType == postType
                            || record.recordType == legacyPostType else { continue }
                    found.append(remotePost(from: record))
                }
                store(changes.changeToken, for: zone.zoneID)
            }
        } catch {
            // A stale token after a zone is re-shared is the common case.
            // Forget it and the next pull re-reads the zone whole.
            forgetTokens()
            return found
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
            return "PRIME SHARE: no iCloud account — nothing primed."
        }
        guard let url = await invitationURL(hostName: "Prime") else {
            return "PRIME SHARE FAILED: could not create the zone, root or share."
        }
        let probe = TablePost(
            authorName: "Prime", authorColorHex: "FF5A3C",
            dishTitle: "Schema probe", caption: "Written to teach CloudKit the type.",
            kind: "dish", createdAt: .now
        )
        guard let name = await publish(probe, hostName: "Prime") else {
            return "PRIME SHARE FAILED: zone exists, but the post would not save.\nShare URL: \(url)"
        }
        return """
        PRIME SHARE OK
          share URL : \(url)
          post record: \(name)
        Both record types now exist in Development. Deploy the schema to \
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

    private static func forgetTokens() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("plated.zonetoken.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func remotePost(from record: CKRecord) -> RemotePost {
        var p = RemotePost()
        p.recordName = record.recordID.recordName
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
    private static func writableZone() async -> (CKDatabase, CKRecordZone.ID)? {
        let mine = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        if (try? await container.privateCloudDatabase.recordZone(for: mine)) != nil {
            return (container.privateCloudDatabase, mine)
        }
        if let shared = try? await container.sharedCloudDatabase.allRecordZones(),
           let zone = shared.first(where: { $0.zoneID.zoneName == zoneName }) {
            return (container.sharedCloudDatabase, zone.zoneID)
        }
        return nil
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
    struct RemotePost { var recordName = ""; var authorName = ""; var authorColorHex = "FF5A3C"
                        var dishTitle = ""; var caption = ""; var kind = "dish"
                        var createdAt = Date.now; var photoData: Data? }
    static func fetchRemote() async -> [RemotePost] { [] }
    struct Seat: Identifiable { var id = ""; var name = ""; var isOwner = false; var isMe = false }
    static func participants() async -> [Seat] { [] }
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
    static func merge(_ remote: [RemotePost], into context: ModelContext) {
        guard !remote.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<TablePost>())) ?? []
        var byRecord: [String: TablePost] = [:]
        for post in existing where !post.shareRecordName.isEmpty {
            byRecord[post.shareRecordName] = post
        }
        for r in remote {
            if let post = byRecord[r.recordName] {
                // Someone edited their caption; plates and comments are ours
                // and are deliberately not overwritten from the wire.
                post.caption = r.caption
                post.dishTitle = r.dishTitle
            } else {
                let post = TablePost(
                    authorName: r.authorName, authorColorHex: r.authorColorHex,
                    dishTitle: r.dishTitle, caption: r.caption, kind: r.kind,
                    isDiscover: false, createdAt: r.createdAt, photoData: r.photoData
                )
                post.shareRecordName = r.recordName
                post.isRemote = true
                context.insert(post)
            }
        }
        Persist.save(context, "table share merge")
    }
}
