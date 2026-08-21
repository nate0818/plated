import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @Query private var members: [HouseholdMember]
    @Query private var meals: [PlannedMeal]

    @State private var selection: AppTab = .plan

    enum AppTab: Hashable {
        case plan, recipes, grocery, gatherings, insights
    }

    private var tonightPlanned: Bool {
        meals.contains {
            Calendar.current.isDateInToday($0.date) && $0.slotValue == .dinner
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Plan", systemImage: tonightPlanned ? "circle.circle.fill" : "circle.circle", value: AppTab.plan) {
                WeekPlanView()
            }
            Tab("Recipes", systemImage: "book.pages", value: AppTab.recipes) {
                RecipeLibraryView()
            }
            Tab("Grocery", systemImage: "checklist", value: AppTab.grocery) {
                GroceryListView()
            }
            Tab("Gatherings", systemImage: "person.2", value: AppTab.gatherings) {
                GatheringsView()
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: AppTab.insights) {
                InsightsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.tomato)
        .task {
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
