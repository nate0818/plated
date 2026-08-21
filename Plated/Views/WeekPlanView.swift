import SwiftUI
import SwiftData

/// The home screen: a table setting. Tonight's dish sits directly on the cream
/// canvas — the canvas is the tablecloth. Seven small plates form the week
/// strip; the days that already happened collect in a dark ink band at the
/// bottom, cleared plates on a dark table.
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
    private var isCurrentWeek: Bool {
        calendar.isSameDay(calendar.startOfWeek(for: anchorDate), calendar.startOfWeek(for: .now))
    }
    private var today: Date { Date.now.startOfDay }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Group {
                        Masthead(
                            eyebrow: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                            title: isCurrentWeek ? "Tonight" : "That week"
                        ) {
                            HStack(spacing: 6) {
                                ProgressRing(progress: dinnerProgress, size: 22, tone: .successTone)
                                Text("\(plannedDinners) OF 7")
                                    .font(.caption.weight(.semibold))
                                    .fontWidth(.condensed)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.inkSecondary)
                                    .contentTransition(.numericText(value: Double(plannedDinners)))
                            }
                        }
                        .padding(.top, 8)

                        hero
                            .padding(.top, 20)

                        weekStrip
                            .padding(.top, 24)

                        if let suggestion = topSuggestion {
                            SuggestionLine(suggestion: suggestion) {
                                schedule(suggestion.recipe, on: tomorrow, slot: .dinner)
                            } onDismiss: {
                                withAnimation(.appSmooth) {
                                    suggestionDismissedOn = today.formatted(.iso8601.year().month().day())
                                }
                            }
                            .padding(.top, 20)
                        }

                        Eyebrow("This week")
                            .padding(.top, 28)
                            .padding(.bottom, 10)

                        VStack(spacing: 12) {
                            ForEach(upcomingDays, id: \.self) { day in
                                dayRow(day)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    if !pastContent.isEmpty {
                        inkBand
                            .padding(.top, 28)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Household", systemImage: "person.2") { showingHousehold = true }
                        .foregroundStyle(Color.ink)
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

    // MARK: - Hero: tonight's dish on the tablecloth

    @ViewBuilder
    private var hero: some View {
        let heroDay = isCurrentWeek ? today : weekDays.first ?? today
        let dinner = mealsFor(day: heroDay).first { $0.slotValue == .dinner }

        VStack(spacing: 14) {
            if let dinner {
                Button {
                    toggleExpanded(heroDay)
                } label: {
                    VStack(spacing: 14) {
                        DishView(
                            recipe: dinner.recipe ?? Recipe(title: dinner.title),
                            diameter: 280,
                            animated: true
                        )
                        VStack(spacing: 4) {
                            ViewThatFits(in: .horizontal) {
                                Text(dinner.title)
                                    .font(.system(size: 26, weight: .semibold, design: .serif))
                                Text(dinner.title)
                                    .font(.system(size: 21, weight: .semibold, design: .serif))
                            }
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                            Text(heroMetadata(dinner))
                                .font(.caption.weight(.semibold))
                                .fontWidth(.condensed)
                                .tracking(1.5)
                                .monospacedDigit()
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
                .buttonStyle(PressableCardStyle())

                if !dinner.isCooked {
                    Button("Start cooking") { toggleCooked(dinner) }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.tomato)
                } else {
                    Label("Plated", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.successTone)
                }

                if expandedDay == heroDay {
                    SlotList(
                        meals: mealsFor(day: heroDay),
                        members: members,
                        onFillSlot: { slotBeingFilled = DaySlot(date: heroDay, slot: $0) },
                        onToggleCooked: toggleCooked,
                        onDelete: delete
                    )
                    .padding(.horizontal, 16)
                    .cardSurface()
                }
            } else {
                VStack(spacing: 14) {
                    PlateView(state: .empty, diameter: 280)
                    Text("The evening is wide open.")
                        .font(.system(size: 21, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ink)
                    HStack(spacing: 24) {
                        Button("Pick for me") { pickForMe(date: heroDay) }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.tomato)
                        Button("Browse") { slotBeingFilled = DaySlot(date: heroDay, slot: .dinner) }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func heroMetadata(_ meal: PlannedMeal) -> String {
        var parts: [String] = []
        if let minutes = meal.recipe?.totalMinutes, minutes > 0 { parts.append("\(minutes) MIN") }
        parts.append("SERVES \(meal.servings)")
        if let gathering = meal.gathering { parts.append(gathering.title.uppercased()) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Week strip: seven plates

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(weekDays, id: \.self) { day in
                let isToday = calendar.isSameDay(day, today)
                Button {
                    withAnimation(.appSmooth) {
                        if mealsFor(day: day).isEmpty {
                            slotBeingFilled = DaySlot(date: day, slot: .dinner)
                        } else {
                            expandedDay = expandedDay == day ? nil : day
                        }
                    }
                } label: {
                    VStack(spacing: 5) {
                        PlateView(state: plateState(for: day), diameter: 44)
                            .overlay {
                                if isToday && isCurrentWeek {
                                    Circle()
                                        .strokeBorder(Color.tomato, lineWidth: 2)
                                        .frame(width: 52, height: 52)
                                }
                            }
                            .opacity(day < today && plateStateIsEmpty(for: day) ? 0.4 : 1)
                        Text(day.formatted(.dateTime.weekday(.narrow)).uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .fontWidth(.condensed)
                            .foregroundStyle(isToday ? Color.ink : Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                shiftWeek(by: value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private func plateState(for day: Date) -> PlateState {
        let meals = mealsFor(day: day)
        if let dinner = meals.first(where: { $0.slotValue == .dinner }) {
            if dinner.isCooked { return .cleared }
            if let recipe = dinner.recipe { return .planned(recipe) }
            return .cleared
        }
        if let anyCooked = meals.first(where: \.isCooked), anyCooked.isCooked { return .cleared }
        return .empty
    }

    private func plateStateIsEmpty(for day: Date) -> Bool {
        if case .empty = plateState(for: day) { return true }
        return false
    }

    // MARK: - Day rows (upcoming only; past lives in the ink band)

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let meals = mealsFor(day: day)
        if meals.isEmpty {
            EmptyDayRow(
                date: day,
                accentPick: day == firstEmptyDay,
                onPickForMe: { pickForMe(date: day) },
                onBrowse: { slotBeingFilled = DaySlot(date: day, slot: .dinner) }
            )
        } else {
            FilledDayRow(
                date: day,
                meals: meals,
                isExpanded: expandedDay == day,
                forecast: forecast.forecast(for: day),
                onToggleExpand: { toggleExpanded(day) },
                onFillSlot: { slotBeingFilled = DaySlot(date: day, slot: $0) },
                onToggleCooked: toggleCooked,
                onDelete: delete,
                members: members
            )
        }
    }

    // MARK: - Ink band: earlier this week

    private var pastContent: [(day: Date, meals: [PlannedMeal])] {
        guard isCurrentWeek else { return [] }
        return weekDays
            .filter { $0 < today }
            .map { ($0, mealsFor(day: $0)) }
            .filter { !$0.1.isEmpty }
    }

    private var inkBand: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Earlier this week", color: .inkWellText.opacity(0.7))
            ForEach(pastContent, id: \.day) { entry in
                ForEach(entry.meals) { meal in
                    HStack(spacing: 12) {
                        PlateView(state: meal.isCooked ? .cleared : .empty, diameter: 26)
                        Text(meal.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkWellText.opacity(0.55))
                            .strikethrough(meal.isCooked, color: .inkWellText.opacity(0.35))
                        Spacer()
                        Text(entry.day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .fontWidth(.condensed)
                            .foregroundStyle(Color.inkWellText.opacity(0.4))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.inkWell)
    }

    // MARK: - Derived

    private var upcomingDays: [Date] {
        isCurrentWeek ? weekDays.filter { $0 > today } : weekDays
    }

    private var firstEmptyDay: Date? {
        upcomingDays.first { mealsFor(day: $0).isEmpty }
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
        guard isCurrentWeek else { return nil }
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

// MARK: - Day rows

private struct FilledDayRow: View {
    let date: Date
    let meals: [PlannedMeal]
    let isExpanded: Bool
    let forecast: ForecastProvider.DayForecast?
    let onToggleExpand: () -> Void
    let onFillSlot: (MealSlot) -> Void
    let onToggleCooked: (PlannedMeal) -> Void
    let onDelete: (PlannedMeal) -> Void
    let members: [HouseholdMember]

    private var dinner: PlannedMeal? { meals.first { $0.slotValue == .dinner } }
    private var headline: PlannedMeal? { dinner ?? meals.first }

    var body: some View {
        Button(action: onToggleExpand) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    VStack(spacing: 1) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .fontWidth(.condensed)
                            .tracking(1)
                            .foregroundStyle(Color.inkSecondary)
                        Text(date.formattedDayNumber())
                            .font(.dayNumeral)
                            .monospacedDigit()
                            .foregroundStyle(Color.ink)
                    }
                    .frame(width: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline?.title ?? "")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if let gathering = headline?.gathering {
                                Text(gathering.title.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .fontWidth(.condensed)
                                    .tracking(1)
                                    .foregroundStyle(Color.mulledWine)
                            } else if meals.count > 1 {
                                Text("\(meals.count) MEALS")
                                    .font(.system(size: 11, weight: .semibold))
                                    .fontWidth(.condensed)
                                    .tracking(1)
                                    .foregroundStyle(Color.inkSecondary)
                            } else if let forecast {
                                Label("\(Int(forecast.highF.rounded()))°", systemImage: forecast.symbolName)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    if let recipe = dinner?.recipe {
                        DishView(recipe: recipe, diameter: 48)
                    } else if dinner != nil {
                        DishView(title: dinner?.customTitle ?? "meal", diameter: 48)
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
}

private struct EmptyDayRow: View {
    let date: Date
    let accentPick: Bool
    let onPickForMe: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PlateView(state: .empty, diameter: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("What's for \(date.formatted(.dateTime.weekday(.wide)))?")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                HStack(spacing: 16) {
                    Button("Pick for me", action: onPickForMe)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentPick ? Color.tomato : Color.inkSecondary)
                    Button("Browse", action: onBrowse)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

// MARK: - Expanded slot list

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
                PlateView(state: meal.isCooked ? .cleared : .empty, diameter: 26)
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

// MARK: - Suggestion line

private struct SuggestionLine: View {
    let suggestion: SuggestionEngine.Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DishView(recipe: suggestion.recipe, diameter: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.headline)
                    .font(.footnote)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(suggestion.recipe.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .fontWidth(.condensed)
                    .tracking(1)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            Button("Add", action: onAccept)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
        }
        .padding(12)
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
