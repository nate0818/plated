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
    /// The day whose detail page is pushed. Tapping a day used to raise a
    /// change/remove dialog; those two are swipe actions inside the day now.
    @State private var dayShown: Date?
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

    /// Nights still askable — today and later, nothing plated. Past days are
    /// spent, not owed, so they can't hold the week hostage.
    private var openAheadCount: Int {
        weekDates.filter { !isPast($0) && dinner(on: $0) == nil }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if verticalSizeClass == .compact || forceMonth {
                    MonthPlannerView(askTheTable: askTheTable)
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
            .navigationDestination(item: $dayShown) { day in
                DayDetailView(date: day, askTheTable: askTheTable)
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
                // 16, not 24. The row's own 8pt of padding then puts the
                // date tile at 24 from the screen edge — the same line
                // "Your week" starts on. The tile used to sit 12pt inboard
                // of the header, which is the kind of misalignment you feel
                // before you can name it.
                .padding(.horizontal, 16)
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
                // "Aug 30 to Sep 5" is wider than a cross-month range has
                // any right to be, and the header's icons leave it under
                // half the screen. It shrinks to fit; wrapping pushed the
                // title down and broke the masthead.
                MicroLabel(weekRangeLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
        // Completing what's left of the week — that's a kiss. The old
        // trigger demanded all seven, so one unplanned Monday made the
        // week's only celebration impossible by Tuesday.
        .sensoryFeedback(.success, trigger: openAheadCount) { old, new in new == 0 && old > 0 }
        // Read as "5" on its own, which is a number with no noun.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plannedCount) of 7 nights planned")
    }

    // MARK: Rows

    private func plannedRow(_ meal: PlannedMeal, date: Date) -> some View {
        let today = Calendar.current.isDateInToday(date)
        let eatingOut = meal.recipe == nil && meal.customTitle.localizedCaseInsensitiveContains("eating out")
        // The dish photo left this row: the date and its weather earned the
        // width instead. The plate is still the first thing you see the
        // moment you open the day.
        return SwipeRow(isOpen: swipeBinding(date), actions: [.remove { remove(on: date) }]) {
            HStack(spacing: 10) {
                dateCard(date, dimmed: false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.title)
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                    Text(tagLine(for: meal, today: today, date: date))
                        .font(.jakarta(12, .semibold))
                        .foregroundStyle(today ? Color.ink : Color.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let cook = meal.cook, !eatingOut {
                    AvatarCircle(member: cook, size: 30)
                }
            }
            .padding(.vertical, 12)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            // 72 was tight enough that "Creamy Tuscan Chicken" and
            // "Alessandra Fitzgerald cooks" both ended in an ellipsis on the
            // one screen the app is mostly looked at. The height and the
            // reclaimed 18pt of width are what let the row say the thing.
            .frame(minHeight: 88)
            .background(Color.cardFill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
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
                dayShown = date
            }
            // A gesture announces nothing: without this the row's swipe
            // actions scattered onto each child text and the tap itself
            // was invisible to VoiceOver. Home's member rows do the same.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the whole day — every meal, the cook, the weather")
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

    /// Two targets, deliberately. The dashed plate still plates dinner in one
    /// tap — that is the app's core move and it does not deserve a detour —
    /// while the rest of the row opens the day, where breakfast, lunch,
    /// dessert and the cook live.
    private func emptyRow(date: Date) -> some View {
        HStack(spacing: 10) {
            dateCard(date, dimmed: true)
            Button {
                Haptic.tap()
                planDay = date
            } label: {
                Circle()
                    .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.inkFaint)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            // The row speaks for both targets below; a second announcement
            // here would just be the same night read twice.
            .accessibilityHidden(true)
            Text(openLine(date))
                .font(.jakarta(14, .semibold))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 88)
        // An open night is a card like any other. It used to be a dashed
        // ghost in a stack of solid rows, so the week read as two different
        // lists — and in dark mode the page showed straight through it.
        // Apple doesn't mix filled and unfilled rows in one table; the
        // emptiness is the copy's job and the dashed plate's, not the
        // container's.
        .background(Color.cardFill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay {
            // A hovering plate turns the dashed invitation solid. Same
            // corner and weight as a planned row — see plannedRow.
            if dropHoverDay == date {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(Color.ink, lineWidth: 1.5)
            } else {
                // Solid, like every other row. Now that an open night is a
                // white card, a dashed outline around it read as a card that
                // had failed rather than a night that is free. The dashed
                // plate inside is the invitation, and one dashed thing per
                // row is enough to say "nothing here yet".
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(Color.navHairline, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            dayShown = date
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(dayName(date).capitalized), \(openLine(date))")
        .accessibilityHint("Opens the whole day — every meal, the cook, the weather")
        .accessibilityAction(named: "Plate dinner") { planDay = date }
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
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 54)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Color.hairlineSoft, lineWidth: 1.5)
        }
        // History answers questions — "what was that thing we ate Monday?"
        // — so it opens the day like every other row. It just can't be
        // planned from there.
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            dayShown = date
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the day")
    }

    /// The Calendar icon, in Plated's register: a real card — white, hairline
    /// edge, a whisper of lift — carrying a small accent weekday over one
    /// large, light numeral. Apple's numeral is big and airy, not chunky, so
    /// this one is Gabarito medium at 28 rather than bold at 24; everything
    /// else in the tile stays quiet so the date is the only thing you read.
    ///
    /// Today swaps the white fill for a tomato tint and turns the weekday
    /// tomato. That tint is the whole highlight — no heavier line around the
    /// row, no second signal.
    ///
    /// Sized to the dish circle beside it (52 wide) so the row keeps one
    /// rhythm, and to a fixed height so a day the forecast can't answer for
    /// doesn't make its row shorter than its neighbours.
    private func dateCard(_ date: Date, dimmed: Bool) -> some View {
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 1) {
            HStack(spacing: 4) {
                // Today is today whether or not the night is planned.
                Text(date.formattedWeekday().uppercased())
                    .font(.jakarta(11, .bold))
                    .tracking(0.8)
                    .foregroundStyle(today ? Color.tomato : Color.inkFaint)
                if showCalendarEvents && events.hasEvent(on: date) {
                    Circle().fill(Color.grape).frame(width: 5, height: 5)
                }
            }

            // A date is a fact whether or not the night is planned, so an
            // open night no longer reads as disabled — the dashed plate and
            // the faint copy carry the emptiness on their own.
            Text(date.formattedDayNumber())
                .font(.gabarito(32, .medium))
                .monospacedDigit()
                .foregroundStyle(dimmed && !today ? Color.inkSecondary : Color.ink)
                // Gabarito's line box leaves the numeral floating below the
                // weekday; Apple sets them almost touching.
                .padding(.top, -3)

            // Weather always occupies its line, even when the forecast
            // can't answer, so a day without one is not a shorter card.
            Group {
                if let day = forecast.forecast(for: date) {
                    HStack(spacing: 4) {
                        Image(systemName: day.symbolName)
                            .font(.system(size: 12, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(Int(day.highF.rounded()))°")
                            .font(.jakarta(12, .bold))
                            .monospacedDigit()
                    }
                    // inkFaint disappears into the tomato tint.
                    .foregroundStyle(today ? Color.inkSecondary : Color.inkFaint)
                    // The row combines its children, so a bare "72°" would
                    // read as a stray number. Say the condition the way
                    // Weather does.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.conditionDescription), high \(Int(day.highF.rounded())) degrees")
                } else {
                    Text(" ")
                        .font(.jakarta(12, .bold))
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 2)
        }
        // The dish photo used to take this width. With it gone the date can
        // be read at arm's length and the temperature has room to be a
        // temperature rather than a footnote.
        .padding(.vertical, 10)
        .frame(width: 84)
        .frame(minHeight: 76)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(today ? Color.tomatoTint : Color.cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(today ? Color.tomato.opacity(0.16) : Color.hairline, lineWidth: 1)
        }
        .plTileShadow()
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

    private func tagLine(for meal: PlannedMeal, today: Bool, date: Date) -> String {
        let base: String
        if today {
            let minutes = meal.recipe?.totalMinutes ?? 0
            base = minutes > 0 ? "Tonight · \(Recipe.durationText(minutes))" : "Tonight"
        } else if !meal.tagline.isEmpty {
            base = meal.tagline
        } else if let cook = meal.cook, !cook.isOwner {
            base = "\(cook.name) cooks"
        } else {
            let minutes = meal.recipe?.totalMinutes ?? 0
            base = minutes > 0 ? Recipe.durationText(minutes) : "Planned"
        }
        // The week row shows dinner; a day can now hold breakfast, lunch,
        // dessert and a snack too, and hiding them here would make the day
        // page a surprise.
        let others = otherSlots(on: date).count
        return others > 0 ? "\(base) · +\(others) more" : base
    }

    /// Everything planned on a day that isn't its dinner, earliest first.
    private func otherSlots(on date: Date) -> [MealSlot] {
        meals
            .filter { Calendar.current.isSameDay($0.date, date) && $0.slotValue != .dinner }
            .map(\.slotValue)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// An open night is only truly empty when nothing else is planned either.
    private func openLine(_ date: Date) -> String {
        let others = otherSlots(on: date)
        guard !others.isEmpty else { return "Nothing plated yet" }
        let joined = ListFormatter.localizedString(byJoining: others.map { $0.title.lowercased() })
        return joined.prefix(1).uppercased() + joined.dropFirst() + " planned"
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
