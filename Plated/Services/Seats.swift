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
///
/// **Two rooms** (docs/household.md §1). A household invitation lays a seat
/// in the roster and shares the plan; a Table invitation shares what people
/// cook and never creates a `HouseholdMember`. `Kind` says which door, and
/// nothing below ever adds a participant to a share: the link is the
/// credential, and `addParticipant` on a public share raises an exception
/// `try?` cannot catch.
@MainActor
enum Seats {

    enum Kind: String {
        case household, table
    }

    /// What `prepareInvite` handed back: the link, and the name it was
    /// minted for. Carried through the composer so `confirmSent` records
    /// exactly the seat or entry the message named.
    struct Prepared: Equatable {
        var outcome: TableShare.InviteOutcome
        /// Household: the seat record name inside the link.
        var seat: String?
        /// Table: the `TableInvites` entry id inside the link.
        var invite: String?
        /// Why there is no link, when the caller knows something the
        /// outcome cannot say — a request that ran out of clock, say.
        /// `noLinkReason` answers for everything else.
        var reason: String?

        static let noCloud = Prepared(outcome: .noCloud, seat: nil, invite: nil)

        /// A request that never came back. A timeout is not a signed-out
        /// account, and saying so sent people to Settings over a slow
        /// network (DESIGN.md, Honesty).
        static let timedOut = Prepared(
            outcome: .noCloud, seat: nil, invite: nil,
            reason: "iCloud is taking too long. Check your connection and try again."
        )
    }

    /// Why this phone has no household link to hand over, in words that are
    /// true. Four call sites said "Sign in to iCloud" for every failure,
    /// including the one it is never true for: a member, who does not mint a
    /// household link at all (§9), being told to sign in to an account they
    /// are already signed into.
    static func noLinkReason(_ prepared: Prepared? = nil) -> String {
        if HouseholdShare.membership.owner != nil {
            let host = HouseholdShare.cachedOwnerName
                .split(separator: " ").first.map(String.init) ?? ""
            return "Only \(host.isEmpty ? "the host" : host) can invite people to this household."
        }
        if let reason = prepared?.reason, !reason.isEmpty { return reason }
        return "Sign in to iCloud to send an invite link."
    }

    // MARK: Inviting somebody real

    /// Step one: mint the link that opens the room. Creates no row — nobody
    /// has been told anything yet.
    ///
    /// The household door mints the zone, the root and both shares on first
    /// use. The host's first invitation is also the moment the household
    /// starts publishing (§6): `publishAll` runs once, on the transition
    /// out of `.solo`, so the plan is on its way before the message is.
    static func prepareInvite(kind: Kind, hostName: String) async -> Prepared {
        switch kind {
        case .household:
            guard let url = await householdURL(hostName: hostName) else {
                print("PLATED HOUSEHOLD: no household link to send")
                return .noCloud
            }
            let seat = HouseholdShare.mintSeatName()
            let link = Invitation.wrapped(url, hostName: hostName, kind: .household, seat: seat, invite: nil)
            print("PLATED HOUSEHOLD: household link ready for seat \(seat)")
            return Prepared(outcome: .ready(link), seat: seat, invite: nil)

        case .table:
            // `invite` rather than `invitationURL` alone: it is the same
            // membership-aware URL, plus the one repair a table minted
            // before the link became the credential still needs (its
            // share opened to the link). It adds no participant.
            let outcome = await TableShare.invite(phone: nil, email: nil, hostName: hostName)
            guard case .ready(let url) = outcome else {
                print("PLATED HOUSEHOLD: no table link to send")
                return Prepared(outcome: outcome, seat: nil, invite: nil)
            }
            // The entry is not recorded until the composer says the message
            // went; only its id is minted now so the link can carry it.
            let invite = UUID().uuidString
            let link = Invitation.wrapped(url, hostName: hostName, kind: .table, seat: nil, invite: invite)
            print("PLATED HOUSEHOLD: table link ready for invitation \(invite)")
            return Prepared(outcome: .ready(link), seat: nil, invite: invite)
        }
    }

    /// A link that names no seat and no invitation, for handing over by any
    /// road but Messages (Copy link, Share a link). Whoever joins picks
    /// their seat on arrival (§7).
    static func shareableLink(kind: Kind, hostName: String) async -> URL? {
        switch kind {
        case .household:
            guard let url = await householdURL(hostName: hostName) else { return nil }
            return Invitation.wrapped(url, hostName: hostName, kind: .household, seat: nil, invite: nil)
        case .table:
            guard case .ready(let url) = await TableShare.invite(phone: nil, email: nil, hostName: hostName) else {
                return nil
            }
            return Invitation.wrapped(url, hostName: hostName, kind: .table, seat: nil, invite: nil)
        }
    }

    /// The household's live link, with the one rule that always goes with
    /// minting it: the host's first invitation is also the moment the
    /// household starts publishing (§6). Three doors mint this link and the
    /// rule was written on two of them, so a Send again from a household
    /// that had never shared turned it `.hosting` with an empty outbox: no
    /// plan, no cookbook, no roster, and a joiner who accepted into an
    /// empty zone and could not find the seat the link named.
    ///
    /// The transition lives here rather than in `HouseholdShare`, which
    /// must not depend on `HouseholdSync` or the store.
    private static func householdURL(hostName: String) async -> URL? {
        let wasSolo = HouseholdShare.membership == .solo
        guard let url = await HouseholdShare.invitationURL(hostName: hostName) else { return nil }
        if wasSolo {
            print("PLATED HOUSEHOLD: first invitation, publishing the household")
            HouseholdSync.publishAll(in: PlatedStore.shared.mainContext)
        }
        return url
    }

    /// Step two, and the only door to `.invited`: the message actually sent.
    ///
    /// Household: the seat row, named after the seat inside the link, so the
    /// joiner's claim lands on this row and no other. The observer pushes
    /// it. Table: an entry in `TableInvites`, and no row at all.
    static func confirmSent(
        kind: Kind, prepared: Prepared, name: String, phone: String?, email: String?,
        role: String, in context: ModelContext
    ) {
        // The number as the directory spells it, so the host's row and a
        // later lookup agree; the raw string is kept when it cannot be
        // read as a number rather than thrown away.
        let number = phone.flatMap { raw -> String? in
            let clean = raw.trimmingCharacters(in: .whitespaces)
            return clean.isEmpty ? nil : (Directory.normalize(clean) ?? clean)
        }
        guard case .ready = prepared.outcome else { return }

        switch kind {
        case .household:
            let member = HouseholdMember(
                name: name,
                colorHex: nextTone(in: context),
                role: role,
                roleLine: roleLine(for: role),
                seat: .invited,
                phoneE164: number,
                inviteEmail: email,
                invitedAt: .now,
                shareRecordName: prepared.seat
            )
            member.authorID = TableIdentity.cached
            context.insert(member)
            Persist.save(context, "seat invited")
            // Push now, not after the 1.5s save debounce: the joiner can
            // open the link in the next breath, and a named seat that is
            // not in the zone yet used to make them mint a second one.
            HouseholdOutbox.shared.enqueueUpsert(.seat, member.shareRecordName)
            HouseholdInviteLog.record(
                name: name, phone: number, email: email, seat: prepared.seat
            )
            print("PLATED HOUSEHOLD: seat \(member.shareRecordName) invited for \(name)")
            Task { await HouseholdOutbox.shared.drain(context: context) }

        case .table:
            guard let id = prepared.invite else { return }
            TableInvites.shared.record(
                TableInvites.Entry(id: id, name: name, phone: number, email: email, sentAt: .now)
            )
        }
        // Invite APNs is not live. Calling the directory here would fire a
        // banner the UI no longer offers, so the text is the only notice.
    }

    /// The composer was cancelled. Nothing to take back (§6): no row was
    /// inserted, no entry recorded, and no participant was ever added to a
    /// share. The seat name inside the link simply never gets claimed.
    static func abandon(kind: Kind, prepared: Prepared) {
        print("PLATED HOUSEHOLD: \(kind.rawValue) invitation abandoned before sending")
    }

    /// Send the same live link again to someone who hasn't answered: the
    /// same seat, so a second message cannot lay a second place.
    static func resend(_ member: HouseholdMember, hostName: String) async -> Prepared {
        guard member.seat == .invited else { return .noCloud }
        guard let url = await householdURL(hostName: hostName) else { return .noCloud }
        // Read after the mint, never before: on a household that had not
        // published, `publishAll`'s `ensureRecordNames` is what gives this
        // row a name, and the link has to carry the named seat rather than
        // an empty one.
        let seat = member.shareRecordName
        let link = Invitation.wrapped(url, hostName: hostName, kind: .household, seat: seat, invite: nil)
        return Prepared(outcome: .ready(link), seat: seat, invite: nil)
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
            roleLine: roleLine(for: role),
            seat: .notOnPlated
        )
        member.authorID = TableIdentity.cached
        context.insert(member)
        return member
    }

    static func isTaken(_ name: String, in context: ModelContext) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespaces).lowercased()
        return all(in: context).contains { $0.name.lowercased() == clean }
    }

    // MARK: Taking a seat back

    /// The only door out of the roster (§8). Host only. A joined person is
    /// taken off both shares first, and on any refusal nothing local
    /// changes: the caller says so rather than showing a seat that is gone
    /// here and still open on their phone.
    static func remove(_ member: HouseholdMember, in context: ModelContext) async -> Bool {
        let members = all(in: context)
        guard members.me?.isOwner == true else {
            print("PLATED HOUSEHOLD: only the head of table removes a seat")
            return false
        }
        let hosting = HouseholdShare.membership == .hosting

        switch member.seat {
        case .head:
            return false
        case .joined:
            // Identity is the only key on a public share (§1); a joined row
            // without one cannot be evicted, and pretending otherwise would
            // leave them reading the plan.
            guard let identity = member.userRecordName ?? member.participantID, !identity.isEmpty else {
                print("PLATED HOUSEHOLD: \(member.name) has no identity to remove")
                return false
            }
            guard await HouseholdShare.removeParticipant(userRecordName: identity) else { return false }
            // Same person, same record name on the Table share. The
            // household eviction is the one that matters for the plan, so
            // it gates; a refusal here is said and not fatal, because a
            // second attempt could no longer find them on the household
            // share and would refuse forever.
            if !(await TableShare.remove(seatID: identity)) {
                print("PLATED HOUSEHOLD: \(member.name) is off the household but still at the Table")
            }
            HouseholdOutbox.shared.enqueueDelete(.seat, member.shareRecordName)
            appendRemovedID(identity)
        case .invited, .notOnPlated, .left:
            // Nothing on any share. The seat record still has to go if the
            // household has been published; a phone that never shared has
            // no zone to delete from and nothing queued.
            if hosting {
                HouseholdOutbox.shared.enqueueDelete(.seat, member.shareRecordName)
            }
        }

        // Their nights go back to unplanned rather than to whoever the
        // rota picks next; nobody was asked to cook them.
        for meal in member.assignedMeals ?? [] { meal.cook = nil }
        let gone = "\(member.name) (\(member.seat.rawValue))"
        context.delete(member)
        print("PLATED HOUSEHOLD: removed \(gone)")
        return true
    }

    /// A removed identity is refused at join and never seated again (§8).
    /// The list lives on the root; the cache is what `localRoot` reads when
    /// the root entry is pushed.
    private static func appendRemovedID(_ identity: String) {
        var ids = HouseholdShare.cachedRemovedIDs
        guard !ids.contains(identity) else { return }
        ids.append(identity)
        if let data = try? JSONEncoder().encode(ids) {
            HouseholdShare.groupDefaults.set(data, forKey: HouseholdShare.Keys.removedIDs)
        }
        HouseholdOutbox.shared.enqueueRoot()
    }

    // MARK: Roles

    /// The host changes what somebody is to the household (§10). Demoting
    /// away from the pan clears the nights they held, because a kid with a
    /// standing Tuesday is a rota that hands Tuesday to nobody.
    static func changeRole(_ member: HouseholdMember, to role: String, in context: ModelContext) {
        member.role = role
        member.roleLine = roleLine(for: role)
        if role != "owner", role != "partner" {
            member.cookWeekdays = []
        }
    }

    /// The short line a role earns. Never the seat: that is `subtitle`'s.
    static func roleLine(for role: String) -> String {
        switch role {
        case "owner": return "Head of table"
        case "partner": return "Partner"
        case "kid": return "Kid"
        default: return "Member"
        }
    }

    // MARK: Keeping the table honest

    /// Fold what CloudKit knows about the household share into the roster.
    /// Host only: a member's roster arrives by merge, and the standings a
    /// member can read are the same list the host writes from.
    ///
    /// A joiner creates or claims their own seat record (§7), so nothing is
    /// ever inserted here. What this corroborates is the participant list:
    /// a seat that arrived `.joined` gets its `participantID`; a `.joined`
    /// seat whose identity is missing from a successfully read list has
    /// left. An empty list is not read as anybody leaving, because an empty
    /// answer and a failed one look the same from here.
    ///
    /// An Invited row whose person has accepted the share but whose claim
    /// never landed (or landed under a fresh UUID the host never saw) is
    /// promoted here when the match is unambiguous — phone, email, first
    /// name, or the sole open invitation. Leaving Invited forever after a
    /// real accept is the Alessandra bug.
    static func reconcile(in context: ModelContext) async {
        guard case .hosting = HouseholdShare.membership else { return }
        let standings = await HouseholdShare.standings()
        guard !standings.isEmpty else { return }
        let members = all(in: context)
        let accepted = standings.filter(\.accepted)

        for standing in accepted {
            guard let match = match(standing, in: members) else { continue }
            switch match.seat {
            case .joined:
                if match.participantID == nil { match.participantID = standing.participantID }
            // An `.invited` or `.notOnPlated` row is NOT promoted from a
            // standing that already matches by identity alone — see
            // `migrateTableSeats`. Promotion of a still-empty Invited is
            // `inviteToClaim` below.
            case .invited, .notOnPlated, .head, .left:
                break
            }
        }

        var claimed = false
        for standing in accepted {
            if let invite = inviteToClaim(for: standing, among: members) {
                claimInvite(invite, with: standing, in: context)
                claimed = true
            }
        }
        if claimed { Persist.save(context, "invited seats claimed from share") }
        for member in all(in: context) where member.seat == .joined {
            HouseholdInviteLog.markSettled(name: member.name)
        }

        // Do NOT retire joined seats when they are missing from standings.
        // A partial or identity-less participant list used to delete real
        // household members and enqueue CloudKit seat deletes — that is how
        // recovery paths erased people. Leave is `.left` on the seat record
        // or an explicit Remove (`removeParticipant`). Missing from a
        // standings snapshot is not enough.
    }

    /// Which Invited row an accepted share participant should settle, if
    /// any. Nil when the person is already seated, when nothing is waiting,
    /// or when more than one invitation could be them.
    static func inviteToClaim(
        for standing: TableShare.Standing,
        among members: [HouseholdMember]
    ) -> HouseholdMember? {
        guard standing.accepted else { return nil }
        guard let id = standing.participantID, !id.isEmpty else { return nil }
        if match(standing, in: members) != nil { return nil }

        let open = members.filter {
            $0.seat == .invited
                && ($0.userRecordName ?? "").isEmpty
                && ($0.participantID ?? "").isEmpty
        }
        guard !open.isEmpty else { return nil }

        if let phone = standing.phone?.trimmingCharacters(in: .whitespaces), !phone.isEmpty {
            let want = Directory.normalize(phone) ?? phone
            let hits = open.filter {
                let have = $0.phoneE164 ?? ""
                guard !have.isEmpty else { return false }
                return have == phone || have == want || (Directory.normalize(have) ?? have) == want
            }
            if hits.count == 1 { return hits[0] }
        }
        if let email = standing.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !email.isEmpty {
            let hits = open.filter {
                ($0.inviteEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
            }
            if hits.count == 1 { return hits[0] }
        }
        let key = firstNameKey(standing.name)
        if !key.isEmpty {
            let hits = open.filter { firstNameKey($0.name) == key }
            if hits.count == 1 { return hits[0] }
        }
        // Sole open invitation and an accepted person with no other seat:
        // they are that invitation. Two open invitations stay ambiguous.
        if open.count == 1 { return open[0] }
        return nil
    }

    /// A standing that `inviteToClaim` cannot take — the Invited row was
    /// already promoted, or never existed — still has a local seat that
    /// is this person. Minting another row is how "New member" outlived
    /// Alessandra on the host's phone.
    static func attachableRow(
        for standing: TableShare.Standing,
        among members: [HouseholdMember]
    ) -> HouseholdMember? {
        if let invite = inviteToClaim(for: standing, among: members) { return invite }
        guard standing.accepted else { return nil }
        if match(standing, in: members) != nil { return nil }

        let unmatched = members.filter {
            $0.seat != .left && $0.seat != .head
                && ($0.userRecordName ?? "").isEmpty
                && ($0.participantID ?? "").isEmpty
                && !$0.isMe
        }
        guard !unmatched.isEmpty else { return nil }

        let key = firstNameKey(standing.name)
        if !key.isEmpty {
            let hits = unmatched.filter { firstNameKey($0.name) == key }
            if hits.count == 1 { return hits[0] }
        }
        let named = unmatched.filter { !HouseholdIdentity.isUnnamed($0.name) }
        if named.count == 1 { return named[0] }
        let unnamedJoined = unmatched.filter {
            $0.seat == .joined && HouseholdIdentity.isUnnamed($0.name)
        }
        if unnamedJoined.count == 1, named.isEmpty { return unnamedJoined[0] }
        return nil
    }

    private static func firstNameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map { $0.lowercased() } ?? ""
    }

    /// A name the People list can print. CloudKit's share participant is
    /// first, then the invitation this phone actually sent, then the
    /// restored placeholder — never a blank row.
    static func displayName(standingName: String, remembered: String?) -> String {
        let ck = standingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !HouseholdIdentity.isUnnamed(ck) { return ck }
        if let remembered, !HouseholdIdentity.isUnnamed(remembered) { return remembered }
        return "New member"
    }

    /// What a People row should draw right now. Bind writes this onto the
    /// seat; the list still asks here so a known invite/share name cannot
    /// stay "New member" for one more frame, and so the reader's own
    /// subtitle cannot be Head of table even if `isMe` is late.
    static func resolvedDisplay(
        for member: HouseholdMember,
        among members: [HouseholdMember],
        reader: HouseholdMember? = nil
    ) -> (name: String, subtitle: String, photo: Data?) {
        let mine = member.isMe
            || (reader != nil && reader!.persistentModelID == member.persistentModelID)
        var name = member.name
        var photo = member.photoData
        if HouseholdIdentity.isRestoredPlaceholder(name) {
            name = resolvedName(for: member, among: members) ?? name
        }
        if photo == nil {
            photo = resolvedPhoto(for: member, among: members)
        }
        let subtitle = mine ? "You" : member.subtitle
        return (name, subtitle, photo)
    }

    static func resolvedName(
        for member: HouseholdMember,
        among members: [HouseholdMember]
    ) -> String? {
        if !HouseholdIdentity.isRestoredPlaceholder(member.name) { return member.name }
        if member.isMe || member.isOwner || member.seat == .head { return member.name }
        if let id = member.identityKey,
           let named = members.first(where: {
               $0.identityKey == id && !HouseholdIdentity.isUnnamed($0.name)
           }) {
            return named.name
        }
        if let neighbor = namedUnidentifiedNeighbor(of: member, among: members) {
            return neighbor.name
        }
        if let remembered = HouseholdInviteLog.rememberedName(
            forPhone: member.phoneE164,
            email: member.inviteEmail,
            seat: member.shareRecordName.isEmpty ? nil : member.shareRecordName
        ) {
            return remembered
        }
        if let id = member.identityKey, let learned = TableNews.name(for: id),
           !HouseholdIdentity.isUnnamed(learned) {
            return learned
        }
        return nil
    }

    private static func resolvedPhoto(
        for member: HouseholdMember,
        among members: [HouseholdMember]
    ) -> Data? {
        if let photo = member.photoData { return photo }
        if let id = member.identityKey,
           let pictured = members.first(where: {
               $0.identityKey == id && $0.photoData != nil
           }) {
            return pictured.photoData
        }
        return namedUnidentifiedNeighbor(of: member, among: members)?.photoData
    }

    /// One named seat with no CloudKit id next to one unnamed identified
    /// join is the same person: the host's Invited "Alessandra" and the
    /// restored "New member" that actually accepted.
    private static func namedUnidentifiedNeighbor(
        of member: HouseholdMember,
        among members: [HouseholdMember]
    ) -> HouseholdMember? {
        guard member.seat == .joined,
              member.identityKey != nil,
              HouseholdIdentity.isRestoredPlaceholder(member.name) else { return nil }
        let named = members.filter {
            $0 !== member
                && $0.seat != .left && $0.seat != .head
                && !HouseholdIdentity.isUnnamed($0.name)
                && $0.identityKey == nil
                && !$0.isMe && !$0.isOwner
        }
        return named.count == 1 ? named[0] : nil
    }

    private static func bindName(from standing: TableShare.Standing, onto member: HouseholdMember) {
        let incoming = standing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !HouseholdIdentity.isUnnamed(incoming) else { return }
        if HouseholdIdentity.isUnnamed(member.name) {
            member.name = incoming
        }
    }

    /// After a join, a restored accept, or a zone merge: if the share or a
    /// twin seat already names this person, write that name and photograph
    /// onto the row People draws. "New member" with a green N is what
    /// happens when the host mints a seat before the joiner's push lands.
    @discardableResult
    static func bindShareIdentity(
        in context: ModelContext,
        standings: [TableShare.Standing]
    ) -> Int {
        let members = all(in: context)
        var changed = 0
        for row in members where row.seat == .joined || row.seat == .head {
            let beforeName = row.name
            let beforePhoto = row.photoData
            let standing = standings.first { match($0, in: [row]) != nil }
            if let standing {
                bindName(from: standing, onto: row)
            }
            if HouseholdIdentity.isRestoredPlaceholder(row.name),
               !row.isMe, !row.isOwner, row.seat != .head {
                if let resolved = resolvedName(for: row, among: members) {
                    row.name = resolved
                } else {
                    let remembered = HouseholdInviteLog.rememberedName(
                        forPhone: row.phoneE164 ?? standing?.phone,
                        email: row.inviteEmail ?? standing?.email,
                        seat: row.shareRecordName.isEmpty ? nil : row.shareRecordName
                    )
                    if let remembered { row.name = remembered }
                }
            }
            if row.photoData == nil, let photo = resolvedPhoto(for: row, among: members) {
                row.photoData = photo
            }
            if let id = row.identityKey {
                let twins = members.filter {
                    $0 !== row && $0.identityKey == id
                        && ($0.seat == .joined || $0.seat == .head)
                }
                if HouseholdIdentity.isUnnamed(row.name),
                   let named = twins.first(where: { !HouseholdIdentity.isUnnamed($0.name) }) {
                    row.name = named.name
                }
                if row.photoData == nil,
                   let pictured = twins.first(where: { $0.photoData != nil }) {
                    row.photoData = pictured.photoData
                }
            }
            if row.name != beforeName || row.photoData != beforePhoto {
                changed += 1
                if !HouseholdIdentity.isUnnamed(row.name) {
                    HouseholdInviteLog.markSettled(name: row.name)
                }
                if !row.shareRecordName.isEmpty {
                    HouseholdOutbox.shared.enqueueUpsert(.seat, row.shareRecordName)
                }
                print("PLATED HOUSEHOLD: bound share identity onto \(row.name)")
            }
        }
        if changed > 0 { Persist.save(context, "bound share identity") }
        return changed
    }

    private static func claimInvite(
        _ invite: HouseholdMember,
        with standing: TableShare.Standing,
        in context: ModelContext
    ) {
        let id = standing.participantID ?? ""
        invite.userRecordName = id
        invite.participantID = id
        if invite.seat != .joined { invite.seat = .joined }
        if invite.joinedAt == nil { invite.joinedAt = .now }
        bindName(from: standing, onto: invite)
        if !invite.shareRecordName.isEmpty {
            HouseholdOutbox.shared.enqueueUpsert(.seat, invite.shareRecordName)
        }
        print("PLATED HOUSEHOLD: Invited \(invite.name) settled from share accept (\(id.prefix(12)))")
    }

    /// Host pull / Home open: settle Invited rows and restore anyone who
    /// accepted the share but has no seat on this phone.
    static func settleStuckInvites(in context: ModelContext) async {
        // Local names first. Waiting on CloudKit is how TF26 kept drawing
        // "New member" over an invite log that already knew Alessandra.
        bindShareIdentity(in: context, standings: [])
        _ = await HouseholdShare.refreshMembership()
        print("PLATED HOUSEHOLD: settleStuckInvites membership=\(String(describing: HouseholdShare.membership))")
        guard case .hosting = HouseholdShare.membership else {
            print("PLATED HOUSEHOLD: settleStuckInvites skipped, not hosting")
            return
        }
        await reconcile(in: context)
        await restoreUnmatchedAccepts(in: context)
        collapseOrphanInvites(in: context)
        let standings = await HouseholdShare.standings()
        bindShareIdentity(in: context, standings: standings)
    }

    /// Invited + joined twin with the same first name: fold the twin's
    /// identity onto the invitation's seat record (the one the link named),
    /// then drop the twin. Never delete the Invited row alone — that erased
    /// Alessandra when Invited was her only roster entry.
    private static func collapseOrphanInvites(in context: ModelContext) {
        let members = all(in: context)
        var orphans = HouseholdSync.orphanInvites(among: members)
        if orphans.isEmpty {
            // First names do not match when the joined twin is still
            // "New member". One named invite and one unnamed identified
            // join are still the same person.
            let open = members.filter {
                $0.seat == .invited
                    && ($0.userRecordName ?? "").isEmpty
                    && !HouseholdIdentity.isUnnamed($0.name)
            }
            let unnamedJoined = members.filter {
                $0.seat == .joined
                    && $0.identityKey != nil
                    && HouseholdIdentity.isRestoredPlaceholder($0.name)
            }
            if open.count == 1, unnamedJoined.count == 1 {
                orphans = open
            }
        }
        guard !orphans.isEmpty else { return }
        for invite in orphans {
            let key = firstNameKey(invite.name)
            let unnamedJoined = members.filter {
                $0 !== invite
                    && $0.seat == .joined
                    && $0.identityKey != nil
                    && HouseholdIdentity.isRestoredPlaceholder($0.name)
                    && $0.shareRecordName != invite.shareRecordName
            }
            guard let twin = members.first(where: {
                $0 !== invite
                    && ($0.seat == .joined || $0.seat == .head)
                    && !($0.userRecordName ?? "").isEmpty
                    && $0.shareRecordName != invite.shareRecordName
                    && (firstNameKey($0.name) == key
                        || (HouseholdIdentity.isRestoredPlaceholder($0.name) && unnamedJoined.count == 1))
            }) else { continue }
            let id = twin.userRecordName ?? twin.participantID ?? ""
            invite.userRecordName = twin.userRecordName
            invite.participantID = twin.participantID ?? twin.userRecordName
            if invite.seat != .joined { invite.seat = .joined }
            if invite.joinedAt == nil { invite.joinedAt = twin.joinedAt ?? .now }
            if invite.name.isEmpty || HouseholdIdentity.isUnnamed(invite.name) {
                invite.name = twin.name
            }
            if invite.photoData == nil { invite.photoData = twin.photoData }
            for meal in twin.assignedMeals ?? [] { meal.cook = invite }
            if !invite.shareRecordName.isEmpty {
                HouseholdOutbox.shared.enqueueUpsert(.seat, invite.shareRecordName)
            }
            if !twin.shareRecordName.isEmpty {
                HouseholdOutbox.shared.enqueueDelete(.seat, twin.shareRecordName)
            }
            print("PLATED HOUSEHOLD: folded orphan twin \(twin.shareRecordName) onto invite seat \(invite.shareRecordName) for \(invite.name) (\(id.prefix(12)))")
            context.delete(twin)
        }
        Persist.save(context, "orphan invites folded")
    }

    /// An accepted share participant with no roster row at all — for example
    /// after a bad clear of their Invited seat — gets a joined seat back.
    @discardableResult
    static func restoreUnmatchedAccepts(in context: ModelContext) async -> Int {
        let standings = await HouseholdShare.standings()
        let accepted = standings.filter(\.accepted)
        guard !accepted.isEmpty else {
            print("PLATED HOUSEHOLD: restoreUnmatchedAccepts — no accepted participants on the share")
            return 0
        }
        var members = all(in: context)
        var restored = 0
        for standing in accepted {
            let id = standing.participantID ?? ""
            if !id.isEmpty, match(standing, in: members) != nil { continue }
            if id.isEmpty {
                let key = firstNameKey(standing.name)
                if !key.isEmpty,
                   members.contains(where: {
                       firstNameKey($0.name) == key && ($0.seat == .joined || $0.seat == .head)
                   }) {
                    continue
                }
            }
            // Prefer an existing named Invited / unnamed join over minting
            // a fresh "New member" twin that then wins occupying.
            if let existing = attachableRow(for: standing, among: members) {
                claimInvite(existing, with: standing, in: context)
                members = all(in: context)
                restored += 1
                continue
            }
            let ckName = standing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let remembered = HouseholdInviteLog.rememberedName(
                forPhone: standing.phone, email: standing.email, seat: nil
            )
            let name = displayName(standingName: ckName, remembered: remembered)
            let phone = standing.phone ?? HouseholdInviteLog.unsettled(against: members)
                .first { !$0.name.isEmpty && $0.name.caseInsensitiveCompare(name) == .orderedSame }?.phone
            let row = HouseholdMember(
                name: name,
                colorHex: nextTone(in: context),
                role: "partner",
                roleLine: roleLine(for: "partner"),
                seat: .joined,
                phoneE164: phone,
                inviteEmail: standing.email,
                invitedAt: nil,
                shareRecordName: HouseholdShare.mintSeatName()
            )
            if !id.isEmpty {
                row.userRecordName = id
                row.participantID = id
            }
            row.joinedAt = .now
            row.authorID = TableIdentity.cached
            context.insert(row)
            HouseholdOutbox.shared.enqueueUpsert(.seat, row.shareRecordName)
            if !row.name.isEmpty { HouseholdInviteLog.markSettled(name: row.name) }
            print("PLATED HOUSEHOLD: restored joined seat for \(row.name) id=\(id.isEmpty ? "nil" : String(id.prefix(12)))")
            members = all(in: context)
            restored += 1
        }
        bindShareIdentity(in: context, standings: standings)
        // Rename any blank "New member" / "Someone" using the invite log.
        // Not the owner's "Me": that is a prompt, not a restored accept.
        for row in all(in: context)
        where row.seat == .joined
            && !row.isMe && !row.isOwner
            && HouseholdIdentity.isRestoredPlaceholder(row.name) {
            if let remembered = HouseholdInviteLog.rememberedName(
                forPhone: row.phoneE164,
                email: row.inviteEmail,
                seat: row.shareRecordName.isEmpty ? nil : row.shareRecordName
            ) {
                row.name = remembered
                HouseholdInviteLog.markSettled(name: remembered)
                if !row.shareRecordName.isEmpty {
                    HouseholdOutbox.shared.enqueueUpsert(.seat, row.shareRecordName)
                }
                print("PLATED HOUSEHOLD: renamed restored seat to \(remembered)")
            }
        }
        if restored > 0 {
            Persist.save(context, "restored accepted seats")
            Haptic.kiss()
        } else {
            print("PLATED HOUSEHOLD: restoreUnmatchedAccepts — nothing to restore (\(accepted.count) on share, \(members.count) local)")
        }
        return restored
    }

    /// Host tapped "They're in" on an Invited row. Promotes that seat to
    /// joined in place — never deletes, never runs share-retire.
    static func markInviteArrived(_ member: HouseholdMember, in context: ModelContext) async {
        guard member.seat == .invited else { return }
        guard case .hosting = HouseholdShare.membership else { return }
        let name = member.name
        let id = member.persistentModelID

        let standings = await HouseholdShare.standings()
        let accepted = standings.filter(\.accepted)
        let roster = all(in: context)
        if let standing = accepted.first(where: { inviteToClaim(for: $0, among: roster) != nil }),
           let invite = inviteToClaim(for: standing, among: roster),
           invite.persistentModelID == id {
            claimInvite(invite, with: standing, in: context)
            Persist.save(context, "host marked invite arrived from share")
            await restoreUnmatchedAccepts(in: context)
            Haptic.kiss()
            return
        }

        guard let still = all(in: context).first(where: { $0.persistentModelID == id }),
              still.seat == .invited else {
            await restoreUnmatchedAccepts(in: context)
            return
        }

        let seated = Set(all(in: context).compactMap { row -> String? in
            let id = row.userRecordName ?? row.participantID ?? ""
            return id.isEmpty ? nil : id
        })
        if let standing = accepted.first(where: {
            guard let pid = $0.participantID, !pid.isEmpty else { return false }
            return !seated.contains(pid)
        }) {
            claimInvite(still, with: standing, in: context)
        } else {
            still.seat = .joined
            if still.joinedAt == nil { still.joinedAt = .now }
            if !still.shareRecordName.isEmpty {
                HouseholdOutbox.shared.enqueueUpsert(.seat, still.shareRecordName)
            }
            print("PLATED HOUSEHOLD: host marked \(name) joined in place")
        }
        Persist.save(context, "host marked invite arrived")
        await restoreUnmatchedAccepts(in: context)
        Haptic.kiss()
    }

    /// The row a standing belongs to. Identity only (§1): link joiners are
    /// public participants with no phone or email on the share, so an
    /// address can never be the key, and matching on one inserted a fresh
    /// "Someone new" for such a person on every reconcile, on every device.
    static func match(_ standing: TableShare.Standing, in members: [HouseholdMember]) -> HouseholdMember? {
        guard let id = standing.participantID, !id.isEmpty else { return nil }
        return members.first { $0.userRecordName == id || $0.participantID == id }
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
        if migrateTableSeats(in: context) { changed = true }
        return changed
    }

    /// Rows seated from the Table (§8, last paragraph). Every `.joined` row
    /// that predates the household share was seated by `reconcile` from
    /// the Table's participants; those people hold no household share and
    /// cannot see the plan. Once, while nothing has been published, each
    /// becomes `.notOnPlated` keeping its `participantID`, and the bell
    /// says so, so the host knows the seat still has to be given.
    @discardableResult
    static func migrateTableSeats(in context: ModelContext) -> Bool {
        let key = "didMigrateTableSeats"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        guard HouseholdShare.membership == .solo else { return false }
        UserDefaults.standard.set(true, forKey: key)
        var changed = false
        for member in all(in: context) where member.seat == .joined {
            member.seat = .notOnPlated
            changed = true
            Notifier.postKeyed(
                eventKey: "table-seat:\(member.participantID ?? member.name)",
                .seatJoined, actor: member.firstName,
                body: "\(member.firstName) is at your Table but not in your household yet. Invite them from Home to share the plan.",
                link: DeepLink.url(.home).absoluteString,
                into: context
            )
            print("PLATED HOUSEHOLD: \(member.name) was seated from the Table, now not on Plated")
        }
        return changed
    }

    // MARK: Plumbing

    /// The person holding this phone.
    static func me(in context: ModelContext) -> HouseholdMember? {
        all(in: context).me
    }

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
