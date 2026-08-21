import SwiftUI
import SwiftData

/// The home screen. Opening Plated should feel like opening this week's menu
/// at a restaurant you own: tonight is the headline, the rest of the week is
/// the table of contents, and past days recede into a quiet diary.
struct WeekPlanView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(sort: \PlannedMeal.date) private var allMeals: [PlannedMeal]

    @State private var anchorDate = Date.now
    @State private var forecast = ForecastProvider.shared
    @State private var showingHousehold = false
    @State private var expandedDay: Date?
    @State private var slotBeingFilled: DaySlot?
    @AppStorage("suggestionDismissedOn") private var suggestionDismissedOn = ""

    struct DaySlot: Identifiable {
        let date: Date
        let slot: MealSlot
        var id: String { "\(date.timeIntervalSince1970)-\(slot.rawValue)" }
    }

    private var calendar: Calendar { Calendar.current }
    private var weekDays: [Date] { calendar.weekDays(for: anchorDate) }
    private var isCurrentWeek: Bool { calendar.isSameDay(calendar.startOfWeek(for: anchorDate), calendar.startOfWeek(for: .now)) }
    private var today: Date { Date.now.startOfDay }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    if isCurrentWeek {
                        TodayCard(
                            meals: mealsFor(day: today),
                            isExpanded: expandedDay == today,
                            onToggleExpand: { toggleExpanded(today) },
                            onFillSlot: { slotBeingFilled = DaySlot(date: today, slot: $0) },
                            onToggleCooked: toggleCooked,
                            onDelete: delete,
                            onPickForMe: { pickForMe(date: today) },
                            members: members
                        )

                        if let suggestion = topSuggestion {
                            SuggestionBanner(suggestion: suggestion) {
                                schedule(suggestion.recipe, on: tomorrow, slot: .dinner)
                            } onDismiss: {
                                withAnimation(.appSmooth) {
                                    suggestionDismissedOn = today.formatted(.iso8601.year().month().day())
                                }
                            }
                        }
                    }

                    Eyebrow(isCurrentWeek ? "This week" : "Week of \(weekDays.first?.formatted(.dateTime.month().day()) ?? "")")
                        .padding(.top, 12)
                        .padding(.bottom, 2)

                    ForEach(orderedDays, id: \.self) { day in
                        DayRow(
                            date: day,
                            meals: mealsFor(day: day),
                            isPast: day < today,
                            isExpanded: expandedDay == day,
                            forecast: forecast.forecast(for: day),
                            onToggleExpand: { toggleExpanded(day) },
                            onFillSlot: { slotBeingFilled = DaySlot(date: day, slot: $0) },
                            onToggleCooked: toggleCooked,
                            onDelete: delete,
                            onPickForMe: { pickForMe(date: day) },
                            members: members
                        )
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.4)
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Previous week", systemImage: "chevron.left") { shiftWeek(by: -1) }
                    Button("Next week", systemImage: "chevron.right") { shiftWeek(by: 1) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Household", systemImage: "person.2") { showingHousehold = true }
                }
            }
            .toolbarBackground(Color.canvas, for: .navigationBar)
            .tint(.ink)
            .sheet(isPresented: $showingHousehold) {
                HouseholdView()
                    .presentationCornerRadius(Radius.sheet)
            }
            .sheet(item: $slotBeingFilled) { target in
                RecipePickerView(date: target.date, slot: target.slot)
                    .presentationCornerRadius(Radius.sheet)
            }
            .task { await forecast.refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                Spacer()
                HStack(spacing: 6) {
                    ProgressRing(progress: dinnerProgress, size: 22)
                    Text("\(plannedDinners)/7")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.inkSecondary)
                        .contentTransition(.numericText(value: Double(plannedDinners)))
                }
            }
            Text(isCurrentWeek ? "Tonight" : weekTitle)
                .font(.heroTitle)
                .foregroundStyle(Color.ink)
        }
    }

    private var weekTitle: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "This Week" }
        return (first..<last).formatted(.interval.month(.abbreviated).day())
    }

    // MARK: - Derived

    /// Today leads as the hero; future days follow; past days sink to the
    /// bottom as a quiet diary.
    private var orderedDays: [Date] {
        let days = weekDays
        guard isCurrentWeek else { return days }
        let future = days.filter { $0 > today }
        let past = days.filter { $0 < today }
        return future + past
    }

    private var plannedDinners: Int {
        weekDays.filter { day in
            allMeals.contains { calendar.isSameDay($0.date, day) && $0.slotValue == .dinner }
        }.count
    }

    private var dinnerProgress: Double { Double(plannedDinners) / 7 }

    private var tomorrow: Date {
        calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private var topSuggestion: SuggestionEngine.Suggestion? {
        guard suggestionDismissedOn != today.formatted(.iso8601.year().month().day()) else { return nil }
        guard mealsFor(day: tomorrow).filter({ $0.slotValue == .dinner }).isEmpty else { return nil }
        let engine = SuggestionEngine(recipes: recipes, members: members)
        let cook = members.first(where: \.isPrimaryCook) ?? members.first
        return engine.suggestions(
            for: tomorrow,
            forecast: forecast.forecast(for: tomorrow),
            addressing: cook?.name.isEmpty == false ? cook?.name : nil
        ).first
    }

    private func mealsFor(day: Date) -> [PlannedMeal] {
        allMeals
            .filter { calendar.isSameDay($0.date, day) }
            .sorted { $0.slotValue.sortOrder < $1.slotValue.sortOrder }
    }

    // MARK: - Actions

    private func toggleExpanded(_ day: Date) {
        withAnimation(.appSmooth) {
            expandedDay = expandedDay == day ? nil : day
        }
    }

    private func schedule(_ recipe: Recipe, on date: Date, slot: MealSlot) {
        withAnimation(.appBouncy) {
            context.insert(PlannedMeal(date: date, slot: slot, recipe: recipe, servings: recipe.servings))
        }
    }

    private func pickForMe(date: Date) {
        let engine = SuggestionEngine(recipes: recipes, members: members)
        if let pick = engine.suggestions(for: date, forecast: forecast.forecast(for: date)).first {
            schedule(pick.recipe, on: date, slot: .dinner)
        } else {
            slotBeingFilled = DaySlot(date: date, slot: .dinner)
        }
    }

    private func toggleCooked(_ meal: PlannedMeal) {
        withAnimation(.appSnappy) {
            meal.cookedAt = meal.cookedAt == nil ? .now : nil
        }
    }

    private func delete(_ meal: PlannedMeal) {
        withAnimation(.appSmooth) {
            context.delete(meal)
        }
    }

    private func shiftWeek(by delta: Int) {
        guard let next = calendar.date(byAdding: .weekOfYear, value: delta, to: anchorDate) else { return }
        withAnimation(.appSmooth) { anchorDate = next }
    }
}

// MARK: - Today card

private struct TodayCard: View {
    let meals: [PlannedMeal]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onFillSlot: (MealSlot) -> Void
    let onToggleCooked: (PlannedMeal) -> Void
    let onDelete: (PlannedMeal) -> Void
    let onPickForMe: () -> Void
    let members: [HouseholdMember]

    private var dinner: PlannedMeal? { meals.first { $0.slotValue == .dinner } }
    private var otherMeals: [PlannedMeal] { meals.filter { $0.slotValue != .dinner } }

    var body: some View {
        if let dinner {
            plannedCard(dinner)
        } else {
            emptyTonight
        }
    }

    private func plannedCard(_ dinner: PlannedMeal) -> some View {
        Button(action: onToggleExpand) {
            VStack(alignment: .leading, spacing: 0) {
                heroArt(dinner)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .padding(4)

                VStack(alignment: .leading, spacing: 10) {
                    if !otherMeals.isEmpty || isExpanded {
                        HStack(spacing: 6) {
                            ForEach(otherMeals) { meal in
                                SlotChip(slot: meal.slotValue, label: meal.title)
                            }
                            Spacer()
                        }
                    }
                    if isExpanded {
                        SlotList(
                            meals: meals,
                            members: members,
                            onFillSlot: onFillSlot,
                            onToggleCooked: onToggleCooked,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, otherMeals.isEmpty && !isExpanded ? 0 : 10)
                .padding(.bottom, otherMeals.isEmpty && !isExpanded ? 12 : 16)
            }
        }
        .buttonStyle(PressableCardStyle())
        .cardSurface(radius: Radius.hero, elevated: true)
    }

    private func heroArt(_ dinner: PlannedMeal) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let recipe = dinner.recipe {
                    RecipeArt(recipe: recipe)
                } else {
                    LinearGradient(
                        colors: [Color.copper.wash().mix(with: .copper, by: 0.2),
                                 Color.mulledWine.wash().mix(with: .mulledWine, by: 0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.14), location: 0.62),
                    .init(color: .black.opacity(0.45), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TONIGHT")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    if let minutes = dinner.recipe?.totalMinutes, minutes > 0 {
                        Text("\(minutes) MIN")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                    }
                }
                Text(dinner.title)
                    .font(.heroCardTitle)
                    .foregroundStyle(.white)
                    .strikethrough(dinner.isCooked, color: .white.opacity(0.7))
            }
            .padding(16)
        }
    }

    private var emptyTonight: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's for tonight?")
                .font(.cardTitle)
                .foregroundStyle(Color.ink)
            Text("The evening is wide open.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
            HStack(spacing: 20) {
                Button("Pick for me", action: onPickForMe)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tomato)
                Button("Browse") { onFillSlot(.dinner) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}

// MARK: - Compact day row

private struct DayRow: View {
    let date: Date
    let meals: [PlannedMeal]
    let isPast: Bool
    let isExpanded: Bool
    let forecast: ForecastProvider.DayForecast?
    let onToggleExpand: () -> Void
    let onFillSlot: (MealSlot) -> Void
    let onToggleCooked: (PlannedMeal) -> Void
    let onDelete: (PlannedMeal) -> Void
    let onPickForMe: () -> Void
    let members: [HouseholdMember]

    private var dinner: PlannedMeal? { meals.first { $0.slotValue == .dinner } }
    private var headline: PlannedMeal? { dinner ?? meals.first }

    var body: some View {
        if meals.isEmpty {
            if isPast { quietPastRow } else { emptyRow }
        } else {
            filledRow
        }
    }

    private var quietPastRow: some View {
        HStack(spacing: 14) {
            dayBlock
            Text("Nothing planned")
                .font(.subheadline)
                .foregroundStyle(Color.inkTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var filledRow: some View {
        Button(action: onToggleExpand) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    dayBlock

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if isPast && meals.allSatisfy(\.isCooked) && !meals.isEmpty {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.inkTertiary)
                            }
                            Text(headline?.title ?? "")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(isPast ? Color.inkTertiary : Color.ink)
                                .strikethrough(isPast && (headline?.isCooked ?? false), color: .inkTertiary)
                                .lineLimit(1)
                            if headline?.gathering != nil {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.mulledWine).frame(width: 6, height: 6)
                                    Circle().fill(Color.mulledWine.opacity(0.5)).frame(width: 6, height: 6)
                                }
                            }
                        }
                        HStack(spacing: 5) {
                            ForEach(meals) { meal in
                                Circle()
                                    .fill(isPast ? Color.inkTertiary : meal.slotValue.tone)
                                    .frame(width: 6, height: 6)
                            }
                            if let gathering = headline?.gathering {
                                Text(gathering.title)
                                    .font(.caption)
                                    .foregroundStyle(isPast ? Color.inkTertiary : Color.mulledWine)
                            } else if let forecast, !isPast {
                                Label("\(Int(forecast.highF.rounded()))°", systemImage: forecast.symbolName)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    if let recipe = dinner?.recipe {
                        RecipeArt(recipe: recipe)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .opacity(isPast ? 0.5 : 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if isExpanded {
                    SlotList(
                        meals: meals,
                        members: members,
                        onFillSlot: onFillSlot,
                        onToggleCooked: onToggleCooked,
                        onDelete: onDelete
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .cardSurface(radius: Radius.card)
    }

    private var emptyRow: some View {
        HStack(spacing: 14) {
            dayBlock
            VStack(alignment: .leading, spacing: 4) {
                Text("What's for \(date.formatted(.dateTime.weekday(.wide)))?")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                HStack(spacing: 16) {
                    Button("Pick for me", action: onPickForMe)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.tomato)
                    Button("Browse") { onFillSlot(.dinner) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }

    private var dayBlock: some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(isPast ? Color.inkTertiary : Color.inkSecondary)
            Text(date.formattedDayNumber())
                .font(.dayNumeral)
                .monospacedDigit()
                .foregroundStyle(isPast ? Color.inkTertiary : Color.ink)
        }
        .frame(width: 44)
    }
}

// MARK: - Expanded slot list (shared by Today card and day rows)

private struct SlotList: View {
    let meals: [PlannedMeal]
    let members: [HouseholdMember]
    let onFillSlot: (MealSlot) -> Void
    let onToggleCooked: (PlannedMeal) -> Void
    let onDelete: (PlannedMeal) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(MealSlot.allCases.sorted { $0.sortOrder < $1.sortOrder }) { slot in
                let slotMeals = meals.filter { $0.slotValue == slot }
                Divider().overlay(Color.hairline)
                if slotMeals.isEmpty {
                    Button { onFillSlot(slot) } label: {
                        HStack {
                            Label(slot.title, systemImage: slot.symbolName)
                                .font(.subheadline)
                                .foregroundStyle(Color.inkTertiary)
                            Spacer()
                            Image(systemName: "plus")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.inkTertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(slotMeals) { meal in
                        MealLine(
                            meal: meal,
                            members: members,
                            onToggleCooked: { onToggleCooked(meal) },
                            onDelete: { onDelete(meal) }
                        )
                    }
                }
            }
        }
    }
}

private struct MealLine: View {
    let meal: PlannedMeal
    let members: [HouseholdMember]
    let onToggleCooked: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCooked) {
                Image(systemName: meal.isCooked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(meal.isCooked ? Color.successTone : Color.inkTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: meal.isCooked)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .font(.subheadline)
                    .foregroundStyle(meal.isCooked ? Color.inkTertiary : Color.ink)
                    .strikethrough(meal.isCooked, color: .inkTertiary)
                if !conflictText.isEmpty {
                    WarningPill(text: conflictText)
                }
            }

            Spacer()

            SlotChip(slot: meal.slotValue)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .contextMenu {
            Button("Remove from plan", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var conflictText: String {
        guard let recipe = meal.recipe else { return "" }
        return members.compactMap { member -> String? in
            let hits = recipe.conflicts(for: member)
            return hits.isEmpty ? nil : "\(member.name): \(hits.joined(separator: ", "))"
        }.joined(separator: " · ")
    }
}

// MARK: - Suggestion banner

private struct SuggestionBanner: View {
    let suggestion: SuggestionEngine.Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.headline)
                    .font(.footnote)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(suggestion.recipe.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Button("Add to plan", action: onAccept)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tomato)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.tomato.mix(with: .canvas, by: 0.94),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if abs(value.translation.width) > 60 { onDismiss() }
            }
        )
    }
}

#Preview {
    WeekPlanView()
        .modelContainer(SampleData.previewContainer)
}
