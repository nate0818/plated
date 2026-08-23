import SwiftUI
import SwiftData

/// Everyone with a seat at your table — opened from the avatar cluster in
/// the Table header. Household members, friends who post here, and pending
/// invites, each one a row you can message or manage.
struct TableSeatsSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover }) private var posts: [TablePost]

    @AppStorage("pendingSeats") private var pendingSeatsRaw = ""
    @State private var inviteName = ""
    @State private var dmPeer: String?
    @State private var removingMember: HouseholdMember?

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

    private var pendingSeats: [String] {
        pendingSeatsRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("\(members.count + guestSeats.count + pendingSeats.count) seats")
                Text("Your table")
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    seatGroup("Household") {
                        ForEach(members, id: \.persistentModelID) { member in
                            seatRow(
                                name: member.name,
                                subtitle: member.isOwner ? "Head of table" : (member.roleLine.isEmpty ? member.role.capitalized : member.roleLine),
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
                                    subtitle: "Waiting on them",
                                    tone: .neutralPair,
                                    canRemove: true,
                                    canMessage: false
                                ) {
                                    withAnimation(.plSnap) { cancelInvite(name) }
                                }
                            }
                        }
                    }

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
        .confirmationDialog(
            "Remove \(removingMember?.name ?? "") from the table?",
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
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
        }
    }

    private func seatRow(
        name: String, subtitle: String, tone: PersonTone,
        canRemove: Bool, canMessage: Bool, onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(initials: initials(for: name), tone: tone, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.jakarta(12, .semibold))
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

    private var inviteRow: some View {
        HStack(spacing: 8) {
            TextField("Invite someone by name", text: $inviteName)
                .font(.jakarta(14, .medium))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                .onSubmit(invite)
            Button {
                invite()
            } label: {
                Text("Invite")
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(Color.canvas)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color.ink, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(inviteName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(inviteName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
    }

    private func invite() {
        let name = inviteName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Haptic.plate()
        var seats = pendingSeats
        if !seats.contains(name) { seats.append(name) }
        pendingSeatsRaw = seats.joined(separator: "\n")
        inviteName = ""
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
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 10)
            Divider().overlay(Color.hairlineSoft)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    Text("Messages live on your devices for now — they'll deliver when \(peerName.split(separator: " ").first.map(String.init) ?? peerName) is on Plated's network.")
                        .font(.jakarta(11, .medium))
                        .foregroundStyle(Color.inkFaint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)

                    ForEach(messages, id: \.persistentModelID) { message in
                        bubble(message)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.plSnap, value: messages.count)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(messages.isEmpty ? .top : .bottom)

            HStack(spacing: 10) {
                TextField("Message \(peerName.split(separator: " ").first.map(String.init) ?? peerName)…", text: $draft, axis: .vertical)
                    .font(.jakarta(14, .medium))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip))
                    .onTapGesture { composerFocused = true }
                Button {
                    send()
                } label: {
                    Circle()
                        .fill(draft.isEmpty ? Color.fill : Color.tomato)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "arrow.up")
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
                .font(.jakarta(14, .medium))
                .foregroundStyle(message.isMine ? Color.canvas : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    message.isMine ? Color.ink : Color.fill,
                    in: RoundedRectangle(cornerRadius: Radius.chip)
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
