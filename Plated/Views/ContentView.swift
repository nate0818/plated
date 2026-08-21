import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @Query private var members: [HouseholdMember]

    @State private var selection: AppTab = .plan

    enum AppTab: Hashable {
        case plan, recipes, grocery, gatherings, insights
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                WeekPlanView()
            }
            Tab("Recipes", systemImage: "book", value: AppTab.recipes) {
                RecipeLibraryView()
            }
            Tab("Grocery", systemImage: "cart", value: AppTab.grocery) {
                GroceryListView()
            }
            Tab("Gatherings", systemImage: "person.3", value: AppTab.gatherings) {
                GatheringsView()
            }
            Tab("Insights", systemImage: "chart.bar", value: AppTab.insights) {
                InsightsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            // First launch on a fresh device: give the user something to look at
            // rather than five empty tabs.
            if recipes.isEmpty && members.isEmpty {
                SampleData.seed(into: context)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}
