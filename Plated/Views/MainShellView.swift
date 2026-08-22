import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case week, table, cookbook, home
}

/// The shell: four quiet destinations and one tomato + floating over
/// everything. The bar is the only piece of chrome that floats.
struct MainShellView: View {
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @Query private var members: [HouseholdMember]

    @State private var selection: AppTab = .week
    @State private var createPresented = false
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

            PlateTabBar(selection: $selection) {
                createPresented = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .sheet(isPresented: $createPresented) {
            NewRecipeView()
        }
        .task {
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
            if !didStampSampleCategories {
                // Sample recipes seeded before categories existed get filed
                // once, so the cookbook filters have something to hold.
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
                didRepairLegacyDiscover = true
                let all = (try? context.fetch(FetchDescriptor<TablePost>())) ?? []
                let discoverKeys = Set(all.filter(\.isDiscover).map(\.originKey))
                for post in all where !post.isDiscover && discoverKeys.contains(post.originKey) {
                    context.delete(post)
                }
                try? context.save()
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
                PlateGlyph()
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
                        .foregroundStyle(.white)
                }
                .rotationEffect(.degrees(addSpin ? 90 : 0))
            }
            .buttonStyle(.plain)
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

/// The brand mark as an icon: a plate on a placemat. Circles are dishes;
/// rounded rectangles are moments.
struct PlateGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(lineWidth: 2)
                .frame(width: 17, height: 17)
            Circle()
                .strokeBorder(lineWidth: 2)
                .frame(width: 8.5, height: 8.5)
        }
        .frame(width: 23, height: 23)
    }
}
