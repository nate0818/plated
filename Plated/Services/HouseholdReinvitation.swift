import Foundation
import CryptoKit

/// Backward-compatible access entries in the root's existing string-list field.
/// Plain account IDs remain revocations for older clients. Versioned entries
/// grant a removed account one NEW, owner-published invitation, identified by
/// the hash of its unpredictable seat token. The public root never exposes the
/// token itself. No display name or contact match grants access.
enum HouseholdReinvitation {
    struct Edit: Codable, Equatable, Identifiable {
        enum Action: String, Codable { case revoke, accept }
        var id = UUID()
        var action: Action
        var identity: String
        var seat: String? = nil
    }

    /// Replay intent against the fetched server value, never replace its
    /// access list with a device's stale cache. Acceptance is conditional on
    /// the grant still existing, so a concurrent removal wins.
    static func applying(_ edits: [Edit], to entries: [String]) -> [String] {
        edits.reduce(entries) { current, edit in
            switch edit.action {
            case .revoke: return revoking(edit.identity, entries: current)
            case .accept: return accepting(edit.identity, seat: edit.seat ?? "", entries: current)
            }
        }
    }
    private static let prefix = "plated-reinvite-v1:"

    private static func grant(_ entry: String) -> (identity: String, hash: String)? {
        guard entry.hasPrefix(prefix) else { return nil }
        let parts = entry.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let data = Data(base64Encoded: String(parts[0])),
              let identity = String(data: data, encoding: .utf8), !identity.isEmpty,
              parts[1].count == 64, parts[1].allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return (identity, String(parts[1]))
    }

    private static func hash(_ seat: String) -> String {
        SHA256.hash(data: Data(seat.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func removedIdentities(in entries: [String]) -> [String] {
        entries.filter { !$0.isEmpty && !$0.hasPrefix("plated-reinvite-") }
    }

    static func allows(_ identity: String, seat: String?, entries: [String]) -> Bool {
        guard !identity.isEmpty, removedIdentities(in: entries).contains(identity),
              let seat, !seat.isEmpty else { return false }
        let wanted = hash(seat)
        return entries.contains { grant($0).map { $0.identity == identity && $0.hash == wanted } ?? false }
    }

    /// Presentation proof from the fetched invitation root, never local access
    /// cache, a contact name or a URL's host label. This does not authorize a
    /// join; the existing join path independently checks the current grant.
    struct VerifiedInvitation: Equatable {
        fileprivate let identity: String
        fileprivate let seatHash: String
    }

    static func verifiedInvitation(
        for identity: String, seat: String?, fetchedEntries: [String]?
    ) -> VerifiedInvitation? {
        guard let fetchedEntries, let seat,
              allows(identity, seat: seat, entries: fetchedEntries) else { return nil }
        return VerifiedInvitation(identity: identity, seatHash: hash(seat))
    }

    static func blocks(_ identity: String, seat: String?, entries: [String]) -> Bool {
        removedIdentities(in: entries).contains(identity) && !allows(identity, seat: seat, entries: entries)
    }

    /// Called only by the organizer, and saved to the share BEFORE the link
    /// can leave the app. Possession of a fresh invitation is the credential,
    /// just as it is for a first join. Other removed accounts remain removed.
    static func authorizing(seat: String, entries: [String]) -> [String] {
        guard !seat.isEmpty else { return entries }
        let digest = hash(seat)
        let additions = removedIdentities(in: entries).map {
            prefix + Data($0.utf8).base64EncodedString() + ":" + digest
        }
        return Array(Set(entries + additions)).sorted()
    }

    static func revoking(_ identity: String, entries: [String]) -> [String] {
        guard !identity.isEmpty else { return entries }
        // Even a repeated removal invalidates earlier re-invitations.
        let kept = entries.filter { grant($0)?.identity != identity }
        return Array(Set(kept + [identity])).sorted()
    }

    static func accepting(_ identity: String, seat: String, entries: [String]) -> [String] {
        guard allows(identity, seat: seat, entries: entries) else { return entries }
        // Consume every grant for this account. A later removal cannot make
        // an earlier invitation usable again; other people's blocks remain.
        return entries.filter { $0 != identity && grant($0)?.identity != identity }
    }
}

/// All invitation chrome derives from the same state as its available action.
struct HouseholdInvitationCopy {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let acceptsName: Bool
    let restoresAccess: Bool

    init(
        state: HouseholdSync.JoinPreview.State, host: String, household: String,
        reinvitation: HouseholdReinvitation.VerifiedInvitation? = nil
    ) {
        // A failed join can change a previously verified preview to removed.
        // Its current state wins over any older presentation proof.
        switch state {
        case .ready, .willLeave: restoresAccess = reinvitation != nil
        default: restoresAccess = false
        }
        switch state {
        case .removed:
            eyebrow = "Household access"
            title = "New invitation needed"
            subtitle = "You were removed from \(household). Ask \(host) to update Plated and send a new invitation."
            acceptsName = false
        case .ownShare:
            eyebrow = "Household link"
            title = "This is your household"
            subtitle = nil
            acceptsName = false
        case .hostingWithJoined:
            eyebrow = "Household invitation"
            title = "You already organize a household"
            subtitle = nil
            acceptsName = false
        case .alreadyHere:
            eyebrow = "Household"
            title = "You’re already in \(household)"
            subtitle = nil
            acceptsName = false
        case .needsSeat:
            eyebrow = "Household setup"
            title = "Finish joining \(household)"
            subtitle = nil
            acceptsName = true
        case .ready, .willLeave:
            eyebrow = restoresAccess ? "New household invitation" : "Household invitation"
            title = restoresAccess ? "Rejoin \(household)?" : "Join \(household)?"
            subtitle = restoresAccess
                ? "\(host) invited you back. Joining restores your access to this household’s plan, groceries and cookbook."
                : "\(host) invited you to plan, shop and cook together."
            acceptsName = true
        }
    }
}
