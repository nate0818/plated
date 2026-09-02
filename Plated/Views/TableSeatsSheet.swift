import SwiftUI
import SwiftData
import Contacts

/// Everyone with a seat at your table — opened from the avatar cluster in
/// the Table header. Household members, friends who post here, and pending
/// invites, each one a row you can message or manage.
struct TableSeatsSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    // An author is the one thing every real post has. The empty-name
    // rows are blanks the CloudKit mirror adopts (TablePost.isBlank),
    // and counting them puts a dish on the board nobody cooked.
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover && !$0.authorName.isEmpty }) private var posts: [TablePost]

    @AppStorage("pendingSeats") private var pendingSeatsRaw = ""
    @AppStorage("userFirstName") private var userFirstName = ""
    @State private var invite: Invitation.Ready?
    @State private var inviteTarget: InviteTarget?
    @State private var pickingContact = false
    @State private var dmPeer: String?
    @State private var removingMember: HouseholdMember?
    /// Real CloudKit seats — people who accepted a share, as opposed to the
    /// household members and the invites that haven't landed yet.
    @State private var sharedSeats: [TableShare.Seat] = []
    @State private var amGuest = false
    @State private var leaveAsked = false
    /// Contacts who already have Plated. Empty until the directory answers,
    /// and empty forever if it never does — the invite paths below work
    /// regardless, so this section is a shortcut, never a dependency.
    @State private var onPlated: [Directory.Match] = []
    @State private var searchingContacts = false

    /// A friend at the table: someone who posts here but isn't in the household.
    private var guestSeats: [(name: String, colorHex: String)] {
        var seen = Set(members.map(\.name))
        var guests: [(String, String)] = []
        for post in posts where post.kind == "dish" {
            let first = post.firstName
            guard !seen.contains(post.authorName), !seen.contains(first) else { continue }
            seen.insert(post.authorName)
            guests.append((post.authorName, post.authorColorHex))
        }
        return guests
    }

    /// Legacy. Migrated into real seats at launch by `Seats.migrate`; read
    /// here only so a table that hasn't relaunched yet still counts right.
    private var pendingSeats: [String] {
        pendingSeatsRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("\(members.count + guestSeats.count + pendingSeats.count) people")
                Text(amGuest ? "This table" : "Your table")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // "Household" and "table" are different things, and the
                    // difference only becomes visible when you are a guest
                    // somewhere: you are still head of YOUR household while
                    // sitting at somebody else's table, and the sheet used
                    // to print "Head of table" next to their "Host" as
                    // though the two of you were disputing the same chair.
                    // One household per iCloud account is the model; the
                    // labels now say so.
                    seatGroup(amGuest ? "Your household" : "Household") {
                        ForEach(members, id: \.persistentModelID) { member in
                            seatRow(
                                name: member.name,
                                subtitle: member.isOwner
                                    ? (amGuest ? "Head of your household" : "Head of table")
                                    : (member.roleLine.isEmpty ? member.role.capitalized : member.roleLine),
                                tone: member.isOwner ? .neutralPair : member.tone,
                                canRemove: !member.isOwner,
                                canMessage: !member.isOwner
                            ) {
                                removingMember = member
                            }
                        }
                    }

                    if !guestSeats.isEmpty {
                        seatGroup("At your table") {
                            ForEach(guestSeats, id: \.name) { guest in
                                seatRow(
                                    name: guest.name,
                                    subtitle: "Shares dishes here",
                                    tone: PersonTone.from(hex: guest.colorHex),
                                    canRemove: false,
                                    canMessage: true
                                ) {}
                            }
                        }
                    }

                    if !pendingSeats.isEmpty {
                        seatGroup("Invited") {
                            ForEach(pendingSeats, id: \.self) { name in
                                seatRow(
                                    name: name,
                                    subtitle: "Not joined yet",
                                    tone: .neutralPair,
                                    canRemove: true,
                                    canMessage: false
                                ) {
                                    withAnimation(.plSnap) { cancelInvite(name) }
                                }
                            }
                        }
                    }

                    if !sharedSeats.isEmpty {
                        seatGroup(amGuest ? "You're a guest here" : "Joined") {
                            ForEach(sharedSeats) { seat in
                                seatRow(
                                    name: seat.isMe ? "\(seat.name) (you)" : seat.name,
                                    subtitle: seat.isOwner
                                        ? (seat.isMe ? "You host this table" : "Hosts this table")
                                        : "Sees this too",
                                    tone: .basilPair,
                                    canRemove: !seat.isOwner && !seat.isMe,
                                    canMessage: false
                                ) {
                                    Task {
                                        if await TableShare.remove(seatID: seat.id) {
                                            Haptic.plate()
                                            sharedSeats = await TableShare.participants()
                                        } else {
                                            Haptic.warn()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if amGuest {
                        Button {
                            Haptic.tap()
                            leaveAsked = true
                        } label: {
                            Text("Leave this table")
                                .plType(.body, .bold)
                                .foregroundStyle(Color.tomato)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                        }
                        .buttonStyle(.pressable)
                    }

                    alreadyHere
                    inviteRow
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .sheet(item: $dmPeer) { peer in
            DMThreadView(peerName: peer)
        }
        .task {
            sharedSeats = await TableShare.participants()
            amGuest = await TableShare.isGuest()
            invite = await Invitation.prepare(hostName: userFirstName)
            await findPeople()
        }
        .sheet(isPresented: $pickingContact) {
            ContactPicker(
                onPick: { name, phone in
                    pickingContact = false
                    inviteTarget = InviteTarget(name: name, phone: phone)
                },
                onCancel: { pickingContact = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $inviteTarget) { target in
            InviteComposer(
                recipients: [target.phone].compactMap { $0 },
                body: invite?.body ?? Invitation.body(hostName: userFirstName, link: nil)
            ) { sent in
                inviteTarget = nil
                guard sent else { return }
                Haptic.plate()
                withAnimation(.plSnap) { seat(target.name) }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Leave this table?", isPresented: $leaveAsked, titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    if await TableShare.leaveTable() { Haptic.plate(); amGuest = false }
                    else { Haptic.warn() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // True, and worth saying: leaving deletes only this user's copy
            // of the zone. Nothing the host owns is touched.
            Text("You'll stop seeing their dishes. Nothing you've cooked is deleted, and the host keeps their table.")
        }
        .confirmationDialog(
            "Remove \(removingMember?.name ?? "") from the household?",
            isPresented: Binding(get: { removingMember != nil }, set: { if !$0 { removingMember = nil } }),
            titleVisibility: .visible
        ) {
            if let member = removingMember {
                Button("Remove \(member.name)", role: .destructive) {
                    withAnimation(.plSnap) { context.delete(member) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func seatGroup(_ label: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(label)
            VStack(spacing: 0) { rows() }
                .padding(.horizontal, 14)
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
        }
    }

    private func seatRow(
        name: String, subtitle: String, tone: PersonTone,
        canRemove: Bool, canMessage: Bool, onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(initials: initials(for: name), tone: tone, size: 40,
                         photo: members.photo(forAuthor: name))
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
            if canMessage {
                Button {
                    Haptic.tap()
                    dmPeer = name
                } label: {
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "bubble.right")
                                .accessibilityLabel("Message \(name)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.ink)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
            if canRemove {
                Button {
                    Haptic.tap()
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle")
                        .accessibilityLabel("Remove \(name)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, 10)
    }

    /// The people in your phone who are already here. No invitation
    /// needed — they have the app, so seating them is one tap.
    ///
    /// This is the half of "add to household" that iOS cannot answer on
    /// its own: Apple deprecated every local way to discover which of your
    /// contacts use an app, so the names below come from Plated's
    /// directory, matched on salted phone hashes. See `Directory`.
    @ViewBuilder
    private var alreadyHere: some View {
        if searchingContacts {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for people you know…")
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } else if !onPlated.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Already on Plated")
                ForEach(onPlated) { match in
                    HStack(spacing: 12) {
                        AvatarCircle(
                            initials: initials(for: match.name),
                            tone: PersonTone.from(hex: "3DA35D"),
                            size: 38
                        )
                        Text(match.name)
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            Haptic.plate()
                            withAnimation(.plSnap) {
                                seat(match.name)
                                onPlated.removeAll { $0.id == match.id }
                            }
                        } label: {
                            Text("Add")
                                .plType(.footnote, .bold)
                                .foregroundStyle(Color.canvas)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 36)
                                .background(Color.ink, in: Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 6)
        }
    }

    /// Ask the directory who we know. Contacts are read here rather than
    /// handed to the server: only numbers that match come back, and only
    /// the ones we could normalise are ever sent.
    private func findPeople() async {
        guard Directory.isRegistered else { return }
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { return }

        searchingContacts = true
        defer { searchingContacts = false }

        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactNicknameKey, CNContactPhoneNumbersKey
        ] as [CNKeyDescriptor]
        var contacts: [CNContact] = []
        // Off the main thread: a large address book takes real time to walk.
        await Task.detached(priority: .utility) {
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: request) { contact, _ in
                contacts.append(contact)
            }
        }.value

        let seated = Set(members.map(\.name))
        let found = await Directory.onPlated(contacts: contacts)
        withAnimation(.plSnap) {
            // Somebody already at the table is not a suggestion.
            onPlated = found.filter { !seated.contains($0.name) }
        }
    }

    /// The one control that actually invites somebody.
    ///
    /// It used to be a text field: type a name, tap Invite, and the name
    /// appeared under "Invited · Waiting on them" having been written to a
    /// local string and nowhere else. Nobody was contacted. Now the two
    /// real doors are here — pick a contact and send them the link, or hand
    /// the link to anybody else however you like — and a seat only reads as
    /// invited once a message has genuinely gone.
    private var inviteRow: some View {
        VStack(spacing: 10) {
            if InviteComposer.isAvailable {
                Button {
                    Haptic.tap()
                    pickingContact = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Invite someone")
                            .plType(.body, .bold)
                    }
                    .foregroundStyle(Color.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(Color.ink, in: Capsule())
                }
                .buttonStyle(.pressable)
            }

            // Only when there is a real link. This used to fall back to
            // plated.app — a domain Plated does not own, serving somebody
            // else's parked page — and hand it to a friend as an invitation.
            // With no link the honest line below already says so.
            if let url = invite?.url {
            ShareLink(
                item: url,
                message: Text(TableSync.inviteMessage(hostName: userFirstName))
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Share link")
                        .plType(.body, .bold)
                }
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
            }
            }

            // Said plainly, because the alternative is someone wondering why
            // their sister never turned up at the table.
            Text(invite?.hasLink == true
                 ? "They get a link to join."
                 : "Sign in to iCloud to send an invite link.")
                .plType(.micro, .medium)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func seat(_ name: String) {
        var seats = pendingSeats
        if !seats.contains(name) { seats.append(name) }
        pendingSeatsRaw = seats.joined(separator: "\n")
    }

    private func cancelInvite(_ name: String) {
        pendingSeatsRaw = pendingSeats.filter { $0 != name }.joined(separator: "\n")
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

/// A direct line to one seat. The full Instagram-style inbox is a network
/// feature; this is its honest local seed — your side of the conversation,
/// stored and synced through your own iCloud.
struct DMThreadView: View {
    let peerName: String

    @Environment(\.modelContext) private var context
    @Query private var messages: [DirectMessage]

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    init(peerName: String) {
        self.peerName = peerName
        _messages = Query(
            filter: #Predicate<DirectMessage> { $0.peerName == peerName },
            sort: \DirectMessage.createdAt
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Direct")
                Text(peerName)
                    .plName()
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 10)
            Divider().overlay(Color.hairlineSoft)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    Text("These messages stay on this device. \(peerName.split(separator: " ").first.map(String.init) ?? peerName) can't see them yet.")
                        .plType(.micro, .medium)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)

                    ForEach(messages, id: \.persistentModelID) { message in
                        bubble(message)
                            .transition(.plRise)
                    }
                }
                .animation(.plSnap, value: messages.count)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(messages.isEmpty ? .top : .bottom)

            HStack(spacing: 10) {
                TextField("Message \(peerName.split(separator: " ").first.map(String.init) ?? peerName)…", text: $draft, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .onTapGesture { composerFocused = true }
                Button {
                    send()
                } label: {
                    Circle()
                        .fill(draft.isEmpty ? Color.fill : Color.tomato)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "arrow.up")
                                .accessibilityLabel("Send")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(draft.isEmpty ? Color.inkFaint : Color.onTomato)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .animation(.plSnap, value: draft.isEmpty)
                }
                .buttonStyle(.pressable)
                .disabled(draft.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private func bubble(_ message: DirectMessage) -> some View {
        HStack {
            if message.isMine { Spacer(minLength: 60) }
            Text(message.text)
                .plType(.body, .medium)
                .foregroundStyle(message.isMine ? Color.canvas : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    message.isMine ? Color.ink : Color.fill,
                    in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                )
            if !message.isMine { Spacer(minLength: 60) }
        }
    }

    private func send() {
        guard !draft.isEmpty else { return }
        Haptic.plate()
        context.insert(DirectMessage(peerName: peerName, text: draft, isMine: true))
        draft = ""
    }
}
