import Foundation
import SwiftData
import CloudKit

/// Removal reports what actually happened. A roster label is not proof that
/// an iCloud account accepted an invitation.
@MainActor
enum HouseholdRemoval {
    /// Dialogs can outlive the model while dismissing. Keep only value data
    /// there and resolve the live row by ID when the action is confirmed.
    struct Target {
        let id: PersistentIdentifier
        let name: String
        let firstName: String
        let seat: HouseholdMember.Seat
        let identityKey: String?

        init(_ member: HouseholdMember) {
            id = member.persistentModelID
            name = member.name
            firstName = member.firstName
            seat = member.seat
            identityKey = member.identityKey
        }
    }

    enum Identity: Equatable {
        case linked(String), unlinked, unavailable
    }

    enum Outcome: Equatable {
        case removed, removedUnlinked, notOrganizer, protectedPerson
        case identityUnavailable, householdUnavailable, tableUnavailable, saveFailed

        var succeeded: Bool { self == .removed || self == .removedUnlinked }

        func message(name: String) -> String? {
            switch self {
            case .removed: return nil
            case .removedUnlinked:
                return "Removed \(name)’s saved profile. It wasn’t linked to an iCloud account. Existing invitation links may still work."
            case .notOrganizer: return "Only the household organizer can remove someone."
            case .protectedPerson: return "The organizer can’t be removed from their own household."
            case .identityUnavailable:
                return "Couldn’t verify \(name)’s shared account in iCloud. Their profile is still here. Try again when iCloud is available."
            case .householdUnavailable:
                return "iCloud couldn’t confirm that \(name)’s household access was removed. Try again."
            case .tableUnavailable:
                return "\(name)’s household access was removed, but their Table access couldn’t be updated. Try Remove again to finish."
            case .saveFailed:
                return "Couldn’t save the updated household on this phone. Try Remove again to finish."
            }
        }
    }

    @MainActor
    struct Services {
        var identity: @MainActor (String) async -> Identity
        var household: @MainActor (String) async -> Bool
        var table: @MainActor (String) async -> Bool
        var save: @MainActor (ModelContext, StaticString) -> Bool = { Persist.save($0, $1) }

        static var live: Services {
            #if DEBUG
            if PlatedApp.usesPreviewContainer {
                // UI tests exercise the real workflow against memory-only
                // fixtures. This boundary never reaches either live share.
                let failed = ProcessInfo.processInfo.arguments.contains("-plated-review-removal-unavailable")
                return Services(identity: { _ in failed ? .unavailable : .unlinked },
                    household: { _ in !failed }, table: { _ in !failed })
            }
            #endif
            return Services(identity: { await HouseholdShare.removalIdentity(seat: $0) },
                household: { await HouseholdShare.removeParticipant(userRecordName: $0) },
                table: { await TableShare.remove(seatID: $0) })
        }
    }
}

/// One fetched-share removal path for Household and Table. A retry reads a
/// fresh change tag. Only a confirmed missing record/participant is success;
/// inability to read or save is never interpreted as absence.
enum ShareParticipantRemoval {
    static func remove(_ identity: String, rootID: CKRecord.ID, in database: CKDatabase) async -> Bool {
        guard !identity.isEmpty else { return false }
        for attempt in 0..<3 {
            do {
                let root = try await database.record(for: rootID)
                guard let reference = root.share else { return true }
                guard let share = try await database.record(for: reference.recordID) as? CKShare else { return false }
                guard share.currentUserParticipant?.role == .owner else { return false }
                guard let person = share.participants.first(where: {
                    $0.userIdentity.userRecordID?.recordName == identity
                }) else { return true }
                guard person.role != .owner else { return false }
                share.removeParticipant(person)
                let result = try await database.modifyRecords(saving: [share], deleting: [])
                guard let saved = result.saveResults[share.recordID] else { return false }
                _ = try saved.get()
                return true
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                return true
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                print("PLATED REMOVE: share changed during removal; fetching it again")
            } catch {
                print("PLATED REMOVE: access change failed: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }
}
