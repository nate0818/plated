import SwiftUI
import SwiftData

/// The ledger and the tally: cooking history as a beautiful cookbook index —
/// hairline-ruled rows, monumental serif numerals, plates as tally marks.
struct InsightsView: View {
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]

    @State private var window: Window = .ninetyDays
    @Namespace private var rangeNamespace

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

    private var insights: MealInsights { MealInsights(meals: meals, recipes: recipes) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Masthead(eyebrow: "The record", title: "Insights") {
                        EmptyView()
                    }
                    .padding(.top, 8)

                    rangeControl

                    if cooked.isEmpty {
                        emptyState
                    } else {
                        ledger

                        if !tally.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Eyebrow("The tally")
                                VStack(spacing: 0) {
                                    ForEach(Array(tally.enumerated()), id: \.element.id) { index, entry in
                                        if index > 0 { Divider().overlay(Color.hairline) }
                                        TallyRow(entry: entry, index: index)
                                    }
                                }
                            }
                        }

                        slotBreakdown

                        if !neglected.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Eyebrow("Out of rotation")
                                VStack(spacing: 0) {
                                    ForEach(Array(neglected.enumerated()), id: \.element.persistentModelID) { index, recipe in
                                        if index > 0 { Divider().overlay(Color.hairline) }
                                        HStack(spacing: 12) {
                                            DishView(recipe: recipe, diameter: 32)
                                                .opacity(0.6)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(recipe.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(Color.ink)
                                                Text(recipe.lastCookedAt.map {
                                                    "LAST MADE \($0.formatted(.dateTime.month(.abbreviated).day()).uppercased())"
                                                } ?? "NEVER MADE")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .fontWidth(.condensed)
                                                    .tracking(0.5)
                                                    .foregroundStyle(Color.inkTertiary)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                    }
                                }
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

    // MARK: - Ledger

    private var ledger: some View {
        VStack(spacing: 0) {
            ledgerRow(
                value: "\(cooked.count)",
                numeric: Double(cooked.count),
                label: "Meals cooked",
                delta: "IN THE LAST \(window.rawValue.uppercased())"
            )
            Divider().overlay(Color.hairline)
            ledgerRow(
                value: "\(insights.varietyCount(since: window.since))",
                numeric: Double(insights.varietyCount(since: window.since)),
                label: "Different dishes",
                delta: "VARIETY ON THE TABLE"
            )
            Divider().overlay(Color.hairline)
            ledgerRow(
                value: insights.homeCookedShare(since: window.since)
                    .formatted(.percent.precision(.fractionLength(0))),
                numeric: insights.homeCookedShare(since: window.since) * 100,
                label: "From your recipes",
                delta: "VS TAKEOUT & FREEFORM"
            )
        }
    }

    private func ledgerRow(value: String, numeric: Double, label: String, delta: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(value)
                .font(.statNumeral)
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText(value: numeric))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Eyebrow(label)
                Text(delta)
                    .font(.system(size: 10, weight: .semibold))
                    .fontWidth(.condensed)
                    .tracking(0.5)
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - Range control

    private var rangeControl: some View {
        HStack(spacing: 0) {
            ForEach(Window.allCases) { candidate in
                Button {
                    withAnimation(.appSnappy) { window = candidate }
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(window == candidate ? Color.ink : Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if window == candidate {
                                Capsule()
                                    .fill(Color.cardFill)
                                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "range", in: rangeNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.ink.opacity(0.05), in: Capsule())
    }

    // MARK: - Slot breakdown (zero rows deleted)

    @ViewBuilder
    private var slotBreakdown: some View {
        let counts = insights.countsBySlot(since: window.since).filter { $0.count > 0 }
        if counts.count <= 1 {
            Text("All dinners so far — breakfast is an open canvas.")
                .font(.system(size: 15, design: .serif))
                .italic()
                .foregroundStyle(Color.inkSecondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("By meal")
                VStack(spacing: 0) {
                    ForEach(Array(counts.enumerated()), id: \.element.slot) { index, entry in
                        if index > 0 { Divider().overlay(Color.hairline) }
                        HStack(spacing: 10) {
                            Circle().fill(entry.slot.tone).frame(width: 8, height: 8)
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
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var cooked: [PlannedMeal] { insights.cookedMeals(since: window.since) }
    private var tally: [MealInsights.RecipeFrequency] { insights.frequencies(since: window.since, limit: 6) }
    private var neglected: [Recipe] { insights.neglectedRecipes() }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing cooked yet.")
                .font(.cardTitle)
                .foregroundStyle(Color.ink)
            Text("Check meals off on the plan as you cook them and the record builds itself.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

// MARK: - Tally row: N cleared plates, count equals numeral

private struct TallyRow: View {
    let entry: MealInsights.RecipeFrequency
    let index: Int
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            if let recipe = entry.recipe {
                DishView(recipe: recipe, diameter: 32)
            } else {
                DishView(title: entry.title, diameter: 32)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(0..<min(entry.count, 10), id: \.self) { _ in
                        PlateView(state: .cleared, diameter: 16)
                    }
                }
            }

            Spacer()

            Text("\(entry.count)")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
        .padding(.vertical, 10)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -12)
        .onAppear {
            withAnimation(.appSmooth.delay(Double(index) * 0.04)) {
                appeared = true
            }
        }
    }
}

#Preview {
    InsightsView()
        .modelContainer(SampleData.previewContainer)
}
