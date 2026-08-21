import SwiftUI
import SwiftData

@main
struct PlatedApp: App {
    /// One container for the whole app. `cloudKitDatabase: .automatic` uses the
    /// iCloud container when the entitlement is present and quietly falls back
    /// to local-only storage when it is not, so the app runs for anyone who
    /// clones the repo without a signing team configured.
    let container: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            Ingredient.self,
            PlannedMeal.self,
            HouseholdMember.self,
            Gathering.self,
            GroceryItem.self
        ])
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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
