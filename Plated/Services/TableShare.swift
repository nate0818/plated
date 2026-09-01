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

    static func fetchRemote() async -> [RemotePost] {
        guard await TableSync.accountAvailable() else { return [] }
        let db = container.sharedCloudDatabase
        var found: [RemotePost] = []
        do {
            let zones = try await db.allRecordZones()
            for zone in zones where zone.zoneID.zoneName == zoneName {
                let query = CKQuery(
                    recordType: postType,
                    predicate: NSPredicate(value: true)
                )
                query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                let (results, _) = try await db.records(
                    matching: query, inZoneWith: zone.zoneID, resultsLimit: 200
                )
                for (_, result) in results {
                    guard let record = try? result.get() else { continue }
                    found.append(remotePost(from: record))
                }
            }
        } catch {
            return found
        }
        return found
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
