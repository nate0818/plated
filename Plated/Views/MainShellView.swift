import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case week, table, cookbook, home
}

/// What the + can put into the world: two things, because there are two.
/// A recipe arrives however it arrives — pasted, scanned, photographed,
/// typed — and that is one door, not several; the import sheet already
/// holds every way in. Asking the table went back to the plan, where the
/// question has a night attached (see PlanNightSheet).
enum CreateKind: String, Identifiable {
    case tablePost, recipe
    var id: String { rawValue }
}

/// The shell: four quiet destinations either side of one tomato +. The bar
/// is the only chrome that floats — Prongsby's perch floated beside it
/// until he was parked (see ProngsbyFeature), and returns with him.
struct MainShellView: View {
    @Environment(\.modelContext) private var context
    @Query private var members: [HouseholdMember]

    @State private var selection: AppTab = .week
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
    /// Asking left the + for the plan, where the question has a night. The
    /// screenshot flag still needs a way in, so it opens the composer
    /// straight off the shell rather than restoring the row.
    @State private var askPresented = false
    /// A widget asked for the grocery list; the week picks it up on arrival.
    @State private var groceryRequested = false
    /// Guards sample seeding so a slow CloudKit first-import can never race
    /// an "empty" check into duplicating everything.
    @AppStorage("didSeedSampleData") private var didSeedSampleData = false
    @AppStorage("didSeedDiscover") private var didSeedDiscover = false
    /// Guards the legacy Discover repair so a slow CloudKit first-import can
    /// never race an "empty" check into skipping it forever.
    @AppStorage("didRepairLegacyDiscover") private var didRepairLegacyDiscover = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.canvas.ignoresSafeArea()

            Group {
                switch selection {
                case .week:
                    WeekView(
                        askTheTable: { withAnimation(.plSnap) { selection = .table } },
                        openGrocery: $groceryRequested
                    )
                case .table:
                    TableFeedView()
                case .cookbook:
                    CookbookView()
                case .home:
                    HouseholdHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            PlateTabBar(selection: $selection) {
                createPresented = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .environment(\.perchVisibility, perchVisibility)
        .animation(.plSnap, value: perchVisibility.isHidden)
        .onChange(of: selection) { previous, _ in
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
        .sheet(isPresented: $createPresented, onDismiss: { createStart = nil }) {
            CreateFlowSheet(start: createStart)
        }
        .sheet(isPresented: $askPresented) {
            AskComposerSheet(date: Calendar.current.startOfDay(for: .now))
        }
        .sheet(isPresented: $prongsbyPresented) {
            ProngsbyView(session: prongsbySession)
        }
        .onOpenURL { url in
            // An invitation arriving through plated.food is a Universal Link,
            // so it lands here as an ordinary URL rather than at the
            // CloudKit delegate. Same destination, different road.
            if let share = ShareAcceptor.shareURL(from: url) {
                Task { await ShareAcceptor.accept(shareURL: share) }
                return
            }
            guard let destination = DeepLink.destination(for: url) else { return }
            withAnimation(.plSnap) {
                switch destination {
                case .plan: selection = .week
                case .table: selection = .table
                case .cookbook: selection = .cookbook
                // Prongsby left the bar in the elevation pass — he's a sheet
                // off the perch now, not a destination to select.
                case .prongsby: prongsbyPresented = true
                case .home: selection = .home
                case .grocery:
                    selection = .week
                    groceryRequested = true
                }
            }
        }
        .task {
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
            // The table's host, kept honest. The onboarding bootstrap and a
            // first CloudKit import can race a duplicate owner row into
            // being, and installs that onboarded before the bootstrap
            // existed have none at all. Runs on every shell appear (a
            // count is cheap; sync can deliver a dupe weeks later): extras
            // collapse onto the oldest row, meals rehomed; a host-shaped
            // hole gets the sign-in member promoted, or a fresh place
            // laid. A failed fetch does nothing — only confirmed states
            // are acted on.
            if let owners = try? context.fetch(
                FetchDescriptor<HouseholdMember>(
                    predicate: #Predicate { $0.role == "owner" },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            ) {
                // The face chosen during onboarding, hung on the owner's row
                // the first time there is a row to hang it on. Onboarding
                // asks before the head of the table exists, so the bytes wait
                // here rather than racing the sample seed. See ProfilePhoto.
                if let owner = owners.first {
                    if let parked = ProfilePhoto.parked {
                        if owner.photoData == nil { owner.photoData = parked }
                        ProfilePhoto.clearParked()
                        Persist.save(context)
                    }
                    // And the name they gave, when the row is still wearing
                    // the bootstrap placeholder.
                    //
                    // The owner row is written on the way OUT of the contacts
                    // step, so a row that already existed when onboarding ran
                    // (a reinstall pulling its household back from iCloud, or
                    // the simulator's sample seed) never saw the name typed
                    // two screens earlier. It kept answering to "Me" while
                    // the app had been told otherwise, which is the exact
                    // "TAP TO ADD YOUR NAME" prompt appearing to somebody who
                    // just added their name.
                    //
                    // Only a placeholder is overwritten. A real name someone
                    // chose is never quietly replaced, and the rename goes
                    // through the one door so their posts and awards travel
                    // with it.
                    let typed = (UserDefaults.standard.string(forKey: "userFirstName") ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    if HouseholdIdentity.isPlaceholder(owner.name), !typed.isEmpty {
                        HouseholdIdentity.rename(owner, to: typed, in: context)
                    }
                }
                // No owner yet means the block below is about to make one;
                // the parked photo keeps waiting for the next appear.
                if owners.count > 1, let kept = owners.first {
                    for dupe in owners.dropFirst() {
                        for meal in dupe.assignedMeals ?? [] { meal.cook = kept }
                        context.delete(dupe)
                    }
                    Persist.save(context)
                } else if owners.isEmpty {
                    let name = UserDefaults.standard.string(forKey: "userFirstName") ?? ""
                    if let match = members.first(where: {
                        !name.isEmpty && $0.name.caseInsensitiveCompare(name) == .orderedSame
                    }) {
                        match.role = "owner"
                        match.seat = .head
                    } else {
                        context.insert(HouseholdMember(
                            name: name.isEmpty ? "Me" : name,
                            colorHex: "FF5A3C", role: "owner", cookWeekdays: [],
                            seat: .head
                        ))
                    }
                    Persist.save(context)
                }
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
            // What CloudKit knows about who actually accepted.
            Task {
                await Seats.reconcile(in: context)
                Persist.save(context)
            }
        }
        // Somebody just tapped an invitation. This is the moment an invited
        // row becomes a joined one, and the only thing that ever made
        // accepting a share visible inside the household.
        .onReceive(NotificationCenter.default.publisher(for: ShareAcceptor.didAccept)) { _ in
            Task {
                await Seats.reconcile(in: context)
                Persist.save(context)
            }
            #if DEBUG
            // UI-test hook: `simctl launch … -plated-tab table` lands here.
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
}

/// The floating pill. Active tab is ink, the rest are faint; icons bounce on
/// tap. The + is the one always-tomato element in the whole app.
struct PlateTabBar: View {
    @Binding var selection: AppTab
    let onCreate: () -> Void


    var body: some View {
        HStack(spacing: 0) {
            tabItem(.week, label: "Plan") {
                Image(systemName: "calendar")
                    .font(.system(size: 21, weight: .medium))
            }
            tabItem(.table, label: "Table") {
                Image(systemName: "table.furniture")
                    .font(.system(size: 20, weight: .medium))
            }

            Button {
                Haptic.plate()
                onCreate()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.tomato)
                        .frame(width: 54, height: 54)
                        .plFloatShadow()
                    Image(systemName: "plus")
                        .accessibilityLabel("Add")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.onTomato)
                }
            }
            .buttonStyle(.pressable)
            .frame(width: 72)

            tabItem(.cookbook, label: "Recipes") {
                Image(systemName: "book.closed")
                    .font(.system(size: 20, weight: .medium))
            }
            tabItem(.home, label: "Home") {
                Image(systemName: "house")
                    .font(.system(size: 20, weight: .medium))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 68)
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

    private func tabItem(_ tab: AppTab, label: String, @ViewBuilder icon: () -> some View) -> some View {
        let active = selection == tab
        return Button {
            // Selection is the state change; the tick that marks position
            // is `select`, not the `tap` that marks an action.
            Haptic.select()
            selection = tab
        } label: {
            VStack(spacing: 2) {
                icon()
                    .frame(height: 23)
                Text(label)
                    .plType(.micro, active ? TypeWeight.extraBold : .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(active ? Color.ink : Color.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 66)
        }
        .buttonStyle(.pressable)
    }
}

/// The + asks before it assumes — a plated moment for the Table, or a dish
/// for the cookbook. Two rows, because those are the two things there are
/// to add: pasting a recipe and writing one out are ways of adding a
/// recipe, not separate things to add, and the import sheet already offers
/// every one of them. No color until the choice; the first row carries
/// weight instead, because posting is what the + is mostly reached for.
struct CreateMenuSheet: View {
    let onChoose: (CreateKind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Add")
                .plType(.title)
                .foregroundStyle(Color.ink)
                .padding(.top, 26)
                .padding(.bottom, 18)

            // Large type outgrows the fixed detent — the rows scroll, and
            // the grabber offers the full-height detent as a way out.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    row(
                        .tablePost, icon: "camera", weighted: true,
                        title: "Post to the Table",
                        detail: "A photo of what you just cooked"
                    )
                    row(
                        .recipe, icon: "book.closed",
                        title: "Add a recipe",
                        detail: "Paste it, scan it, or write it out"
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.height(210), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    /// No circle around the glyph and no chevron beside it. The circle was
    /// a stroke drawn around a stroke, and a chevron that appears on every
    /// row says nothing — it also promised a push this sheet never made.
    private func row(
        _ kind: CreateKind, icon: String, weighted: Bool = false,
        title: String, detail: String
    ) -> some View {
        Button {
            Haptic.tap()
            onChoose(kind)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(weighted ? Color.fill : Color.clear)
            }
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
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
    init(start: CreateKind? = nil) {
        _kind = State(initialValue: start)
    }

    @State private var kind: CreateKind?

    var body: some View {
        if let kind {
            switch kind {
            case .tablePost:
                TableComposerSheet()
            case .recipe:
                RecipeImportSheet()
            }
        } else {
            CreateMenuSheet { chosen in
                withAnimation(.plSnap) { kind = chosen }
            }
        }
    }
}
