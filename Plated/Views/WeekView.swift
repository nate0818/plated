import SwiftUI
import SwiftData

/// Home. The next seven nights, tonight on top — planned nights are plated
/// photos, open nights are dashed placemats waiting. The ring fills as the
/// week does.
struct WeekView: View {
    var askTheTable: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var expandedDay: Date?
    @State private var bounceDay: Date?
    @State private var groceryPresented = false
    @State private var pickerDay: Date?

    private var weekDates: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private var plannedCount: Int {
        weekDates.filter { dinner(on: $0) != nil }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { date in
                        if let meal = dinner(on: date) {
                            plannedRow(meal, date: date)
                        } else {
                            emptyRow(date: date)
                        }
                    }
                    cooksFooter
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 110)
            }
        }
        .sheet(isPresented: $groceryPresented) { GrocerySheet() }
        .onAppear {
            #if DEBUG
            // UI-test hook: `simctl launch … -plated-open-grocery` lands here.
            if ProcessInfo.processInfo.arguments.contains("-plated-open-grocery") {
                groceryPresented = true
            }
            #endif
        }
        .sheet(item: $pickerDay) { date in
            RecipePickerSheet(date: date) { recipe in
                plate(recipe, on: date, tagline: "")
            }
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

                VStack(spacing: 2) {
                    AvatarCircle(initials: hostInitial, tone: .neutralPair, size: 44)
                    Text("HOST")
                        .font(.jakarta(9, .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.inkFaint)
                }
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
        return HStack(spacing: 12) {
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
    }

    private func dayColumn(_ date: Date, dimmed: Bool) -> some View {
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 0) {
            Text(date.formattedWeekday().uppercased())
                .font(.jakarta(10, .extraBold))
                .tracking(0.6)
                .foregroundStyle(today && !dimmed ? Color.ink : Color.inkFaint)
            Text(date.formattedDayNumber())
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(dimmed ? Color.inkFaint : Color.ink)
        }
        .frame(width: 40)
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

    private func plate(_ recipe: Recipe, on date: Date, tagline: String) {
        Haptic.plate()
        let cook = members.first { $0.cookWeekdays.contains(Calendar.current.component(.weekday, from: date)) }
            ?? members.first(where: \.isOwner)
        let meal = PlannedMeal(
            date: date, slot: .dinner, recipe: recipe,
            servings: recipe.servings, cook: cook, tagline: tagline
        )
        withAnimation(.plPop) {
            context.insert(meal)
            expandedDay = nil
            bounceDay = date
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            if bounceDay == date { bounceDay = nil }
        }
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

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

#Preview {
    MainShellView().modelContainer(SampleData.previewContainer)
}
