import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Home. The next seven nights, tonight on top — planned nights are plated
/// photos, open nights are dashed placemats waiting. The ring fills as the
/// week does, and the weeks after scroll on below so planning ahead is just
/// more scrolling. Sideways, the plan becomes a month.
struct WeekView: View {
    var askTheTable: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false

    @State private var expandedDay: Date?
    @State private var bounceDay: Date?
    @State private var groceryPresented = false
    @State private var pickerDay: Date?
    @State private var profilePresented = false
    @State private var actionDay: Date?
    @State private var swipedDay: Date?
    @State private var forecast = ForecastProvider.shared
    @State private var events = DayEventsProvider.shared

    /// How far ahead the plan scrolls — this week plus three more.
    private let weeksAhead = 4

    /// UI-test hook: renders the landscape month view in any orientation.
    private var forceMonth: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-plated-force-month")
        #else
        false
        #endif
    }

    private var weekDates: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private var futureWeeks: [[Date]] {
        let today = Calendar.current.startOfDay(for: .now)
        return (1..<weeksAhead).map { week in
            (0..<7).compactMap {
                Calendar.current.date(byAdding: .day, value: week * 7 + $0, to: today)
            }
        }
    }

    private var plannedCount: Int {
        weekDates.filter { dinner(on: $0) != nil }.count
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact || forceMonth {
                MonthPlannerView()
            } else {
                portraitPlan
            }
        }
        .sheet(isPresented: $groceryPresented) { GrocerySheet() }
        .sheet(isPresented: $profilePresented) { ProfileSheet() }
        .sheet(item: $pickerDay) { date in
            RecipePickerSheet(date: date) { recipe in
                plate(recipe, on: date, tagline: "")
            }
        }
        .confirmationDialog(
            actionDay.map { "Dinner on \(dayName($0))" } ?? "",
            isPresented: Binding(get: { actionDay != nil }, set: { if !$0 { actionDay = nil } }),
            titleVisibility: .visible
        ) {
            if let date = actionDay {
                Button("Swap the dish") { pickerDay = date }
                Button("Remove from \(dayName(date))", role: .destructive) { remove(on: date) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task {
            await forecast.refresh(days: 10)
            if showCalendarEvents { events.refresh() }
        }
        .onAppear {
            #if DEBUG
            // UI-test hook: `simctl launch … -plated-open-grocery` lands here.
            // One-shot on purpose — it must never replay on tab reselect.
            if LaunchFlags.consume("-plated-open-grocery") {
                groceryPresented = true
            }
            if LaunchFlags.consume("-plated-open-profile") {
                profilePresented = true
            }
            #endif
        }
    }

    private var portraitPlan: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { date in
                        dayRow(date)
                    }
                    ForEach(Array(futureWeeks.enumerated()), id: \.offset) { index, week in
                        HStack {
                            MicroLabel(weekSectionLabel(week, index: index))
                            Spacer()
                            Text("\(week.filter { dinner(on: $0) != nil }.count) of 7")
                                .font(.jakarta(11, .bold))
                                .foregroundStyle(Color.inkFaint)
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 2)
                        ForEach(week, id: \.self) { date in
                            dayRow(date)
                        }
                    }
                    cooksFooter
                        .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 110)
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ date: Date) -> some View {
        if let meal = dinner(on: date) {
            plannedRow(meal, date: date)
        } else {
            emptyRow(date: date)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                MicroLabel(weekRangeLabel)
                Text("Your week")
                    .font(.gabarito(25, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    Haptic.tap()
                    groceryPresented = true
                } label: {
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "basket")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.ink)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)

                HStack(spacing: 7) {
                    progressRing
                    Text("of 7\nplated")
                        .font(.jakarta(11, .bold))
                        .foregroundStyle(Color.inkSecondary)
                        .lineSpacing(0)
                        .fixedSize()
                }

                Button {
                    Haptic.tap()
                    profilePresented = true
                } label: {
                    VStack(spacing: 2) {
                        AvatarCircle(initials: hostInitial, tone: .neutralPair, size: 44)
                        Text("HOST")
                            .font(.jakarta(9, .bold))
                            .tracking(0.7)
                            .foregroundStyle(Color.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var progressRing: some View {
        let fraction = Double(plannedCount) / 7
        return ZStack {
            Circle()
                .fill(AngularGradient(
                    stops: [
                        .init(color: .basil, location: 0),
                        .init(color: .basil, location: fraction),
                        .init(color: .hairline, location: fraction),
                        .init(color: .hairline, location: 1)
                    ],
                    center: .center,
                    angle: .degrees(-90)
                ))
                .frame(width: 34, height: 34)
            Circle().fill(Color.canvas).frame(width: 26, height: 26)
            Text("\(plannedCount)")
                .font(.jakarta(11, .extraBold))
                .foregroundStyle(Color.ink)
        }
        .animation(.plSnap, value: plannedCount)
    }

    // MARK: Rows

    private func plannedRow(_ meal: PlannedMeal, date: Date) -> some View {
        let today = Calendar.current.isDateInToday(date)
        return SwipeToRemove(isOpen: swipeBinding(date), onRemove: { remove(on: date) }) {
            HStack(spacing: 12) {
                dayColumn(date, dimmed: false)

                dishCircle(for: meal)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.title)
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(tagLine(for: meal, today: today))
                        .font(.jakarta(12, .semibold))
                        .foregroundStyle(today ? Color.ink : Color.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let cook = meal.cook {
                    AvatarCircle(initials: cook.firstInitial, tone: cook.tone, size: 30)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(minHeight: 72)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.row))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.row)
                    .strokeBorder(today ? Color.ink : Color.navHairline, lineWidth: today ? 1.5 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptic.tap()
                actionDay = date
            }
        }
        .draggable(DayTransfer.token(for: date)) {
            dishCircle(for: meal)
        }
        .dropDestination(for: String.self) { tokens, _ in
            moveMeal(from: tokens.first, to: date)
        }
        .scaleEffect(bounceDay == date ? 1.02 : 1)
        .animation(.plPop, value: bounceDay)
    }

    private func emptyRow(date: Date) -> some View {
        let expanded = expandedDay == date
        return VStack(spacing: 0) {
            Button {
                Haptic.tap()
                withAnimation(.plSnap) { expandedDay = expanded ? nil : date }
            } label: {
                HStack(spacing: 12) {
                    dayColumn(date, dimmed: true)
                    Circle()
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.inkFaint)
                        }
                    Text("Nothing plated yet")
                        .font(.jakarta(14, .semibold))
                        .foregroundStyle(Color.inkSecondary)
                    Spacer()
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ViewThatFits(in: .horizontal) {
                    quickChips(date)
                    ScrollView(.horizontal, showsIndicators: false) { quickChips(date) }
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(minHeight: 72)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        }
        .dropDestination(for: String.self) { tokens, _ in
            moveMeal(from: tokens.first, to: date)
        }
    }

    private func dayColumn(_ date: Date, dimmed: Bool) -> some View {
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 0) {
            HStack(spacing: 3) {
                Text(date.formattedWeekday().uppercased())
                    .font(.jakarta(10, .extraBold))
                    .tracking(0.6)
                    .foregroundStyle(today && !dimmed ? Color.ink : Color.inkFaint)
                if showCalendarEvents && events.hasEvent(on: date) {
                    Circle().fill(Color.grape).frame(width: 5, height: 5)
                }
            }
            Text(date.formattedDayNumber())
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(dimmed ? Color.inkFaint : Color.ink)
            if let day = forecast.forecast(for: date) {
                HStack(spacing: 2) {
                    Image(systemName: day.symbolName)
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(Int(day.highF.rounded()))°")
                        .font(.jakarta(9, .bold))
                }
                .foregroundStyle(Color.inkFaint)
                .padding(.top, 1)
            }
        }
        .frame(width: 44)
    }

    private func dishCircle(for meal: PlannedMeal) -> some View {
        Group {
            if let data = meal.recipe?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            } else if let recipe = meal.recipe {
                DishView(recipe: recipe, diameter: 52)
            } else {
                DishView(title: meal.title, diameter: 52)
            }
        }
        .plDishShadow()
    }

    private func quickChips(_ date: Date) -> some View {
        HStack(spacing: 8) {
            quickChip("Pick for me", filled: true) { pickForMe(date) }
            quickChip("Cookbook") { pickerDay = date }
            quickChip("Ask the table") { ask(date) }
        }
    }

    private func quickChip(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.jakarta(13, .bold))
                .fixedSize()
                .foregroundStyle(filled ? Color.canvas : Color.ink)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background {
                    if filled {
                        Capsule().fill(Color.ink)
                    } else {
                        Capsule().strokeBorder(Color.hairline)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var cooksFooter: some View {
        HStack(spacing: 6) {
            if let first = members.first(where: { !$0.isOwner && !$0.cookWeekdays.isEmpty }) {
                AvatarCircle(initials: first.firstInitial, tone: first.tone, size: 26)
            }
            Text(cooksLine)
                .font(.jakarta(12, .semibold))
                .foregroundStyle(Color.inkSecondary)
        }
    }

    // MARK: Data

    private func dinner(on date: Date) -> PlannedMeal? {
        meals.first {
            Calendar.current.isSameDay($0.date, date) && $0.slotValue == .dinner
        }
    }

    private func tagLine(for meal: PlannedMeal, today: Bool) -> String {
        if today {
            let minutes = meal.recipe?.totalMinutes ?? 0
            return minutes > 0 ? "Tonight · \(minutes) min" : "Tonight"
        }
        if !meal.tagline.isEmpty { return meal.tagline }
        if let cook = meal.cook, !cook.isOwner { return "\(cook.name) cooks" }
        let minutes = meal.recipe?.totalMinutes ?? 0
        return minutes > 0 ? "\(minutes) min" : "Planned"
    }

    private var weekRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let calendar = Calendar.current
        let month = DateFormatter()
        month.dateFormat = "MMMM"
        let shortMonth = DateFormatter()
        shortMonth.dateFormat = "MMM d"
        if calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            let f = calendar.component(.day, from: first)
            let l = calendar.component(.day, from: last)
            return "\(month.string(from: first)) \(f)–\(l)"
        }
        return "\(shortMonth.string(from: first)) – \(shortMonth.string(from: last))"
    }

    private func weekSectionLabel(_ week: [Date], index: Int) -> String {
        guard let first = week.first else { return "" }
        if index == 0 { return "Next week" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: first))"
    }

    private func dayName(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "tonight" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private var hostInitial: String {
        members.first(where: \.isOwner)?.firstInitial ?? "?"
    }

    private var cooksLine: String {
        let names = DateFormatter()
        names.dateFormat = "EEE"
        let parts: [String] = members.filter { !$0.isOwner && !$0.cookWeekdays.isEmpty }.map { member in
            let todayWeekday = Calendar.current.component(.weekday, from: .now)
            let ordered = member.cookWeekdays.sorted {
                (($0 - todayWeekday + 7) % 7) < (($1 - todayWeekday + 7) % 7)
            }
            let days = ordered.compactMap { weekday -> String? in
                var comps = DateComponents()
                comps.weekday = weekday
                guard let date = Calendar.current.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime) else { return nil }
                return names.string(from: date)
            }
            guard !days.isEmpty else { return "" }
            if days.count == 1 {
                let full = DateFormatter()
                full.dateFormat = "EEEE"
                var comps = DateComponents()
                comps.weekday = ordered[0]
                if let date = Calendar.current.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime) {
                    return "\(member.name) takes \(full.string(from: date))"
                }
            }
            return "\(member.name) cooks \(days.joined(separator: " & "))"
        }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Tap an open night to plan it" : parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func swipeBinding(_ date: Date) -> Binding<Bool> {
        Binding(
            get: { swipedDay == date },
            set: { open in swipedDay = open ? date : (swipedDay == date ? nil : swipedDay) }
        )
    }

    private func pickForMe(_ date: Date) {
        let engine = SuggestionEngine(recipes: recipes, members: members)
        // Avoid repeating a dish within the visible week only — history is
        // fair game (that is the point of resurfacing old favorites).
        let thisWeek = Set(weekDates.compactMap { dinner(on: $0)?.recipe?.persistentModelID })
        let ranked = engine.suggestions(for: date, forecast: nil, limit: recipes.count)
        // Prefer something not already on the week; if the whole cookbook is
        // plated, repeating the top pick is honest. Never bypass the engine —
        // it is what enforces everyone's dietary hard-no's.
        guard let recipe = (ranked.first { !thisWeek.contains($0.recipe.persistentModelID) } ?? ranked.first)?.recipe
        else { return }
        let minutes = recipe.totalMinutes
        plate(recipe, on: date, tagline: minutes > 0 ? "Picked for you · \(minutes) min" : "Picked for you")
    }

    /// Lands a recipe on a night — or, when the night is already planned,
    /// swaps the dish in place so "change my mind" is one pick, not
    /// delete-then-add.
    private func plate(_ recipe: Recipe, on date: Date, tagline: String) {
        Haptic.plate()
        let cook = members.first { $0.cookWeekdays.contains(Calendar.current.component(.weekday, from: date)) }
            ?? members.first(where: \.isOwner)
        withAnimation(.plPop) {
            if let existing = dinner(on: date) {
                existing.recipe = recipe
                existing.customTitle = ""
                existing.servings = recipe.servings
                existing.tagline = tagline
            } else {
                context.insert(PlannedMeal(
                    date: date, slot: .dinner, recipe: recipe,
                    servings: recipe.servings, cook: cook, tagline: tagline
                ))
            }
            expandedDay = nil
            bounceDay = date
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            if bounceDay == date { bounceDay = nil }
        }
    }

    private func remove(on date: Date) {
        guard let meal = dinner(on: date) else { return }
        Haptic.plate()
        withAnimation(.plSnap) {
            swipedDay = nil
            context.delete(meal)
        }
    }

    /// Drag a plate to another night. Dropping on a planned night swaps the
    /// two dinners rather than eating one.
    private func moveMeal(from token: String?, to target: Date) -> Bool {
        guard let source = DayTransfer.date(from: token),
              !Calendar.current.isSameDay(source, target),
              let meal = dinner(on: source) else { return false }
        Haptic.plate()
        withAnimation(.plPop) {
            if let occupant = dinner(on: target) {
                occupant.date = source.startOfDay
            }
            meal.date = target.startOfDay
            swipedDay = nil
            bounceDay = target
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            if bounceDay == target { bounceDay = nil }
        }
        return true
    }

    private func ask(_ date: Date) {
        Haptic.plate()
        let dayName = DateFormatter()
        dayName.dateFormat = "EEEE"
        let owner = members.first(where: \.isOwner)
        let post = TablePost(
            authorName: owner?.name ?? "Me",
            authorColorHex: owner?.colorHex ?? "FF5A3C",
            caption: "What should we plate \(Calendar.current.isDateInToday(date) ? "tonight" : dayName.string(from: date))? Open to ideas.",
            kind: "ask"
        )
        context.insert(post)
        expandedDay = nil
        askTheTable()
    }
}

/// Encodes a day as a drag payload — plain date tokens, no model IDs, so a
/// drop can never dangle if the store changes mid-drag.
private enum DayTransfer {
    static func token(for date: Date) -> String {
        "plated-day:\(Int(date.startOfDay.timeIntervalSince1970))"
    }

    static func date(from token: String?) -> Date? {
        guard let token, token.hasPrefix("plated-day:"),
              let seconds = TimeInterval(token.dropFirst("plated-day:".count)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

/// Swipe a planned night left to reveal Remove — the standard gesture,
/// rebuilt for rows that live outside a List.
private struct SwipeToRemove<Content: View>: View {
    @Binding var isOpen: Bool
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    private let revealWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            if isOpen || dragOffset < 0 {
                Button {
                    onRemove()
                } label: {
                    Circle()
                        .fill(Color.tomato)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }

            content()
                .offset(x: (isOpen ? -revealWidth : 0) + dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            // Horizontal-dominant only, so the plan still scrolls.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base: CGFloat = isOpen ? -revealWidth : 0
                            dragOffset = min(max(value.translation.width, -revealWidth - base), -base)
                        }
                        .onEnded { value in
                            let projected = (isOpen ? -revealWidth : 0) + value.translation.width
                            withAnimation(.plSnap) {
                                isOpen = projected < -revealWidth / 2
                                dragOffset = 0
                            }
                        }
                )
        }
        .animation(.plSnap, value: isOpen)
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

#Preview {
    MainShellView().modelContainer(SampleData.previewContainer)
}
