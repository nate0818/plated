import SwiftUI
import SwiftData

/// Everyone with a seat at your table, opened from the avatar cluster in
/// the Table header. One source per group (docs/household.md §9): the
/// roster is the household, the share's participants are the friends at
/// the table, `TableInvites` is who was actually sent a link, and the
/// shared database is the tables this person joined on their own. The
/// legacy pending-names string was a fourth notion of "invited" that
/// reconciled with none of them, and it is gone.
struct TableSeatsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    // An author is the one thing every real post has. The empty-name
    // rows are blanks the CloudKit mirror adopts (TablePost.isBlank),
    // and counting them puts a dish on the board nobody cooked.
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover && !$0.authorName.isEmpty }) private var storedPosts: [TablePost]
    private var posts: [TablePost] { storedPosts.filter(\.isUserContent) }

    @AppStorage("userFirstName") private var userFirstName = ""

    /// A friend at the table who is not in the household: a participant on
    /// the Table share, named as well as the share and their posts allow.
    struct Guest: Identifiable, Equatable {
        var id: String
        var name: String
        var colorHex: String?
        var tone: PersonTone { colorHex.map(PersonTone.from(hex:)) ?? .neutralPair }
    }

    /// A table joined on its own, not the household's.
    struct JoinedTable: Identifiable, Equatable {
        var owner: String
        var title: String
        var id: String { owner }
    }

    /// The Table's link, asked for once. Three states, never one: while
    /// CloudKit is still answering, the sheet must not say there is no
    /// link, and once it has answered it must not keep promising one.
    enum LinkState: Equatable {
        case asking
        case ready(URL)
        case missing
    }

    /// Which group a refusal belongs under, so the sentence sits beside
    /// the row it is about rather than at the foot of a long sheet.
    enum Group: Equatable { case household, table, invited, joined, invite }
    struct Problem: Equatable {
        var group: Group
        var text: String
    }

    /// One dialog at a time, keyed on the thing it is about. The seat rows
    /// have no swipe state to put back, so this is simpler than Home's.
    enum Dialog {
        case removeMember(HouseholdMember)
        case removeGuest(Guest)
        case leave(JoinedTable)
    }

    /// Nil while CloudKit is still being asked. The groups drawn from
    /// these show nothing until the answer lands, because an empty group
    /// is a claim that nobody is there, and it is only true once the
    /// share has actually been read.
    @State private var participants: [TableShare.Seat]?
    @State private var joinedTables: [JoinedTable]?
    /// Nil until asked. When the answer is anything but available, the
    /// sheet says so once above the groups rather than letting an empty
    /// participant list read as an empty table.
    @State private var reach: TableSync.AccountState?
    @State private var link: LinkState = .asking
    /// Table invitations this phone sent, from the book written only when
    /// the composer reported the message went.
    @State private var invites = TableInvites.shared
    @State private var dialog: Dialog?
    @State private var problem: Problem?

    /// Only the host edits seats (docs/household.md §8, §9). On a member's
    /// phone `me` is the claimed seat, never the head, so this is false
    /// there without a membership check.
    private var readerIsHead: Bool { members.readable.me?.isOwner == true }

    /// The people at the table who are not in the household: the share's
    /// participants minus every identity the roster already carries, minus
    /// me, once each. Identity is the only key (§1): link joiners carry no
    /// phone or email on the share, so a name can never be the match.
    private var guests: [Guest] {
        guard let participants else { return [] }
        var known = Set<String>()
        for member in members {
            if let id = member.userRecordName, !id.isEmpty { known.insert(id) }
            if let id = member.participantID, !id.isEmpty { known.insert(id) }
        }
        // On a member's phone the host is in the roster by definition, so
        // the owner participant is never a guest even if the head's row
        // has not been stamped with an identity yet.
        if let owner = HouseholdShare.membership.owner { known.insert(owner) }
        var seen = Set<String>()
        return participants.compactMap { seat in
            guard !seat.isMe, !known.contains(seat.id), seen.insert(seat.id).inserted else { return nil }
            // iOS hands over a participant's name only when it can look
            // the identity up, which for a link joiner it often cannot.
            // `participants()` spells the blank as "Someone"; their posts
            // are the next best source, keyed on the same identity.
            let named = seat.name.trimmingCharacters(in: .whitespaces)
            let theirs = posts.first { $0.authorID == seat.id }
            if !named.isEmpty, named != "Someone" {
                return Guest(id: seat.id, name: named, colorHex: theirs?.authorColorHex)
            }
            if let theirs, !theirs.authorName.isEmpty {
                return Guest(id: seat.id, name: theirs.authorName, colorHex: theirs.authorColorHex)
            }
            return Guest(id: seat.id, name: "Someone at your table", colorHex: nil)
        }
    }

    /// Everyone at the table, each once: the roster, the friends the
    /// roster does not hold, and the invitations that actually went.
    private var headCount: Int {
        members.count + guests.count + invites.pending.count
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel(headCount.things("person", "people"))
                // On every phone: a member's Table is the household's own
                // (§9), so it is theirs too.
                Text("Your table")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    reachLine

                    // The roster is the household on every phone, subtitled
                    // by seat and role (§10): the same sentence Home prints,
                    // so the two screens cannot disagree about what somebody
                    // is.
                    seatGroup("Household", problem: .household) {
                        let people = members.readable.listed
                        let reader = people.me
                        ForEach(people, id: \.persistentModelID) { member in
                            memberRow(member, reader: reader, among: people)
                        }
                    }

                    if !guests.isEmpty || problem?.group == .table {
                        seatGroup("At your table", problem: .table) {
                            ForEach(guests) { guest in
                                guestRow(guest)
                            }
                        }
                    }

                    // Invitations that actually went (§9). An entry that
                    // never settles can always be cancelled by hand.
                    if !invites.pending.isEmpty || problem?.group == .invited {
                        seatGroup("Invited to the table", problem: .invited) {
                            ForEach(invites.pending) { entry in
                                invitedRow(entry)
                            }
                        }
                    }

                    // Leaving the household's own Table is Leave household,
                    // in Settings; only tables joined on their own are
                    // listed here, and `joinedTables()` already leaves the
                    // household's out.
                    if let joinedTables, !joinedTables.isEmpty || problem?.group == .joined {
                        seatGroup("Tables you've joined", problem: .joined) {
                            ForEach(joinedTables) { table in
                                joinedRow(table)
                            }
                        }
                    }

                    inviteRow
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 30)
                .animation(.plSnap, value: guests)
                .animation(.plSnap, value: joinedTables)
                .animation(.plSnap, value: invites.pending)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .task {
            Seats.bindShareIdentity(in: context, standings: [])
            // Everything CloudKit is asked at once; the roster is local and
            // already on screen. `reach` lands with the answers rather than
            // before them, because it is what says whether an empty list
            // means nobody or means the share could not be read.
            async let state = TableSync.accountState()
            async let seats = TableShare.participants()
            async let tables = TableShare.joinedTables()
            // Membership-aware: on a member's phone this is the household's
            // link off the root, and nothing is minted.
            async let url = TableShare.invitationURL(hostName: userFirstName)
            let (answered, found, joined, minted) = await (state, seats, tables, url)
            withAnimation(.plSnap) {
                reach = answered
                participants = found
                joinedTables = joined.map { JoinedTable(owner: $0.owner, title: $0.title) }
                link = minted.map(LinkState.ready) ?? .missing
            }
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } }),
            titleVisibility: .visible
        ) {
            dialogButtons
        } message: {
            Text(dialogMessage)
        }
    }

    // MARK: Could not ask

    /// Said once, above the groups. The roster below is local; everything
    /// else is what the last successful read brought, and nothing read
    /// now.
    @ViewBuilder
    private var reachLine: some View {
        if let reach, reach != .available, reach != .notArmed {
            Text("Can't reach iCloud. The people below are what last arrived.")
                .plType(.caption, .semibold)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }

    // MARK: Rows

    private func memberRow(
        _ member: HouseholdMember,
        reader: HouseholdMember?,
        among people: [HouseholdMember]
    ) -> some View {
        let drawn = Seats.resolvedDisplay(for: member, among: people, reader: reader)
        let isMe = member.isMe
            || (reader != nil && reader!.persistentModelID == member.persistentModelID)
        seatRow(
            name: drawn.name,
            subtitle: drawn.subtitle,
            // Colour is earned by being here. An invitation is the one
            // unresolved thing, so it stays grey until they arrive. The
            // reader's own row is neutral (§10); on a member's phone the
            // host keeps their colour.
            tone: (isMe || !member.showsColor) ? .neutralPair : member.tone,
            photo: drawn.photo
        ) {
            // `messageURL` rather than a boolean: a Message button is only
            // honest where there is somewhere for the message to go, and
            // never for the reader's own row.
            if let url = member.messageURL {
                discButton("bubble.right", label: "Message \(member.name)") {
                    openURL(url)
                }
            }
            // The head keeps their seat, and only the head takes one away.
            if readerIsHead, !member.isOwner {
                discButton("minus", label: "Remove \(member.name)") {
                    dialog = .removeMember(member)
                }
            }
        }
    }

    private func guestRow(_ guest: Guest) -> some View {
        seatRow(name: guest.name, subtitle: "Sees what you cook", tone: guest.tone) {
            // A CloudKit participant is an identity, not a contact: the
            // share carries no number we are allowed to open, so there is
            // no Message here. Only the owner edits participants, so Remove
            // is the head's alone.
            if readerIsHead {
                discButton("minus", label: "Remove \(guest.name)") {
                    dialog = .removeGuest(guest)
                }
            }
        }
    }

    private func invitedRow(_ entry: TableInvites.Entry) -> some View {
        seatRow(
            name: entry.name,
            subtitle: "Invited \(HouseholdMember.when(entry.sentAt))",
            tone: .neutralPair
        ) {
            // Send again IS the message to them, so no separate Message
            // disc: three controls on one row left no room for a name.
            // Without Messages the control would open a blank composer.
            if InviteComposer.isAvailable {
                discButton("paperplane", label: "Send \(entry.name) the link again") {
                    sendAgain(entry)
                }
            }
            discButton("minus", label: "Cancel \(entry.name)'s invitation") {
                withAnimation(.plSnap) { invites.cancel(entry.id) }
            }
        }
    }

    private func joinedRow(_ table: JoinedTable) -> some View {
        seatRow(
            name: table.title,
            subtitle: "You see what they cook",
            tone: .neutralPair
        ) {
            // A verb that names the outcome, not a glyph: leaving is the
            // one thing this row offers, and "minus" would read as taking
            // the host off a list they are not on.
            Button {
                Haptic.tap()
                dialog = .leave(table)
            } label: {
                Text("Leave")
                    .plType(.footnote, .bold)
                    .plActionLabel()
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 34)
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Leave \(table.title)")
        }
    }

    /// The row every group shares: a face, a name, the one true sentence
    /// under it, and whatever controls the group earns on the right.
    private func seatRow(
        name: String, subtitle: String, tone: PersonTone, photo: Data? = nil,
        @ViewBuilder controls: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(initials: initials(for: name), tone: tone, size: 40, photo: photo)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .plName()
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            controls()
        }
        .padding(.vertical, 10)
    }

    /// The one container every icon control on a row wears. Message and
    /// Remove are peers on one row and were once drawn as unlike things: a
    /// contained disc beside a bare glyph, and the bare one in inkFaint,
    /// which is the tone this app reserves for a control that is
    /// genuinely off. Remove is not off.
    private func discButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .plTapTarget()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private func seatGroup(_ label: String, problem group: Group, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(label)
            VStack(spacing: 0) { rows() }
                .padding(.horizontal, 14)
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
            if let problem, problem.group == group {
                ProblemRow(problem.text)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
    }

    // MARK: The dialog

    private var dialogTitle: String {
        switch dialog {
        case .removeMember(let member): return "Remove \(member.name) from the household?"
        case .removeGuest(let guest): return "Remove \(guest.name) from your table?"
        case .leave(let table): return "Leave \(table.title)?"
        case nil: return ""
        }
    }

    /// What is true for this seat (§8), and nothing more.
    private var dialogMessage: String {
        switch dialog {
        case .removeMember(let member):
            switch member.seat {
            case .joined:
                return "\(member.firstName) loses the plan, the grocery list and the cookbook. Their own recipes stay in the cookbook."
            case .invited:
                // Not "the invitation stops working": the household link is
                // the credential (§1), and a joiner whose named seat is gone
                // is given a fresh one (`HouseholdSync.claimSeat`). Saying
                // the link is dead would be a claim the app cannot keep.
                return "Their seat goes away. If they still open the link, they get a new seat."
            case .head, .notOnPlated, .left:
                return "Nothing gets sent to them."
            }
        case .removeGuest:
            return "They stop seeing what everyone here cooks."
        case .leave:
            return "You'll stop seeing their dishes. Nothing you've cooked is deleted."
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private var dialogButtons: some View {
        switch dialog {
        case .removeMember(let member):
            Button("Remove \(member.name)", role: .destructive) {
                Task { await remove(member) }
            }
        case .removeGuest(let guest):
            Button("Remove \(guest.name)", role: .destructive) {
                Task { await remove(guest) }
            }
        case .leave(let table):
            Button("Leave", role: .destructive) {
                Task { await leave(table) }
            }
        case nil:
            EmptyView()
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: Doing things

    /// Through the one door. A local delete of a seat somebody holds on
    /// the share is not a removal, it is a row that comes back.
    private func remove(_ member: HouseholdMember) async {
        let first = member.firstName
        withAnimation(.plSnap) { problem = nil }
        if await Seats.remove(member, in: context) {
            Haptic.plate()
            Persist.save(context, "seat removed")
        } else {
            Haptic.warn()
            withAnimation(.plSnap) {
                problem = Problem(group: .household, text: "Couldn't remove \(first). Check your connection and try again.")
            }
        }
    }

    /// Off the Table share. The list is re-read rather than edited
    /// locally, because the share is the only thing that knows who is on
    /// it and a row dropped on optimism would come back on the next read.
    private func remove(_ guest: Guest) async {
        withAnimation(.plSnap) { problem = nil }
        if await TableShare.remove(seatID: guest.id) {
            Haptic.plate()
            let fresh = await TableShare.participants()
            withAnimation(.plSnap) { participants = fresh }
        } else {
            Haptic.warn()
            withAnimation(.plSnap) {
                problem = Problem(group: .table, text: "Couldn't remove \(guest.name). Check your connection and try again.")
            }
        }
    }

    /// Out of one table. Deleting the zone from my own shared database
    /// removes only my copy, so nothing of anyone's is at stake.
    private func leave(_ table: JoinedTable) async {
        withAnimation(.plSnap) { problem = nil }
        if await TableShare.leaveTable(owner: table.owner) {
            Haptic.plate()
            let fresh = await TableShare.joinedTables()
            withAnimation(.plSnap) {
                joinedTables = fresh.map { JoinedTable(owner: $0.owner, title: $0.title) }
            }
        } else {
            Haptic.warn()
            withAnimation(.plSnap) {
                problem = Problem(group: .joined, text: "Couldn't leave. Check your connection and try again.")
            }
        }
    }

    /// The same link again, to the same person. The entry's own id goes
    /// inside it, so the claim that comes back settles this row instead of
    /// minting a second person, and `record` updates the date rather than
    /// listing them twice.
    private func sendAgain(_ entry: TableInvites.Entry) {
        withAnimation(.plSnap) { problem = nil }
        let host = userFirstName
        InviteFlow.run(
            kind: .table,
            hostName: host,
            to: InviteFlow.Recipient(name: entry.name, phone: entry.phone),
            prepare: {
                guard let url = await TableShare.invitationURL(hostName: host) else { return .noCloud }
                let link = Invitation.wrapped(url, hostName: host, kind: .table, seat: nil, invite: entry.id)
                return Seats.Prepared(outcome: .ready(link), seat: nil, invite: entry.id)
            }
        ) { result in
            switch result {
            case .sent(let name, let phone, let prepared):
                Haptic.plate()
                Seats.confirmSent(
                    kind: .table, prepared: prepared, name: name, phone: phone,
                    email: entry.email, role: "member", in: context
                )
            case .failed(_, _, let prepared), .declined(_, _, let prepared):
                Seats.abandon(kind: .table, prepared: prepared)
                if case .failed = result {
                    Haptic.warn()
                    withAnimation(.plSnap) {
                        problem = Problem(group: .invited, text: "The message didn't send. Try again.")
                    }
                }
            case .noLink(_, let reason):
                Haptic.warn()
                withAnimation(.plSnap) { problem = Problem(group: .invited, text: reason) }
            case .cancelled:
                break
            }
        }
    }

    /// Invite somebody to the Table (§9): the picker, the link, the
    /// composer, from UIKit. Never a `HouseholdMember`; the entry is
    /// recorded only when the composer says the message went.
    private func startInvite() {
        withAnimation(.plSnap) { problem = nil }
        InviteFlow.run(
            kind: .table,
            hostName: userFirstName,
            prepare: { await Seats.prepareInvite(kind: .table, hostName: userFirstName) }
        ) { result in
            switch result {
            case .sent(let name, let phone, let prepared):
                Haptic.plate()
                Seats.confirmSent(
                    kind: .table, prepared: prepared, name: name, phone: phone,
                    email: nil, role: "member", in: context
                )
            case .failed(_, _, let prepared), .declined(_, _, let prepared):
                Seats.abandon(kind: .table, prepared: prepared)
                if case .failed = result {
                    Haptic.warn()
                    withAnimation(.plSnap) {
                        problem = Problem(group: .invite, text: "The message didn't send. Try again.")
                    }
                }
            case .noLink(_, let reason):
                Haptic.warn()
                withAnimation(.plSnap) { problem = Problem(group: .invite, text: reason) }
            case .cancelled:
                break
            }
        }
    }

    // MARK: Inviting

    /// The one control that actually invites somebody. Two real doors:
    /// pick a contact and send them the link, or hand the link to anybody
    /// else however you like. A row only reads as invited once a message
    /// has genuinely gone.
    private var inviteRow: some View {
        VStack(spacing: 10) {
            // Hidden, not disabled, once CloudKit has said there is no
            // link: the line under it says why, and a pill over that line
            // would be a control that cannot do what it names. While the
            // answer is still coming the pill stays, because its own flow
            // mints the link and reports for itself.
            if InviteComposer.isAvailable, link != .missing {
                // The shared atom: the same 56pt pill Home uses for the
                // household door, so the one control that invites somebody
                // does not look like two different buttons depending on
                // which screen you reached it from.
                InkPillButton(title: "Invite to the Table", systemImage: "person.badge.plus") {
                    startInvite()
                }
            }

            // Only when there is a real link. A seatless Table link names no
            // invitation entry, so the sheet never claims a person it
            // cannot name — they join as a guest under "At your table".
            if case .ready(let url) = link {
                ShareLink(
                    item: Invitation.wrapped(url, hostName: userFirstName, kind: .table, seat: nil, invite: nil),
                    message: Text(Invitation.sentence(hostName: userFirstName, kind: .table))
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text(InviteComposer.isAvailable ? "Share link" : "Share or copy link")
                            .plType(.body, .bold)
                            .plActionLabel()
                    }
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                    .contentShape(Capsule())
                }
            }

            if let problem, problem.group == .invite {
                ProblemRow(problem.text)
                    .transition(.opacity)
            }

            // Said plainly, because the alternative is someone wondering
            // why their sister never turned up at the table. What a seat
            // here is, and is not (§9): the Table, never the plan. Share
            // link is seatless on purpose — Invited rows only track a
            // Messages invite with an `i=` id.
            Text(link == .missing
                  ? noLinkLine
                  : (InviteComposer.isAvailable
                     ? "They get a text with a link. They see what everyone here cooks. They don't see the plan."
                     : "Share the link however you like. They see what everyone here cooks, not the plan."))
                .plType(.micro, .medium)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Why there is no link, specifically. "Sign in to iCloud" was the one
    /// sentence for every case, and on a signed-in member's phone whose
    /// host has not uploaded the root yet it was simply untrue.
    private var noLinkLine: String {
        switch reach {
        case .noAccount:
            return "Sign in to iCloud to send an invite link."
        case .restricted:
            return "iCloud is restricted on this iPhone, so there's no invite link."
        default:
            break
        }
        if HouseholdShare.membership.owner != nil {
            let host = HouseholdShare.cachedOwnerName.split(separator: " ").first.map(String.init) ?? ""
            return "The Table's link is still arriving from \(host.isEmpty ? "the host's" : "\(host)'s") phone."
        }
        return "Couldn't reach iCloud, so there's no invite link right now."
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
