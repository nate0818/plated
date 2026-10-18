import SwiftUI
import SwiftData
import CloudKit

extension Notification.Name {
    static let platedCreateRequested = Notification.Name("plated.create.requested")
}

enum AppTab: String, CaseIterable {
    case week, cookbook, groceries, table
}

/// The durable part of a timer deep link's presentation handshake.
///
/// Assigning an item to `fullScreenCover` is only a request: UIKit can reject
/// it while a tab-owned sheet is still dismissing. The request is complete
/// only when the cover says it appeared. Keeping that distinction in a small
/// value also prevents the retry loop from issuing two presentations at once.
struct CookResumeIntent {
    private(set) var isPending = false
    private(set) var isCoverVisible = false
    private(set) var isPresentationInFlight = false

    var needsPresentation: Bool { isPending && !isCoverVisible }

    mutating func request() {
        // A timer tap while the cook screen is already visible is already
        // fulfilled; otherwise preserve any attempt currently in flight.
        isPending = !isCoverVisible
    }

    mutating func beginPresentation() -> Bool {
        guard needsPresentation, !isPresentationInFlight else { return false }
        isPresentationInFlight = true
        return true
    }

    mutating func presentationDidNotAppear() {
        guard !isCoverVisible else { return }
        isPresentationInFlight = false
    }

    mutating func coverAppeared() {
        isCoverVisible = true
        isPresentationInFlight = false
        isPending = false
    }

    mutating func coverDisappeared() {
        isCoverVisible = false
        isPresentationInFlight = false
    }

    mutating func expireWithoutSession() {
        guard !isCoverVisible else { return }
        isPresentationInFlight = false
        isPending = false
    }
}

private struct ActiveAppTabKey: EnvironmentKey {
    static let defaultValue: AppTab = .week
}

extension EnvironmentValues {
    var activeAppTab: AppTab {
        get { self[ActiveAppTabKey.self] }
        set { self[ActiveAppTabKey.self] = newValue }
    }
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

/// The shell: four quiet destinations either side of one olive +. The bar
/// is the only chrome that floats — Prongsby's perch floated beside it
/// until he was parked (see ProngsbyFeature), and returns with him.
struct MainShellView: View {
    // The first-run destination seeds state only once; subsequent renders preserve navigation.
    init(initialTab: AppTab = .week) {
        _selection = State(initialValue: initialTab)
        _visitedTabs = State(initialValue: [initialTab])
    }

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var members: [HouseholdMember]
    @Query private var recipes: [Recipe]
    @Query private var meals: [PlannedMeal]
    @State private var ledger = CookLedger.shared
    @State private var resumedRecipe: Recipe?
    @State private var cookResumeIntent = CookResumeIntent()
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
                resetTab(.week)
                // The night the notice was about, not just the tab.
                if let day = DeepLink.planDay(in: url) {
                    Task { @MainActor in
                        await Task.yield()
                        LinkRelay.request(day: day)
                    }
                }
            case .table: resetTab(.table)
            case .cookbook:
                resetTab(.cookbook)
                if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value {
                    if let recipe = recipes.first(where: { $0.shareRecordName == id }) {
                        Task { @MainActor in
                            await Task.yield()
                            LinkRelay.request(recipe: recipe)
                        }
                    } else { showToast("This recipe is no longer in your cookbook.") }
                }
            case .cook:
                // A timer may arrive while a retained recipe detail or the
                // Activity list covers Recipes. Clear that route first; if
                // there is no live session the shelf is the honest fallback.
                resetTab(.cookbook)
                cookResumeIntent.request()
                resumePendingCookIfPossible()
            case .home:
                resetTab(.week)
                Task { @MainActor in
                    await Task.yield()
                    LinkRelay.requestHousehold()
                }
            case .grocery: selection = .groceries
            // The thing the notice was about, not the tab it lives on.
            // The feed does the second leg once it is on screen.
            case .post:
                resetTab(.table)
                if let id = DeepLink.postID(in: url) {
                    Task { @MainActor in
                        await Task.yield()
                        LinkRelay.request(post: id)
                    }
                }
            case .activity:
                resetTab(.week)
                Task { @MainActor in
                    await Task.yield()
                    LinkRelay.requestActivity()
                }
            case .invite:
                // Read by `Invitation.parse` above; a `plated://invite` that
                // gets this far carried no https share and is nothing.
                break
            }
        }
    }

    /// External links are stronger than retained tab history. Selecting a
    /// tab without clearing its pushed profile/thread/detail left the old
    /// screen covering the destination the notification named.
    private func resetTab(_ tab: AppTab) {
        tabPop = TabPopRequest(tab: tab, count: tabPop.count + 1)
        selection = tab
    }

    /// Raised when the bar is tapped on the tab already showing. See
    /// `TabPopRequest`.
    @State private var tabPop = TabPopRequest()
    /// Prongsby's draft and in-flight reply outlive the sheet he lives in.
    @State private var perchVisibility = PerchVisibility()
    @State private var floatingChromeVisibility = FloatingChromeVisibility()

    #if DEBUG
    /// Which tab has to be on screen for a launch flag to be consumed.
    /// Keep this in step with every `LaunchFlags.consume` that lives inside
    /// a tab body — a flag missing here is a flag that silently does
    /// nothing, which is worse than one that errors.
    private static let flagHomes: [(String, AppTab)] = [
        ("-plated-open-stats", .week),
        ("-plated-open-seats", .table),
        ("-plated-open-thread", .table),
        ("-plated-open-grocery", .week),
        ("-plated-open-profile", .week),
        ("-plated-open-edit-profile", .week),
        ("-plated-open-recipe-detail", .cookbook),
        ("-plated-review-recipe-share", .cookbook),
        ("-plated-open-recipe-ingredients", .cookbook),
        ("-plated-review-cooking-timer", .cookbook),
        ("-plated-open-activity", .week),
        ("-plated-open-plan-day", .week),
        ("-plated-review-plan-night", .week),
        ("-plated-review-move-meal", .week)
    ]
    #endif
    @State private var createdRecipe: Recipe?
    @State private var createPresented = false
    /// Screenshot flags open a composer without passing through the menu;
    /// the flow starts there instead of at the rows. Nil for a real tap.
    @State private var createStart: CreateKind?
    /// Content handed over by Notes, Safari, Messages, or another app's share
    /// sheet. It enters the same review flow as paste and scan.
    @State private var sharedRecipeInput = ""
    @State private var sharedRecipeImages: [Data] = []
    @State private var sharedRecipeReceipt: RecipeShareInbox.Import?
    @State private var sharedRecipeNeedsAcknowledgement = false
    /// The item binding may queue another destination while one sheet is
    /// visible. Remember what is actually on screen so dismissing it clears
    /// only its own state.
    @State private var activeShellSheetID: String?
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
                        case .cookbook: CookbookView(onPlanNight: { selection = .week })
                        case .groceries: NavigationStack { GrocerySheet(embedded: true) }
                        }
                    }
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
                    .accessibilityHidden(selection != tab)
                }
            }
            .frame(
                maxWidth: horizontalSizeClass == .regular ? Layout.readableMaxWidth : .infinity,
                maxHeight: .infinity
            )
            .padding(.bottom, activeRecipe == nil ? 0 : 60)


            if !floatingChromeVisibility.isHidden {
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
                            }.foregroundStyle(Color.ink).padding(.horizontal, 16).frame(minHeight: 54)
                                .background(Color.canvas, in: Radius.shape(Radius.chip)).overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                        }.buttonStyle(.pressable).accessibilityLabel("Resume cooking \(session.titleSnapshot ?? recipe.title)")
                    }
                    PlateTabBar(selection: $selection, onReselect: { tab in
                        tabPop = TabPopRequest(tab: tab, count: tabPop.count + 1)
                    })
                }
                .padding(.bottom, 0)
                .frame(
                    maxWidth: .infinity
                )
                .transition(.plRise)
            }
        }
        .fullScreenCover(item: $resumedRecipe, onDismiss: {
            cookResumeIntent.coverDisappeared()
            resumePendingCookIfPossible()
        }) { recipe in
            let session = ledger.session(for: recipe)
            CookingFocusView(recipe: recipe, meal: meals.first { session?.mealID != nil && $0.shoppingID == session?.mealID }, servings: session?.servings ?? recipe.servings, remotePlanID: session?.remotePlanID)
                .onAppear { cookResumeIntent.coverAppeared() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .platedCreateRequested)) { _ in
            guard !createPresented, !askPresented, householdInvitation == nil, activeShellSheetID == nil else { return }
            createStart = nil
            createPresented = true
        }
        .environment(\.activeAppTab, selection)
        .environment(\.tabPop, tabPop)
        .environment(\.perchVisibility, perchVisibility)
        .environment(\.floatingChromeVisibility, floatingChromeVisibility)
        .animation(.plSnap, value: perchVisibility.isHidden)
        .animation(.plSnap, value: floatingChromeVisibility.isHidden)
        .task { Presence.follow(selection) }
        .onChange(of: selection) { _, current in
            visitedTabs.insert(current)
            Presence.follow(current)
        }
        .onChange(of: recipes.count) { _, _ in
            resumePendingCookIfPossible()
        }
        .task(id: cookResumeIntent.isPending) {
            guard cookResumeIntent.isPending else { return }
            await retryPendingCookResume()
        }
        // Two `.sheet` modifiers on one view is undefined — see CLAUDE.md.
        // One item binding, four destinations; flags stay so callers keep
        // writing createPresented / askPresented / … without knowing.
        .sheet(item: shellSheet, onDismiss: {
            let dismissedID = activeShellSheetID
            activeShellSheetID = nil
            if sharedRecipeNeedsAcknowledgement {
                // The share arrived behind another sheet (or behind an
                // already-open Add flow). Keep it queued and give it the
                // next presentation instead of replacing work in progress.
                Task { @MainActor in
                    await Task.yield()
                    openSharedRecipeIfNeeded()
                }
            } else if dismissedID == "create" {
                createStart = nil
                sharedRecipeInput = ""
                sharedRecipeImages = []
                sharedRecipeReceipt = nil
            }
            if let createdRecipe {
                selection = .cookbook
                LinkRelay.request(recipe: createdRecipe)
                self.createdRecipe = nil
            }
            resumePendingCookIfPossible()
        }) { destination in
            Group {
                switch destination {
                case .create:
                    CreateFlowSheet(
                        start: createStart,
                        initialRecipeInput: sharedRecipeInput,
                        initialRecipeImages: sharedRecipeImages,
                        onRecipeSaved: { createdRecipe = $0 }
                    )
                case .ask:
                    AskComposerSheet(date: Calendar.current.startOfDay(for: .now))
                case .household(let invitation):
                    JoinHouseholdSheet(
                        metadata: invitation.metadata, root: invitation.root,
                        seat: invitation.seat, linkHost: invitation.host,
                        failure: invitation.failure
                    )
                }
            }
            .onAppear {
                activeShellSheetID = destination.id
                if destination.id == "create", let receipt = sharedRecipeReceipt {
                    let removed = RecipeShareInbox.acknowledge(receipt)
                    sharedRecipeReceipt = nil
                    // If another share replaced this exact parcel before the
                    // importer appeared, it remains in the inbox and gets the
                    // next sheet. Never acknowledge B while displaying A.
                    sharedRecipeNeedsAcknowledgement = !removed
                }
            }
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
                    withAnimation(.plSnap) { selection = .week }
                    LinkRelay.requestHousehold()
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
            #if DEBUG
            handleDebugLaunchFlags()
            #endif
            // Preview-backed shells already have a complete in-memory table.
            // Running live-store repair here mixes app-group membership and
            // CloudKit identity into that fixture and can manufacture people
            // who do not exist. Nothing below is presentation-only.
            guard !PlatedApp.usesPreviewContainer else { return }
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
            // Invite-log / twin names before any CloudKit wait, so Account
            // and Activity do not open on "New member".
            Seats.bindShareIdentity(in: context, standings: [])
            // What CloudKit knows about who actually accepted.
            Task {
                await Seats.reconcile(in: context)
                Persist.save(context)
            }

        }
    }

    #if DEBUG
    /// Presentation-only launch routing stays available to previews even
    /// though their production repair and sync work is intentionally inert.
    private func handleDebugLaunchFlags() {
        // UI-test hook: `simctl launch … -plated-tab table` lands here.
        // Accepted names are AppTab raw values, not always the visible labels.
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-plated-tab"), args.indices.contains(flag + 1) {
            let name = args[flag + 1]
            if let tab = AppTab(rawValue: name) {
                selection = tab
            } else if name == "home" {
                // Compatibility for the old hidden fifth-tab harness:
                // Household is now a pushed destination from Plan.
                selection = .week
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1200))
                    LinkRelay.requestHousehold()
                }
            } else {
                print("PLATED FLAG: unknown -plated-tab '\(name)' — expected one of \(AppTab.allCases.map(\.rawValue).joined(separator: ", "))")
            }
        }

        // Standalone destination flags route to the tab that owns them.
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
    }
    #endif

    private enum ShellSheet: Identifiable {
        case create, ask, household(HouseholdInvitation)
        var id: String {
            switch self {
            case .create: "create"
            case .ask: "ask"
            case .household(let invitation): "household-\(invitation.id)"
            }
        }
    }
    private var shellSheet: Binding<ShellSheet?> {
        Binding(
            get: {
                if createPresented { return .create }
                if askPresented { return .ask }
                if let householdInvitation { return .household(householdInvitation) }
                return nil
            },
            set: {
                if $0 == nil {
                    switch activeShellSheetID {
                    case "create": createPresented = false
                    case "ask": askPresented = false
                    case let id? where id.hasPrefix("household-"):
                        householdInvitation = nil
                    default:
                        // Presentation can be dismissed before its content's
                        // onAppear on a very fast swipe. Fall back to the same
                        // priority the getter used, still clearing one item.
                        if createPresented { createPresented = false }
                        else if askPresented { askPresented = false }
                        else { householdInvitation = nil }
                    }
                }
            }
        )
    }

    private func showToast(_ message: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.plSnap) { toast = message }
        AccessibilityNotification.Announcement(message).post()
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
        guard let shared = RecipeShareInbox.peek() else {
            sharedRecipeNeedsAcknowledgement = false
            sharedRecipeReceipt = nil
            return
        }
        let presentationBusy = createPresented || askPresented
            || householdInvitation != nil || activeShellSheetID != nil
        guard !presentationBusy else {
            // Do not replace inputs already owned by a visible sheet. The
            // app-group inbox remains the durable queue for the next one.
            sharedRecipeNeedsAcknowledgement = true
            return
        }
        sharedRecipeInput = shared.text
        sharedRecipeImages = shared.images
        sharedRecipeReceipt = shared
        sharedRecipeNeedsAcknowledgement = true
        createStart = .recipe
        createPresented = true
    }

    private func resumePendingCookIfPossible() {
        guard cookResumeIntent.needsPresentation,
              !sharedRecipeNeedsAcknowledgement,
              !createPresented, !askPresented,
              householdInvitation == nil, activeShellSheetID == nil,
              resumedRecipe == nil,
              let activeRecipe,
              cookResumeIntent.beginPresentation()
        else { return }
        resumedRecipe = activeRecipe
    }

    /// Keep the timer intent alive until the cover itself confirms it is on
    /// screen. A tab-owned sheet is invisible to the shell; if UIKit declines
    /// the first request, cycle the item back through nil and try again after
    /// that sheet has had a chance to leave. Only one attempt may be in flight.
    @MainActor
    private func retryPendingCookResume() async {
        var missingRecipeChecks = 0

        while cookResumeIntent.needsPresentation, !Task.isCancelled {
            if activeRecipe == nil {
                missingRecipeChecks += 1
                if missingRecipeChecks >= 6 {
                    resumedRecipe = nil
                    cookResumeIntent.expireWithoutSession()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }

            missingRecipeChecks = 0
            resumePendingCookIfPossible()

            // Normal presentation calls `coverAppeared` well before this.
            // If it did not, release the stale item so the next loop creates a
            // fresh nil -> recipe transition after any local sheet dismissal.
            try? await Task.sleep(for: .milliseconds(900))
            guard cookResumeIntent.needsPresentation, !Task.isCancelled else { return }
            if cookResumeIntent.isPresentationInFlight {
                resumedRecipe = nil
                cookResumeIntent.presentationDidNotAppear()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
}

/// A fixed, quiet baseline keeps navigation separate from creation.
struct PlateTabBar: View {
    @Binding var selection: AppTab
    var onReselect: (AppTab) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.week, label: "Plan", symbol: "calendar")
            tabItem(.cookbook, label: "Recipes", symbol: "book")
            tabItem(.groceries, label: "Groceries", symbol: "basket")
            tabItem(.table, label: "Table", symbol: "person.2")
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .plChrome()
        .background(Color.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.navHairline).frame(height: 1) }
    }

    private func tabItem(_ tab: AppTab, label: String, symbol: String) -> some View {
        let active = selection == tab
        return Button {
            Haptic.select()
            if active { onReselect(tab) } else { selection = tab }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: active ? .medium : .regular))
                Text(label).plType(.micro, active ? .semibold : .regular).lineLimit(1)
            }
            .foregroundStyle(active ? Color.accentText : Color.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tray-\(tab.rawValue)")
        .accessibilityHint(active ? "Return to the top of \(label)" : "Open \(label)")
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
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
                        detail: "Photos, food finds, places, and questions"
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
        initialRecipeImages: [Data] = [],
        onRecipeSaved: @escaping (Recipe) -> Void = { _ in }
    ) {
        self.onRecipeSaved = onRecipeSaved
        _kind = State(initialValue: start)
        self.initialRecipeInput = initialRecipeInput
        self.initialRecipeImages = initialRecipeImages
    }

    @State private var kind: CreateKind?
    private let initialRecipeInput: String
    private let initialRecipeImages: [Data]
    private let onRecipeSaved: (Recipe) -> Void

    var body: some View {
        if let kind {
            switch kind {
            case .tablePost:
                TableComposerSheet()
            case .recipe:
                RecipeImportSheet(
                    initialInput: initialRecipeInput,
                    initialImages: initialRecipeImages,
                    onSaved: onRecipeSaved
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
