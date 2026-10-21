import Foundation
import Observation

/// Per-device, transient publication attempts. `TablePost.isPublished` remains
/// the durable CloudKit save receipt; this ledger never claims delivery or reads.
@MainActor
@Observable
final class TablePostPublication {
    static let shared = TablePostPublication()

    struct Key: Hashable {
        let account: String
        let destination: String
        let recordName: String

        init(account: String, owner: String, recordName: String, isPublished: Bool = false) {
            self.account = account
            // A published legacy own-zone row uses an empty owner. A new,
            // unassigned post does not yet mean this account's private Table.
            self.destination = owner.isEmpty && isPublished ? account : owner
            self.recordName = recordName
        }
    }

    struct Attempt: Hashable { fileprivate let id = UUID() }
    enum Status: Equatable {
        case saved, waitingForConnection, sending, failed, shared
        var label: String {
            switch self {
            case .saved: "Saved on this device · not shared yet"
            case .waitingForConnection: "Waiting for connection · Your post is saved"
            case .sending: "Sending…"
            case .failed: "Couldn’t share · saved on this device"
            case .shared: "Shared with your Table"
            }
        }
        var symbol: String {
            switch self {
            case .saved, .waitingForConnection: "clock"
            case .sending: "arrow.up.circle"
            case .failed: "exclamationmark.circle"
            case .shared: "checkmark"
            }
        }
    }

    private var attempts: [Attempt: Key] = [:]
    private var failedKeys: Set<Key> = []
    private var deferredRecoveries: Set<Key> = []
    private(set) var recoveryRevision: UInt64 = 0

    /// A real recovery event encountered work already in flight. Remember one
    /// retry request for this exact scope, without replacing that active writer.
    func requestRecovery(for key: Key) {
        guard attempts.values.contains(key) else { return }
        deferredRecoveries.insert(key)
    }

    /// Consume one request immediately before its attempt. Leaving other ready
    /// records queued prevents a new completion or scene change from cancelling
    /// a view task that already removed work it had not reached yet.
    func takeNextReadyRecovery(account: String) -> Key? {
        deferredRecoveries = Set(deferredRecoveries.filter { $0.account == account })
        guard let key = deferredRecoveries.first(where: { !attempts.values.contains($0) }) else { return nil }
        deferredRecoveries.remove(key)
        return key
    }

    /// A request is a chance to recover in the current foreground session.
    /// Returning later supplies a fresh recovery event instead of carrying an
    /// old account, audience or background request into a new session.
    func discardRecoveries() {
        deferredRecoveries.removeAll()
    }

    func status(
        for key: Key, isPublished: Bool,
        connection: NetworkAvailability.State = .unknown
    ) -> Status {
        if attempts.values.contains(key) { return .sending }
        // A second failed overlapping attempt, or a failed edit that rolls
        // back locally, cannot undo an acknowledged existing publication.
        if isPublished { return .shared }
        // Generic failures, a not-yet-observed path and a path requiring
        // connection never imply offline. A known current path outage can
        // explain why this saved, unpublished post is waiting.
        if connection == .unavailable { return .waitingForConnection }
        return failedKeys.contains(key) ? .failed : .saved
    }

    /// A path recovery is a chance to retry existing saved work while the
    /// Table is foregrounded, not a promise of background delivery. Changing
    /// these inputs cancels the view task; the writer still verifies account
    /// identity and the post's own destination before each CloudKit save.
    struct RecoveryContext: Equatable {
        let connection: NetworkAvailability.State
        let isForeground: Bool
        let isTableActive: Bool
        let isPreview: Bool
        let isIdentityReady: Bool

        var permitsRetry: Bool {
            connection == .available && isForeground && isTableActive && !isPreview && isIdentityReady
        }
    }

    /// Coalesce recovery/pull requests while an older CloudKit pass finishes.
    /// A newly recovered path must not lose its retry just because the earlier
    /// cancelled task is still awaiting CloudKit. One follow-up consumes all
    /// requests received during that pass; no request means no retry loop.
    struct BacklogPass {
        private var running = false
        private var requested = false

        mutating func begin() -> Bool {
            guard !running else { requested = true; return false }
            running = true
            return true
        }

        mutating func finish() -> Bool {
            running = false
            let followUp = requested
            requested = false
            return followUp
        }
    }

    @discardableResult
    func begin(_ key: Key) -> Attempt {
        let attempt = Attempt()
        attempts[attempt] = key
        failedKeys.remove(key)
        return attempt
    }

    /// Destination resolution and first-account confirmation may happen while
    /// preflight is running. Move only this attempt; other work keeps its scope.
    func move(_ attempt: Attempt, to key: Key) {
        guard let previous = attempts[attempt] else { return }
        attempts[attempt] = key
        if deferredRecoveries.contains(previous) {
            // Resolve only an unchosen destination in the same account. A
            // known audience or account changing cannot transfer retry intent.
            if previous.account == key.account && previous.recordName == key.recordName
                && (previous.destination == key.destination || previous.destination.isEmpty) {
                deferredRecoveries.insert(key)
            }
            if !attempts.values.contains(previous) { deferredRecoveries.remove(previous) }
        }
    }

    func finish(_ attempt: Attempt, succeeded: Bool) {
        guard let key = attempts.removeValue(forKey: attempt) else { return }
        if succeeded {
            failedKeys.remove(key)
            deferredRecoveries.remove(key)
        } else {
            failedKeys.insert(key)
            if deferredRecoveries.contains(key), !attempts.values.contains(key) {
                recoveryRevision &+= 1
            }
        }
    }

    func clear() {
        attempts.removeAll()
        failedKeys.removeAll()
        deferredRecoveries.removeAll()
        recoveryRevision &+= 1
    }

    /// A pending row may retain the exact placeholder captured by this
    /// attempt while its account is confirmed. An unrelated placeholder is
    /// another author's row, not permission to adopt any offline content.
    /// Empty authors retain the existing legacy-local publication path.
    static func mayPublish(authorID: String, initialAccount: String, confirmedAccount: String) -> Bool {
        guard mayContinue(from: initialAccount, as: confirmedAccount) else { return false }
        return authorID.isEmpty || authorID == confirmedAccount
            || (initialAccount.hasPrefix("local-") && authorID == initialAccount)
    }

    /// A local placeholder can resolve to the real account. A known account
    /// changing to another account must never carry an in-flight post with it.
    static func mayContinue(from initialAccount: String, as confirmedAccount: String) -> Bool {
        !confirmedAccount.isEmpty && !confirmedAccount.hasPrefix("local-")
            && (initialAccount == confirmedAccount || initialAccount.hasPrefix("local-"))
    }
}
