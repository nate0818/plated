import Foundation
import SwiftData
import SQLite3

/// THE container — one instance, one schema list, shared by the app and by
/// App Intents servicing Siri while the app is cold. Never build a second
/// ModelContainer over this store: two CloudKit mirrors in one process is a
/// configuration Core Data explicitly does not support, and writes through a
/// second container never merge into the UI's contexts.
enum PlatedStore {
    /// The single source of truth for the model list. New models get added
    /// HERE and nowhere else.
    static let schema = Schema([
        Recipe.self,
        Ingredient.self,
        PlannedMeal.self,
        HouseholdMember.self,
        Gathering.self,
        GroceryItem.self,
        TablePost.self,
        TableComment.self,
        DirectMessage.self,
        RecipePhoto.self,
        PlatedNotification.self,
        HouseholdProfile.self
    ])

    /// `cloudKitDatabase: .automatic` uses the iCloud container when the
    /// entitlement is present and quietly falls back to local-only storage
    /// when it is not, so the app runs without a signing team configured.
    static let shared: ModelContainer = {
        migrateLegacyStoreIfNeeded()
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A schema mismatch during development should be loud, not silent.
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// Adopting the widget app group silently moved SwiftData's default
    /// store location from the app sandbox into the group container —
    /// without this, every pre-widget install wakes up to an empty table.
    ///
    /// Mechanics, in blood: everything stages into a temp directory first
    /// and the main store file moves into place LAST, so a kill at any
    /// point either leaves no group store (next launch retries) or a
    /// complete one. The hidden `.default_SUPPORT` directory rides along —
    /// that's where external-storage photo blobs live; without it every
    /// user photo dangles. The guard probes for actual user rows, because
    /// installs that ran the migration-less intermediate build already
    /// have an auto-created EMPTY group store that must still be replaced.
    /// The legacy files stay behind as a backup.
    private static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard let group = fm.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID
        ) else { return }

        let groupSupport = group.appending(path: "Library/Application Support")
        let newStore = groupSupport.appending(path: "default.store")
        let legacyStore = URL.applicationSupportDirectory.appending(path: "default.store")
        let supportDirName = ".default_SUPPORT"

        let marker = groupSupport.appending(path: ".plated-migration-complete")

        // Once disarmed, forever disarmed — the destructive replace branch
        // below must never re-arm on a later launch, no matter what a
        // transient probe says about the live store.
        if fm.fileExists(atPath: marker.path) { return }
        guard fm.fileExists(atPath: legacyStore.path) else { return }

        if fm.fileExists(atPath: newStore.path) {
            switch probeUserData(at: newStore) {
            case .hasData:
                // Real data lives in the group store; record that verdict so
                // the live store is never probed (or replaced) again.
                try? fm.createDirectory(at: groupSupport, withIntermediateDirectories: true)
                fm.createFile(atPath: marker.path, contents: Data())
                return
            case .unreadable:
                // An unreadable store is precious, not disposable — a
                // transient SQLITE_BUSY months from now must not roll the
                // user back to migration day. No marker, no destruction:
                // just try the probe again next launch.
                return
            case .empty:
                // The auto-created shell from the intermediate build —
                // replacing it is the whole point.
                break
            }
        }

        let staging = group.appending(path: "store-migration-staging")
        // Nothing at the destination is touched until this flips — so a
        // staging-phase failure (disk full, most likely) must clean up
        // nothing but the staging directory itself.
        var destructionBegan = false
        do {
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }

            // Stage copies: sidecars and blobs first, the main file last.
            var moves: [(from: URL, to: URL)] = []
            for suffix in ["-wal", "-shm"] {
                let src = URL(fileURLWithPath: legacyStore.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                let stagedFile = staging.appending(path: "default.store" + suffix)
                try fm.copyItem(at: src, to: stagedFile)
                moves.append((stagedFile, URL(fileURLWithPath: newStore.path + suffix)))
            }
            let legacySupport = legacyStore.deletingLastPathComponent().appending(path: supportDirName)
            if fm.fileExists(atPath: legacySupport.path) {
                let stagedDir = staging.appending(path: supportDirName)
                try fm.copyItem(at: legacySupport, to: stagedDir)
                moves.append((stagedDir, groupSupport.appending(path: supportDirName)))
            }
            let stagedMain = staging.appending(path: "default.store")
            try fm.copyItem(at: legacyStore, to: stagedMain)
            moves.append((stagedMain, newStore))

            // Clear whatever empty/partial store is in the way, then move —
            // same-volume renames are atomic, and until the main file (last
            // in the list) lands, the guard above still allows a retry.
            try fm.createDirectory(at: groupSupport, withIntermediateDirectories: true)
            destructionBegan = true
            for suffix in ["", "-wal", "-shm"] {
                let stale = URL(fileURLWithPath: newStore.path + suffix)
                if fm.fileExists(atPath: stale.path) { try fm.removeItem(at: stale) }
            }
            let staleSupport = groupSupport.appending(path: supportDirName)
            if fm.fileExists(atPath: staleSupport.path) { try fm.removeItem(at: staleSupport) }
            for (from, to) in moves {
                try fm.moveItem(at: from, to: to)
            }

            // Success: disarm forever, and retire the legacy files to a
            // named backup so even a lost marker can't re-arm this branch.
            fm.createFile(atPath: marker.path, contents: Data())
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: legacyStore.path + suffix)
                if fm.fileExists(atPath: src.path) {
                    try? fm.moveItem(at: src, to: URL(fileURLWithPath: legacyStore.path + suffix + ".migrated-backup"))
                }
            }
            if fm.fileExists(atPath: legacySupport.path) {
                try? fm.moveItem(
                    at: legacySupport,
                    to: legacyStore.deletingLastPathComponent().appending(path: supportDirName + ".migrated-backup")
                )
            }
        } catch {
            // Unwind only what this attempt actually wrote. A staging-phase
            // failure never touched the live store — deleting the
            // destination there would turn "failed, unchanged" into
            // "failed, store gone".
            if destructionBegan {
                for suffix in ["", "-wal", "-shm"] {
                    try? fm.removeItem(at: URL(fileURLWithPath: newStore.path + suffix))
                }
                try? fm.removeItem(at: groupSupport.appending(path: supportDirName))
            }
            assertionFailure("Legacy store migration failed: \(error)")
        }
    }

    private enum StoreProbe {
        case hasData, empty, unreadable
    }

    /// What the store at `url` holds. Raw sqlite on purpose: a second
    /// ModelContainer to peek would spin up a second CloudKit mirror.
    /// Checks every user-content table, not just members — a store that was
    /// wiped and then refilled with recipes must still count as data. Any
    /// store that cannot be read confidently is `.unreadable`, and the
    /// caller must treat that as precious.
    private static func probeUserData(at url: URL) -> StoreProbe {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return .unreadable
        }
        defer { sqlite3_close(db) }

        let tables = ["ZHOUSEHOLDMEMBER", "ZRECIPE", "ZPLANNEDMEAL", "ZTABLEPOST"]
        var anyReadable = false
        for table in tables {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK else {
                continue
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { continue }
            anyReadable = true
            if sqlite3_column_int(statement, 0) > 0 { return .hasData }
        }
        return anyReadable ? .empty : .unreadable
    }
}
