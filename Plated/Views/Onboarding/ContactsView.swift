import SwiftUI
import SwiftData
import Contacts

/// "Set a place" — inviting someone is laying a place setting for them.
/// Contacts are matched on-device; nothing leaves the phone.
struct ContactsView: View {
    let onDone: () -> Void

    /// Names the user seated, newline-separated. Real invites ride on CloudKit
    /// sharing later; until then the choice is kept, not thrown away.
    @AppStorage("pendingSeats") private var pendingSeatsRaw = ""

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
    @State private var candidates: [Candidate] = []
    @State private var accessState: AccessState = .notAsked
    /// The live CKShare link and the message that carries it, once CloudKit
    /// has minted one. A nil link means the invite goes out as words alone —
    /// still worth sending, and exactly what shipped before sharing existed.
    @State private var invite: Invitation.Ready?
    /// Who the open message composer is addressed to.
    @State private var inviteTarget: InviteTarget?
    @State private var arrived = false

    enum AccessState { case notAsked, granted, denied }

    /// Every table has a host. Simulators get theirs from the sample seed
    /// (inserting here would defeat the seed's members.isEmpty check); a
    /// real device lays the owner's own place from the sign-in name —
    /// without it the user's profile, posts, and the cook rotation all
    /// point at nobody. A fetch FAILURE aborts rather than inserting: only
    /// a confirmed zero earns a new row. The delete-and-reinstall race —
    /// zero local owners while the first CloudKit import is still inbound —
    /// can't be closed here; MainShellView collapses duplicate owners
    /// whenever they appear.
    private func finish() {
        #if !targetEnvironment(simulator)
        let owners = try? context.fetchCount(
            FetchDescriptor<HouseholdMember>(predicate: #Predicate { $0.role == "owner" })
        )
        if owners == 0 {
            context.insert(HouseholdMember(
                name: userFirstName.isEmpty ? "Me" : userFirstName,
                colorHex: "FF5A3C", isPrimaryCook: true,
                role: "owner", roleLine: "Head of table", cookWeekdays: []
            ))
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

                Text("Invite your people")
                    .plType(.hero)
                    .foregroundStyle(Color.ink)
                Text(accessState == .granted
                     ? "Anyone you invite sees your plan and what you cook."
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
                ScrollView {
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
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                Spacer()
            }

            VStack(spacing: 12) {
                if accessState == .granted {
                    // Always offered, not only once somebody is seated: the
                    // five names above are a shortlist, and the person you
                    // most want at your table is often not on it.
                    // Only when there is a real link — the old fallback
                    // shared a domain Plated does not own.
                    if let url = invite?.url {
                    ShareLink(
                        item: url,
                        message: Text(TableSync.inviteMessage(hostName: userFirstName))
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Share a link")
                                .plType(.body, .bold)
                        }
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                    }
                    }
                    TomatoPillButton(title: "Done") { finish() }
                } else {
                    TomatoPillButton(title: "Use Contacts") { requestContacts() }
                    if accessState == .denied {
                        Text("Plated can't see your contacts. Allow access in iOS Settings, or invite people later.")
                            .plType(.caption)
                            .foregroundStyle(Color.inkFaint)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        // Naming Settings without a route there is a dead
                        // end dressed up as help.
                        if let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: settings)
                                .plType(.footnote, .bold)
                                .foregroundStyle(Color.ink)
                                .frame(minHeight: 44)
                        }
                    }
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
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                    Text("Contacts are matched on your device. Never uploaded, never sold.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
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
        .task {
            guard invite == nil else { return }
            invite = await Invitation.prepare(hostName: userFirstName)
        }
        .sheet(item: $inviteTarget) { target in
            InviteComposer(
                recipients: [target.phone].compactMap { $0 },
                body: invite?.body ?? Invitation.body(hostName: userFirstName, link: nil)
            ) { sent in
                inviteTarget = nil
                // A seat is claimed only by an invitation that actually
                // went. Cancelling the composer used to still mark them
                // "Waiting on them", which was a lie about a message that
                // was never sent.
                guard sent, let index = candidates.firstIndex(where: { $0.id == target.id || $0.name == target.name })
                else { return }
                Haptic.plate()
                withAnimation(.plPop) { candidates[index].seated = true }
                // A real seat, not a name in a string only one sheet could
                // read. Onboarding used to invite three people and hand you
                // a household of one.
                Seats.confirmSent(
                    name: target.name, phone: target.phone, email: nil, in: context
                )
            }
            .ignoresSafeArea()
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
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Button {
                    Haptic.plate()
                    inviteTarget = InviteTarget(name: person.name, phone: person.phone)
                } label: {
                    Text("Invite")
                        .plType(.footnote, .bold)
                        .foregroundStyle(Color.onTomato)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 36)
                        .background(Color.tomato, in: Capsule())
                        .plDishShadow()
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, 12)
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
