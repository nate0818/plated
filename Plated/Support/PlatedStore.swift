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
        DirectMessage.self
    ])

    /// `cloudKitDatabase: .automatic` uses the iCloud container when the
    /// entitlement is present and quietly falls back to local-only storage
    /// when it is not, so the app runs without a signing team configured.
    static let shared: ModelContainer = {
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
}
