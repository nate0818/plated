import SwiftUI
import SwiftData
import Charts

/// Cooking analytics as editorial stat tiles — what the household actually
/// eats, how often, and what has dropped out of rotation.
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

    private let tileColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Insights")
                        .font(.heroTitle)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 8)

                    Picker("Window", selection: $window.animation(.appSnappy)) {
                        ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if cooked.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: tileColumns, spacing: 12) {
                            StatTile(
                                label: "Meals cooked",
                                value: "\(cooked.count)",
                                numericValue: Double(cooked.count),
                                detail: "in the last \(window.rawValue.lowercased())"
                            )
                            StatTile(
                                label: "Different dishes",
                                value: "\(insights.varietyCount(since: window.since))",
                                numericValue: Double(insights.varietyCount(since: window.since)),
                                detail: "variety on the table"
                            )
                            StatTile(
                                label: "From your recipes",
                                value: insights.homeCookedShare(since: window.since)
                                    .formatted(.percent.precision(.fractionLength(0))),
                                numericValue: insights.homeCookedShare(since: window.since) * 100,
                                detail: "vs takeout & freeform"
                            )
                            StatTile(
                                label: "Most cooked",
                                value: "\(topMeals.first?.count ?? 0)×",
                                numericValue: Double(topMeals.first?.count ?? 0),
                                detail: topMeals.first?.title ?? "—"
                            )
                        }

                        if topMeals.count > 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow("Most cooked")
                                VStack(alignment: .leading, spacing: 12) {
                                    Chart(topMeals) { entry in
                                        BarMark(
                                            x: .value("Times", entry.count),
                                            y: .value("Dish", entry.title)
                                        )
                                        .foregroundStyle(Color.tomato.gradient)
                                        .cornerRadius(5)
                                    }
                                    .chartXAxis {
                                        AxisMarks(values: .automatic(desiredCount: 4)) {
                                            AxisGridLine().foregroundStyle(Color.hairline)
                                            AxisValueLabel().foregroundStyle(Color.inkSecondary)
                                        }
                                    }
                                    .chartYAxis {
                                        AxisMarks {
                                            AxisValueLabel().foregroundStyle(Color.ink)
                                        }
                                    }
                                    .frame(height: CGFloat(topMeals.count) * 36 + 24)
                                }
                                .padding(16)
                                .cardSurface()
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow("By meal")
                            VStack(spacing: 0) {
                                ForEach(Array(slotCounts.enumerated()), id: \.element.slot) { index, entry in
                                    if index > 0 { Divider().overlay(Color.hairline).padding(.leading, 16) }
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(entry.slot.tone)
                                            .frame(width: 8, height: 8)
                                        Text(entry.slot.title)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.ink)
                                        Spacer()
                                        Text("\(entry.count)")
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(Color.inkSecondary)
                                            .contentTransition(.numericText(value: Double(entry.count)))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                            }
                            .cardSurface()
                        }

                        if !neglected.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow("Out of rotation")
                                VStack(spacing: 0) {
                                    ForEach(Array(neglected.enumerated()), id: \.element.persistentModelID) { index, recipe in
                                        if index > 0 { Divider().overlay(Color.hairline).padding(.leading, 16) }
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(recipe.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(Color.ink)
                                                Text(recipe.lastCookedAt.map {
                                                    "Last made \($0.formatted(date: .abbreviated, time: .omitted))"
                                                } ?? "Never made")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.inkTertiary)
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                }
                                .cardSurface()
                                Text("Worth bringing back.")
                                    .font(.caption)
                                    .foregroundStyle(Color.inkTertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .scrollIndicators(.hidden)
            .toolbarBackground(Color.canvas, for: .navigationBar)
        }
    }

    private var cooked: [PlannedMeal] { insights.cookedMeals(since: window.since) }
    private var topMeals: [MealInsights.RecipeFrequency] { insights.frequencies(since: window.since, limit: 6) }
    private var slotCounts: [(slot: MealSlot, count: Int)] { insights.countsBySlot(since: window.since) }
    private var neglected: [Recipe] { insights.neglectedRecipes() }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing cooked yet.")
                .font(.cardTitle)
                .foregroundStyle(Color.ink)
            Text("Check meals off on the plan as you cook them and your history shows up here.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let numericValue: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(label)
            Text(value)
                .font(.statNumeral)
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText(value: numericValue))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 108, alignment: .topLeading)
        .padding(16)
        .cardSurface()
    }
}

#Preview {
    InsightsView()
        .modelContainer(SampleData.previewContainer)
}
