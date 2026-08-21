import SwiftUI
import SwiftData
import Charts

/// Cooking analytics: what the household actually eats, how often, and what has
/// dropped out of rotation.
struct InsightsView: View {
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]

    @State private var window: Window = .ninetyDays

    enum Window: String, CaseIterable, Identifiable {
        case thirtyDays = "30 days"
        case ninetyDays = "90 days"
        case year = "1 year"
        case allTime = "All time"

        var id: String { rawValue }

        var since: Date? {
            let calendar = Calendar.current
            switch self {
            case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: .now)
            case .ninetyDays: return calendar.date(byAdding: .day, value: -90, to: .now)
            case .year: return calendar.date(byAdding: .year, value: -1, to: .now)
            case .allTime: return nil
            }
        }
    }

    private var insights: MealInsights {
        MealInsights(meals: meals, recipes: recipes)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Window", selection: $window) {
                        ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Summary") {
                    LabeledContent("Meals cooked", value: "\(insights.cookedMeals(since: window.since).count)")
                    LabeledContent("Different dishes", value: "\(insights.varietyCount(since: window.since))")
                    LabeledContent(
                        "From your recipes",
                        value: insights.homeCookedShare(since: window.since).formatted(.percent.precision(.fractionLength(0)))
                    )
                }

                if !topMeals.isEmpty {
                    Section("Most cooked") {
                        Chart(topMeals) { entry in
                            BarMark(
                                x: .value("Times", entry.count),
                                y: .value("Dish", entry.title)
                            )
                            .cornerRadius(4)
                        }
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                        .frame(height: CGFloat(topMeals.count) * 32 + 24)
                        .padding(.vertical, 4)

                        ForEach(topMeals) { entry in
                            HStack {
                                Text(entry.title)
                                Spacer()
                                Text("\(entry.count)×")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section("By meal") {
                    ForEach(insights.countsBySlot(since: window.since), id: \.slot) { entry in
                        HStack {
                            Label(entry.slot.title, systemImage: entry.slot.symbolName)
                            Spacer()
                            Text("\(entry.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                if !neglected.isEmpty {
                    Section {
                        ForEach(neglected) { recipe in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.title)
                                Text(recipe.lastCookedAt.map { "Last made \($0.formatted(date: .abbreviated, time: .omitted))" }
                                     ?? "Never made")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Out of rotation")
                    } footer: {
                        Text("Recipes you haven't cooked in a while. Worth bringing back.")
                    }
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if insights.cookedMeals(since: window.since).isEmpty {
                    ContentUnavailableView(
                        "Nothing cooked yet",
                        systemImage: "chart.bar",
                        description: Text("Check meals off on the week plan and your history shows up here.")
                    )
                }
            }
        }
    }

    private var topMeals: [MealInsights.RecipeFrequency] {
        insights.frequencies(since: window.since, limit: 8)
    }

    private var neglected: [Recipe] {
        insights.neglectedRecipes()
    }
}

#Preview {
    InsightsView()
        .modelContainer(SampleData.previewContainer)
}
