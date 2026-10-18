import SwiftUI
import SwiftData
import PhotosUI

/// Home — the household itself. Who sits here, what they have earned
/// together, and whose night it is. The banner is theirs to hang, the
/// deeper numbers live one tap in, and the people come before the
/// paperwork: this page is about a family, not a dashboard.
struct HouseholdHomeView: View {
    var embedded = false

    var body: some View {
        HouseholdDestination(embedded: embedded).equatable()
    }
}

/// Like ProfileDestination, keep newly initialized Query wrappers out of
/// navigation's destination comparison without suppressing live data updates.
private struct HouseholdDestination: View, Equatable {
    var embedded: Bool

    var body: some View {
        HouseholdHomeContent(embedded: embedded)
    }
}

private struct HouseholdHomeContent: View {
    /// Root when opened from the app's Household destination; pushed when
    /// opened from a person's profile. The pushed form borrows the parent
    /// navigation stack and draws a real back affordance.
    var embedded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.activeAppTab) private var activeAppTab
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    /// Seats a body may touch. The raw `@Query` can still hold a row whose
    /// backing data was deleted mid-render; `memberRow` trapped there.
    private var roster: [HouseholdMember] { members.readable }
    // An author is the one thing every real post has. The empty-name
    // rows are blanks the CloudKit mirror adopts (TablePost.isBlank),
    // and counting them puts a dish on the board nobody cooked.
    @Query(filter: #Predicate<TablePost> { !$0.isDiscover && !$0.authorName.isEmpty }) private var storedPosts: [TablePost]
    private var posts: [TablePost] { storedPosts.filter(\.isUserContent) }
    private var dishPosts: [TablePost] { posts.filter { $0.kind == "dish" } }
    @Query private var meals: [PlannedMeal]
    // Oldest first — see PersonProfileView: the oldest row is the
    // household's one true profile when a sync race left more than one.
    @Query(sort: \HouseholdProfile.createdAt) private var profiles: [HouseholdProfile]

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
    @State private var namingFromMasthead = false
    @State private var turnsTipShown = false
    @State private var rotationDay: Int?
    @State private var rotationPerson: String?
    @State private var bannerItem: PhotosPickerItem?
    /// Item-based, not two `isPresented` booleans: a binding set
    /// asynchronously (the launch harness does exactly that) pops an
    /// isPresented destination straight back off.
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
    @State private var removingName: String?
    /// The host's outbox while the household is first published (§6): what
    /// is still to go, and how many there were when publishing began.
    @State private var sharingPending = 0
    /// A member's phone that cannot reach iCloud right now (§10): edits
    /// still land locally and go out when it is back, and the line says so.
    @State private var cloudUnreachable = false
    /// Host tapped Refresh people — brief status under the roster.
    @State private var peopleRefreshNote: String?

    enum RosterDialog: Identifiable {
        case remove(HouseholdRemoval.Target)
        case role(HouseholdMember)
        case demote(HouseholdMember, to: String)

        var id: String {
            switch self {
            case .remove(let m): return "remove-\(m.id)"
            case .role(let m): return "role-\(m.shareRecordName)"
            case .demote(let m, let role): return "demote-\(m.shareRecordName)-\(role)"
            }
        }

    }
    #if DEBUG
    /// One arming per view lifetime, so a re-appearance can't queue a
    /// second push behind the first.
    @State private var statsFlagHandled = false
    #endif

    enum HomeDestination: String, Identifiable {
        case activity, stats, settings
        var id: String { rawValue }
    }

    private var owner: HouseholdMember? { roster.first(where: \.isOwner) }
    private var kissCount: Int {
        let seats = TableKiss.seating(members: roster, dishAuthors: dishPosts.map(\.authorName))
        return dishPosts.filter { $0.hasChefsKiss(seats: seats) }.count
    }
    private var platesEarned: Int { dishPosts.reduce(0) { $0 + $1.totalPlates } }
    /// Every dinner this household has put on the plan. Breakfast and a
    /// deleted night are not dinners simply because they share a model.
    private var nightsPlated: Int {
        meals.filter { !$0.isDeleted && $0.slotValue == .dinner }.count
    }

    /// An unnamed household opens settings with the name field focused.
    /// Members cannot rename the shared household.
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
        return first.isEmpty ? "Organizer's household" : "\(first)'s household"
    }

    @ViewBuilder
    var body: some View {
        if embedded {
            navigablePage
        } else {
            NavigationStack { navigablePage }
        }
    }

    private var navigablePage: some View {
        page
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                case .stats: HouseholdStatsView()
                case .settings:
                    SettingsSheet(
                        focusHouseholdName: namingFromMasthead,
                        isPushed: true,
                        scope: .household
                    )
                }
            }
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID, authorID: person.authorID)
                    .navigationTransition(.zoom(sourceID: personDoor, in: zoom))
            }
            .toolbar(.hidden, for: .navigationBar)
            .plSwipeBack()
            .hidesFloatingChrome()
    }

    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                masthead
                sharingLine
                iCloudLine
                banner
                peopleSection
                cooksSection
                statsStrip
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, 6)
            .padding(.bottom, Layout.focusedPageBottom)
        }
        // Scrolling puts an open row away, the way a list does.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting, swipedMember != nil {
                withAnimation(.plSnap) { swipedMember = nil }
            }
        }
        .background(Color.canvas)
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
            case .rotation(let day):
                rotationEditor(day)
            }
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
        .onAppear {
            Presence.shared.householdVisible = activeAppTab == .week
            #if DEBUG
            if LaunchFlags.consume("-plated-review-add-household-member") {
                addPresented = true
            }
            #endif
            // Names already on this phone (invite log, twin seats) bind
            // before any CloudKit wait. TF26 left Alessandra as New member
            // until a pull that never had to run for the name to be known.
            Seats.bindShareIdentity(in: context, standings: [])
            // Stuck Invited labels settle when Home is opened, not only
            // when CloudKit happens to send a share delta. Replay the zone
            // so a seat we deleted locally but that still exists in iCloud
            // is not skipped by a stale change token.
            if !PlatedApp.usesPreviewContainer {
                Task {
                    TableShare.requestReplay(zoneOwner: "")
                    await TablePull.pull(reason: "home")
                    await Seats.settleStuckInvites(in: context)
                }
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
        .onChange(of: activeAppTab) { _, tab in
            // The shell preserves every visited tab under opacity, so this
            // screen may stay mounted while another tab is visible.
            Presence.shared.householdVisible = tab == .week
        }
        .onDisappear { Presence.shared.householdVisible = false }
        .onChange(of: bannerItem) { _, item in
            guard let item else { return }
            Task {
                guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
                // Vision on a full-size photo is not main-thread work.
                let framed = await Task.detached(priority: .userInitiated) {
                    BannerFocus.framed(raw) ?? ProfilePhoto.downscale(raw)
                }.value
                setBanner(framed)
            }
        }
    }

    private enum HomeSheet: Identifiable {
        case add, resend(InviteTarget), paywall, rotation(Int)
        var id: String {
            switch self {
            case .add: "add"
            case .resend(let target): "resend-\(target.id)"
            case .paywall: "paywall"
            case .rotation(let day): "rotation-\(day)"
            }
        }
    }
    private var homeSheet: Binding<HomeSheet?> {
        Binding(
            get: {
                if let rotationDay { return .rotation(rotationDay) }
                if addPresented { return .add }
                if let resendTarget { return .resend(resendTarget) }
                if paywallPresented { return .paywall }
                return nil
            },
            set: {
                if $0 == nil {
                    rotationDay = nil
                    addPresented = false
                    resendTarget = nil
                    paywallPresented = false
                }
            }
        )
    }

    // MARK: Masthead

    private var hugeType: Bool { typeSize >= .accessibility1 }

    @ViewBuilder
    private var masthead: some View {
        let layout = hugeType ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                              : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if embedded { backButton }
            mastheadTitle
            HStack(spacing: 4) { mastheadControls }.plChrome()
        }
    }

    private var mastheadTitle: some View {
        Text(householdDisplayName)
            .plType(hugeType ? .heading : .pageTitle)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("household-page-title")
    }

    private var backButton: some View {
        Button {
            Haptic.tap()
            dismiss()
        } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 38, height: 38)
                .background(Color.canvas.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1.5))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Back")
    }

    @ViewBuilder
    private var mastheadControls: some View {
            Button {
                Haptic.tap()
                namingFromMasthead = !isNamed
                pushed = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .plTapTarget()
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Household settings")
            .accessibilityHint("Shows household name, sharing and membership settings.")
            .accessibilityIdentifier("household-settings")

            ActivityBellButton(size: 44, accessibilityID: "household-notifications-bell") {
                pushed = .activity
            }

            if !embedded {
                // The root Household page keeps the same profile door as the
                // rest of the app. The pushed page omits it because its back
                // button already returns to that exact profile.
                Button {
                    Haptic.tap()
                    openOwnProfile()
                } label: {
                    VStack(spacing: 2) {
                        AvatarCircle(initials: ownerInitial, tone: .neutralPair, size: 40,
                                     photo: roster.me?.photoData)
                        Text("You")
                            .plType(.micro)
                            .foregroundStyle(Color.inkSecondary)
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
    }

    // The corner says "You", so it has to be the reader's row and not the
    // head's: on a member's phone those are two different people.
    private var ownerInitial: String {
        String(roster.me?.name.first ?? "Y").uppercased()
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

    /// Locked reach copy on a member's phone (docs/household.md §10), in
    /// the sharing line's own dress: a fact under the masthead, never a
    /// banner, with the one retry the copy lock names.
    @ViewBuilder
    private var iCloudLine: some View {
        if cloudUnreachable {
            VStack(alignment: .leading, spacing: 6) {
                Text(HouseholdIdentity.PeopleCopy.reachFailure)
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(HouseholdIdentity.PeopleCopy.tryAgain) {
                    Haptic.tap()
                    Task { await recheckiCloud() }
                }
                .plType(.caption, .bold)
                .plActionLabel()
                .foregroundStyle(Color.accentText)
                .buttonStyle(.pressable)
            }
            .transition(.plUnfold)
        }
    }

    private func recheckiCloud() async {
        var unreachable = false
        if case .member = HouseholdShare.membership {
            let state = await TableSync.accountState()
            unreachable = state != .available && state != .notArmed
        }
        withAnimation(.plSnap) { cloudUnreachable = unreachable }
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
                if member.identityKey == nil {
                    return "We’ll check this profile’s shared account in iCloud. If it isn’t linked, only the saved profile is removed and existing invitation links may still work."
                }
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
    private func remove(_ target: HouseholdRemoval.Target) async {
        guard removingName == nil,
              let member = context.model(for: target.id) as? HouseholdMember,
              member.isRenderable else { return }
        let first = member.firstName
        removingName = first
        defer { removingName = nil }
        withAnimation(.plSnap) { problem = nil; peopleRefreshNote = nil }
        let result = await Seats.remove(member, in: context)
        if result.succeeded {
            Haptic.plate()
            peopleRefreshNote = result.message(name: first)
        } else {
            Haptic.warn()
            withAnimation(.plSnap) { problem = result.message(name: first) }
        }
    }

    private func openOwnProfile() {
        let me = roster.me
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
                            .frame(height: 104)
                            .overlay {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))

                        HStack(spacing: 5) {
                            Image(systemName: "camera")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Change")
                                .plType(.micro)
                        }
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.ultraThinMaterial, in: Radius.shape(Radius.chip))
                        .padding(10)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(Color.fill, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a household photo")
                                    .plType(.footnote, .bold)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Shared with everyone in your household")
                                    .plType(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .layoutPriority(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                                .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
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
            Text(Seats.seatedCaption(among: roster, reader: roster.me))
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
        WidgetBridge.publish(from: context)
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
                    CountBlock(value: "\(platesEarned)", label: "Likes")
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
                .background(Color.olive.opacity(0.09), in: Radius.shape(Radius.chip))
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
            HStack(spacing: 8) {
                Text("People").plType(.heading)
                Text("\(roster.listed.count) people").plType(.caption).foregroundStyle(Color.inkSecondary)
                Spacer()
                addSomeoneButton
                if roster.me?.isOwner == true {
                    Menu {
                        Button {
                            Haptic.tap()
                            Task { await refreshPeopleFromiCloud() }
                        } label: {
                            Label("Refresh from iCloud", systemImage: "arrow.clockwise")
                        }
                        .disabled(peopleRefreshNote == "Looking in iCloud…")
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("People options")
                    .accessibilityHint("Includes iCloud recovery for a missing household member.")
                }
            }

            VStack(spacing: 0) {
                let people = roster.listed
                let lastID = people.last?.persistentModelID
                let reader = people.me
                let readerIsHead = reader?.isOwner == true
                ForEach(people, id: \.persistentModelID) { member in
                    SwipeRow(isOpen: swipeBinding(member), actions: swipeActions(for: member, readerIsHead: readerIsHead)) {
                        // SwipeRow retains this closure during removal animation.
                        if member.isRenderable {
                            memberRow(member, readerIsHead: readerIsHead, reader: reader, among: people.filter(\.isRenderable))
                        }
                    }
                    if member.persistentModelID != lastID {
                        Divider().overlay(Color.hairlineSoft)
                    }
                }
            }
            .background(Color.canvas)
            .animation(.plSnap, value: roster.count)
            .disabled(removingName != nil)

            if let removingName {
                ProgressView("Removing \(removingName)…")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .accessibilityIdentifier("household-removal-progress")
            }
            if let problem {
                ProblemRow(problem)
                    .transition(.opacity)
            }
            if let peopleRefreshNote {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: peopleRefreshNote == HouseholdIdentity.PeopleCopy.reachFailure
                          ? "icloud.slash"
                          : peopleRefreshNote == "Looking in iCloud…" ? "icloud" : "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(peopleRefreshNote == HouseholdIdentity.PeopleCopy.reachFailure
                                         ? Color.accentText : Color.completion)
                    Text(peopleRefreshNote)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if peopleRefreshNote == HouseholdIdentity.PeopleCopy.reachFailure {
                        Button(HouseholdIdentity.PeopleCopy.tryAgain) {
                            Haptic.tap()
                            Task { await refreshPeopleFromiCloud() }
                        }
                        .plType(.caption, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.accentText)
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color.raisedFill, in: Radius.shape(Radius.card))
                .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
                .transition(.plUnfold)
            }

        }
    }

    /// Host recovery after a stuck Invited clear: full zone reread, then
    /// rebuild any accepted share participant who has no seat on this phone.
    private func refreshPeopleFromiCloud() async {
        withAnimation(.plSnap) { peopleRefreshNote = "Looking in iCloud…" }
        let state = await TableSync.accountState()
        if state != .available && state != .notArmed {
            withAnimation(.plSnap) {
                peopleRefreshNote = HouseholdIdentity.PeopleCopy.reachFailure
            }
            return
        }
        // Reread the whole household zone so a seat that still exists there
        // is not skipped because our change token moved past it.
        TableShare.requestReplay(zoneOwner: "")
        await TablePull.pull(reason: "refresh-people")
        guard TablePull.lastHouseholdReadSucceeded else {
            withAnimation(.plSnap) { peopleRefreshNote = HouseholdIdentity.PeopleCopy.reachFailure }
            return
        }
        let before = Set(roster.map(\.persistentModelID))
        await Seats.settleStuckInvites(in: context)
        let after = Seats.all(in: context)
        let added = after.filter { !before.contains($0.persistentModelID) && $0.seat == .joined }
        let missing = HouseholdInviteLog.unsettled(against: after)
        withAnimation(.plSnap) {
            if let someone = added.first {
                let label = HouseholdIdentity.isUnnamed(someone.name)
                    ? "A household member"
                    : someone.firstName
                peopleRefreshNote = added.count == 1
                    ? "\(label) is here. Tap their row to open their profile."
                    : "\(added.count) people restored."
            } else if let invite = missing.first {
                peopleRefreshNote = "\(invite.name)'s invitation is still waiting for a confirmed join."
            } else {
                peopleRefreshNote = "Household refreshed."
            }
        }
    }

    /// Every seat opens its person's profile — the head of table included.
    ///
    /// `readerIsHead` is computed once in `peopleSection` so this row never
    /// walks the full `@Query` (and a deleted twin) via `members.me`.
    private func memberRow(
        _ member: HouseholdMember,
        readerIsHead: Bool,
        reader: HouseholdMember?,
        among people: [HouseholdMember]
    ) -> some View {
        let drawn = Seats.resolvedDisplay(for: member, among: people, reader: reader)
        let name = drawn.name
        let colorHex = member.colorHex
        let memberID = member.persistentModelID
        let isMe = member.isMe
            || (reader != nil && reader!.persistentModelID == member.persistentModelID)
        let seat = member.seat
        let tone = member.tone
        let recorded = MemberDinnerActivity(member: member, roster: people, meals: meals,
            remote: PlanLedger.shared.all, posts: posts)
        let latest = PlanMemberEvent.latest(member: member, roster: people, meals: meals,
            remote: PlanLedger.shared.all, recorded: recorded.latest)
        let subtitle = !isMe && member.seat.canPost
            ? latest.map { "\($0.line) · \($0.date.formatted(.relative(presentation: .numeric)))" } ?? drawn.subtitle
            : drawn.subtitle
        let photo = drawn.photo
        let firstInitial = name.first.map(String.init)?.uppercased() ?? member.firstInitial
        let showsColor = member.showsColor
        let isOwner = member.isOwner
        return HStack(spacing: 8) {
            Button {
                Haptic.tap()
                personDoor = .person(name)
                personShown = PersonRef(name: name, colorHex: colorHex, memberID: memberID)
            } label: {
                HStack(spacing: 12) {
                    AvatarCircle(
                        initials: firstInitial,
                        tone: (isMe || !showsColor) ? .neutralPair : tone,
                        size: 36,
                        photo: photo
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .plName()
                            .plType(.body, .medium)
                            .foregroundStyle(Color.ink)
                        Text(subtitle)
                            .plType(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(name)
            .accessibilityValue(subtitle)
            .accessibilityHint("Opens profile")
            .matchedTransitionSource(id: ZoomID.person(name), in: zoom)

            // Stuck invitation: one tap marks them joined in place.
            if seat == .invited, readerIsHead {
                Button {
                    Haptic.tap()
                    Task {
                        guard let live = liveMember(memberID) else { return }
                        await Seats.markInviteArrived(live, in: context)
                    }
                } label: {
                    Text("They're in")
                        .plType(.caption, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.accentText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(Color.olive.opacity(0.09), in: Radius.shape(Radius.chip))
                        // Keep the compact status-pill treatment while the
                        // button itself still meets the 44-point tap target.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Marks them as joined in your household.")
            }

            if !isOwner {
                memberActionsMenu(member, readerIsHead: readerIsHead)
            }
        }
        .padding(.vertical, 12)
    }

    private func memberActionsMenu(_ member: HouseholdMember, readerIsHead: Bool) -> some View {
        let id = member.persistentModelID
        let canResend = member.canResend
        let messageURL = member.messageURL
        let seat = member.seat
        let name = member.name
        return Menu {
            if canResend, InviteComposer.isAvailable, readerIsHead {
                Button("Send invitation again", systemImage: "paperplane") {
                    Task {
                        guard let live = liveMember(id) else { return }
                        await resend(live)
                    }
                }
            }
            if let url = messageURL {
                Button("Message", systemImage: "bubble.right") { openURL(url) }
            }
            if readerIsHead, seat != .left {
                Button("Change role", systemImage: "person.text.rectangle") {
                    guard let live = liveMember(id) else { return }
                    dialog = .role(live)
                }
            }
            if readerIsHead {
                Button("Remove from household", systemImage: "person.badge.minus", role: .destructive) {
                    guard let live = liveMember(id) else { return }
                    dialog = .remove(HouseholdRemoval.Target(live))
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 38, height: 38)
                .background(Color.fill, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options for \(name)")
    }

    /// The head of table keeps their seat — you cannot swipe away the
    /// person who owns the account.
    private func swipeActions(for member: HouseholdMember, readerIsHead: Bool) -> [SwipeAction] {
        let id = member.persistentModelID
        guard !member.isOwner else { return [] }
        // Only the host edits the roster (docs/household.md §8): a member's
        // phone can message or resend, but Remove is the head's alone.
        var actions: [SwipeAction] = []
        // An invitation nobody answered needs a way forward, not just a way
        // out. Same live link, sent again — and only when Messages can
        // actually open. Without it the resend sheet crashed or blanked.
        if member.canResend, InviteComposer.isAvailable, readerIsHead {
            actions.append(SwipeAction(symbol: "paperplane", label: "Send again") {
                swipedMember = nil
                Task {
                    guard let live = liveMember(id) else { return }
                    await resend(live)
                }
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
                    guard let live = liveMember(id) else { return }
                    dialog = .role(live)
                })
            }
            actions.append(.remove {
                guard let live = liveMember(id) else { return }
                dialog = .remove(HouseholdRemoval.Target(live))
            })
        }
        return actions
    }

    private func liveMember(_ id: PersistentIdentifier) -> HouseholdMember? {
        roster.first { $0.persistentModelID == id }
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
            if !PlatedPlus.gatingEnabled || PlatedPlus.isActive || roster.count <= 1 {
                addPresented = true
            } else {
                paywallPresented = true
            }
        } label: {
            Text(roster.me?.isOwner == true ? "Invite" : "Add person")
                .plType(.footnote, .semibold).foregroundStyle(Color.accentText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(roster.me?.isOwner == true ? "Invite someone" : "Add someone by name")
        .accessibilityHint("Opens household invitation options.")
    }

    // MARK: Whose night it is
    // Under the people, because the rota is something the people do.

    private var cooksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Who cooks when").plType(.heading)
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { turnsTipShown.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("How turns work")
                Spacer()
            }

            cookGrid

            Text("Choose a day to set its standing cook.")
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
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(weekdaysInOrder, id: \.self) { weekday in
                    cookCell(weekday: weekday, isToday: weekday == today)
                        .frame(minWidth: 44)
                }
            }
        }.scrollIndicators(.hidden)
    }

    private func cookCell(weekday: Int, isToday: Bool) -> some View {
        let cook = roster.first { $0.cookWeekdays.contains(weekday) }
        let dayName = Calendar.current.weekdaySymbols[weekday - 1]
        return Button {
            rotationPerson = cook?.shareRecordName
            rotationDay = weekday
        } label: {
            VStack(spacing: 6) {
                Text(shortDay(weekday).uppercased())
                    .plType(.micro, .extraBold)
                    .foregroundStyle(isToday ? Color.accentText : Color.inkSecondary)
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
                    .strokeBorder(isToday ? Color.olive : Color.hairline, lineWidth: isToday ? 2 : 1)
            }
        }
        .buttonStyle(.pressable)
        // A weekday abbreviation over an initial announces as neither.
        .accessibilityLabel(cook.map { "\(dayName), \($0.name) cooks" } ?? "\(dayName), nobody yet")
        .accessibilityHint("Choose a cook, then save this standing assignment")
        .accessibilityIdentifier("household-rotation-\(weekday)")
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

    private func dayChipLabel(_ weekdays: [Int]) -> String {
        let days = weekdays.filter { (1...7).contains($0) }
        if days.count == 1, let day = days.first {
            return "\(Calendar.current.weekdaySymbols[day - 1])s"
        }
        // Same order as the rota above it. Sorting these today-first while
        // the grid ran week-first would print "Sat + Wed" under a row that
        // shows Wednesday to the left of Saturday.
        let order = weekdaysInOrder
        return days
            // Three letters, not the grid's one. `shortDay` is a calendar
            // header, where an ordered row of seven makes "S" unambiguous;
            // this chip is a sentence about a person and reads "Sun + Mon".
            // It borrowed shortDay and briefly became "S + M".
            .sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
            .map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
            .joined(separator: " + ")
    }

    private func rotationEditor(_ day: Int) -> some View {
        NavigationStack {
            List {
                Section {
                    Button { rotationPerson = nil } label: {
                        HStack {
                            Text("Unassigned")
                            Spacer()
                            if rotationPerson == nil { Image(systemName: "checkmark") }
                        }.foregroundStyle(Color.ink).frame(minHeight: 44)
                    }
                    ForEach(roster.filter(\.cooks)) { member in
                        Button { rotationPerson = member.shareRecordName } label: {
                            HStack(spacing: 12) {
                                AvatarCircle(member: member, size: 36)
                                Text(member.name).foregroundStyle(Color.ink)
                                Spacer()
                                if rotationPerson == member.shareRecordName { Image(systemName: "checkmark") }
                            }.frame(minHeight: 44)
                        }
                        .accessibilityAddTraits(rotationPerson == member.shareRecordName ? .isSelected : [])
                    }
                } footer: {
                    Text("This sets the standing cook for \(Calendar.current.weekdaySymbols[day - 1])s. Existing meal assignments stay as planned.")
                }
            }
            .tint(Color.accentText)
            .navigationTitle("Who cooks \(Calendar.current.weekdaySymbols[day - 1])?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { rotationDay = nil } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveRotation(day) } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func saveRotation(_ day: Int) {
        guard rotationPerson == nil || roster.contains(where: { $0.shareRecordName == rotationPerson && $0.cooks }) else {
            problem = "That person is no longer available. Choose another cook."
            rotationDay = nil
            return
        }
        let previous = roster.map { ($0, $0.cookWeekdays) }
        for member in roster {
            member.cookWeekdays.removeAll { $0 == day }
            if member.shareRecordName == rotationPerson { member.cookWeekdays.append(day) }
        }
        if !Persist.save(context, "standing cook changed") {
            for (member, days) in previous { member.cookWeekdays = days }
            problem = "Couldn't save this standing cook. Please try again."
        } else { Haptic.select() }
        rotationDay = nil
    }

}

/// Adding somebody, with the invitation as the thing the sheet is for.
///
/// The host's door is a text with a link. The by-name door stays for a
/// kid or a grandparent who will never have the app. The directory
/// shortcut is hidden until invite APNs is live: an "Already on Plated"
/// row would promise a nudge the server cannot send.
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
    @State private var removingName: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add to your household")
                    // .title at 22, the app's sheet masthead.
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)

                roleChips

                inviteDoor

                if let problem {
                    // Loud enough to be the answer to "did anything happen?"
                    ProblemRow(problem)
                        .transition(.opacity)
                }

                // The second door is a local place card, not a lesser kind
                // of invitation. Name it for the situation it serves.
                if isHost {
                    HStack(spacing: 10) {
                        Rectangle().fill(Color.hairline).frame(height: 1)
                        Text("WITHOUT THE APP")
                            .plType(.caption, .bold)
                            .foregroundStyle(Color.inkSecondary)
                        Rectangle().fill(Color.hairline).frame(height: 1)
                    }
                    .padding(.vertical, 2)
                }

                byNameDoor
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, 30)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
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
            Text(role == "partner"
                 ? "Partners can have standing cook nights."
                 : "You can still assign them a meal whenever you need to.")
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
            Text(hostFirstName == "the organizer"
                 ? "Only the organizer can invite people to this household."
                 : "Only \(hostFirstName), the organizer, can invite people to this household.")
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
        return first.isEmpty ? "the organizer" : first
    }

    private var hostInviteDoor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if InviteComposer.isAvailable {
                PrimaryActionButton(title: "Invite someone", systemImage: "person.badge.plus") {
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
                SecondaryActionButton(
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

            SecondaryActionButton(title: "Add") {
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
    private func startInvite() {
        InviteFlow.run(
            kind: .household,
            hostName: userFirstName,
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
                        Radius.shape(Radius.chip).strokeBorder(Color.hairline)
                    }
                }
                // Only the SELECTED chip was tappable. A filled capsule hit
                // tests; a stroked one hit tests its ring and nothing else,
                // so the two chips a person actually needs to reach were the
                // two that ignored them.
                .frame(minHeight: 44)
                .contentShape(Radius.shape(Radius.chip))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
