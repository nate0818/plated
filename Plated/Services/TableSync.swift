import Foundation
import CloudKit

/// Phase 3 scaffolding for real multi-household Tables.
///
/// The architecture: each Table becomes a CKShare-backed record zone; setting
/// a place sends a share invitation, and accepted seats sync TablePosts both
/// ways. All of that requires the iCloud entitlement and a signing team —
/// see README "Turning on iCloud sync". Until that's wired, this service
/// reports capability honestly and composes the invite people actually send
/// today: a message.
enum TableSync {
    /// Whether this build can reach CloudKit at all. Gated on the
    /// PLATED_CLOUDKIT compile flag, set alongside the iCloud capability
    /// (see README) — CKContainer must never be touched in an unentitled
    /// build, where its missing-entitlement failure is an Objective-C
    /// exception `try?` cannot catch. Callers treat `false` as "local
    /// table" — never as an error.
    static func accountAvailable() async -> Bool {
        await accountState() == .available
    }

    /// Why the table is or isn't leaving this device. The boolean above
    /// could only say "no", which is why nothing ever called it — a warning
    /// a user cannot act on is one you don't show. This says which thing to
    /// go and fix.
    enum AccountState: Equatable {
        case available
        /// Signed out of iCloud entirely.
        case noAccount
        /// Managed device, parental controls, or iCloud Drive switched off.
        case restricted
        /// A real account that iCloud could not reach right now. Usually
        /// the network, and usually temporary — worth saying so, since
        /// "unavailable" reads as broken when it means "later".
        case temporarilyUnavailable
        /// Built without the entitlement. Never shown; the local table is
        /// the honest and expected state for such a build.
        case notArmed

        var isSyncing: Bool { self == .available }

        /// Plain, and never alarming: nothing is lost, it just isn't leaving.
        var line: String? {
            switch self {
            case .available, .notArmed: return nil
            case .noAccount:
                return "Sign in to iCloud in Settings and your table follows you to every device."
            case .restricted:
                return "iCloud is switched off for Plated, so your table stays on this phone."
            case .temporarilyUnavailable:
                return "iCloud can't be reached right now. Your table is safe here and will sync when it's back."
            }
        }
    }

    static func accountState() async -> AccountState {
        #if PLATED_CLOUDKIT
        do {
            switch try await CKContainer.default().accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            default: return .temporarilyUnavailable
            }
        } catch {
            return .temporarilyUnavailable
        }
        #else
        return .notArmed
        #endif
    }

    #if DEBUG
    /// Deletes every mirrored record from the private database by dropping
    /// Core Data's mirror zone, then removes the local group store — the
    /// zone tombstone would wipe it on the next armed launch anyway, so the
    /// purge leaves a true clean slate rather than trusting the operator to
    /// reinstall. Maintenance path for the `-plated-purge-cloud` launch
    /// flag, which also forces the store local-only for the run (see
    /// PlatedStore) so nothing re-exports while the zone falls. Debug-only
    /// structurally: a shipped binary must not contain this path at all.
    static func purgeMirroredData() async throws {
        #if PLATED_CLOUDKIT
        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
        _ = try await CKContainer.default().privateCloudDatabase
            .deleteRecordZone(withID: zoneID)
        removeLocalStore()
        #else
        throw NSError(
            domain: "Plated", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "This build is not armed with PLATED_CLOUDKIT — nothing was purged."
            ]
        )
        #endif
    }

    /// The group store and its sidecars, gone. The app exits immediately
    /// after the purge, so deleting under the open local-only container is
    /// a closing act, not a live mutation.
    private static func removeLocalStore() {
        let fm = FileManager.default
        guard let group = fm.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetBridge.appGroupID
        ) else { return }
        let support = group.appending(path: "Library/Application Support")
        for name in ["default.store", "default.store-wal", "default.store-shm",
                     ".default_SUPPORT", "default_ckAssets"] {
            try? fm.removeItem(at: support.appending(path: name))
        }
    }
    #endif

    /// The message a host sends with an invitation. Once CloudKit sharing is
    /// live this carries the CKShare URL; today it sets expectations honestly.
    static func inviteMessage(hostName: String) -> String {
        let host = hostName.isEmpty ? "I" : hostName
        return """
        \(host) set a place for you at our table on Plated — a private, \
        invite-only feed of what we're actually cooking. \
        The app is in early testing; your seat is saved and your invite \
        will be first out the door.
        """
    }
}
