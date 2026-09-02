import SwiftUI
import SwiftData
import Contacts
import PhotosUI

/// Home — the household itself. Who sits here, what they have earned
/// together, and whose night it is. The banner is theirs to hang, the
/// deeper numbers live one tap in, and the people come before the
/// paperwork: this page is about a family, not a dashboard.
struct HouseholdHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    // An author is the one thing every real post has. The empty-name
    // rows are blanks the CloudKit mirror adopts (TablePost.isBlank),
    // and counting them puts a dish on the board nobody cooked.
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover && !$0.authorName.isEmpty }) private var posts: [TablePost]
    @Query private var meals: [PlannedMeal]
    // Oldest first — see PersonProfileView: the oldest row is the
    // household's one true profile when a sync race left more than one.
    @Query(sort: \HouseholdProfile.createdAt) private var profiles: [HouseholdProfile]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("autoRotateOpenNights") private var autoRotate = true
    @AppStorage("userFamilyName") private var userFamilyName = ""
    @AppStorage("householdName") private var householdName = ""
    @State private var addPresented = false
    @State private var resendTarget: InviteTarget?
    @State private var resendBody = ""
    @AppStorage("userFirstName") private var userFirstName = ""
    @Environment(\.openURL) private var openURL
    @State private var paywallPresented = false
    @State private var settingsPresented = false
    @State private var namingFromMasthead = false
    @State private var turnsTipShown = false
    @State private var bannerItem: PhotosPickerItem?
    /// Item-based, not two `isPresented` booleans: a binding set
    /// asynchronously (the launch harness does exactly that) pops an
    /// isPresented destination straight back off.
    @State private var pushed: HomeDestination?
    @State private var personShown: PersonRef?
    @State private var dmPeer: String?
    @State private var swipedMember: PersistentIdentifier?
    @State private var removingMember: HouseholdMember?
    #if DEBUG
    /// One arming per view lifetime, so a re-appearance can't queue a
    /// second push behind the first.
    @State private var statsFlagHandled = false
    #endif

    enum HomeDestination: String, Identifiable {
        case activity, stats
        var id: String { rawValue }
    }

    private var owner: HouseholdMember? { members.first(where: \.isOwner) }
    private var kissCount: Int { posts.filter(\.hasChefsKiss).count }
    private var platesEarned: Int { posts.reduce(0) { $0 + $1.totalPlates } }
    /// Every dinner this household has ever put on the plan.
    private var nightsPlated: Int { meals.count }

    /// Whether the house has a name at all, or is still "Your Household".
    private var isNamed: Bool {
        !HouseholdIdentity.familyName(
            typed: householdName,
            appleFamilyName: userFamilyName,
            ownerName: owner?.name ?? ""
        ).isEmpty
    }

    /// "The Meadows" — the name the user typed, else the one Apple handed
    /// over at sign-in, else the head of table's own surname. Just the
    /// name: the word "household" is already the label above it.
    private var householdDisplayName: String {
        HouseholdIdentity.displayName(
            typed: householdName,
            appleFamilyName: userFamilyName,
            ownerName: owner?.name ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            page
                .navigationDestination(item: $pushed) { destination in
                    switch destination {
                    case .activity: NotificationsView()
                    case .stats: HouseholdStatsView()
                    }
                }
                .navigationDestination(item: $personShown) { person in
                    PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
                }
                .toolbar(.hidden, for: .navigationBar)
                .plSwipeBack()
        }
    }

    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                masthead
                banner
                statsStrip
                peopleSection
                cooksSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, Layout.floatingChromeInset)
        }
        // Scrolling puts an open row away, the way a list does.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting, swipedMember != nil {
                withAnimation(.plSnap) { swipedMember = nil }
            }
        }
        .background(alignment: .topTrailing) {
            // After Dark lets the chrome sleep — no ambient glow in the dark room.
            if colorScheme == .light {
                RadialGradient(colors: [.basilTint, .basilTint.opacity(0)], center: .center, startRadius: 0, endRadius: 220)
                    .frame(width: 440, height: 440)
                    .offset(x: 140, y: -160)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $addPresented) {
            AddMemberSheet()
        }
        .sheet(item: $resendTarget) { target in
            InviteComposer(
                recipients: [target.phone].compactMap { $0 },
                body: resendBody
            ) { _ in resendTarget = nil }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallSheet()
        }
        .sheet(isPresented: $settingsPresented, onDismiss: { namingFromMasthead = false }) {
            SettingsSheet(focusHouseholdName: namingFromMasthead)
        }
        .sheet(item: $dmPeer) { peer in
            DMThreadView(peerName: peer)
        }
        .confirmationDialog(
            "Remove \(removingMember?.name ?? "") from the household?",
            isPresented: Binding(
                get: { removingMember != nil },
                set: {
                    // Dismissing by tapping outside has to put the row
                    // back too, or the seat sits open with no dialog.
                    if !$0 {
                        removingMember = nil
                        swipedMember = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let member = removingMember {
                Button("Remove \(member.name)", role: .destructive) {
                    Haptic.plate()
                    withAnimation(.plSnap) {
                        swipedMember = nil
                        context.delete(member)
                    }
                }
                Button("Cancel", role: .cancel) { swipedMember = nil }
            }
        }
        .task {
            await reframeStoredBannerIfNeeded()
        }
        .onAppear {
            #if DEBUG
            // UI-test hook, one-shot: `simctl launch … -plated-open-stats`.
            // Works standalone — MainShellView routes to this tab first (see
            // `flagHomes`). ALWAYS `simctl terminate` before a flag-carrying
            // launch: a second launch on a running process re-uses the
            // original argv and the already-spent `consumed` set, so it is
            // completely inert while still printing a pid and reporting
            // success.
            //
            // `consume` fires once per PROCESS, and Home's onAppear runs
            // before the launch opener lifts — so on its own the flag was
            // spent on a pass that then slept, and any later appearance
            // found it already consumed. Checked here, consumed only when
            // the push actually happens.
            if !statsFlagHandled, ProcessInfo.processInfo.arguments.contains("-plated-open-stats") {
                statsFlagHandled = true
                // After the opener has lifted: pushing a destination while
                // the launch animation is still running wedges the update
                // cycle (the splash's repeatForever + a fresh push).
                Task {
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard LaunchFlags.consume("-plated-open-stats") else { return }
                    pushed = .stats
                }
            }
            #endif
        }
        .onChange(of: bannerItem) { _, item in
            guard let item else { return }
            Task {
                guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
                // Vision on a full-size photo is not main-thread work.
                let framed = await Task.detached(priority: .userInitiated) {
                    BannerFocus.framed(raw) ?? PersonProfileView.downscale(raw)
                }.value
                setBanner(framed)
            }
        }
    }

    // MARK: Masthead

    /// Past this, the trailing cluster and a 26pt title cannot share a
    /// line — the row becomes two.
    private var hugeType: Bool { typeSize >= .accessibility1 }

    @ViewBuilder
    private var masthead: some View {
        if hugeType {
            VStack(alignment: .leading, spacing: 12) {
                mastheadTitle
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    mastheadControls
                }
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                mastheadTitle
                Spacer(minLength: 6)
                mastheadControls
            }
        }
    }

    private var mastheadTitle: some View {
            // An unnamed house is a house Apple never told us the name of.
            // The title is the way to fix that — tap it and go name it.
            Button {
                Haptic.tap()
                namingFromMasthead = true
                settingsPresented = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel("Household")
                    HStack(spacing: 5) {
                        Text(householdDisplayName)
                            .font(.gabarito(26, .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.ink)
                            // One line at ordinary sizes — it wrapped
                            // "Your / Household" the moment two were
                            // allowed. Only huge type gets to wrap.
                            .lineLimit(hugeType ? 3 : 1)
                            // Shrinking is what stops a mid-word break, so
                            // it has to apply at huge type too. It used to
                            // be 1 there, which is the one setting under
                            // which a long surname has no way to fit.
                            .minimumScaleFactor(hugeType ? 0.7 : 0.6)
                            .allowsTightening(true)
                            .fixedSize(horizontal: false, vertical: hugeType)
                        if !isNamed {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(isNamed ? householdDisplayName : "Name your household")
            .layoutPriority(1)
    }

    @ViewBuilder
    private var mastheadControls: some View {
            ActivityBellButton(size: 36) {
                pushed = .activity
            }

            Button {
                Haptic.tap()
                settingsPresented = true
            } label: {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Settings")

            // The host sits in the corner of every room — the same door
            // to your own profile that the plan already offers.
            Button {
                Haptic.tap()
                openOwnProfile()
            } label: {
                VStack(spacing: 2) {
                    AvatarCircle(initials: ownerInitial, tone: .neutralPair, size: 40,
                                 photo: members.first(where: \.isOwner)?.photoData)
                    Text("You")
                        .font(.jakarta(10, .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.inkFaint)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Your profile")
    }

    private var ownerInitial: String {
        String(owner?.name.first ?? "Y").uppercased()
    }

    private func openOwnProfile() {
        personShown = PersonRef(
            name: owner?.name ?? "You",
            colorHex: owner?.colorHex ?? "",
            memberID: owner?.persistentModelID
        )
    }

    // MARK: Banner

    /// The household's photo over the door, cropped at pick time to hold
    /// the faces in it. The caption names who sits here — the photo is of
    /// the household, so the line under it should be too.
    private var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $bannerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    if let data = profiles.first?.bannerPhotoData, let image = UIImage(data: data) {
                        Color.clear
                            .aspectRatio(BannerFocus.aspect, contentMode: .fit)
                            .overlay {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                            .plCardShadow()

                        HStack(spacing: 5) {
                            Image(systemName: "camera")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Change")
                                .font(.jakarta(11, .bold))
                        }
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                            .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                            .aspectRatio(BannerFocus.aspect, contentMode: .fit)
                            .overlay {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 18, weight: .medium))
                                    Text("Add a photo")
                                        .font(.jakarta(13, .bold))
                                }
                                .foregroundStyle(Color.inkFaint)
                            }
                    }
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Household photo")

            Text(HouseholdIdentity.seatedLine(names: members.map(\.name)))
                .font(.jakarta(12, .medium))
                .foregroundStyle(Color.inkFaint)
                .padding(.horizontal, 2)
        }
    }

    /// A banner hung before the crop existed is still whatever shape it
    /// was picked at, and the well is 16:9 now — so a portrait group shot
    /// gets centre-cropped and the people at the edges walk out of frame.
    /// Re-aim it once, in the background, and write it back.
    private func reframeStoredBannerIfNeeded() async {
        guard let profile = profiles.first, let data = profile.bannerPhotoData else { return }
        guard let image = UIImage(data: data), image.size.height > 0 else { return }
        let ratio = image.size.width / image.size.height
        // Already the right shape (within a hair) — leave it alone.
        guard abs(ratio - BannerFocus.aspect) > 0.02 else { return }

        let framed = await Task.detached(priority: .utility) {
            BannerFocus.framed(data)
        }.value
        if let framed { profile.bannerPhotoData = framed }
    }

    private func setBanner(_ framed: Data?) {
        guard let framed else { return }
        if let profile = profiles.first {
            profile.bannerPhotoData = framed
        } else {
            context.insert(HouseholdProfile(bannerPhotoData: framed))
        }
        Haptic.plate()
    }

    // MARK: The count
    // Three numbers under the photo; everything else lives one tap in.
    //
    // Four boxed tiles with a stock glyph each read as a dashboard of
    // buttons that weren't buttons. Instagram's profile triad is the
    // shape that works: number over word, three across, no chrome — and
    // the words are what someone would say out loud, so no glyph has to
    // explain them. The whole strip is the tap target now, which is both
    // a bigger target and one fewer capsule on the page.

    private var statsStrip: some View {
        Button {
            Haptic.tap()
            pushed = .stats
        } label: {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    CountBlock(value: "\(nightsPlated)", label: "Dinners")
                    CountDivider()
                    CountBlock(value: "\(platesEarned)", label: "Happy plates")
                    CountDivider()
                    CountBlock(value: "\(kissCount)", label: "Chef's kisses", accent: kissCount > 0)
                }

                HStack(spacing: 4) {
                    Text("All stats and badges")
                        .font(.jakarta(12, .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                // The only affordance saying this strip is tappable — it
                // cannot be the faintest thing on the page.
                .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens all stats and badges")
    }

    // MARK: The people

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel("People")

            VStack(spacing: 0) {
                ForEach(members, id: \.persistentModelID) { member in
                    SwipeRow(isOpen: swipeBinding(member), actions: swipeActions(for: member)) {
                        memberRow(member)
                    }
                    if member.persistentModelID != members.last?.persistentModelID {
                        Divider().overlay(Color.hairlineSoft)
                    }
                }
            }
            .padding(.horizontal, 18)
            .background(Color.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous).strokeBorder(Color.hairline))
            .plCardShadow()
            .animation(.plSnap, value: members.count)

            addSomeoneButton
        }
    }

    /// Every seat opens its person's profile — the head of table included.
    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(
                initials: member.firstInitial,
                // Colour is earned by being here. An invitation is the one
                // thing still unresolved, so it is the one grey row —
                // their colour arrives when they do.
                tone: (member.isOwner || !member.showsColor) ? .neutralPair : member.tone,
                size: 46,
                photo: member.photoData
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .plName()
                    .font(.jakarta(15, .bold))
                    .foregroundStyle(Color.ink)
                if member.isOwner, HouseholdIdentity.isPlaceholder(member.name) {
                    Text("Head of table")
                        .font(.jakarta(12, .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                } else {
                    // The seat, not a role line frozen at insert. "Partner ·
                    // plans & cooks" was printed under a name typed four
                    // seconds earlier about somebody with no account and
                    // nothing to plan with.
                    Text(member.subtitle)
                        .font(.jakarta(12, .semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 6)
            if !member.isOwner, member.cooks, !member.cookWeekdays.isEmpty {
                Text(dayChipLabel(member))
                    .font(.jakarta(12, .bold))
                    .foregroundStyle(member.tone.tone)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background(member.tone.tint, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.inkFaint)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            personShown = PersonRef(name: member.name, colorHex: member.colorHex, memberID: member.persistentModelID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens \(member.name)'s profile")
    }

    /// The head of table keeps their seat — you cannot swipe away the
    /// person who owns the account.
    private func swipeActions(for member: HouseholdMember) -> [SwipeAction] {
        guard !member.isOwner else { return [] }
        var actions: [SwipeAction] = []
        // An invitation nobody answered needs a way forward, not just a way
        // out. Same live link, sent again.
        if member.canResend {
            actions.append(SwipeAction(symbol: "paperplane", label: "Send again") {
                swipedMember = nil
                Task { await resend(member) }
            })
        }
        // Message only where a message can actually go. Everywhere else the
        // button opened a thread that could never deliver.
        if let url = member.messageURL {
            actions.append(SwipeAction(symbol: "bubble.right", label: "Message") {
                swipedMember = nil
                openURL(url)
            })
        }
        actions.append(.remove { removingMember = member })
        return actions
    }

    /// Reopen the composer with the link that already belongs to them.
    private func resend(_ member: HouseholdMember) async {
        let outcome = await Seats.resend(member, hostName: userFirstName)
        guard case .ready(let url) = outcome else {
            Haptic.warn()
            return
        }
        resendTarget = InviteTarget(name: member.name, phone: member.phoneE164)
        resendBody = Invitation.body(hostName: userFirstName, link: url)
    }

    /// Keyed by identity, not by name — two people called Sam are two
    /// rows, and swiping one must not open the other.
    private func swipeBinding(_ member: HouseholdMember) -> Binding<Bool> {
        Binding(
            get: { swipedMember == member.persistentModelID },
            set: { swipedMember = $0 ? member.persistentModelID : nil }
        )
    }

    private var addSomeoneButton: some View {
        Button {
            Haptic.tap()
            // One seat is free — the head of table. The rest is Plated+.
            if !PlatedPlus.gatingEnabled || PlatedPlus.isActive || members.count <= 1 {
                addPresented = true
            } else {
                paywallPresented = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add someone")
                    .font(.jakarta(15, .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .overlay {
                Capsule().strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    // MARK: Whose night it is
    // Under the people, because the rota is something the people do.

    private var cooksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                MicroLabel("Who cooks when")
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { turnsTipShown.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("How turns work")
                Spacer()
            }

            cookGrid

            Text("Tap a day to hand it to someone else. Nobody is notified.")
                .font(.jakarta(12, .medium))
                .foregroundStyle(Color.inkFaint)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take turns automatically")
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(Color.ink)
                    Text("Open nights go to whoever has cooked least")
                        .font(.jakarta(12, .medium))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Toggle("", isOn: $autoRotate)
                    .labelsHidden()
                    .sensoryFeedback(.selection, trigger: autoRotate)
                    .tint(Color.basil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
            .padding(.top, 8)

            if turnsTipShown {
                Text("A day with a standing cook always goes to them. Open nights go to whoever has cooked least that week, or to you with this off.")
                    .font(.jakarta(12, .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .lineSpacing(3)
                    .padding(14)
                    .background(Color.hairlineSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var cookGrid: some View {
        let today = Calendar.current.component(.weekday, from: .now)
        return HStack(spacing: 6) {
            ForEach(weekdaysInOrder, id: \.self) { weekday in
                cookCell(weekday: weekday, isToday: weekday == today)
            }
        }
    }

    private func cookCell(weekday: Int, isToday: Bool) -> some View {
        let cook = members.first { $0.cookWeekdays.contains(weekday) }
        let dayName = Calendar.current.weekdaySymbols[weekday - 1]
        return Button {
            cycleCook(weekday: weekday)
        } label: {
            VStack(spacing: 6) {
                Text(shortDay(weekday).uppercased())
                    .font(.jakarta(10, .extraBold))
                    .tracking(0.4)
                    .foregroundStyle(isToday ? Color.tomato : Color.inkFaint)
                // The seat swap animates — a new cook scales in rather than
                // hard-cutting inside the spring.
                ZStack {
                    if let cook {
                        AvatarCircle(member: cook, size: 28)
                            .id(cook.name)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    } else {
                        Circle()
                            .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                            .frame(width: 28, height: 28)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isToday ? Color.todayTint : Color.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(isToday ? Color.tomato : Color.hairline, lineWidth: isToday ? 2 : 1)
            }
        }
        .buttonStyle(.pressable)
        // A weekday abbreviation over an initial announces as neither.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cook.map { "\(dayName), \($0.name) cooks" } ?? "\(dayName), nobody yet")
        .accessibilityHint("Passes this night to the next person")
    }

    /// The seven days in calendar order, starting where the user's week
    /// starts.
    ///
    /// It used to run today-first, so on a Tuesday the rota read TUE WED THU
    /// FRI SAT SUN MON. A rota is a shape you learn by looking at it, and it
    /// cannot be learned if it rearranges itself every morning: the cell your
    /// eye goes to for Saturday moves one place to the left each day. Worse,
    /// the rest of the app already disagreed with it. `Calendar.startOfWeek`
    /// honours `firstWeekday`, so the week screen, the stats and the grocery
    /// roll-up were all counting a Sunday-to-Saturday week while this row
    /// drew a Tuesday-to-Monday one.
    ///
    /// `firstWeekday` rather than a hard-coded Sunday: it IS Sunday in the
    /// US, which is what was asked for, and it stays right for a household
    /// whose region starts on Monday instead of quietly being wrong for them.
    private var weekdaysInOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func shortDay(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    private func dayChipLabel(_ member: HouseholdMember) -> String {
        if member.cookWeekdays.count == 1, let day = member.cookWeekdays.first {
            return "\(Calendar.current.weekdaySymbols[day - 1])s"
        }
        // Same order as the rota above it. Sorting these today-first while
        // the grid ran week-first would print "Sat + Wed" under a row that
        // shows Wednesday to the left of Saturday.
        let order = weekdaysInOrder
        return member.cookWeekdays
            .sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            .map { shortDay($0) }
            .joined(separator: " + ")
    }

    /// Tap a day: hand it to the next person around the table, or open it up.
    private func cycleCook(weekday: Int) {
        Haptic.tap()
        let current = members.firstIndex { $0.cookWeekdays.contains(weekday) }
        withAnimation(.plPop) {
            if let current {
                members[current].cookWeekdays.removeAll { $0 == weekday }
                let next = current + 1
                if next < members.count {
                    members[next].cookWeekdays.append(weekday)
                }
                // Past the last member the day goes open.
            } else if let first = members.first {
                first.cookWeekdays.append(weekday)
            }
        }
    }
}

/// New seat at the household table — name, role, and the next color around
/// the rotation.
/// Adding someone to the household, with the three doors that actually
/// exist rather than the one that didn't.
///
/// **What was wrong.** This sheet asked for a name, offered three role
/// chips, and inserted a local row. Nobody was contacted. The person
/// appeared at the table having never been told they were invited to
/// anything, and there was no way from here to reach them — the real
/// invite lived on a different screen, behind the Table's avatar cluster,
/// which is not where anybody looks for "add someone to the household".
///
/// **The three doors.** Someone already on Plated is one tap, no
/// invitation needed. Someone in your contacts who isn't gets a real text
/// with a real link. And a name typed by hand still works, because a
/// six-year-old has no phone and still eats dinner — it is just no longer
/// the only thing on offer, and it says what it is.
/// Adding somebody, with the invitation as the thing the sheet is for.
///
/// **What was wrong.** The tomato pill — the app's one always-tomato
/// element, its strongest possible affordance — sat on a text field that
/// inserted a local row and contacted nobody. Setting a role there did
/// nothing twice over: the chip wrote a display string that was never read
/// again, and the person it described had no account to hold a role in.
///
/// **Now.** The primary door binds them to the table's CloudKit share and
/// opens a message carrying a link that actually opens it — and the seat
/// exists only if that message reports itself sent. The by-name door stays,
/// because a six-year-old has no phone and still eats dinner, but it says
/// what it is and takes the quieter pill.
struct AddMemberSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [HouseholdMember]

    @AppStorage("userFirstName") private var userFirstName = ""

    @State private var name = ""
    @State private var role = "member"
    @State private var pickingContact = false
    /// Who came back from the picker, held until the picker has actually
    /// gone. SwiftUI stands up one sheet at a time: presenting the composer
    /// from inside the picker's callback raced its dismissal, and the
    /// composer lost — you picked somebody and nothing happened at all.
    /// The same two-step the create menu already learned.
    @State private var picked: InviteTarget?
    @State private var inviteTarget: InviteTarget?
    @State private var inviteBody = ""
    @State private var working: String?
    @State private var problem: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add someone")
                    .font(.gabarito(21, .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                inviteDoor

                if let problem {
                    // Loud enough to be the answer to "did anything happen?"
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.tomato)
                        Text(problem)
                            .font(.jakarta(13, .semibold))
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tomatoTint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .transition(.opacity)
                }

                HStack(spacing: 10) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                    Text("No phone?")
                        .font(.jakarta(12, .bold))
                        .foregroundStyle(Color.inkFaint)
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
                .padding(.vertical, 2)

                byNameDoor
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)

    }

    /// The door that reaches a person.
    private var inviteDoor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TomatoPillButton(
                title: working ?? "Invite someone",
                systemImage: working == nil ? "person.badge.plus" : nil
            ) {
                // Tapping while it works must not stack a second picker.
                guard working == nil else { return }
                withAnimation(.plSnap) { problem = nil }
                startInvite()
            }
            .disabled(working != nil || !InviteComposer.isAvailable)
            .opacity(working != nil ? 0.6 : (InviteComposer.isAvailable ? 1 : 0.4))

            Text(InviteComposer.isAvailable
                 ? "They get a text with a link to join."
                 : "This iPhone can't send messages. Add them by name below.")
                .font(.jakarta(12, .medium))
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The door for somebody who will never have the app.
    private var byNameDoor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add by name")
                .font(.jakarta(15, .bold))
                .foregroundStyle(Color.ink)
            Text("For a kid, a grandparent, anyone without the app. Nothing gets sent to them.")
                .font(.jakarta(12, .medium))
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Their name", text: $name)
                .font(.jakarta(16, .semibold))
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                .plTappableField()

            HStack(spacing: 8) {
                roleChip("partner", "Partner")
                roleChip("kid", "Kid")
                roleChip("member", "Guest")
            }
            Text("Kids and guests don't get cook nights.")
                .font(.jakarta(11, .medium))
                .foregroundStyle(Color.inkFaint)

            InkPillButton(title: "Add") {
                let clean = name.trimmingCharacters(in: .whitespaces)
                guard !Seats.isTaken(clean, in: context) else {
                    Haptic.warn()
                    withAnimation(.plSnap) { problem = "\(clean) is already in your household. Try another name." }
                    return
                }
                // A new seat at the table is a plate-weight moment.
                Haptic.plate()
                Seats.layPlace(name: clean, role: role, in: context)
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
    }

    /// Bind them to the share first. Nothing is created here — if this
    /// can't produce a working link, we say so and no seat appears.
    /// Hand the whole picker → link → composer sequence to UIKit, which is
    /// the only layer that can promise a presentation happens after the one
    /// before it is genuinely gone. See `InviteFlow`.
    private func startInvite() {
        InviteFlow.run(
            hostName: userFirstName,
            prepare: { phone in
                await withTimeout(seconds: 20) {
                    await Seats.prepareInvite(phone: phone, email: nil, hostName: userFirstName)
                } ?? .noCloud
            }
        ) { result in
            switch result {
            case .sent(let name, let phone):
                Haptic.plate()
                Seats.confirmSent(name: name, phone: phone, email: nil, in: context)
                dismiss()
            case .notSent(let name, _):
                Haptic.warn()
                withAnimation(.plSnap) {
                    problem = "The message didn't send, so \(firstWord(name)) wasn't added. Try again."
                }
            case .noLink(_, let reason):
                Haptic.warn()
                withAnimation(.plSnap) { problem = reason }
            case .cancelled:
                break
            }
        }
    }

    private func beginInvite(_ target: InviteTarget) async {
        let who = target.name
        let phone = target.phone
        withAnimation(.plSnap) { working = "Preparing the invite…" }
        defer { withAnimation(.plSnap) { working = nil } }
        print("PLATED INVITE: preparing for \(who) at \(phone ?? "no number")")

        // CloudKit can sit forever on a bad network. A spinner that never
        // resolves is the same experience as a button that does nothing, so
        // give it a deadline and say so when it passes.
        let outcome = await withTimeout(seconds: 20) {
            await Seats.prepareInvite(phone: phone, email: nil, hostName: userFirstName)
        } ?? .noCloud

        switch outcome {
        case .ready(let url):
            print("PLATED INVITE: link ready — opening the composer")
            inviteBody = Invitation.body(hostName: userFirstName, link: url)
            inviteTarget = target
        case .noAccount:
            print("PLATED INVITE: no iCloud account for \(phone ?? "that address")")
            Haptic.warn()
            withAnimation(.plSnap) {
                problem = "That number has no iCloud account, so the link won't reach them. Try another number, or add them by name."
            }
        case .noCloud:
            print("PLATED INVITE: CloudKit unavailable, or the share could not be minted")
            Haptic.warn()
            withAnimation(.plSnap) {
                problem = "Sign in to iCloud to send an invite link."
            }
        }
    }

    /// The seat exists only if the message went.
    private func finishInvite(_ target: InviteTarget, sent: Bool) async {
        guard sent else {
            await Seats.abandon(phone: target.phone, email: nil)
            Haptic.warn()
            withAnimation(.plSnap) {
                problem = "The message didn't send, so \(firstWord(target.name)) wasn't added. Try again."
            }
            return
        }
        Haptic.plate()
        Seats.confirmSent(name: target.name, phone: target.phone, email: nil, in: context)
        dismiss()
    }

    private func firstWord(_ who: String) -> String {
        who.split(separator: " ").first.map(String.init) ?? who
    }

    /// Whichever finishes first: the work, or the clock.
    private func withTimeout<T: Sendable>(
        seconds: Double, _ work: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func roleChip(_ value: String, _ label: String) -> some View {
        let active = role == value
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) { role = value }
        } label: {
            Text(label)
                .font(.jakarta(13, .bold))
                .foregroundStyle(active ? Color.canvas : Color.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background {
                    if active {
                        Capsule().fill(Color.ink)
                    } else {
                        Capsule().strokeBorder(Color.hairline)
                    }
                }
        }
        .buttonStyle(.pressable)
    }
}
