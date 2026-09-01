import Foundation
import CloudKit
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
    private static let postType = "TablePost"

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
                return url
            }

            let share = CKShare(rootRecord: root)
            let shareTitle: String = "\(tableTitle) on Plated"
            share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
            // Invite-only by design. A public URL would make the Table a
            // broadcast surface, which is the opposite of the product.
            share.publicPermission = .none

            let saved = try await db.modifyRecords(saving: [root, share], deleting: [])
            _ = saved
            return share.url
        } catch {
            return nil
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
                          record.recordType == postType else { continue }
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
