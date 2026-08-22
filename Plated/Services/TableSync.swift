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
        #if PLATED_CLOUDKIT
        let status = (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine
        return status == .available
        #else
        return false
        #endif
    }

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
