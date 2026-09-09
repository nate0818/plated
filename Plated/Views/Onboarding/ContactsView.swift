import SwiftUI
import SwiftData
import Contacts

/// "Invite your household": a household invitation through the same door
/// Home uses (docs/household.md §6), with a shortlist from Contacts to make
/// the first one easy. Contacts are matched on-device; nothing leaves the
/// phone. Nothing is minted until somebody taps Invite or Share a link, so
/// a person passing through on their way to somebody else's household
/// never hosts an empty Table.
struct ContactsView: View {
    let onDone: () -> Void

    struct Candidate: Identifiable {
        let id: String
        let name: String
        let imageData: Data?
        /// How the invitation reaches them. A contact without one cannot be
        /// invited, so `requestContacts` never offers one.
        let phone: String?
        var seated: Bool = false
    }

    @AppStorage("userFirstName") private var userFirstName = ""
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var candidates: [Candidate] = []
    @State private var accessState: AccessState = .notAsked
    @State private var arrived = false
    /// Minting the seatless link for Share a link. The button says so
    /// rather than doing nothing for the seconds CloudKit takes.
    @State private var minting = false
    /// Whose Invite is in flight. Minting the household share is several
    /// CloudKit round trips, and with nothing on screen saying so the
    /// second tap presented a second composer over the first and dropped
    /// the first one's delegate. See `InviteFlow`.
    @State private var inviting: Candidate.ID?
    @State private var problem: String?

    enum AccessState { case notAsked, granted, denied }

    /// Every table has a host. `ProfileSetupView` lays the owner's place
    /// now, so the host seat exists before the first invitation; this is
    /// the safety net for a row that is somehow still missing on the way
    /// out. Simulators get theirs from the sample seed (inserting here
    /// would defeat the seed's members.isEmpty check); a real device lays
    /// the owner's own place from the sign-in name — without it the user's
    /// profile, posts, and the cook rotation all point at nobody. A fetch
    /// FAILURE aborts rather than inserting: only a confirmed zero earns a
    /// new row. The delete-and-reinstall race — zero local owners while the
    /// first CloudKit import is still inbound — can't be closed here;
    /// MainShellView collapses duplicate owners whenever they appear.
    private func finish() {
        #if !targetEnvironment(simulator)
        let owners = try? context.fetchCount(
            FetchDescriptor<HouseholdMember>(predicate: #Predicate { $0.role == "owner" })
        )
        if owners == 0 {
            let me = HouseholdMember(
                name: userFirstName.isEmpty ? "Me" : userFirstName,
                colorHex: "FF5A3C", isPrimaryCook: true,
                role: "owner", roleLine: "Head of table", cookWeekdays: [],
                seat: .head
            )
            if !TableIdentity.isPlaceholder { me.userRecordName = TableIdentity.cached }
            me.authorID = TableIdentity.cached
            context.insert(me)
            Persist.save(context)
        }
        #endif
        onDone()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                // Place settings around the table.
                HStack(spacing: -12) {
                    seatBubble("😋", tone: .tomatoPair)
                    seatBubble("🤗", tone: .basilPair)
                    seatBubble("😄", tone: .amberPair)
                    seatBubble("+", tone: .grapePair)
                }
                .padding(.bottom, 8)

                Text("Invite your household")
                    .plType(.hero)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    // Without this the hero is compressed to one line and
                    // truncated: at AX5 "Invite your people" was drawn as
                    // "Invite...", which DESIGN.md names as the one thing a
                    // title may never do. Its own subtitle already had it.
                    .fixedSize(horizontal: false, vertical: true)
                Text(accessState == .granted
                     ? "Anyone who joins sees the plan, the grocery list and the cookbook, and can change them."
                     : "Plated is invite only. Nobody sees your plan or your recipes unless you invite them.")
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 84)
            .padding(.horizontal, 28)
            .opacity(arrived ? 1 : 0)

            if accessState == .granted && candidates.isEmpty {
                VStack(spacing: 6) {
                    Text("Nobody here to suggest")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text("We only suggest contacts with a phone number. Share a link instead.")
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 34)
                .padding(.top, 30)
                Spacer()
            } else if accessState == .granted && !candidates.isEmpty {
                // The screen scrolls as a whole now, and a scroll view
                // inside a scroll view is two things to drag one direction.
                VStack(spacing: 0) {
                    ForEach($candidates) { $candidate in
                        candidateRow($candidate)
                        if candidate.id != candidates.last?.id {
                            Divider().overlay(Color.hairlineSoft)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .background(Color.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous).strokeBorder(Color.hairline))
                .plCardShadow()
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .transition(.plArrive)
            } else {
                Spacer()
            }

            VStack(spacing: 12) {
                if let problem {
                    ProblemRow(problem)
                        .transition(.opacity)
                }
                if accessState == .granted {
                    // Always offered, not only once somebody is seated: the
                    // five names above are a shortlist, and the person you
                    // most want at your table is often not on it.
                    // The link is minted on the tap, never ahead of it, and
                    // the share sheet opens only once there is one: no
                    // link, no sheet, and the line under it says why.
                    Button {
                        shareLink()
                    } label: {
                        HStack(spacing: 6) {
                            if minting {
                                ProgressView().controlSize(.small).tint(Color.ink)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(minting ? "Preparing the link" : "Share a link")
                                .plType(.body, .bold)
                                .plActionLabel()
                        }
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(minting)
                    TomatoPillButton(title: "Done") { finish() }
                } else if accessState == .denied {
                    // iOS asks once. After a refusal `requestContacts()`
                    // raises no prompt and changes nothing, so the tomato
                    // pill — the committing action on this screen — sat
                    // there saying "Use Contacts" and doing nothing at all,
                    // with the real route buried underneath it as a link.
                    // The pill is the route now.
                    Text("Plated can't see your contacts. You can turn that on in Settings, or invite people later.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        TomatoPillButton(title: "Open Settings") { openURL(settings) }
                    }
                } else {
                    TomatoPillButton(title: "Use Contacts") { requestContacts() }
                }
                // Only before contacts are granted. Once the list is up,
                // "Done" is directly above this and calls the
                // same function, so the screen was ending on two buttons
                // that do the same thing and promise opposite outcomes.
                if accessState != .granted {
                    Button {
                        Haptic.tap()
                        finish()
                    } label: {
                        Text("Not now")
                            .plType(.body)
                            .plActionLabel()
                            .foregroundStyle(Color.inkSecondary)
                            .plTapTarget()
                    }
                    .buttonStyle(.pressable)
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("Contacts are matched on your device. Never uploaded, never sold.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        // A Text in an HStack beside a fixed-size icon
                        // truncates before it wraps. This is a privacy
                        // claim, and half of one is worse than none: the
                        // sentence has to arrive whole at every text size.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .plFitsOrScrolls()
        .background {
            ZStack(alignment: .topLeading) {
                DriftingFoodPattern()
                RadialGradient(colors: [.mangoTint, .mangoTint.opacity(0)], center: .center, startRadius: 0, endRadius: 220)
                    .frame(width: 440, height: 440)
                    .offset(x: -120, y: -180)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.plSettle.delay(0.1)) { arrived = true }
            // UI-test hook: jump straight to the granted list when contacts
            // permission is pre-granted via `simctl privacy`.
            if LaunchFlags.consume("-plated-find-people") { requestContacts() }
        }
        .animation(.plSettle, value: accessState == .granted)
        .animation(.plSnap, value: problem)
    }

    /// The same door Home uses, with the person already chosen so the
    /// picker is skipped. The link is minted between the tap and the
    /// composer, and a seat is laid only when the composer says the message
    /// went: cancelling used to still mark them "Waiting on them", which
    /// was a lie about a message that was never sent.
    private func startInvite(_ person: Candidate) {
        guard inviting == nil else { return }
        withAnimation(.plSnap) {
            problem = nil
            inviting = person.id
        }
        InviteFlow.run(
            kind: .household,
            hostName: userFirstName,
            to: InviteFlow.Recipient(name: person.name, phone: person.phone),
            prepare: { await Seats.prepareInvite(kind: .household, hostName: userFirstName) }
        ) { result in
            withAnimation(.plSnap) { inviting = nil }
            switch result {
            case .sent(let name, let phone, let prepared):
                Haptic.plate()
                // A real seat, not a name in a string only one sheet could
                // read. Onboarding used to invite three people and hand you
                // a household of one. Partner, because the first person
                // invited from here is almost always the one who cooks.
                Seats.confirmSent(
                    kind: .household, prepared: prepared, name: name, phone: phone,
                    email: nil, role: "partner", in: context
                )
                Persist.save(context, "invited from onboarding")
                if let index = candidates.firstIndex(where: { $0.id == person.id }) {
                    withAnimation(.plPop) { candidates[index].seated = true }
                }
            case .failed(_, _, let prepared), .declined(_, _, let prepared):
                Seats.abandon(kind: .household, prepared: prepared)
                if case .failed = result {
                    Haptic.warn()
                    withAnimation(.plSnap) { problem = "The message didn't send. Try again." }
                }
            case .noLink(_, let reason):
                Haptic.warn()
                withAnimation(.plSnap) { problem = reason }
            case .cancelled:
                break
            }
        }
    }

    /// A seatless household link, handed over however they like. Whoever
    /// joins picks their seat on arrival (docs/household.md §7).
    private func shareLink() {
        guard !minting else { return }
        Haptic.tap()
        withAnimation(.plSnap) {
            problem = nil
            minting = true
        }
        Task {
            let url = await Seats.shareableLink(kind: .household, hostName: userFirstName)
            withAnimation(.plSnap) { minting = false }
            guard let url else {
                Haptic.warn()
                withAnimation(.plSnap) { problem = Seats.noLinkReason() }
                return
            }
            InviteFlow.share(url, message: Invitation.sentence(hostName: userFirstName, kind: .household))
        }
    }

    private var seatedCount: Int { candidates.filter(\.seated).count }

    private func seatBubble(_ symbol: String, tone: PersonTone) -> some View {
        Circle()
            .fill(tone.tint)
            .frame(width: 52, height: 52)
            .overlay {
                if symbol == "+" {
                    Text(symbol).font(.jakarta(17, .bold)).foregroundStyle(tone.tone)
                } else {
                    Text(symbol).font(.system(size: 26))
                }
            }
            .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
            .plCardShadow()
    }

    private func candidateRow(_ candidate: Binding<Candidate>) -> some View {
        let person = candidate.wrappedValue
        let tone = PersonTone.from(hex: PersonTone.rotation[abs(person.id.hashValue) % PersonTone.rotation.count])
        return HStack(spacing: 12) {
            if let data = person.imageData, let photo = UIImage(data: data) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                AvatarCircle(initials: initials(of: person.name), tone: tone, size: 44)
            }
            // The name alone. A second line reading "In your contacts" on a
            // screen that is entirely a list of your contacts was a row of
            // text carrying no information.
            Text(person.name)
                .plName()
                .plType(.body)
                .foregroundStyle(Color.ink)
            Spacer()
            if person.seated {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                    Text("Invited").plType(.footnote, .bold)
                }
                .foregroundStyle(Color.basil)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(Color.basilTint, in: Capsule())
                .transition(.plArrive)
            } else if InviteComposer.isAvailable {
                invitePill(person)
            }
            // No Messages: Share a link at the bottom of the screen is the
            // door. A tomato Invite that opens a blank composer is worse
            // than no pill.
        }
        .padding(.vertical, 12)
    }

    /// The one control on this row, and it says what it is doing. Minting
    /// the household share takes seconds, so the tapped pill takes the off
    /// dress a disabled `TomatoPillButton` wears (`inkSecondary` on `fill`,
    /// never a faded tomato) and every pill on the screen goes with it: a
    /// second invitation cannot be started while the first is in flight.
    private func invitePill(_ person: Candidate) -> some View {
        let busy = inviting == person.id
        return Button {
            Haptic.tap()
            startInvite(person)
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).tint(Color.inkSecondary)
                }
                Text(busy ? "Preparing the link" : "Invite")
                    .plType(.footnote, .bold)
                    .plActionLabel()
            }
            .foregroundStyle(inviting == nil ? Color.onTomato : Color.inkSecondary)
            .padding(.horizontal, 18)
            // 44, not the 36 the label happened to be: a stroked or filled
            // capsule is only tappable across what it draws, and the row
            // beside it is 68 high.
            .frame(minHeight: 44)
            .background(inviting == nil ? Color.tomato : Color.fill, in: Capsule())
            .plDishShadow()
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(inviting != nil)
        .accessibilityLabel(busy ? "Preparing the link for \(person.name)" : "Invite \(person.name)")
    }

    private func initials(of name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func requestContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                DispatchQueue.main.async { accessState = .denied }
                return
            }
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                        CNContactNicknameKey, CNContactOrganizationNameKey,
                        CNContactThumbnailImageDataKey, CNContactImageDataAvailableKey,
                        CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
                        CNContactBirthdayKey, CNContactTypeKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)

            // "Most contacted" is not a thing iOS will tell a third-party
            // app. There is no public API for call, message or FaceTime
            // frequency — not in Contacts, not in CallKit, not in Intents.
            // Anything claiming to rank your top five by usage is either
            // guessing or using something we can't ship.
            //
            // So this ranks by EFFORT INVESTED, which is the honest signal
            // sitting in the database: the card you gave a photo, a
            // nickname and a birthday is a card you maintain, and you only
            // maintain cards for people you actually deal with. Businesses
            // and stale imports have a name, a number, and nothing else.
            //
            // Ordered by how deliberate the act is, not by how common the
            // field is — a saved birthday is a much stronger claim on
            // "this is my person" than an email address.
            var scored: [(candidate: Candidate, score: Int)] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                // A company is never a seat at a household table.
                guard contact.contactType == .person,
                      contact.organizationName.isEmpty else { return }
                // No way to reach them is no way to invite them.
                guard !contact.phoneNumbers.isEmpty else { return }

                var score = 2
                if contact.imageDataAvailable { score += 3 }
                if contact.birthday != nil { score += 3 }
                if !contact.nickname.isEmpty { score += 2 }
                if contact.phoneNumbers.count > 1 { score += 1 }
                if !contact.emailAddresses.isEmpty { score += 1 }
                // A full name beats a first name alone: "Mum" is dear but
                // "Sarah Okafor" is a card someone actually filled in.
                if !contact.familyName.isEmpty { score += 1 }

                scored.append((Candidate(id: contact.identifier, name: name,
                                         imageData: contact.thumbnailImageData,
                                         phone: contact.phoneNumbers.first?.value.stringValue),
                               score))
            }
            scored.sort {
                $0.score != $1.score ? $0.score > $1.score : $0.candidate.name < $1.candidate.name
            }
            // Five. A wall of contacts is a chore; five is a decision.
            let top = scored.prefix(5).map(\.candidate)
            DispatchQueue.main.async {
                candidates = top
                accessState = .granted
            }
        }
    }
}

/// The fun under the quiet: a sparse field of dishes drifting diagonally,
/// faint enough that the type and the card stay in charge. Fades out before
/// the CTA stack so the bottom of the screen keeps its calm.
private struct DriftingFoodPattern: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let emojis = ["🍕", "🥗", "🌮", "🍜", "🍳", "🥑", "🍓", "🥐", "🍤", "🫑", "🧀", "🍋"]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { ctx in
            Canvas { context, size in
                let tile: CGFloat = 118
                let t = ctx.date.timeIntervalSinceReferenceDate
                let drift = CGFloat((t * 6).truncatingRemainder(dividingBy: Double(tile)))
                let cols = Int(size.width / tile) + 2
                let rows = Int(size.height / tile) + 2
                for row in -1..<rows {
                    for col in -1..<cols {
                        let seed = abs(row &* 31 &+ col &* 17)
                        let emoji = Self.emojis[abs(row * 5 + col * 3) % Self.emojis.count]
                        let jitterX = CGFloat(seed &* 37 % 52) - 26
                        let jitterY = CGFloat(seed &* 53 % 44) - 22
                        var layer = context
                        layer.translateBy(x: CGFloat(col) * tile + jitterX + drift,
                                          y: CGFloat(row) * tile + jitterY + drift)
                        layer.rotate(by: .degrees(Double(seed % 30) - 15))
                        layer.opacity = 0.18
                        layer.draw(Text(verbatim: emoji).font(.system(size: 25)), at: .zero)
                    }
                }
            }
        }
        .mask(
            LinearGradient(stops: [.init(color: .white, location: 0),
                                   .init(color: .white, location: 0.55),
                                   .init(color: .clear, location: 0.92)],
                           startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
