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
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover && !$0.authorName.isEmpty }) private var storedPosts: [TablePost]
    private var posts: [TablePost] { storedPosts.filter(\.isUserContent) }
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
    @Environment(\.tabPop) private var tabPop
    @State private var pushed: HomeDestination?
    /// The face you tapped is the face that opens. See CookbookView.
    @Namespace private var zoom
    /// Which door was used. The owner is on this screen twice — in the
    /// masthead and in People — and two sources cannot share one id, so
    /// the tap records which one it came through.
    @State private var personDoor: ZoomID = .host
    @State private var personShown: PersonRef?
    @State private var swipedMember: PersistentIdentifier?
    /// The one dialog the roster raises, so two questions can never be up
    /// at once: Remove, Change role, and the demotion that clears nights.
    @State private var dialog: RosterDialog?
    /// A refusal, said under the roster: "Couldn't remove Riley."
    @State private var problem: String?
    /// The host's outbox while the household is first published (§6): what
    /// is still to go, and how many there were when publishing began.
    @State private var sharingPending = 0
    /// A member's phone that cannot reach iCloud right now (§10): edits
    /// still land locally and go out when it is back, and the line says so.
    @State private var cloudUnreachable = false
    /// Host tapped Refresh people — brief status under the roster.
    @State private var peopleRefreshNote: String?

    enum RosterDialog: Identifiable {
        case remove(HouseholdMember)
        case role(HouseholdMember)
        case demote(HouseholdMember, to: String)

        var id: String {
            switch self {
            case .remove(let m): return "remove-\(m.shareRecordName)"
            case .role(let m): return "role-\(m.shareRecordName)"
            case .demote(let m, let role): return "demote-\(m.shareRecordName)-\(role)"
            }
        }

        var member: HouseholdMember {
            switch self {
            case .remove(let m), .role(let m), .demote(let m, _): return m
            }
        }
    }
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
    private var kissCount: Int {
        let seats = TableKiss.seating(members: members, dishAuthors: posts.map(\.authorName))
        return posts.filter { $0.hasChefsKiss(seats: seats) }.count
    }
    private var platesEarned: Int { posts.reduce(0) { $0 + $1.totalPlates } }
    /// Every dinner this household has ever put on the plan.
    private var nightsPlated: Int { meals.count }

    /// Whether the house has a name at all, or is still "Your Household"
    /// with the pencil beside it. A member always has one and cannot rename
    /// it in any case: naming is the host's (§10, Settings).
    private var isNamed: Bool {
        if HouseholdShare.membership.owner != nil { return true }
        return !HouseholdIdentity.familyName(
            typed: householdName,
            appleFamilyName: userFamilyName,
            ownerName: owner?.name ?? ""
        ).isEmpty
    }

    /// "The Meadows" — the name the user typed, else the one Apple handed
    /// over at sign-in, else the head of table's own surname. Just the
    /// name: the word "household" is already the label above it.
    private var householdDisplayName: String {
        if HouseholdShare.membership.owner != nil { return memberHouseholdName }
        return HouseholdIdentity.displayName(
            typed: householdName,
            appleFamilyName: userFamilyName,
            ownerName: owner?.name ?? ""
        )
    }

    /// On a member's phone the name is the root's alone (§3.6). The
    /// reader's own Apple surname is not this household's name, and while
    /// the host has never typed one the root's `name` is empty, so a Nguyen
    /// who joined the Meadows household read "Nguyen" over Home. The same
    /// three steps `SettingsSheet.memberHouseholdName` takes, so the two
    /// screens cannot say different things about one household.
    private var memberHouseholdName: String {
        let typed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let cached = HouseholdShare.cachedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cached.isEmpty { return cached }
        let host = HouseholdShare.cachedOwnerName.trimmingCharacters(in: .whitespaces)
        let first = host.split(separator: " ").first.map(String.init) ?? host
        return "\(first.isEmpty ? "The host" : first)'s household"
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
                        .navigationTransition(.zoom(sourceID: personDoor, in: zoom))
                }
                .toolbar(.hidden, for: .navigationBar)
                .plSwipeBack()
        }
    }

    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                masthead
                sharingLine
                iCloudLine
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
        // Two `.sheet` modifiers on one view is undefined — see CLAUDE.md.
        .sheet(item: homeSheet, onDismiss: { namingFromMasthead = false }) { destination in
            switch destination {
            case .add:
                AddMemberSheet()
            case .resend(let target):
                InviteComposer(
                    recipients: [target.phone].compactMap { $0 },
                    body: resendBody
                ) { sent in
                    resendTarget = nil
                    // The same seat, so nothing is laid; only the date moves,
                    // and only when the message went. Matched on the seat
                    // record, never the name: two invited Sams are two rows.
                    guard sent, let member = members.first(where: {
                        $0.shareRecordName == target.seat && $0.seat == .invited
                    }) else { return }
                    member.invitedAt = .now
                }
                .ignoresSafeArea()
            case .paywall:
                PaywallSheet()
            case .settings:
                SettingsSheet(focusHouseholdName: namingFromMasthead)
            }
        }
        // See TabPopRequest: tapping Home from a pushed screen returns home.
        .onChange(of: tabPop) { _, request in
            guard request.tab == .home else { return }
            pushed = nil
            personShown = nil
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { dialog != nil },
                set: {
                    // Dismissing by tapping outside has to put the row
                    // back too, or the seat sits open with no dialog.
                    if !$0 {
                        dialog = nil
                        swipedMember = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            dialogButtons
        } message: {
            Text(dialogMessage)
        }
        .task {
            // The outbox is a plain book, not observed: read it while Home
            // is on screen and the line answers within a couple of seconds.
            while !Task.isCancelled {
                let pending = HouseholdShare.membership == .hosting ? HouseholdOutbox.shared.pending.count : 0
                if pending != sharingPending {
                    withAnimation(.plSnap) { sharingPending = pending }
                }
                // Same loop, one more fact: a member's iCloud standing
                // (§10). The account check is a local daemon query, and
                // `.notArmed` is a build without the entitlement, never a
                // phone that lost iCloud.
                var unreachable = false
                if case .member = HouseholdShare.membership {
                    let state = await TableSync.accountState()
                    unreachable = state != .available && state != .notArmed
                }
                if unreachable != cloudUnreachable {
                    withAnimation(.plSnap) { cloudUnreachable = unreachable }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task {
            await reframeStoredBannerIfNeeded()
        }
        // A tapped notice about the bell lands on the bell. Parked if Home
        // was not on screen yet; collected the moment it is.
        .onReceive(NotificationCenter.default.publisher(for: LinkRelay.activityRequested)) { _ in
            if LinkRelay.takeActivity() { pushed = .activity }
        }
        .onAppear {
            if LinkRelay.takeActivity() { pushed = .activity }
            // Stuck Invited labels (Alessandra) settle when Home is opened,
            // not only when CloudKit happens to send a share delta.
            Task {
                await TablePull.pull(reason: "home")
                await Seats.settleStuckInvites(in: context)
            }
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

    private enum HomeSheet: Identifiable {
        case add, resend(InviteTarget), paywall, settings
        var id: String {
            switch self {
            case .add: "add"
            case .resend(let target): "resend-\(target.id)"
            case .paywall: "paywall"
            case .settings: "settings"
            }
        }
    }
    private var homeSheet: Binding<HomeSheet?> {
        Binding(
            get: {
                if addPresented { return .add }
                if let resendTarget { return .resend(resendTarget) }
                if paywallPresented { return .paywall }
                return settingsPresented ? .settings : nil
            },
            set: {
                if $0 == nil {
                    addPresented = false
                    resendTarget = nil
                    paywallPresented = false
                    settingsPresented = false
                }
            }
        )
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
            HStack(alignment: .discCentre, spacing: 10) {
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
                            .plType(.display)
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
                                 photo: members.me?.photoData)
                    Text("You")
                        .plType(.micro)
                        .foregroundStyle(Color.inkSecondary)
                        // One line, always. This sits in a squeezed masthead
                        // HStack, so at XXXL it wrapped and broke the word
                        // across two lines: "HO" over "ST".
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Your profile")
            .matchedTransitionSource(id: ZoomID.host, in: zoom)
            .plDiscAligned(40)
            .plChrome()
    }

    // The corner says "You", so it has to be the reader's row and not the
    // head's: on a member's phone those are two different people.
    private var ownerInitial: String {
        String(members.me?.name.first ?? "Y").uppercased()
    }

    /// "Sharing with your household, 40 of 360." while the host's first
    /// publish is still going out (docs/household.md §6). The total is
    /// what `publishAll` counted when it began; without it the line still
    /// says that sharing is happening, and never invents a number.
    @ViewBuilder
    private var sharingLine: some View {
        // Only while the FIRST publish is still going out, which is what
        // `publishedAt` records (§3.6). The total is what `publishAll`
        // counted when it began and is never counted again, so after the
        // first drain every later queued edit — a recipe changed offline, a
        // night planned on a train — read "Sharing with your household, 359
        // of 360.": a fabricated progress bar for a publish that finished
        // weeks ago. The contract reserves this line for the first publish
        // and makes no claim about ordinary edits, so they say nothing.
        if sharingPending > 0, HouseholdShare.cachedPublishedAt == nil, Self.publishTotal > 0 {
            let total = Self.publishTotal
            Text("Sharing with your household, \(max(0, min(total, total - sharingPending))) of \(total).")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .transition(.plUnfold)
        }
    }

    /// "Can't reach iCloud. Changes reach your household when it's back."
    /// on a member's phone (docs/household.md §10), in the sharing line's
    /// own dress: a fact under the masthead, never a banner.
    @ViewBuilder
    private var iCloudLine: some View {
        if cloudUnreachable {
            Text("Can't reach iCloud. Changes reach your household when it's back.")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.plUnfold)
        }
    }

    /// Written by `HouseholdSync.publishAll`; read from the app group first
    /// because that is where every other household fact lives, and from
    /// the standard defaults second.
    private static var publishTotal: Int {
        let key = "plated.household.publishTotal"
        let group = UserDefaults(suiteName: WidgetBridge.appGroupID)?.integer(forKey: key) ?? 0
        return group > 0 ? group : UserDefaults.standard.integer(forKey: key)
    }

    // MARK: The roster's one dialog

    private var dialogTitle: String {
        switch dialog {
        case .remove(let member): return "Remove \(member.name) from the household?"
        case .role(let member): return "\(member.firstName)'s role"
        case .demote(let member, _): return "\(member.firstName)'s cook nights are cleared."
        case nil: return ""
        }
    }

    /// What is true for this seat (§8): a joined person loses the plan,
    /// the list and the cookbook; an invited seat goes away but its link
    /// still admits them; a by-name seat was never sent anything. The same
    /// sentences as `TableSeatsSheet`'s dialog, on purpose.
    private var dialogMessage: String {
        switch dialog {
        case .remove(let member):
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
        case .role:
            return "Partners share cook nights."
        case .demote, nil:
            return ""
        }
    }

    @ViewBuilder
    private var dialogButtons: some View {
        switch dialog {
        case .remove(let member):
            Button("Remove \(member.name)", role: .destructive) {
                swipedMember = nil
                Task { await remove(member) }
            }
            Button("Cancel", role: .cancel) { swipedMember = nil }
        case .role(let member):
            ForEach(["partner", "kid", "member"], id: \.self) { role in
                if role != member.role {
                    Button(Seats.roleLine(for: role)) { choose(role, for: member) }
                }
            }
            Button("Cancel", role: .cancel) { swipedMember = nil }
        case .demote(let member, let role):
            Button("Change to \(Seats.roleLine(for: role))") {
                swipedMember = nil
                Haptic.plate()
                Seats.changeRole(member, to: role, in: context)
            }
            Button("Cancel", role: .cancel) { swipedMember = nil }
        case nil:
            EmptyView()
        }
    }

    /// Demoting somebody who holds nights is said before it is done; every
    /// other change of role is one tap.
    private func choose(_ role: String, for member: HouseholdMember) {
        let losesNights = member.cooks && !member.cookWeekdays.isEmpty
            && role != "partner" && role != "owner"
        if losesNights {
            // The dialog binding has just cleared; the next question is
            // raised after the first has actually gone.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                dialog = .demote(member, to: role)
            }
        } else {
            swipedMember = nil
            Haptic.plate()
            Seats.changeRole(member, to: role, in: context)
        }
    }

    /// Through the one door (§8). On a refusal the row stays and the
    /// reason is said under the roster.
    private func remove(_ member: HouseholdMember) async {
        let first = member.firstName
        withAnimation(.plSnap) { problem = nil }
        if await Seats.remove(member, in: context) {
            Haptic.plate()
            Persist.save(context, "seat removed")
        } else {
            Haptic.warn()
            withAnimation(.plSnap) {
                problem = "Couldn't remove \(first). Check your connection and try again."
            }
        }
    }

    private func openOwnProfile() {
        let me = members.me
        personDoor = .host
        personShown = PersonRef(
            name: me?.name ?? "You",
            colorHex: me?.colorHex ?? "",
            memberID: me?.persistentModelID
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
                                .plType(.micro)
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
                                        .plType(.footnote, .bold)
                                }
                                .foregroundStyle(Color.inkSecondary)
                            }
                    }
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Household photo")

            // Who SITS here (§10): a seat that left is gone and an invited
            // seat is a message that went out and nothing that came back.
            // Naming either is the same claim as "You host this household
            // with Riley" over somebody who never opened the link.
            Text(HouseholdIdentity.seatedLine(
                names: members.filter { $0.seat != .left && $0.seat != .invited }.map(\.name)
            ))
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
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

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("All stats and badges")
                        .plType(.caption, .semibold)
                        .plActionLabel()
                }
                .foregroundStyle(Color.accentText)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Color.tomato.opacity(0.09), in: Capsule())
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

            if let problem {
                ProblemRow(problem)
                    .transition(.opacity)
            }
            if let peopleRefreshNote {
                Text(peopleRefreshNote)
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            addSomeoneButton
            if members.me?.isOwner == true {
                Button {
                    Haptic.tap()
                    Task { await refreshPeopleFromiCloud() }
                } label: {
                    Text("Refresh people from iCloud")
                        .plType(.caption, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.accentText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Looks for household members who are on your share but missing from this list.")
            }
        }
    }

    /// Host recovery after a stuck Invited clear: pull, then rebuild any
    /// accepted share participant who has no seat on this phone.
    private func refreshPeopleFromiCloud() async {
        withAnimation(.plSnap) { peopleRefreshNote = "Looking in iCloud…" }
        await TablePull.pull(reason: "refresh-people")
        let before = Set(members.map(\.persistentModelID))
        await Seats.settleStuckInvites(in: context)
        let after = Seats.all(in: context)
        let added = after.filter { !before.contains($0.persistentModelID) && $0.seat == .joined }
        withAnimation(.plSnap) {
            if let someone = added.first {
                peopleRefreshNote = added.count == 1
                    ? "\(someone.firstName) is back."
                    : "\(added.count) people restored."
            } else {
                peopleRefreshNote = "Nobody new on the share. Invite them again from Add someone."
            }
        }
    }

    /// Every seat opens its person's profile — the head of table included.
    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(
                initials: member.firstInitial,
                // Colour is earned by being here, so an invitation is grey
                // until they arrive; and the reader's own row is the neutral
                // one, which on a member's phone leaves the host in their
                // colour (§10). Keyed on `isOwner` that second half was the
                // wrong way round and disagreed with `TableSeatsSheet`,
                // which draws the same person's row.
                tone: (member.isMe || !member.showsColor) ? .neutralPair : member.tone,
                size: 46,
                photo: member.photoData
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .plName()
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                if member.isOwner, HouseholdIdentity.isPlaceholder(member.name) {
                    Text("Head of table")
                        .plType(.caption, .bold)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                } else {
                    // The seat, not a role line frozen at insert. "Partner ·
                    // plans & cooks" was printed under a name typed four
                    // seconds earlier about somebody with no account and
                    // nothing to plan with.
                    Text(member.subtitle)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 6)
            // Stuck invitation: one tap marks them joined in place.
            if member.seat == .invited, members.me?.isOwner == true {
                Button {
                    Haptic.tap()
                    Task { await Seats.markInviteArrived(member, in: context) }
                } label: {
                    Text("They're in")
                        .plType(.caption, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.accentText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(Color.tomato.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Marks them as joined in your household.")
            } else if !member.isMe, member.cooks, !member.cookWeekdays.isEmpty {
                Text(dayChipLabel(member))
                    .plType(.caption, .bold)
                    .foregroundStyle(member.tone.tone)
                    // One line. A status chip squeezed between a name and a
                    // chevron has nowhere to reflow, and at accessibility
                    // sizes "Sun + Mon" came apart into "Sun / + / Mo / n".
                    // Same reason the cook grid beside it holds.
                    .lineLimit(1)
                    .fixedSize()
                    .plChrome()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background(member.tone.tint, in: Capsule())
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            personDoor = .person(member.name)
            personShown = PersonRef(name: member.name, colorHex: member.colorHex, memberID: member.persistentModelID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens \(member.name)'s profile")
        .matchedTransitionSource(id: ZoomID.person(member.name), in: zoom)
    }

    /// The head of table keeps their seat — you cannot swipe away the
    /// person who owns the account.
    private func swipeActions(for member: HouseholdMember) -> [SwipeAction] {
        guard !member.isOwner else { return [] }
        // Only the host edits the roster (docs/household.md §8): a member's
        // phone can message or resend, but Remove is the head's alone.
        let readerIsHead = members.me?.isOwner == true
        var actions: [SwipeAction] = []
        // An invitation nobody answered needs a way forward, not just a way
        // out. Same live link, sent again — and only when Messages can
        // actually open. Without it the resend sheet crashed or blanked.
        if member.canResend, InviteComposer.isAvailable, readerIsHead {
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
        if readerIsHead {
            // What somebody is to the household, and only the host says.
            if member.seat != .left {
                actions.append(SwipeAction(symbol: "person.text.rectangle", label: "Change role") {
                    dialog = .role(member)
                })
            }
            actions.append(.remove { dialog = .remove(member) })
        }
        return actions
    }

    /// Reopen the composer with the link that already belongs to them: the
    /// same seat, so a second message cannot lay a second place.
    private func resend(_ member: HouseholdMember) async {
        let prepared = await Seats.resend(member, hostName: userFirstName)
        guard case .ready(let url) = prepared.outcome else {
            Haptic.warn()
            withAnimation(.plSnap) { problem = Seats.noLinkReason(prepared) }
            return
        }
        resendTarget = InviteTarget(
            seat: member.shareRecordName, name: member.name, phone: member.phoneE164
        )
        resendBody = Invitation.body(hostName: userFirstName, kind: .household, link: url)
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
                    .plType(.body, .bold)
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
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)

            // A 51pt switch beside a sentence is a fixed-width companion,
            // and at accessibility sizes it squeezed the label until
            // "automatically" broke across two lines as "automatical / ly".
            // The switch goes underneath rather than the words getting
            // narrower: it is the same answer the cook grid needed.
            let stacked = typeSize.isAccessibilitySize
            let label = VStack(alignment: .leading, spacing: 2) {
                Text("Take turns automatically")
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                Text("Open nights go to whoever has cooked least")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
            }
            // Named, then hidden: labelsHidden() takes it off the screen and
            // leaves it for VoiceOver, which was otherwise reading an
            // anonymous switch.
            let control = Toggle("Take turns automatically", isOn: $autoRotate)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: autoRotate)
                .tint(Color.basil)

            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 12) {
                        label
                        control
                    }
                } else {
                    HStack {
                        label
                        Spacer()
                        control
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
            .padding(.top, 8)

            if turnsTipShown {
                Text("A day with a standing cook always goes to them. Open nights go to whoever has cooked least that week, or to you with this off.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(14)
                    .background(Color.hairlineSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .transition(.plUnfold)
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
                    .plType(.micro, .extraBold)
                    .foregroundStyle(isToday ? Color.tomato : Color.inkSecondary)
                    // One line, always. Seven cells share the page width, so
                    // a cell is about 44pt wide on a 393pt phone and 32 of
                    // that is content. "MON" and "WED" are the two widest
                    // labels, and at a large text size they were the two
                    // that broke: "MO" over "N". Worse, a wrapped label made
                    // its own cell wider and taller than the five beside it,
                    // so the whole strip went ragged.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                // The seat swap animates — a new cook scales in rather than
                // hard-cutting inside the spring.
                ZStack {
                    if let cook {
                        AvatarCircle(member: cook, size: 28)
                            .id(cook.name)
                            .transition(.plArrive)
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
            // Seven fixed cells across one row: furniture, and it cannot
            // reflow. This is the grid plChrome was written for and the one
            // I did not apply it to. See VerticalAlignment.discCentre's
            // neighbour in Theme.swift.
            .plChrome()
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

    /// One letter, the way every seven-across weekday row in this app
    /// already does it: the month grid reads `veryShortWeekdaySymbols` and
    /// the week widget takes `prefix(1)`. This row was the only one asking
    /// for three letters, and seven cells split a 393pt page into about 44pt
    /// each — 32pt of content — which has to hold the label AND a 28pt
    /// avatar. It was tight at the default size and crowded above it.
    ///
    /// A single letter is ambiguous read alone and completely unambiguous in
    /// an ordered row of seven, which is why every calendar on the platform
    /// does this. VoiceOver is unaffected: the cell ignores its children and
    /// announces the full weekday name.
    private func shortDay(_ weekday: Int) -> String {
        Calendar.current.veryShortWeekdaySymbols[weekday - 1]
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
            // Three letters, not the grid's one. `shortDay` is a calendar
            // header, where an ordered row of seven makes "S" unambiguous;
            // this chip is a sentence about a person and reads "Sun + Mon".
            // It borrowed shortDay and briefly became "S + M".
            .sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            .map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
            .joined(separator: " + ")
    }

    /// Tap a day: hand it to the next person around the table, or open it up.
    private func cycleCook(weekday: Int) {
        Haptic.tap()
        // Ordered by record name, not by the query: `@Query` sorts on
        // `createdAt`, and once seats arrive by merge that order differs per
        // phone, so the same tap would hand Tuesday to different people in
        // the same household.
        let order = members.sorted { $0.shareRecordName < $1.shareRecordName }
        let current = order.firstIndex { $0.cookWeekdays.contains(weekday) }
        withAnimation(.plPop) {
            if let current {
                order[current].cookWeekdays.removeAll { $0 == weekday }
                let next = current + 1
                if next < order.count {
                    order[next].cookWeekdays.append(weekday)
                }
                // Past the last member the day goes open.
            } else if let first = order.first {
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

    @AppStorage("userFirstName") private var userFirstName = ""

    @State private var name = ""
    /// Partner by default: the first person invited to a household is
    /// almost always the one who shares the cooking. Applies to both doors.
    @State private var role = "partner"
    /// Minting the seatless link for Copy link.
    @State private var copying = false
    @State private var copied = false
    @State private var problem: String?
    /// People in this phone's contacts who already have Plated.
    ///
    /// The Table's own invite sheet has offered this since it shipped and
    /// the household's did not, so the more intimate room was the one that
    /// texted a signup link to somebody already holding the app. Empty
    /// until the directory answers and empty forever if it never does: the
    /// two doors below work regardless, so this is a shortcut and never a
    /// dependency.
    @State private var onPlated: [Directory.Match] = []
    @State private var searchingContacts = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add someone")
                    // .title at 22, the app's sheet masthead.
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)

                roleChips

                // Before the text door, because somebody already on Plated
                // is the likeliest person being added and asking them by
                // name costs one tap instead of a contact picker and a
                // message they do not need.
                if isHost { alreadyOnPlated }

                inviteDoor

                if let problem {
                    // Loud enough to be the answer to "did anything happen?"
                    ProblemRow(problem)
                        .transition(.opacity)
                }

                // "No phone?" is the second half of a choice. On a member's
                // phone there is no first half, so there is nothing to
                // divide and Add by name is simply the door.
                if isHost {
                    HStack(spacing: 10) {
                        Rectangle().fill(Color.hairline).frame(height: 1)
                        Text("No phone?")
                            .plType(.caption, .bold)
                            .foregroundStyle(Color.inkSecondary)
                        Rectangle().fill(Color.hairline).frame(height: 1)
                    }
                    .padding(.vertical, 2)
                }

                byNameDoor
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .task { await findPeople() }
    }

    /// Ask the directory which of this phone's contacts already have the
    /// app. Nothing here is required for either invite door to work, so a
    /// refused permission, an unregistered phone or a directory that never
    /// answers all end the same way: the section is simply not drawn.
    private func findPeople() async {
        guard isHost, Directory.isRegistered else { return }
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

        let found = await Directory.onPlated(contacts: contacts)
        withAnimation(.plSnap) {
            // Somebody already in the household is not a suggestion.
            onPlated = found.filter { !Seats.isTaken($0.name, in: context) }
        }
    }

    /// The role, above both doors, because it is true of both: an invited
    /// partner and a by-name partner both share cook nights.
    private var roleChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                roleChip("partner", "Partner")
                roleChip("kid", "Kid")
                roleChip("member", "Member")
            }
            Text("Partners share cook nights.")
                .plType(.micro, .medium)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    /// The door that reaches a person. Only the head of table has one: a
    /// member does not mint a household link (§9), so offering them the
    /// pill was a control that could only ever refuse, and the refusal told
    /// somebody signed into iCloud to sign into iCloud. DESIGN.md, Honesty:
    /// where the app cannot do a thing it says so rather than showing a
    /// door. Add by name stays, because a member's own by-name seats are
    /// explicitly theirs to lay (§8, "Max comes with you").
    /// Only the head of table mints household links (§9).
    private var isHost: Bool { HouseholdShare.membership.owner == nil }

    @ViewBuilder
    private var inviteDoor: some View {
        if !isHost {
            Text("Only \(hostFirstName) can invite people to this household.")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            hostInviteDoor
        }
    }

    /// The host's first name, from the app-group value the join recorded.
    private var hostFirstName: String {
        let host = HouseholdShare.cachedOwnerName.trimmingCharacters(in: .whitespaces)
        let first = host.split(separator: " ").first.map(String.init) ?? host
        return first.isEmpty ? "the host" : first
    }

    private var hostInviteDoor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if InviteComposer.isAvailable {
                TomatoPillButton(title: "Invite someone", systemImage: "person.badge.plus") {
                    withAnimation(.plSnap) { problem = nil }
                    startInvite()
                }
                Text("They get a text with a link. Anyone who joins sees the plan, the grocery list and the cookbook, and can change them.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // No Messages on this iPhone. The link still exists, and a
                // seatless one lets whoever joins pick their seat (§7).
                InkPillButton(
                    title: copied ? "Copied" : (copying ? "Preparing the link" : "Copy link"),
                    systemImage: copied ? "checkmark" : "link"
                ) {
                    copyLink()
                }
                .disabled(copying)
                Text("Send it however you like. Whoever joins picks their seat.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The door for somebody who will never have the app.
    /// The people this phone knows who already have Plated, each a single
    /// tap away from an invitation.
    ///
    /// Hidden entirely when the directory finds nobody, which is the common
    /// case early on: an empty "Already on Plated" heading is a verdict on
    /// the person's friends rather than a state of the app. The spinner
    /// says nothing while it looks, for the same reason.
    @ViewBuilder
    private var alreadyOnPlated: some View {
        if searchingContacts {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for people you know")
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !onPlated.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel("Already on Plated")
                ForEach(onPlated) { match in
                    HStack(spacing: 12) {
                        // Neutral, not the tone a real seat wears: nobody
                        // here has been asked yet.
                        AvatarCircle(
                            initials: initials(for: match.name),
                            tone: .neutralPair,
                            size: 40
                        )
                        Text(match.name)
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Spacer()
                        if InviteComposer.isAvailable {
                            Button {
                                withAnimation(.plSnap) { problem = nil }
                                startInvite(to: InviteFlow.Recipient(name: match.name, phone: match.phone))
                            } label: {
                                Text("Invite")
                                    .plType(.footnote, .bold)
                                    .plActionLabel()
                                    .foregroundStyle(Color.canvas)
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 36)
                                    .background(Color.ink, in: Capsule())
                                    .frame(minHeight: 44)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Invite \(match.name) to your household")
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    /// Two letters for the avatar. A fifth private copy of this in the app,
    /// which is the OptionRow story starting again; it belongs on
    /// AvatarCircle and moving all five is its own change.
    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var byNameDoor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add by name")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
            Text("For a kid, a grandparent, anyone without the app. Nothing gets sent to them.")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Their name", text: $name)
                .plType(.body)
                .padding(14)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                .plTappableField()

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
        }
    }

    /// Hand the whole picker, link, composer sequence to UIKit, which is
    /// the only layer that can promise a presentation happens after the one
    /// before it is genuinely gone. See `InviteFlow`. Nothing is created
    /// here: the seat is laid only when the composer reports the message
    /// sent, and a link that cannot be minted says so and lays nothing.
    private func startInvite(to recipient: InviteFlow.Recipient? = nil) {
        InviteFlow.run(
            kind: .household,
            hostName: userFirstName,
            to: recipient,
            prepare: {
                // CloudKit can sit forever on a bad network. A spinner that
                // never resolves is the same experience as a button that
                // does nothing, so give it a deadline and say so when it
                // passes.
                // A timeout is not a signed-out account, and it used to be
                // reported as one.
                await withTimeout(seconds: 20) {
                    await Seats.prepareInvite(kind: .household, hostName: userFirstName)
                } ?? .timedOut
            }
        ) { result in
            switch result {
            case .sent(let name, let phone, let prepared):
                Haptic.plate()
                Seats.confirmSent(
                    kind: .household, prepared: prepared, name: name, phone: phone,
                    email: nil, role: role, in: context
                )
                Persist.save(context, "seat invited")
                dismiss()
            case .failed(let name, _, let prepared):
                Seats.abandon(kind: .household, prepared: prepared)
                Haptic.warn()
                withAnimation(.plSnap) {
                    problem = "The message didn't send, so \(firstWord(name)) wasn't added. Try again."
                }
            case .declined(_, _, let prepared):
                Seats.abandon(kind: .household, prepared: prepared)
            case .noLink(_, let reason):
                Haptic.warn()
                withAnimation(.plSnap) { problem = reason }
            case .cancelled:
                break
            }
        }
    }

    /// A seatless household link on the pasteboard. Only once it exists:
    /// "Copied" is a claim, and it is made after the copy.
    private func copyLink() {
        guard !copying else { return }
        withAnimation(.plSnap) {
            problem = nil
            copying = true
            copied = false
        }
        Task {
            // Two nils, and they are not the same sentence: the outer one is
            // the clock running out, the inner one is CloudKit refusing.
            let answer = await withTimeout(seconds: 20) {
                await Seats.shareableLink(kind: .household, hostName: userFirstName)
            }
            withAnimation(.plSnap) { copying = false }
            guard let url = answer ?? nil else {
                Haptic.warn()
                let reason = Seats.noLinkReason(answer == nil ? .timedOut : nil)
                withAnimation(.plSnap) { problem = reason }
                return
            }
            UIPasteboard.general.url = url
            Haptic.plate()
            withAnimation(.plSnap) { copied = true }
            print("PLATED HOUSEHOLD: copied a seatless household link")
        }
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
                .plType(.footnote, .bold)
                .plActionLabel()
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
                // Only the SELECTED chip was tappable. A filled capsule hit
                // tests; a stroked one hit tests its ring and nothing else,
                // so the two chips a person actually needs to reach were the
                // two that ignored them.
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
