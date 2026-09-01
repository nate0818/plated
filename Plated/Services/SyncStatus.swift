import Foundation
import SwiftData
import Observation

/// What the app knows about whether this table is leaving the device, and
/// whether the last write actually landed.
///
/// Deliberately not a banner. Plated does not nag: both of these live as a
/// quiet line in Settings, where someone who suspects something is wrong
/// goes to look. The exception is a failed save, which is the one case
/// where silence is a lie — the user watched something happen on screen
/// that did not happen on disk.
@MainActor
@Observable
final class SyncStatus {
    static let shared = SyncStatus()

    private(set) var account: TableSync.AccountState = .notArmed
    /// Set when a write failed. Sticky until acknowledged: a save failure
    /// that clears itself on the next screen is a save failure nobody sees.
    private(set) var saveFailed = false

    private init() {}

    func refresh() async {
        account = await TableSync.accountState()
    }

    func noteSaveFailure() { saveFailed = true }
    func acknowledgeSaveFailure() { saveFailed = false }
}

/// One place that writes, so one place can notice when writing fails.
///
/// `Persist.save(context)` was scattered across eight call sites, which meant
/// a full disk, a schema conflict or a validation failure looked exactly
/// like success. It stays non-throwing at the call site — no caller wants
/// to grow a `do/catch` around adding a grocery item — but the failure now
/// reaches somewhere a person can see it.
enum Persist {
    @MainActor
    static func save(_ context: ModelContext, _ what: StaticString = "") {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Not a crash: the object is still live in memory and the user's
            // work is on screen. What must not happen is pretending it was
            // written.
            print("PLATED SAVE FAILED [\(what)]: \(error)")
            SyncStatus.shared.noteSaveFailure()
        }
    }
}
