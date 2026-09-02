import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Home. The next seven nights, tonight on top — planned nights are plated
/// photos, open nights are dashed placemats waiting. The ring fills as the
/// week does, and the weeks after scroll on below. Tapping an open night
/// opens the planning page; sideways, the plan becomes a month.
struct WeekView: View {
    var askTheTable: () -> Void = {}
    /// Set by the shell when a widget deep-links to the grocery list. The
    /// week owns the basket, so the request has to arrive here rather than
    /// the shell reaching into another screen's state.
    var openGrocery: Binding<Bool> = .constant(false)

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

    /// The real calendar week, honoring the user's first weekday — not a
    /// rolling seven days from today. A week you can only ever see the front
    /// half of never has a shape; this one does, and "4 of 7" means the week
    /// rather than the next seven nights.
    private var weekDates: [Date] {
        Calendar.current.weekDays(for: .now)
    }

    private var futureWeeks: [[Date]] {
        let today = Calendar.current.startOfDay(for: .now)
        return (1..<weeksAhead).compactMap { week in
            guard let inWeek = Calendar.current.date(byAdding: .day, value: week * 7, to: today)
            else { return nil }
            return Calendar.current.weekDays(for: inWeek)
        }
    }

    private func isPast(_ date: Date) -> Bool {
        date < Calendar.current.startOfDay(for: .now)
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
            .plSwipeBack()
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
            }
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                }
            }
        }
        .sheet(isPresented: $groceryPresented) { GrocerySheet() }
        .onChange(of: openGrocery.wrappedValue, initial: true) { _, requested in
            guard requested else { return }
            openGrocery.wrappedValue = false
            groceryPresented = true
        }
        .sheet(item: $planDay) { date in
            PlanNightSheet(date: date, askTheTable: askTheTable)
        }
        .confirmationDialog(
            actionDay.map { date in
                Calendar.current.isDateInToday(date) ? "Dinner tonight" : "Dinner on \(dayName(date))"
            } ?? "",
            isPresented: Binding(get: { actionDay != nil }, set: { if !$0 { actionDay = nil } }),
            titleVisibility: .visible
        ) {
            if let date = actionDay {
                Button("Change what's for dinner") { planDay = date }
                Button("Remove from \(dayName(date))", role: .destructive) { remove(on: date) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task {
            await forecast.refresh(days: 10)
            if showCalendarEvents { events.refresh() }
            Notifier.nudgeTurnIfNeeded(meals: meals, members: members, into: context)
            // Rebuilt here too, not only where a night is planned: meals get
            // moved and cooks get swapped from several places, and a
            // reminder for a dish nobody is making any more is worse than
            // no reminder. No-ops when notifications aren't authorised.
            await NotificationScheduler.rebuild(
                meals: meals, ownerName: members.first(where: \.isOwner)?.name ?? ""
            )
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
            if let planFlag = LaunchFlags.consume("-plated-open-plan-day") ? weekDates.first(where: { !isPast($0) && dinner(on: $0) == nil }) : nil {
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
                .padding(.bottom, Layout.floatingChromeInset)
            }
            // Scrolling puts an open row away, the way a list does.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, swipedDay != nil {
                    withAnimation(.plSnap) { swipedDay = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ date: Date) -> some View {
        if isPast(date) {
            pastRow(date)
        } else if let meal = dinner(on: date) {
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
                    .font(.gabarito(25, .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)

            headerIcon("Grocery list") {
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
                    AvatarCircle(initials: hostInitial, tone: .neutralPair, size: 42,
                                 photo: members.first(where: \.isOwner)?.photoData)
                    Text("HOST")
                        .font(.jakarta(10, .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.inkFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
    }

    private func headerIcon(
        _ label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 36, height: 36)
                .overlay { content() }
                // 44 in BOTH axes. It was 40 wide, and this is the only
                // route to the shopping list.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
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
        // The seventh plate completes the week, and that is a kiss.
        .sensoryFeedback(.success, trigger: plannedCount) { old, new in new == 7 && old < 7 }
        // Read as "5" on its own, which is a number with no noun.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plannedCount) of 7 nights planned")
    }

    // MARK: Rows

    private func plannedRow(_ meal: PlannedMeal, date: Date) -> some View {
        let today = Calendar.current.isDateInToday(date)
        let eatingOut = meal.recipe == nil && meal.customTitle.localizedCaseInsensitiveContains("eating out")
        return SwipeRow(isOpen: swipeBinding(date), actions: [.remove { remove(on: date) }]) {
            HStack(spacing: 12) {
                dateCard(date, dimmed: false)

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
                    AvatarCircle(member: cook, size: 30)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(minHeight: 72)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            // Every row in the plan draws the same shape at the same weight —
            // planned rows used to be an 18pt corner at 1pt (1.5 on today)
            // while open rows were a 20pt corner at 2pt, and stacked 8pt
            // apart the mismatch read as crooked. Today is carried by the
            // tinted date card now, not by a heavier outline.
            .overlay {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(Color.navHairline, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptic.tap()
                actionDay = date
            }
            // A gesture announces nothing: without this the row's swipe
            // actions scattered onto each child text and the tap itself
            // was invisible to VoiceOver. Home's member rows do the same.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens what you can do with this night")
        }
        .draggable(DayTransfer.token(for: date)) {
            dishCircle(for: meal)
        }
        .dropDestination(for: String.self) { tokens, _ in
            moveMeal(from: tokens.first, to: date)
        } isTargeted: { over in
            if over { Haptic.select() }
            withAnimation(.plSnap) {
                // Dragging from one row to the next fires `true` on the new
                // row before `false` on the old one, so clearing
                // unconditionally wiped the lean on the row you were
                // actually over. Only ever clear your own.
                if over { dropHoverDay = date }
                else if dropHoverDay == date { dropHoverDay = nil }
            }
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
                dateCard(date, dimmed: true)
                Circle()
                    .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
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
                // A hovering plate turns the dashed invitation solid. Same
                // corner and weight as a planned row — see plannedRow.
                if dropHoverDay == date {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .dropDestination(for: String.self) { tokens, _ in
            moveMeal(from: tokens.first, to: date)
        } isTargeted: { over in
            if over { Haptic.select() }
            withAnimation(.plSnap) {
                // Same guard as plannedRow, and open nights are the common
                // drop target — a bare `else -> nil` here wiped the lean
                // belonging to the row the finger had already moved onto,
                // so indication died for the rest of any drag that crossed
                // one open night. It also strands the lean when a drop
                // turns this row into a planned one and tears down its drop
                // interaction mid-gesture; clearing only your own makes a
                // stranded value harmless the moment the next row is entered.
                if over { dropHoverDay = date }
                else if dropHoverDay == date { dropHoverDay = nil }
            }
        }
        .scaleEffect(dropHoverDay == date ? 1.015 : 1)
    }

    /// Nights already gone. They stay on screen so the week keeps its real
    /// shape, but they collapse to a history strip — no plus, no forecast
    /// (last night's weather is noise), nothing to tap or drag. The month
    /// grid has always treated the past this way. The compression is also
    /// what keeps tonight on screen come Saturday, when six of these sit
    /// above it.
    private func pastRow(_ date: Date) -> some View {
        let meal = dinner(on: date)
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.formattedWeekday())
                    .font(.jakarta(9, .bold))
                    .tracking(0.3)
                Text(date.formattedDayNumber())
                    .font(.gabarito(17, .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.inkFaint)
            .frame(width: 52, height: 38)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.chipFill)
            }

            if let meal {
                dishCircle(for: meal, diameter: 34)
                    .opacity(0.65)
                Text(meal.title)
                    .font(.jakarta(13, .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            } else {
                // Past tense on purpose: "yet" promises a night you can
                // still cook.
                Text("Nothing plated")
                    .font(.jakarta(13, .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Color.hairlineSoft, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    /// Apple's Calendar tile, in Plated's register: an accent weekday over a
    /// large numeral, the day's weather under it. Today is the only day that
    /// gets paint — a tomato tint fills the tile, so the highlight lives on
    /// the date rather than in a heavier line around the whole row.
    ///
    /// Sized to the dish circle it sits beside (52 wide) so the row keeps one
    /// rhythm instead of two.
    private func dateCard(_ date: Date, dimmed: Bool) -> some View {
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 0) {
            HStack(spacing: 3) {
                // Today is today whether or not the night is planned.
                Text(date.formattedWeekday())
                    .font(.jakarta(10, .bold))
                    .tracking(0.3)
                    .foregroundStyle(today ? Color.tomato : Color.inkFaint)
                if showCalendarEvents && events.hasEvent(on: date) {
                    Circle().fill(Color.grape).frame(width: 4.5, height: 4.5)
                }
            }
            // A date is a fact whether or not the night is planned, so an
            // open night no longer reads as disabled — the dashed plate and
            // the faint copy carry the emptiness on their own.
            Text(date.formattedDayNumber())
                .font(.gabarito(24, .bold))
                .monospacedDigit()
                .foregroundStyle(dimmed && !today ? Color.inkSecondary : Color.ink)
            if let day = forecast.forecast(for: date) {
                HStack(spacing: 2) {
                    Image(systemName: day.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(Int(day.highF.rounded()))°")
                        .font(.jakarta(10, .bold))
                        .monospacedDigit()
                }
                // inkFaint disappears into the tomato tint.
                .foregroundStyle(today ? Color.inkSecondary : Color.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
                // The row combines its children, so a bare "72°" would read
                // as a stray number. Say the condition the way Weather does.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.conditionDescription), high \(Int(day.highF.rounded())) degrees")
            }
        }
        // Fixed height, so a day the forecast can't answer for doesn't make
        // its row shorter than its neighbours.
        .frame(width: 52, height: 56)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(today ? Color.tomatoTint : Color.chipFill)
        }
    }

    private func dishCircle(for meal: PlannedMeal, diameter: CGFloat = 52, simmering: Bool = false) -> some View {
        Group {
            if let data = meal.recipe?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else if let recipe = meal.recipe {
                DishView(recipe: recipe, diameter: diameter, animated: simmering)
            } else {
                DishView(title: meal.title, diameter: diameter)
            }
        }
        .plDishShadow()
    }

    private var cooksFooter: some View {
        HStack(spacing: 6) {
            if let first = members.first(where: { !$0.isOwner && !$0.cookWeekdays.isEmpty }) {
                AvatarCircle(member: first, size: 26)
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
            return "\(month.string(from: first)) \(f) to \(l)"
        }
        return "\(shortMonth.string(from: first)) to \(shortMonth.string(from: last))"
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
        personShown = PersonRef(name: owner.name, colorHex: owner.colorHex, memberID: owner.persistentModelID)
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
