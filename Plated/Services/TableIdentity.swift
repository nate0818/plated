import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

/// This user, in CloudKit's terms.
///
/// The first stable identity the app has ever had for a person. Everything
/// today keys on first names: `isMine`, `seatCount`, `members.photo(forAuthor:)`,
/// `PersonRef.author`. Two people called Sam break the app in about six
/// places, and the code already carries comments admitting it. A record name
/// is the thing that does not collide, does not change when somebody edits
/// their profile, and is the same string on every one of that person's
/// devices.
///
/// Stored in the app group beside the change tokens rather than in
/// `UserDefaults.standard`: one home for sync state, so nothing has to
/// remember which half lives where.
enum TableIdentity {
    private static let key = "plated.userRecordName"

    private static var store: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    /// The cached id, or a persisted local placeholder.
    ///
    /// Synchronous on purpose. A SwiftUI body cannot await, and a plate
    /// tapped on a plane still has to be attributed to somebody — the write
    /// goes into the outbox under this id and is re-stamped when CloudKit
    /// finally answers.
    static var cached: String {
        if let existing = store.string(forKey: key), !existing.isEmpty { return existing }
        let placeholder = "local-\(UUID().uuidString)"
        store.set(placeholder, forKey: key)
        return placeholder
    }

    static var isPlaceholder: Bool { cached.hasPrefix("local-") }

    /// Ask CloudKit who this is, and remember.
    ///
    /// Returns nil when it could not ask. It never re-derives a placeholder
    /// while offline: minting a fresh `local-` id on an offline launch would
    /// orphan everything already queued under the previous one.
    @discardableResult
    static func confirm() async -> String? {
        #if canImport(CloudKit)
        guard let id = try? await CKContainer.default().userRecordID() else { return nil }
        let name = id.recordName
        guard !name.isEmpty else { return nil }
        if store.string(forKey: key) != name {
            store.set(name, forKey: key)
        }
        return name
        #else
        return nil
        #endif
    }

    /// The Apple ID changed underneath us.
    ///
    /// Without this, `cached` keeps answering with the previous account's
    /// id: the outbox drains writes minted under the old identity into the
    /// new account's zone, and plates are attributed to a stranger. The
    /// change tokens go too, because they describe a zone this account has
    /// never read.
    @MainActor
    static func reset() {
        store.removeObject(forKey: key)
        TableOutbox.shared.clear()
        TableLedger.shared.clear()
        for k in store.dictionaryRepresentation().keys
        where k.hasPrefix("plated.zonetoken.") {
            store.removeObject(forKey: k)
        }
        for k in UserDefaults.standard.dictionaryRepresentation().keys
        where k.hasPrefix("plated.zonetoken.") {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
}
