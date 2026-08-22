import Foundation
import SwiftData

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
    /// One-time, copy-then-leave: the legacy files stay behind as a backup.
    private static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard let group = fm.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID
        ) else { return }

        let groupSupport = group.appending(path: "Library/Application Support")
        let newStore = groupSupport.appending(path: "default.store")
        let legacyStore = URL.applicationSupportDirectory.appending(path: "default.store")
        guard !fm.fileExists(atPath: newStore.path),
              fm.fileExists(atPath: legacyStore.path) else { return }

        do {
            try fm.createDirectory(at: groupSupport, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: legacyStore.path + suffix)
                let to = URL(fileURLWithPath: newStore.path + suffix)
                if fm.fileExists(atPath: from.path) {
                    try fm.copyItem(at: from, to: to)
                }
            }
        } catch {
            // A failed copy leaves the group location empty; better to run
            // fresh than to crash the launch over a migration.
            assertionFailure("Legacy store migration failed: \(error)")
        }
    }
}
