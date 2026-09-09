import SwiftUI
import SwiftData
import CloudKit

enum AppTab: String, CaseIterable {
    case week, cookbook, groceries, table, home
}

/// A request to send a tab back to its own first screen.
///
/// Tapping the tab you are already on is how iOS says "take me to the top",
/// and nothing in Plated was listening: the shell is a `switch` rather than a
/// `TabView`, so there is no stack here to pop. Pushed screens are optional
/// state owned by each root view, and only that view can clear it — so the
/// shell raises a request and the roots answer it.
///
/// The tab is carried so a re-tap of Plan cannot also close the recipe
/// somebody left open under Recipes. `count` is what changes: two re-taps of
/// the same tab are two requests, not one.
struct TabPopRequest: Equatable {
    var tab: AppTab?
    var count = 0
}

private struct TabPopKey: EnvironmentKey {
    static let defaultValue = TabPopRequest()
}

extension EnvironmentValues {
    var tabPop: TabPopRequest {
        get { self[TabPopKey.self] }
        set { self[TabPopKey.self] = newValue }
    }
}

/// What the + can put into the world: two things, because there are two.
/// A recipe arrives however it arrives — pasted, scanned, photographed,
/// typed — and that is one door, not several; the import sheet already
/// holds every way in. Asking the table went back to the plan, where the
/// question has a night attached (see PlanNightSheet).
enum CreateKind: String, Identifiable {
    case tablePost, recipe, ask
    var id: String { rawValue }
}

/// The shell: four quiet destinations either side of one tomato +. The bar
/// is the only chrome that floats — Prongsby's perch floated beside it
/// until he was parked (see ProngsbyFeature), and returns with him.
struct MainShellView: View {
    @Environment(\.modelContext) private var context
    @Query private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]
    @Query private var meals: [PlannedMeal]
    @State private var ledger = CookLedger.shared
    @State private var resumedRecipe: Recipe?
    private var activeRecipe: Recipe? {
        recipes.filter { ledger.isCooking($0) }.max {
            (ledger.session(for: $0)?.lastTouched ?? .distantPast) < (ledger.session(for: $1)?.lastTouched ?? .distantPast)
        }
    }

    @State private var selection: AppTab = .week
    @State private var visitedTabs: Set<AppTab> = [.week]

    /// A seat somebody kept at their Table, waiting for a yes. Every road
    /// (a Universal Link, `plated://join`, the directory's push, a raw
    /// iCloud link) ends in `ShareAcceptor.received`, which reads the share
    /// and answers here; a tap must not seat anybody on its own, or any
    /// push could put a person at a stranger's table.
    struct TableInvitation {
        var metadata: CKShare.Metadata
        var host: String
        var invite: String?
    }
    @State private var tableInvitation: TableInvitation?

    /// Somebody's household, read and waiting for the join sheet — or the
    /// reason it could not be read, which is the sheet's third state (§7)
    /// and not a toast: "Sign in to iCloud on this iPhone to join, then
    /// open the link again." is an instruction, and one that removes
    /// itself after four seconds cannot be acted on or re-read.
    struct HouseholdInvitation: Identifiable {
        let id = UUID()
        var metadata: CKShare.Metadata?
        var root: HouseholdShare.RemoteRoot?
        var seat: String?
        var host: String
        var failure: String?
    }
    @State private var householdInvitation: HouseholdInvitation?

    /// One quiet line over the tab bar, for a sentence that has no screen
    /// of its own: an invitation that could not be read, a household you
    /// are already in. Replaced, never stacked.
    @State private var toast: String?
    @State private var toastToken = 0

    private var invitationTitle: String {
        let who = tableInvitation?.host.trimmingCharacters(in: .whitespaces) ?? ""
        return who.isEmpty ? "Someone kept you a seat at their table" : "\(who) kept you a seat at their table"
    }

    /// Every `plated://` link and every invitation, one door. Links arrive
    /// through `LinkRelay`: `RootView` owns `onOpenURL`, so a link that
    /// lands during onboarding is answered there and never twice.
    private func route(_ url: URL) {
        if url.scheme == "plated", url.host == "import-shared" {
            openSharedRecipeIfNeeded()
            return
        }
        // An invitation, by whichever road. The share is read with its
        // root, and which room it opens is decided by the zone it resolves
        // to, never by what the link claimed (docs/household.md §7).
        if let invitation = Invitation.parse(url) {
            print("PLATED HOUSEHOLD: routing a \(invitation.kind.rawValue) invitation link")
            Task {
                await ShareAcceptor.received(
                    shareURL: invitation.share, seat: invitation.seat,
                    invite: invitation.invite, linkHost: invitation.host
                )
            }
            return
        }
        guard let destination = DeepLink.destination(for: url) else { return }
        withAnimation(.plSnap) {
            switch destination {
            case .plan:
                selection = .week
                // The night the notice was about, not just the tab.
                if let day = DeepLink.planDay(in: url) { LinkRelay.request(day: day) }
            case .table: selection = .table
            case .cookbook: selection = .cookbook
            // Prongsby left the bar in the elevation pass — he's a sheet
            // off the perch now, not a destination to select.
            case .prongsby: prongsbyPresented = true
            case .home: selection = .home
            case .grocery: selection = .groceries
            // The thing the notice was about, not the tab it lives on.
            // The feed does the second leg once it is on screen.
            case .post:
                selection = .table
                if let id = DeepLink.postID(in: url) { LinkRelay.request(post: id) }
            case .activity:
                selection = .home
                LinkRelay.requestActivity()
            case .invite:
                // Read by `Invitation.parse` above; a `plated://invite` that
                // gets this far carried no https share and is nothing.
                break
            }
        }
    }

    /// Raised when the bar is tapped on the tab already showing. See
    /// `TabPopRequest`.
    @State private var tabPop = TabPopRequest()
    /// The tabs you came through, so a left-edge swipe has somewhere to go
    /// back to. The tab bar is a `switch`, so without this there is no
    /// history at all and the gesture would have nothing to pop.
    @State private var tabHistory: [AppTab] = []
    /// Set while the edge gesture is doing the popping, so the history
    /// watcher does not record the pop as another forward step and trap the
    /// user bouncing between two tabs.
    @State private var poppingTab = false
    /// Prongsby's draft and in-flight reply outlive the sheet he lives in.
    @State private var prongsbySession = ProngsbySession()
    @State private var prongsbyPresented = false
    @State private var perchVisibility = PerchVisibility()

    #if DEBUG
    /// Which tab has to be on screen for a launch flag to be consumed.
    /// Keep this in step with every `LaunchFlags.consume` that lives inside
    /// a tab body — a flag missing here is a flag that silently does
    /// nothing, which is worse than one that errors.
    private static let flagHomes: [(String, AppTab)] = [
        ("-plated-open-stats", .home),
        ("-plated-open-discover", .table),
        ("-plated-open-seats", .table),
        ("-plated-open-thread", .table),
        ("-plated-open-grocery", .week),
        ("-plated-open-profile", .week),
        ("-plated-open-activity", .week),
        ("-plated-open-plan-day", .week)
    ]
    #endif
    @State private var createPresented = false
    /// Screenshot flags open a composer without passing through the menu;
    /// the flow starts there instead of at the rows. Nil for a real tap.
    @State private var createStart: CreateKind?
    /// Content handed over by Notes, Safari, Messages, or another app's share
    /// sheet. It enters the same review flow as paste and scan.
    @State private var sharedRecipeInput = ""
    @State private var sharedRecipeImages: [Data] = []
    /// Asking left the + for the plan, where the question has a night. The
    /// screenshot flag still needs a way in, so it opens the composer
    /// straight off the shell rather than restoring the row.
    @State private var askPresented = false
    /// A widget asked for the grocery list; the week picks it up on arrival.
    @State private var groceryRequested = false
    // `didSeedSampleData` and `didSeedDiscover` lived here, each with a
    // careful comment about guarding a seed against a slow CloudKit import.
    // Neither was ever read or written, and `SampleData` is called from
    // SwiftUI previews and nowhere else — so a real first launch has always
    // been a genuinely empty app, and the guard was for a race that could
    // not happen. Two more comments describing machinery that was not there.
    /// Guards the legacy Discover repair so a slow CloudKit first-import can
    /// never race an "empty" check into skipping it forever.
    @AppStorage("didRepairLegacyDiscover") private var didRepairLegacyDiscover = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.canvas.ignoresSafeArea()

            ZStack {
                ForEach(AppTab.allCases.filter { visitedTabs.contains($0) }, id: \.self) { tab in
                    Group {
                        switch tab {
                        case .week: WeekView(askTheTable: { selection = .table }, openGrocery: $groceryRequested)
                        case .table: TableFeedView()
                        case .cookbook: CookbookView()
                        case .home: HouseholdHomeView()
                        case .groceries: NavigationStack { GrocerySheet(embedded: true) }
                        }
                    }
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
                    .accessibilityHidden(selection != tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, activeRecipe == nil ? 0 : 60)

            if ProngsbyFeature.isEnabled, !perchVisibility.isHidden {
                ProngsbyPerch(session: prongsbySession) {
                    // SwiftUI stands up one sheet at a time. The create
                    // flow is a single presentation now, so this is just
                    // "is a sheet already up".
                    guard !createPresented, !askPresented else { return }
                    prongsbyPresented = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                // Flush with the bar's own chrome inset (20) and 12pt above
                // it (4 bottom pad + 68 bar height), so the two float as one
                // cluster instead of two loose objects.
                .padding(.trailing, 20)
                .padding(.bottom, Layout.perchBottom)
                .transition(.plArrive)
            }

            VStack(spacing: 8) {
                if let recipe = activeRecipe, let session = ledger.session(for: recipe) {
                    Button { resumedRecipe = recipe } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife.circle.fill").font(.system(size: 28)).foregroundStyle(Color.accentText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Resume cooking").plType(.footnote, .semibold)
                                Text(session.titleSnapshot ?? recipe.title).plType(.caption).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text("\((session.step ?? 0) + 1) / \(max(1, session.stepsSnapshot?.count ?? session.stepCount))").plType(.caption).monospacedDigit()
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.canvas)
                                .frame(width: 30, height: 30)
                                .background(Color.ink, in: Circle())
                        }.foregroundStyle(Color.ink).padding(.horizontal, 16).frame(height: 54)
                            .background(Color.canvas, in: Capsule()).overlay(Capsule().strokeBorder(Color.hairline))
                    }.buttonStyle(.pressable).accessibilityLabel("Resume cooking \(session.titleSnapshot ?? recipe.title)")
                }
            PlateTabBar(selection: $selection, onReselect: { tab in
                tabPop = TabPopRequest(tab: tab, count: tabPop.count + 1)
            }) {
                createPresented = true
            }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .fullScreenCover(item: $resumedRecipe) { recipe in
            let session = ledger.session(for: recipe)
            CookingFocusView(recipe: recipe, meal: meals.first { session?.mealID != nil && $0.shoppingID == session?.mealID }, servings: session?.servings ?? recipe.servings)
        }
        .environment(\.tabPop, tabPop)
        .environment(\.perchVisibility, perchVisibility)
        .animation(.plSnap, value: perchVisibility.isHidden)
        .task { Presence.follow(selection) }
        .onChange(of: selection) { previous, current in
            visitedTabs.insert(current)
            Presence.follow(current)
            guard !poppingTab else { poppingTab = false; return }
            tabHistory.append(previous)
            // A session's worth of tab hopping is not a browser history.
            // Ten steps is more than anyone walks back; beyond that the
            // oldest is dropped rather than grown forever.
            if tabHistory.count > 10 { tabHistory.removeFirst() }
        }
        .plEdgeBack {
            guard let previous = tabHistory.popLast() else { return }
            poppingTab = true
            // Moving between tabs is a change of position, not an action.
            // The tab bar itself uses select() for the same change.
            Haptic.select()
            withAnimation(.plSnap) { selection = previous }
        }
        .sheet(isPresented: $createPresented, onDismiss: {
            createStart = nil
            sharedRecipeInput = ""
            sharedRecipeImages = []
        }) {
            CreateFlowSheet(
                start: createStart,
                initialRecipeInput: sharedRecipeInput,
                initialRecipeImages: sharedRecipeImages
            )
        }
        .sheet(isPresented: $askPresented) {
            AskComposerSheet(date: Calendar.current.startOfDay(for: .now))
        }
        .sheet(isPresented: $prongsbyPresented) {
            ProngsbyView(session: prongsbySession)
        }
        // Every link comes in through LinkRelay: a tapped notification
        // parks one from UIKit, and RootView parks every `onOpenURL`. The
        // onAppear collects a link parked before the shell existed, which
        // is every cold start from a banner or an invitation.
        .onReceive(NotificationCenter.default.publisher(for: LinkRelay.opened)) { _ in
            if let url = LinkRelay.take() { route(url) }
        }
        .onAppear {
            if let url = LinkRelay.take() { route(url) }
            // An ask parked by a cold-start share accept. The opener has
            // lifted by the time this view has been on screen a beat.
            if NotificationScheduler.takePendingAsk() {
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    await NotificationScheduler.askOnce()
                }
            }
        }
        .confirmationDialog(
            invitationTitle, isPresented: Binding(
                get: { tableInvitation != nil },
                set: { if !$0 { tableInvitation = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Join the Table") {
                guard let invitation = tableInvitation else { return }
                tableInvitation = nil
                Task {
                    // The sentence is the outcome's, not this screen's:
                    // two screens each kept their own copy and both said
                    // "check your connection" for a revoked link, a
                    // signed-out phone and a seat already taken.
                    let outcome = await ShareAcceptor.acceptTable(
                        invitation.metadata, invite: invitation.invite
                    )
                    if let line = outcome.line { showToast(line) }
                }
            }
            Button("Not now", role: .cancel) { tableInvitation = nil }
        } message: {
            Text("Their dishes and asks join your Table, and they see what you post.")
        }
        .sheet(item: $householdInvitation) { invitation in
            JoinHouseholdSheet(
                metadata: invitation.metadata, root: invitation.root,
                seat: invitation.seat, linkHost: invitation.host,
                failure: invitation.failure
            )
        }
        // What the share turned out to be. The Table asks with a dialog on
        // every road; the household opens its sheet; a share that could
        // not be read says why, in one line, and nothing else changes.
        .onReceive(NotificationCenter.default.publisher(for: ShareAcceptor.invitationReceived)) { note in
            guard let received = note.userInfo?["received"] as? ShareAcceptor.Received else { return }
            switch received {
            case .table(let metadata, let host, let invite):
                tableInvitation = TableInvitation(metadata: metadata, host: host, invite: invite)
            case .household(let metadata, let root, let seat, let host):
                // Already in this household: no sheet at all (§7). Computed
                // here rather than inside the sheet, which had to present
                // itself, draw a monogram and a spinner, and then close
                // itself again — and left the person on whatever tab they
                // were on instead of routing Home.
                let read = HouseholdSync.preview(
                    for: metadata, root: root, linkHost: host, context: context
                )
                // `.needsSeat` is deliberately not caught here: it opens
                // the sheet, which goes straight to the picker.
                if read.state == .alreadyHere {
                    let name = read.hostName.trimmingCharacters(in: .whitespaces)
                    withAnimation(.plSnap) { selection = .home }
                    showToast("You're already in \(name.isEmpty ? "this" : "\(name)'s") household.")
                    return
                }
                householdInvitation = HouseholdInvitation(metadata: metadata, root: root, seat: seat, host: host)
            case .failed(let reason):
                Haptic.warn()
                householdInvitation = HouseholdInvitation(
                    metadata: nil, root: nil, seat: nil, host: "", failure: reason
                )
            }
        }
        // Joined: the plan is the thing that just arrived, so the Plan tab
        // is where the person lands (docs/household.md §7, step 6).
        .onReceive(NotificationCenter.default.publisher(for: JoinHouseholdSheet.didJoin)) { _ in
            householdInvitation = nil
            withAnimation(.plSnap) { selection = .week }
        }
        .onReceive(NotificationCenter.default.publisher(for: JoinHouseholdSheet.notice)) { note in
            if let text = note.userInfo?["text"] as? String { showToast(text) }
        }
        // The household this phone was in is gone (§8, being removed). Every
        // sheet closes and every tab returns to its root, because what they
        // were showing was the household's.
        .onReceive(NotificationCenter.default.publisher(for: HouseholdSync.householdRemoved)) { _ in
            createPresented = false
            askPresented = false
            prongsbyPresented = false
            householdInvitation = nil
            tableInvitation = nil
            resumedRecipe = nil
            popEveryTab()
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.canvas)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(minHeight: 40)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .padding(.horizontal, 32)
                    .padding(.bottom, Layout.floatingChromeInset)
                    .transition(.plRise)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .task {
            openSharedRecipeIfNeeded()
            if !didRepairLegacyDiscover {
                // Stores seeded before Discover posts were stamped left those
                // rows with isDiscover == false, so open-table posts bled into
                // the private feed. Any unstamped post whose author+dish
                // matches a stamped Discover row is that legacy artifact.
                // Stamps only after judging real rows (and never on a failed
                // fetch): a fresh install's first appear can beat the
                // CloudKit import, and a premature stamp would leave the
                // imported artifacts unrepaired forever.
                if let all = try? context.fetch(FetchDescriptor<TablePost>()), !all.isEmpty {
                    didRepairLegacyDiscover = true
                    let discoverKeys = Set(all.filter(\.isDiscover).map(\.originKey))
                    for post in all where !post.isDiscover && discoverKeys.contains(post.originKey) {
                        context.delete(post)
                    }
                    Persist.save(context)
                }
            }
            // The person holding this phone, kept honest (docs/household.md
            // §5). Keyed on identity, never on role: on a member's phone the
            // owner row is the host, and a repair that collapsed "owners"
            // would have collapsed them. Rows carrying this device's
            // identity fold onto one (the named one, else the oldest), meals
            // rehomed; the parked onboarding photo and the typed name are
            // hung on that row only; a row carrying anybody else's identity
            // is never touched. A head is laid only while this phone hosts
            // its own household. A failed fetch does nothing.
            if let rows = try? context.fetch(
                FetchDescriptor<HouseholdMember>(sortBy: [SortDescriptor(\.createdAt)])
            ) {
                let identity = TableIdentity.cached
                let membership = HouseholdShare.membership
                let mine = rows.filter { row in
                    if let id = row.userRecordName, !id.isEmpty {
                        return !TableIdentity.isPlaceholder && id == identity
                    }
                    // No identity on the row yet. On this phone's own
                    // household the head is the reader (§5); on a member's
                    // phone an unstamped head is the host, and is left alone.
                    return membership.owner == nil && row.isOwner
                }
                let kept = mine.first { !$0.shareRecordName.isEmpty } ?? mine.first
                if let kept {
                    if mine.count > 1 {
                        let dupes = mine.filter { $0.persistentModelID != kept.persistentModelID }
                        // A row sharing the kept row's record name is the
                        // mirror's copy of ONE seat, not a second seat.
                        // Deleted in the open, the save observer parks a
                        // delete for that record name and the drain takes
                        // this person's own seat out of the zone; the kept
                        // row's next push then meets `.unknownItem` and
                        // `.gone` deletes the row on every device.
                        // `collapseDuplicates` folds these under suppression
                        // for exactly this reason, two seconds later.
                        let twins = dupes.filter {
                            !$0.shareRecordName.isEmpty && $0.shareRecordName == kept.shareRecordName
                        }
                        if !twins.isEmpty {
                            HouseholdSync.suppressed = true
                            for twin in twins {
                                for meal in twin.assignedMeals ?? [] { meal.cook = kept }
                                context.delete(twin)
                            }
                            Persist.save(context, "owner repair, mirror twins")
                            HouseholdSync.suppressed = false
                        }
                        let twinIDs = Set(twins.map(\.persistentModelID))
                        for dupe in dupes where !twinIDs.contains(dupe.persistentModelID) {
                            for meal in dupe.assignedMeals ?? [] { meal.cook = kept }
                            context.delete(dupe)
                        }
                    }
                    // The face chosen during onboarding, hung the first time
                    // there is a row to hang it on. See ProfilePhoto.
                    if let parked = ProfilePhoto.parked {
                        if kept.photoData == nil { kept.photoData = parked }
                        ProfilePhoto.clearParked()
                    }
                    // And the name they gave, when the row is still wearing
                    // the bootstrap placeholder. Only a placeholder is
                    // overwritten: a real name someone chose is never quietly
                    // replaced, and the rename goes through the one door so
                    // their posts and awards travel with it.
                    let typed = (UserDefaults.standard.string(forKey: "userFirstName") ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    if HouseholdIdentity.isPlaceholder(kept.name), !typed.isEmpty {
                        HouseholdIdentity.rename(kept, to: typed, in: context)
                    }
                    Persist.save(context, "owner repair")
                } else if membership.owner == nil {
                    // A host-shaped hole: the sign-in member promoted, or a
                    // fresh place laid. Never on a member's phone, where the
                    // seat this person is arrives by join.
                    let name = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                    let unclaimed = rows.filter { ($0.userRecordName ?? "").isEmpty }
                    if let match = unclaimed.first(where: {
                        !name.isEmpty && $0.name.caseInsensitiveCompare(name) == .orderedSame
                    }) {
                        match.role = "owner"
                        match.seat = .head
                    } else {
                        let me = HouseholdMember(
                            name: name.isEmpty ? "Me" : name,
                            colorHex: "FF5A3C", role: "owner", cookWeekdays: [],
                            seat: .head
                        )
                        if !TableIdentity.isPlaceholder { me.userRecordName = identity }
                        me.authorID = identity
                        context.insert(me)
                    }
                    Persist.save(context, "owner laid")
                }
                // The identity stamp itself, once CloudKit has confirmed one,
                // for a household that has never been shared.
                HouseholdSync.stampIdentityIfUnshared(in: context)
            }

            // Seats, once, before any people screen can render a stale one.
            // Everything that predates the seat is `.notOnPlated`, which is
            // the truth about all of it, and the old pending-names string
            // becomes real invited rows rather than being stranded.
            let pendingKey = "pendingSeats"
            let pending = UserDefaults.standard.string(forKey: pendingKey) ?? ""
            if !UserDefaults.standard.bool(forKey: "didMigrateSeats") {
                if Seats.migrate(in: context, pendingSeats: pending) {
                    Persist.save(context)
                }
                UserDefaults.standard.set(true, forKey: "didMigrateSeats")
                UserDefaults.standard.removeObject(forKey: pendingKey)
            }
            // Rows seated from the Table before the household could be
            // shared (docs/household.md §8, last paragraph). Its own
            // one-shot, because the migration above ran long ago.
            if Seats.migrateTableSeats(in: context) {
                Persist.save(context, "table seats")
            }
            // What CloudKit knows about who actually accepted.
            Task {
                await Seats.reconcile(in: context)
                Persist.save(context)
            }

            #if DEBUG
            // UI-test hook: `simctl launch … -plated-tab table` lands here.
            // In the launch task, where it belongs: a Sept 2 edit stranded
            // this block inside the share-accepted handler, so every
            // screenshot flag waited for an invitation nobody was sending.
            //
            // Accepted names are the AppTab raw values — `week`, `table`,
            // `cookbook`, `home` — which are NOT the words on the tab bar
            // ("Plan", "Recipes"). An unknown name is ignored silently, so
            // `-plated-tab plan` looks exactly like a plain launch.
            let args = ProcessInfo.processInfo.arguments
            if let flag = args.firstIndex(of: "-plated-tab"), args.indices.contains(flag + 1) {
                let name = args[flag + 1]
                if let tab = AppTab(rawValue: name) {
                    selection = tab
                } else if name == "prongsby" {
                    // He is no longer a tab; the harness keeps its old word.
                    prongsbyPresented = true
                } else {
                    print("PLATED FLAG: unknown -plated-tab '\(name)' — expected one of \(AppTab.allCases.map(\.rawValue).joined(separator: ", ")) or prongsby")
                }
            }

            // Flags whose `consume()` lives inside a tab body only fire once
            // that tab is on screen, so standalone they silently no-op and
            // the screenshot is indistinguishable from a plain launch. Rather
            // than make every caller remember to compose `-plated-tab` first
            // — the old comment on `-plated-open-stats` actually prescribed
            // the form that fails — the shell sends you to the owning tab.
            for (flag, tab) in Self.flagHomes where args.contains(flag) {
                selection = tab
            }
            if LaunchFlags.consume("-plated-open-create") {
                createPresented = true
            }
            if LaunchFlags.consume("-plated-open-table-post") {
                createStart = .tablePost
                createPresented = true
            }
            if LaunchFlags.consume("-plated-open-recipe") {
                createStart = .recipe
                createPresented = true
            }
            if LaunchFlags.consume("-plated-open-ask") {
                askPresented = true
            }
            // Prongsby has been a pushed page and a tab; he is a sheet off
            // the perch now. The flag keeps its name and still opens him.
            if LaunchFlags.consume("-plated-open-prongsby"), ProngsbyFeature.isEnabled {
                prongsbyPresented = true
            }
            // `-plated-prongsby-demo` consumes itself inside ProngsbyView,
            // which is a SHEET rather than a tab — so `flagHomes` above
            // structurally cannot reach it, and it was the one of the five
            // that stayed a silent no-op standalone. Open him; the sheet
            // then consumes its own flag.
            if ProcessInfo.processInfo.arguments.contains("-plated-prongsby-demo") {
                prongsbyPresented = true
            }
            #endif
        }
    }

    private func showToast(_ message: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.plSnap) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toastToken == token {
                withAnimation(.plSnap) { toast = nil }
            }
        }
    }

    /// Every tab back to its root. `TabPopRequest` carries one tab, and
    /// each root answers only its own, so the requests go out one at a
    /// time with a beat between them rather than the last overwriting the
    /// rest before anybody has read it.
    private func popEveryTab() {
        Task { @MainActor in
            for tab in AppTab.allCases {
                tabPop = TabPopRequest(tab: tab, count: tabPop.count + 1)
                try? await Task.sleep(for: .milliseconds(60))
            }
            withAnimation(.plSnap) { selection = .week }
        }
    }

    private func openSharedRecipeIfNeeded() {
        guard let shared = RecipeShareInbox.consume() else { return }
        sharedRecipeInput = shared.text
        sharedRecipeImages = shared.images
        createStart = .recipe
        createPresented = true
    }
}

/// Four miniature kitchen objects. Only a deliberate tap plays their motion.
struct PlateTabBar: View {
    @Binding var selection: AppTab
    /// Tapping the tab already showing. Selection does not change, so
    /// `onChange(of: selection)` never fires and the tap was going nowhere.
    var onReselect: (AppTab) -> Void = { _ in }
    let onCreate: () -> Void

    /// Separate triggers preserve the animator's identity on the first tap.
    @State private var responseCounts: [AppTab: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.week, label: "Plan")
            tabItem(.cookbook, label: "Recipes")
            tabItem(.groceries, label: "Groceries")
            tabItem(.table, label: "Table")
        }
        .padding(.horizontal, 8)
        .frame(height: 68)
        .plChrome()
        .background { barSurface }
        .plFloatShadow()
    }

    /// Liquid Glass where the OS has it, the hand-rolled twin where it
    /// doesn't. The deployment target is iOS 18, so the material below is
    /// not dead code — it is what most of the fleet actually renders.
    ///
    /// Glass is left un-tinted on purpose. The system material already
    /// samples and bends what scrolls beneath it; painting canvas over the
    /// top is what made the old bar read as a flat capsule with a blur
    /// behind it rather than as a layer of the OS.
    @ViewBuilder
    private var barSurface: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(Color.canvas.opacity(0.94))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.navHairline))
        }
    }

    private func tabItem(_ tab: AppTab, label: String) -> some View {
        let active = selection == tab
        return Button {
            // Selection is the state change; the tick that marks position
            // is `select`, not the `tap` that marks an action. Going back to
            // the top of a tab is a change of position too.
            Haptic.select()
            responseCounts[tab, default: 0] += 1
            if active {
                onReselect(tab)
            } else {
                selection = tab
            }
        } label: {
            VStack(spacing: 1) {
                TrayNavigationIcon(tab: tab, active: active, trigger: responseCounts[tab] ?? 0)
                    .frame(width: 60, height: 37)
                    .background {
                        if active {
                            Capsule().fill(Color.ink)
                        }
                    }
                Text(label)
                    .plType(.micro, active ? TypeWeight.extraBold : .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(active ? Color.ink : Color.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 66)
            // The most-touched control in the product, and only the glyphs
            // were tappable: `.pressable` draws no surface, so a 66pt column
            // was hit-testable across roughly 26x38pt of icon and label,
            // with 14pt of dead strip along the top and bottom of the bar.
            // That strip is where a thumb lands first.
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tray-\(tab.rawValue)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The + asks before it assumes — a plated moment for the Table, a question
/// for the Table, or a dish for the cookbook. Three rows, because those are
/// the three things there are to add: pasting a recipe and writing one out are ways of adding a
/// recipe, not separate things to add, and the import sheet already offers
/// every one of them.
///
/// All three rows are `OptionRow`, which is to say all three are the same row.
/// Posting used to be drawn heavier because it is what the + is mostly
/// reached for, and "heavier" meant a `fill` ground: this app's selection
/// paint, on a row nobody had selected, with the side effect of erasing
/// its own border. Two choices that are peers look like peers.
struct CreateMenuSheet: View {
    let onChoose: (CreateKind) -> Void

    /// The sheet's height, measured rather than typed.
    ///
    /// It was a literal 210 against 221 points of content, so this sheet
    /// scrolled: two rows and a word, and you could drag them.
    ///
    /// The title lives INSIDE the scroll view so this measurement can be
    /// taken. A greedy `ScrollView` beside a header in a `VStack` takes
    /// whatever height the detent gives it, so measuring anything in that
    /// stack measures the detent's own answer coming back around — set the
    /// detent from it and the sheet walks itself taller every pass. Scroll
    /// content has a natural height that owes the detent nothing.
    @State private var measured: CGFloat = 210

    var body: some View {
        // Large type outgrows the sheet — the content scrolls, and the
        // grabber offers the full-height detent as a way out.
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("Add")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                    // 22, the top padding every other sheet masthead uses.
                    // These were 18, 20, 22 and 26 across four sheets.
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                VStack(spacing: 10) {
                    OptionRow(
                        icon: "camera",
                        title: "Post to the Table",
                        detail: "A photo of what you just cooked"
                    ) { onChoose(.tablePost) }
                    OptionRow(
                        icon: "book.closed",
                        title: "Add a recipe",
                        detail: "Paste it, scan it, or write it out"
                    ) { onChoose(.recipe) }
                    // The Table's other kind of post, which had no door.
                    // `askPresented` was set by a debug launch flag and by
                    // nothing else, so in a shipped build an ask could only
                    // be reached from inside the Plan tab's night sheet —
                    // three taps away, on the other side of the app from the
                    // Table it posts to.
                    OptionRow(
                        icon: "bubble.and.pencil",
                        title: "Ask the Table",
                        detail: "What should we eat, or put up a poll"
                    ) { onChoose(.ask) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured = $0 }
        }
        .presentationDetents([.height(measured), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }
}

/// One sheet, not two. Choosing used to lower the menu and wait for
/// `onDismiss` to raise the composer, because two sheets can't stand on
/// the same view at once — two full sheet animations to perform one
/// action, with a beat of nothing in between. The composer replaces the
/// menu inside the same presentation instead: one animation, and a
/// composer's own `dismiss()` still closes the whole thing rather than
/// walking back to a menu nobody wants to see again.
struct CreateFlowSheet: View {
    /// Non-nil skips the menu and opens that composer directly.
    init(
        start: CreateKind? = nil,
        initialRecipeInput: String = "",
        initialRecipeImages: [Data] = []
    ) {
        _kind = State(initialValue: start)
        self.initialRecipeInput = initialRecipeInput
        self.initialRecipeImages = initialRecipeImages
    }

    @State private var kind: CreateKind?
    private let initialRecipeInput: String
    private let initialRecipeImages: [Data]

    var body: some View {
        if let kind {
            switch kind {
            case .tablePost:
                TableComposerSheet()
            case .recipe:
                RecipeImportSheet(
                    initialInput: initialRecipeInput,
                    initialImages: initialRecipeImages
                )
            case .ask:
                AskComposerSheet(date: Calendar.current.startOfDay(for: .now))
            }
        } else {
            CreateMenuSheet { chosen in
                withAnimation(.plSnap) { kind = chosen }
            }
        }
    }
}
