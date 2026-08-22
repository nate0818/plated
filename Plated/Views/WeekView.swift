import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Home. The next seven nights, tonight on top — planned nights are plated
/// photos, open nights are dashed placemats waiting. The ring fills as the
/// week does, and the weeks after scroll on below. Tapping an open night
/// opens the planning page; sideways, the plan becomes a month.
struct WeekView: View {
    var askTheTable: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false

    @State private var bounceDay: Date?
    /// The day a dragged plate is hovering over — it leans in to receive.
    @State private var dropHoverDay: Date?
    @State private var groceryPresented = false
    @State private var planDay: Date?
    @State private var actionDay: Date?
    @State private var swipedDay: Date?
    @State private var personShown: PersonRef?
    @State private var pushed: PlanDestination?

    enum PlanDestination: String, Identifiable {
        case activity
        var id: String { rawValue }
    }
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
        NavigationStack {
            Group {
                if verticalSizeClass == .compact || forceMonth {
                    MonthPlannerView()
                } else {
                    portraitPlan
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex)
            }
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                }
            }
        }
        .sheet(isPresented: $groceryPresented) { GrocerySheet() }
        .sheet(item: $planDay) { date in
            PlanNightSheet(date: date, askTheTable: askTheTable)
        }
        .confirmationDialog(
            actionDay.map { "Dinner on \(dayName($0))" } ?? "",
            isPresented: Binding(get: { actionDay != nil }, set: { if !$0 { actionDay = nil } }),
            titleVisibility: .visible
        ) {
            if let date = actionDay {
                Button("Swap or re-plan") { planDay = date }
                Button("Remove from \(dayName(date))", role: .destructive) { remove(on: date) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task {
            await forecast.refresh(days: 10)
            if showCalendarEvents { events.refresh() }
            Notifier.nudgeTurnIfNeeded(meals: meals, members: members, into: context)
        }
        .onAppear {
            #if DEBUG
            // UI-test hooks — one-shot on purpose, they must never replay
            // on tab reselect.
            if LaunchFlags.consume("-plated-open-grocery") {
                groceryPresented = true
            }
            if LaunchFlags.consume("-plated-open-profile") {
                openOwnProfile()
            }
            if LaunchFlags.consume("-plated-open-activity") {
                pushed = .activity
            }
            if let planFlag = LaunchFlags.consume("-plated-open-plan-day") ? weekDates.first(where: { dinner(on: $0) == nil }) : nil {
                planDay = planFlag
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
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                MicroLabel(weekRangeLabel)
                Text("Your week")
                    .font(.gabarito(25, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)

            headerIcon {
                groceryPresented = true
            } content: {
                Image(systemName: "basket")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }

            ActivityBellButton(size: 36) {
                pushed = .activity
            }

            progressRing

            Button {
                Haptic.tap()
                openOwnProfile()
            } label: {
                VStack(spacing: 2) {
                    AvatarCircle(initials: hostInitial, tone: .neutralPair, size: 42)
                    Text("HOST")
                        .font(.jakarta(8, .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.inkFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
    }

    private func headerIcon(action: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 36, height: 36)
                .overlay { content() }
                .frame(minWidth: 40, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
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
                .contentTransition(.numericText())
        }
        .animation(.plSnap, value: plannedCount)
        // The seventh plate completes the week — that's a kiss.
        .sensoryFeedback(.success, trigger: plannedCount) { old, new in new == 7 && old < 7 }
    }

    // MARK: Rows

    private func plannedRow(_ meal: PlannedMeal, date: Date) -> some View {
        let today = Calendar.current.isDateInToday(date)
        let eatingOut = meal.recipe == nil && meal.customTitle.localizedCaseInsensitiveContains("eating out")
        return SwipeRow(isOpen: swipeBinding(date), actions: [.remove { remove(on: date) }]) {
            HStack(spacing: 12) {
                dayColumn(date, dimmed: false)

                if eatingOut {
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 2)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "fork.knife.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                } else {
                    // Tonight's plate simmers — the one ambient mesh drift
                    // per screen that DishView was built for.
                    dishCircle(for: meal, simmering: today)
                }

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
                if let cook = meal.cook, !eatingOut {
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
        } isTargeted: { over in
            if over { Haptic.select() }
            withAnimation(.plSnap) { dropHoverDay = over ? date : nil }
        }
        .scaleEffect(bounceDay == date ? 1.02 : (dropHoverDay == date ? 1.015 : 1))
        .animation(.plPop, value: bounceDay)
    }

    private func emptyRow(date: Date) -> some View {
        Button {
            Haptic.tap()
            planDay = date
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
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(minHeight: 72)
            .overlay {
                // A hovering plate turns the dashed invitation solid.
                if dropHoverDay == date {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Color.ink, lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .dropDestination(for: String.self) { tokens, _ in
            moveMeal(from: tokens.first, to: date)
        } isTargeted: { over in
            if over { Haptic.select() }
            withAnimation(.plSnap) { dropHoverDay = over ? date : nil }
        }
        .scaleEffect(dropHoverDay == date ? 1.015 : 1)
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

    private func dishCircle(for meal: PlannedMeal, simmering: Bool = false) -> some View {
        Group {
            if let data = meal.recipe?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            } else if let recipe = meal.recipe {
                DishView(recipe: recipe, diameter: 52, animated: simmering)
            } else {
                DishView(title: meal.title, diameter: 52)
            }
        }
        .plDishShadow()
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

    private func openOwnProfile() {
        guard let owner = members.first(where: \.isOwner) else { return }
        personShown = PersonRef(name: owner.name, colorHex: owner.colorHex)
    }

    private func swipeBinding(_ date: Date) -> Binding<Bool> {
        Binding(
            get: { swipedDay == date },
            set: { open in swipedDay = open ? date : (swipedDay == date ? nil : swipedDay) }
        )
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
}

/// Encodes a day as a drag payload — plain date tokens, no model IDs, so a
/// drop can never dangle if the store changes mid-drag.
enum DayTransfer {
    static func token(for date: Date) -> String {
        "plated-day:\(Int(date.startOfDay.timeIntervalSince1970))"
    }

    static func date(from token: String?) -> Date? {
        guard let token, token.hasPrefix("plated-day:"),
              let seconds = TimeInterval(token.dropFirst("plated-day:".count)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

#Preview {
    MainShellView().modelContainer(SampleData.previewContainer)
}
