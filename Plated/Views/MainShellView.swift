import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case week, table, cookbook, home
}

/// What the + can put into the world. Instagram asks before it assumes;
/// so do we.
enum CreateKind: String, Identifiable {
    case recipe, pasteRecipe, tablePost, ask
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
    /// The pick made inside the menu; presented only after the menu is
    /// fully down — two sheets can't stand on the same view at once.
    @State private var createChoice: CreateKind?
    @State private var activeCreate: CreateKind?
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
                    // SwiftUI stands up one sheet at a time; the create
                    // hand-off already owns a two-step, so don't race it.
                    guard !createPresented, activeCreate == nil else { return }
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
        .sheet(isPresented: $createPresented, onDismiss: {
            if let choice = createChoice {
                createChoice = nil
                activeCreate = choice
            }
        }) {
            CreateMenuSheet { choice in
                createChoice = choice
                createPresented = false
            }
        }
        .sheet(isPresented: $prongsbyPresented) {
            ProngsbyView(session: prongsbySession)
        }
        .sheet(item: $activeCreate) { kind in
            switch kind {
            case .recipe:
                RecipeEditorView()
            case .tablePost:
                TableComposerSheet()
            case .pasteRecipe:
                RecipeImportSheet()
            case .ask:
                AskComposerSheet(date: Calendar.current.startOfDay(for: .now))
            }
        }
        .onOpenURL { url in
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
                        match.roleLine = "Head of table"
                    } else {
                        context.insert(HouseholdMember(
                            name: name.isEmpty ? "Me" : name,
                            colorHex: "FF5A3C", isPrimaryCook: true,
                            role: "owner", roleLine: "Head of table", cookWeekdays: []
                        ))
                    }
                    Persist.save(context)
                }
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
                activeCreate = .tablePost
            }
            if LaunchFlags.consume("-plated-open-recipe") {
                activeCreate = .recipe
            }
            if LaunchFlags.consume("-plated-open-ask") {
                activeCreate = .ask
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
                        .shadow(color: Color.shadowInk.opacity(0.16), radius: 10, y: 8)
                    Image(systemName: "plus")
                        .accessibilityLabel("Create")
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
                    .font(.jakarta(10, active ? .extraBold : .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(active ? Color.ink : Color.inkFaint)
            .frame(maxWidth: .infinity, minHeight: 66)
        }
        .buttonStyle(.pressable)
    }
}

/// The + asks before it assumes — a recipe for the cookbook, a plated
/// moment for the Table, or an open ask. Instagram's create menu, our
/// register: three quiet rows, no color until the choice.
struct CreateMenuSheet: View {
    let onChoose: (CreateKind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Create")
                Text("What are you adding?")
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 16)

            // Large type outgrows the fixed detent — the rows scroll, and
            // the grabber offers the full-height detent as a way out.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    row(
                        .tablePost, icon: "camera",
                        title: "Post to the Table",
                        detail: "A photo of what you just cooked"
                    )
                    row(
                        .recipe, icon: "book.closed",
                        title: "Recipe",
                        detail: "A dish for the cookbook"
                    )
                    // The empty cookbook offers this too, but that state
                    // disappears the moment there's one recipe in it — and
                    // pasting the second is exactly as useful as the first.
                    row(
                        .pasteRecipe, icon: "doc.on.clipboard",
                        title: "Paste a recipe",
                        detail: "From a website, a note, or a text"
                    )
                    row(
                        .ask, icon: "hand.raised",
                        title: "Ask the table",
                        detail: "A question or a poll. What should we plate?"
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .presentationDetents([.height(330), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private func row(_ kind: CreateKind, icon: String, title: String, detail: String) -> some View {
        Button {
            Haptic.tap()
            onChoose(kind)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .font(.jakarta(12, .medium))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.pressable)
    }
}
