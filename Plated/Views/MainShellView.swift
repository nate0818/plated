import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case week, table, cookbook, home
}

/// What the + can put into the world. Instagram asks before it assumes;
/// so do we.
enum CreateKind: String, Identifiable {
    case recipe, tablePost, ask
    var id: String { rawValue }
}

/// The shell: four quiet destinations either side of one tomato +, with
/// Prongsby perched above the bar. Those two are the only chrome that
/// floats, and they float together.
struct MainShellView: View {
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @Query private var members: [HouseholdMember]

    @State private var selection: AppTab = .week
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
    /// Guards sample seeding so a slow CloudKit first-import can never race
    /// an "empty" check into duplicating everything.
    @AppStorage("didSeedSampleData") private var didSeedSampleData = false
    @AppStorage("didSeedDiscover") private var didSeedDiscover = false
    @AppStorage("didRepairLegacyDiscover") private var didRepairLegacyDiscover = false
    @AppStorage("didStampSampleCategories") private var didStampSampleCategories = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.canvas.ignoresSafeArea()

            Group {
                switch selection {
                case .week:
                    WeekView(askTheTable: { withAnimation(.plSnap) { selection = .table } })
                case .table:
                    TableFeedView()
                case .cookbook:
                    CookbookView()
                case .home:
                    HouseholdHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !perchVisibility.isHidden {
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
            case .ask:
                AskComposerSheet(date: Calendar.current.startOfDay(for: .now))
            }
        }
        .task {
            // Sample data is a simulator-only furnishing: a real device
            // starts empty and stays truthful (and never uploads fake
            // rows to the owner's CloudKit database).
            #if targetEnvironment(simulator)
            if !didSeedSampleData && recipes.isEmpty && members.isEmpty {
                didSeedSampleData = true
                didSeedDiscover = true
                SampleData.seed(into: context)
            } else if !didSeedDiscover {
                // Installs seeded before Discover existed get its open tables
                // once — guarded at the store too, so a CloudKit import that
                // already carries them can never be double-seeded.
                didSeedDiscover = true
                let existing = try? context.fetchCount(
                    FetchDescriptor<TablePost>(predicate: #Predicate { $0.isDiscover })
                )
                if (existing ?? 0) == 0 {
                    SampleData.seedDiscover(into: context)
                    try? context.save()
                }
            }
            #endif
            if !didStampSampleCategories, !recipes.isEmpty {
                // Sample recipes seeded before categories existed get filed
                // once, so the cookbook filters have something to hold.
                // Stamps only after judging real rows: a fresh install's
                // first appear can run before the CloudKit import delivers,
                // and stamping against an empty store would skip the repair
                // forever.
                didStampSampleCategories = true
                let sampleFiling: [String: RecipeCategory] = [
                    "Lemon Butter Salmon": .quick,
                    "Pizza Night": .kidsPick,
                    "BBQ Skewers": .grill,
                    "Rainbow Bowls": .bowls,
                    "Steak Bowls": .bowls,
                    "Poke Night": .healthy,
                    "Pancake Dinner": .comfort
                ]
                for recipe in recipes where recipe.category.isEmpty {
                    if let filed = sampleFiling[recipe.title] {
                        recipe.categoryValue = filed
                    }
                }
                try? context.save()
            }
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
                    try? context.save()
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
                if owners.count > 1, let kept = owners.first {
                    for dupe in owners.dropFirst() {
                        for meal in dupe.assignedMeals ?? [] { meal.cook = kept }
                        context.delete(dupe)
                    }
                    try? context.save()
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
                    try? context.save()
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
            if LaunchFlags.consume("-plated-open-prongsby") {
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

    @State private var bouncing: String?
    @State private var addSpin = false

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
                withAnimation(.plPop) { addSpin.toggle() }
                onCreate()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.tomato)
                        .frame(width: 54, height: 54)
                        .shadow(color: Color.shadowInk.opacity(0.16), radius: 10, y: 8)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.onTomato)
                }
                .rotationEffect(.degrees(addSpin ? 90 : 0))
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
        .background {
            Capsule()
                .fill(Color.canvas.opacity(0.94))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.navHairline))
        }
        .plFloatShadow()
    }

    private func tabItem(_ tab: AppTab, label: String, @ViewBuilder icon: () -> some View) -> some View {
        let active = selection == tab
        return Button {
            Haptic.tap()
            selection = tab
            bounce(tab.rawValue)
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
            .scaleEffect(bouncing == tab.rawValue ? 1.25 : 1)
        }
        .buttonStyle(.pressable)
    }

    private func bounce(_ key: String) {
        withAnimation(.plPop) { bouncing = key }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if bouncing == key {
                withAnimation(.plSnap) { bouncing = nil }
            }
        }
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
                        detail: "A plated moment for the household feed"
                    )
                    row(
                        .recipe, icon: "book.closed",
                        title: "Recipe",
                        detail: "A dish for the cookbook"
                    )
                    row(
                        .ask, icon: "hand.raised",
                        title: "Ask the table",
                        detail: "A question or a poll — what should we plate?"
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
