import XCTest
import SwiftData
@testable import Plated

/// A reminder rebuild is intentionally delayed so a burst of plan edits
/// becomes one Notification Center transaction. The delay must not extend a
/// SwiftData context beyond the lifetime of the container that owns it.
@MainActor
final class NotificationSchedulerLifetimeTests: XCTestCase {

    func testDebouncedPlanRebuildDoesNotRetainATransientContext() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "remindersOn")
        defaults.set(false, forKey: "remindersOn")
        defer {
            if let previous {
                defaults.set(previous, forKey: "remindersOn")
            } else {
                defaults.removeObject(forKey: "remindersOn")
            }
        }

        try scheduleFromTransientStore()

        // The production debounce is 250 ms. With the old implementation,
        // this is where its retained ModelContext fetched after the local
        // ModelContainer had been released and trapped the test process.
        try await Task.sleep(for: .milliseconds(400))
    }

    private func scheduleFromTransientStore() throws {
        let container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [
                ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            ]
        )
        let context = container.mainContext
        context.insert(PlannedMeal(date: .now, customTitle: "Transient dinner"))
        XCTAssertTrue(Persist.save(context, "transient reminder regression"))
    }
}
