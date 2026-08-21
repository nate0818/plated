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
                SampleData.seed(into: context)
            }
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
            tabItem(.week, label: "Week") {
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
                        .shadow(color: Color(rgb: 0x3C3228).opacity(0.16), radius: 10, y: 8)
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
                Image(systemName: "person.2")
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
            RoundedRectangle(cornerRadius: 5.5)
                .strokeBorder(lineWidth: 2)
                .frame(width: 17, height: 17)
            Circle()
                .strokeBorder(lineWidth: 2)
                .frame(width: 8.5, height: 8.5)
        }
        .frame(width: 23, height: 23)
    }
}
