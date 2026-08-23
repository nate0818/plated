import Foundation
import CoreData

/// What the mirror is doing, for the one gesture that asks.
///
/// SwiftData's `cloudKitDatabase: .automatic` is an
/// `NSPersistentCloudKitContainer` underneath, and that class posts its
/// progress on the default notification centre whoever built it. We never
/// touch the container itself — reaching for one would spin up a second
/// mirror, which the store law forbids — we only listen.
enum CloudSync {

    /// Wait for CloudKit to finish pulling, so a pull-to-refresh means
    /// something.
    ///
    /// Resolves on the first completed import, or at `timeout`, whichever
    /// comes first — but never before `floor`, so the refresh control
    /// doesn't flash and snap back in a way that reads as a no-op. An
    /// offline table hits the timeout and that is the correct answer for
    /// it: waited, nothing came.
    static func waitForImport(
        floor: Duration = .milliseconds(450),
        timeout: Duration = .seconds(2)
    ) async {
        async let settled: Void = raceImportAgainst(timeout)
        async let minimumBeat: Void = sleep(floor)
        _ = await (settled, minimumBeat)
    }

    private static func raceImportAgainst(_ timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await nextFinishedImport() }
            group.addTask { await sleep(timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Returns when CloudKit reports an import that has actually ended.
    /// A started-but-unfinished event is not news — `endDate` is the part
    /// that means the records have landed and `@Query` has seen them.
    private static func nextFinishedImport() async {
        let stream = NotificationCenter.default.notifications(
            named: NSPersistentCloudKitContainer.eventChangedNotification
        )
        for await note in stream {
            let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event
            guard let event, event.type == .import, event.endDate != nil else { continue }
            return
        }
    }

    /// Cancellation here is ordinary — the user let go and walked away —
    /// so it is swallowed at the one place that knows it is harmless,
    /// rather than by a `try?` at a call site that then can't tell a
    /// finished wait from an abandoned one.
    private static func sleep(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
