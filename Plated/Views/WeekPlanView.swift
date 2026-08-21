import SwiftUI
import SwiftData

/// The week calendar — the backbone of the app. Seven days down, meal slots
/// within each day, plus the weather-driven suggestion banner at the top.
struct WeekPlanView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(sort: \PlannedMeal.date) private var allMeals: [PlannedMeal]

    @State private var anchorDate = Date.now
    @State private var forecast = ForecastProvider.shared
    @State private var showingHousehold = false
    @State private var slotBeingFilled: (date: Date, slot: MealSlot)?

    private var weekDays: [Date] { Calendar.current.weekDays(for: anchorDate) }

    var body: some View {
        NavigationStack {
            List {
                if let suggestion = topSuggestion {
                    Section {
                        SuggestionBanner(suggestion: suggestion) {
                            schedule(suggestion.recipe, on: tomorrow, slot: .dinner)
                        }
                    }
                }

                ForEach(weekDays, id: \.self) { day in
                    Section {
                        ForEach(MealSlot.allCases.sorted(by: { $0.sortOrder < $1.sortOrder })) { slot in
                            slotRow(day: day, slot: slot)
                        }
                    } header: {
                        DayHeader(date: day, forecast: forecast.forecast(for: day))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(weekTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Previous week", systemImage: "chevron.left") { shiftWeek(by: -1) }
                    Button("Next week", systemImage: "chevron.right") { shiftWeek(by: 1) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Household", systemImage: "person.2") { showingHousehold = true }
                }
            }
            .sheet(isPresented: $showingHousehold) {
                HouseholdView()
            }
            .sheet(isPresented: Binding(
                get: { slotBeingFilled != nil },
                set: { if !$0 { slotBeingFilled = nil } }
            )) {
                if let target = slotBeingFilled {
                    RecipePickerView(date: target.date, slot: target.slot)
                }
            }
            .task {
                await forecast.refresh()
            }
        }
    }

    @ViewBuilder
    private func slotRow(day: Date, slot: MealSlot) -> some View {
        let meals = mealsFor(day: day, slot: slot)

        if meals.isEmpty {
            Button {
                slotBeingFilled = (day, slot)
            } label: {
                HStack {
                    Label(slot.title, systemImage: slot.symbolName)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            ForEach(meals) { meal in
                PlannedMealRow(meal: meal, members: members) {
                    toggleCooked(meal)
                }
                .swipeActions(edge: .trailing) {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        context.delete(meal)
                    }
                }
            }
        }
    }

    private var weekTitle: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "This Week" }
        let range = first..<last
        return range.formatted(.interval.month(.abbreviated).day())
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: .now)?.startOfDay ?? Date.now.startOfDay
    }

    private var topSuggestion: SuggestionEngine.Suggestion? {
        // Only nudge when tomorrow's dinner is still open.
        guard mealsFor(day: tomorrow, slot: .dinner).isEmpty else { return nil }
        let engine = SuggestionEngine(recipes: recipes, members: members)
        let cook = members.first(where: \.isPrimaryCook) ?? members.first
        return engine.suggestions(
            for: tomorrow,
            forecast: forecast.forecast(for: tomorrow),
            addressing: cook?.name.isEmpty == false ? cook?.name : nil
        ).first
    }

    private func mealsFor(day: Date, slot: MealSlot) -> [PlannedMeal] {
        allMeals.filter {
            Calendar.current.isSameDay($0.date, day) && $0.slotValue == slot
        }
    }

    private func schedule(_ recipe: Recipe, on date: Date, slot: MealSlot) {
        let meal = PlannedMeal(date: date, slot: slot, recipe: recipe, servings: recipe.servings)
        context.insert(meal)
    }

    private func toggleCooked(_ meal: PlannedMeal) {
        meal.cookedAt = meal.cookedAt == nil ? .now : nil
    }

    private func shiftWeek(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: anchorDate) else { return }
        anchorDate = next
    }
}

// MARK: - Rows

private struct DayHeader: View {
    let date: Date
    let forecast: ForecastProvider.DayForecast?

    var body: some View {
        HStack(spacing: 6) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            if Calendar.current.isDateInToday(date) {
                Text("Today")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            Spacer()
            if let forecast {
                Label("\(Int(forecast.highF.rounded()))°", systemImage: forecast.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
        }
    }
}

private struct PlannedMealRow: View {
    let meal: PlannedMeal
    let members: [HouseholdMember]
    let onToggleCooked: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggleCooked) {
                Image(systemName: meal.isCooked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(meal.isCooked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(meal.isCooked ? "Mark as not cooked" : "Mark as cooked")

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .strikethrough(meal.isCooked, color: .secondary)
                HStack(spacing: 6) {
                    Label(meal.slotValue.title, systemImage: meal.slotValue.symbolName)
                    if meal.servings > 0 {
                        Text("· \(meal.servings) servings")
                    }
                    if let gathering = meal.gathering {
                        Text("· \(gathering.title)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !conflictWarnings.isEmpty {
                    Label(conflictWarnings, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// Surfaces dietary conflicts inline rather than making people remember them.
    private var conflictWarnings: String {
        guard let recipe = meal.recipe else { return "" }
        let issues = members.compactMap { member -> String? in
            let hits = recipe.conflicts(for: member)
            guard !hits.isEmpty else { return nil }
            return "\(member.name): \(hits.joined(separator: ", "))"
        }
        return issues.joined(separator: " · ")
    }
}

private struct SuggestionBanner: View {
    let suggestion: SuggestionEngine.Suggestion
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tomorrow", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(suggestion.headline)
                .font(.headline)
            Button("Add to tomorrow's dinner", action: onAccept)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WeekPlanView()
        .modelContainer(SampleData.previewContainer)
}
