import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case week, table, prongsby, cookbook, home
}

/// What the + can put into the world. Instagram asks before it assumes;
/// so do we.
enum CreateKind: String, Identifiable {
    case recipe, tablePost, ask
    var id: String { rawValue }
}

/// The shell: five quiet destinations and one tomato + floating over
/// everything. The bar is the only piece of chrome that floats.
struct MainShellView: View {
    @Environment(\.modelContext) private var context
    @Query private var members: [HouseholdMember]

    @State private var selection: AppTab = .week
    /// Prongsby's draft and in-flight reply outlive his tab's view.
    @State private var prongsbySession = ProngsbySession()
    @State private var createPresented = false
    /// The pick made inside the menu; presented only after the menu is
    /// fully down — two sheets can't stand on the same view at once.
    @State private var createChoice: CreateKind?
    @State private var activeCreate: CreateKind?
    /// Guards the legacy Discover repair so a slow CloudKit first-import can
    /// never race an "empty" check into skipping it forever.
    @AppStorage("didRepairLegacyDiscover") private var didRepairLegacyDiscover = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.canvas.ignoresSafeArea()

            Group {
                switch selection {
                case .week:
                    WeekView(askTheTable: { withAnimation(.plSnap) { selection = .table } })
                case .table:
                    TableFeedView()
                case .prongsby:
                    ProngsbyView(session: prongsbySession)
                case .cookbook:
                    CookbookView()
                case .home:
                    HouseholdHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlateTabBar(selection: $selection) {
                createPresented = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
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
            let args = ProcessInfo.processInfo.arguments
            if let flag = args.firstIndex(of: "-plated-tab"), args.indices.contains(flag + 1),
               let tab = AppTab(rawValue: args[flag + 1]) {
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
            // Prongsby graduated from a pushed page to a tab; the old flag
            // still lands where it says.
            if LaunchFlags.consume("-plated-open-prongsby") {
                selection = .prongsby
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
            .buttonStyle(.plain)
            .frame(width: 72)

            tabItem(.prongsby, label: "Prongsby") {
                // Explicit fills don't hear foregroundStyle — the glyph
                // takes its tone from the selection directly.
                ProngsbyGlyph(size: 22, tone: selection == .prongsby ? .ink : .inkFaint)
            }
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
        .buttonStyle(.plain)
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
                    .font(.gabarito(22, .extraBold))
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
        .buttonStyle(.plain)
    }
}
