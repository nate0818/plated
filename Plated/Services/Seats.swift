import Foundation
import SwiftData

/// The one place a seat at the table is created, changed, or taken back.
///
/// **Why it exists.** Three screens each hand-rolled their own idea of
/// membership and no two agreed: a `HouseholdMember` row with no state, an
/// `@AppStorage` string of pending names that only one sheet could see, and
/// the CloudKit share's real participants that nothing consulted. Two
/// buttons labelled "Add" under the same heading did different things
/// depending on which sheet you were standing in, and the one screen called
/// "Add someone to the household" did the one thing that reached nobody.
///
/// **The rule.** A seat's state is never asserted, only recorded from
/// something that verifiably happened — a composer that reported `.sent`, a
/// participant CloudKit says has accepted. Nothing here ever writes
/// `.invited` or `.joined` on optimism.
@MainActor
enum Seats {

    // MARK: Inviting somebody real

    /// Step one: bind them to the share and get the link that opens it.
    /// Creates no row — nobody has been told anything yet.
    static func prepareInvite(phone: String?, email: String?, hostName: String) async
        -> TableShare.InviteOutcome {
        await TableShare.invite(phone: phone, email: email, hostName: hostName)
    }

    /// Step two, and the only door to `.invited`: the message actually sent.
    @discardableResult
    static func confirmSent(
        name: String, phone: String?, email: String?,
        role: String = "member", in context: ModelContext
    ) -> HouseholdMember {
        let member = HouseholdMember(
            name: name,
            colorHex: nextTone(in: context),
            role: role,
            seat: .invited,
            phoneE164: phone,
            inviteEmail: email,
            invitedAt: .now
        )
        context.insert(member)
        return member
    }

    /// The composer was cancelled. Take the participant back off the share:
    /// a door left open for somebody who was never told it exists is worse
    /// than no door.
    static func abandon(phone: String?, email: String?) async {
        await TableShare.revokeInvite(phone: phone, email: email)
    }

    /// Send the same live link again to someone who hasn't answered.
    static func resend(_ member: HouseholdMember, hostName: String) async
        -> TableShare.InviteOutcome {
        await TableShare.invite(
            phone: member.phoneE164, email: member.inviteEmail, hostName: hostName
        )
    }

    // MARK: Keeping a place for somebody who isn't coming

    /// The by-name door. A kid, a grandparent, anyone who won't be getting
    /// the app — a full seat, and honest about being one.
    @discardableResult
    static func layPlace(name: String, role: String, in context: ModelContext) -> HouseholdMember? {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !isTaken(clean, in: context) else { return nil }
        let member = HouseholdMember(
            name: clean,
            colorHex: nextTone(in: context),
            role: role,
            seat: .notOnPlated
        )
        context.insert(member)
        return member
    }

    static func isTaken(_ name: String, in context: ModelContext) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespaces).lowercased()
        return all(in: context).contains { $0.name.lowercased() == clean }
    }

    // MARK: Taking a seat back

    /// Removing somebody means it on the share too, when there is one to
    /// mean it on. Returns false only when iCloud was needed and refused —
    /// the caller says so rather than pretending the seat is gone.
    static func remove(_ member: HouseholdMember, in context: ModelContext) async -> Bool {
        switch member.seat {
        case .joined:
            guard let id = member.participantID else { break }
            guard await TableShare.remove(seatID: id) else { return false }
        case .invited:
            await TableShare.revokeInvite(phone: member.phoneE164, email: member.inviteEmail)
        case .head, .notOnPlated:
            break
        }
        context.delete(member)
        return true
    }

    // MARK: Keeping the table honest

    /// Fold what CloudKit knows into what we show. Runs at launch, when a
    /// share is accepted, and whenever a people screen appears.
    ///
    /// Matching is on the address the invitation went to, because that is
    /// the only thing a pending participant carries — it has no user record
    /// until the moment it accepts, which is why an earlier attempt to key
    /// on that produced a fresh identity on every single fetch.
    static func reconcile(in context: ModelContext) async {
        let standings = await TableShare.standings()
        guard !standings.isEmpty else { return }
        let members = all(in: context)

        for standing in standings where standing.accepted {
            let match = members.first { member in
                (standing.phone != nil && member.phoneE164 == standing.phone)
                    || (standing.email != nil && member.inviteEmail == standing.email)
            }
            if let match {
                guard match.seat != .joined else { continue }
                match.seat = .joined
                match.joinedAt = .now
                match.participantID = standing.participantID
                if !standing.name.isEmpty { match.name = standing.name }
                Notifier.post(
                    .general, actor: match.firstName,
                    body: "\(match.firstName) joined. They can see the plan now.",
                    into: context
                )
                Haptic.kiss()
            } else {
                // They got the link some other way. A seat is a seat.
                let member = HouseholdMember(
                    name: standing.name.isEmpty ? "Someone new" : standing.name,
                    colorHex: nextTone(in: context),
                    role: "member",
                    seat: .joined,
                    phoneE164: standing.phone,
                    inviteEmail: standing.email
                )
                member.joinedAt = .now
                member.participantID = standing.participantID
                context.insert(member)
            }
        }
    }

    /// One-time repair of tables that predate the seat.
    ///
    /// Every existing hand-typed row becomes `.notOnPlated`, which is the
    /// truth about all of them, and the old pending-names string becomes
    /// real `.invited` rows — a message did go to those people, so their
    /// seat survives; nothing recorded when, so `invitedAt` stays nil and
    /// the row says "Invited a while back" rather than inventing a date.
    static func migrate(in context: ModelContext, pendingSeats: String) -> Bool {
        let members = all(in: context)
        var changed = false

        for member in members where member.isOwner && member.seat != .head {
            member.seat = .head
            changed = true
        }

        let pending = pendingSeats
            .split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        for name in pending where !isTaken(name, in: context) {
            let member = HouseholdMember(
                name: name,
                colorHex: nextTone(in: context),
                role: "member",
                seat: .invited
            )
            context.insert(member)
            changed = true
        }
        return changed
    }

    // MARK: Plumbing

    static func all(in context: ModelContext) -> [HouseholdMember] {
        (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? []
    }

    /// A colour nobody at this table is already wearing. The old rule was
    /// `count % rotation.count`, which shifts every time somebody is
    /// removed and lands the fourth person on the reserved tomato.
    private static func nextTone(in context: ModelContext) -> String {
        let taken = Set(all(in: context).map(\.colorHex))
        return PersonTone.rotation.dropFirst().first { !taken.contains($0) }
            ?? PersonTone.rotation.dropFirst().first
            ?? "3DA35D"
    }
}
