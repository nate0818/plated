import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Plan keeps the date picker and its content in agreement: changing the
/// selected date changes the day below it, without adding a second timeline.
struct WeekView: View {
    var askTheTable: () -> Void = {}
    /// Set by the shell when a widget deep-links to the grocery list. The
    /// week owns the basket, so the request has to arrive here rather than
    /// the shell reaching into another screen's state.
    var openGrocery: Binding<Bool> = .constant(false)

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.activeAppTab) private var activeAppTab
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false

    @State private var weekAnchor = Calendar.current.startOfDay(for: Date.now)
    @State private var dateNavigationRevision = 0
    @State private var showMonth = false
    @State private var cookRequest: PlanCookRequest?
    @State private var pendingCookRequest: PlanCookRequest?
    @State private var cookLedger = CookLedger.shared
    @State private var bounceDay: Date?
    /// The day a dragged plate is hovering over — it leans in to receive.
    @State private var dropHoverDay: Date?
    @State private var groceryPresented = false
    @State private var planDay: Date?
    @State private var reusingMeal: PlannedMeal?
    @State private var mealToMove: PlannedMeal?
    @State private var calendarShown = false
    /// The day whose detail page is pushed. Tapping a day used to raise a
    /// change/remove dialog; those two are swipe actions inside the day now.
    @Environment(\.tabPop) private var tabPop
    @State private var swipedDay: Date?
    @State private var pushed: PlanDestination?
    /// The night you tapped is the night that opens, and your own face is
    /// the door to your own profile. See CookbookView for the reasoning.
    @Namespace private var zoom

    /// One navigation owner for every destination above Plan. Keeping these
    /// in separate optionals allowed a household deep link to leave Activity,
    /// a profile, and Household active at the same time.
    enum PlanDestination: Hashable, Identifiable {
        case activity
        case household
        case person(PersonRef)
        case recipe(Recipe)
        case day(Date)

        var id: String {
            switch self {
            case .activity: "activity"
            case .household: "household"
            case .person(let person): "person-\(person.id)"
            case .recipe(let recipe): "recipe-\(recipe.persistentModelID.hashValue)"
            case .day(let date): "day-\(date.timeIntervalSinceReferenceDate)"
            }
        }
    }
    @State private var forecast = ForecastProvider.shared
    @State private var events = DayEventsProvider.shared
    /// The host's first name while their household is still uploading
    /// (docs/household.md §7, step 6): nil once the root's `publishedAt`
    /// lands, "" when the name never arrived. The app-group cache is not
    /// observed, so it is polled while the plan is on screen, the way Home
    /// reads the outbox.
    @State private var arrivingHost: String?
    /// The sentence a removal left for the first empty week (§8), shown in
    /// place of the invitation until a meal is planned.
    @State private var removedNotice: String?
    @State private var dinnerSaveFailed = false

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
        Calendar.current.weekDays(for: weekAnchor)
    }

    private var futureWeeks: [[Date]] {
        let selected = Calendar.current.startOfDay(for: weekAnchor)
        return (1..<weeksAhead).compactMap { week in
            guard let inWeek = Calendar.current.date(byAdding: .day, value: week * 7, to: selected)
            else { return nil }
            return Calendar.current.weekDays(for: inWeek)
        }
    }

    private func isPast(_ date: Date) -> Bool {
        date < Calendar.current.startOfDay(for: .now)
    }

    /// A night is a night: one somebody else planned counts the same as
    /// one planned here, in the "N planned" line, the strip's dots and the
    /// open count.
    private func hasAnyDinner(on date: Date) -> Bool {
        dinner(on: date) != nil || PlanLedger.shared.dinner(on: date) != nil
    }

    private var plannedCount: Int {
        weekDates.filter { hasAnyDinner(on: $0) }.count
    }

    /// What the app group says about the household, folded into the two
    /// lines this screen can show (docs/household.md §7 step 6, §8).
    ///
    /// The removal notice is cleared the first time a week with a meal on
    /// it is looked at: the invitation is true again, and a sentence about
    /// a household that is gone must not outlive the plan that replaced it.
    private func readHouseholdStanding() {
        var arriving: String?
        if case .member = HouseholdShare.membership, HouseholdShare.cachedPublishedAt == nil {
            let host = HouseholdShare.cachedOwnerName.trimmingCharacters(in: .whitespaces)
            arriving = host.split(separator: " ").first.map(String.init) ?? host
        }
        let defaults = HouseholdShare.groupDefaults
        var notice = defaults.string(forKey: HouseholdSync.Keys.removedNotice)
        if notice != nil, plannedCount > 0 {
            defaults.removeObject(forKey: HouseholdSync.Keys.removedNotice)
            notice = nil
        }
        guard arriving != arrivingHost || notice != removedNotice else { return }
        withAnimation(.plSnap) {
            arrivingHost = arriving
            removedNotice = notice
        }
    }

    /// Nights still askable — today and later, nothing plated. Past days are
    /// spent, not owed, so they can't hold the week hostage.
    private var openAheadCount: Int {
        weekDates.filter { !isPast($0) && !hasAnyDinner(on: $0) }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if showMonth {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            DesignIconButton(symbol: "arrow.left", label: "Back to tonight") { returnToTonight() }
                            Text("Calendar").plType(.body, .semibold)
                            Spacer(minLength: 0)
                            DesignIconButton(symbol: "calendar", label: "Choose a date") { calendarShown = true }
                            Button("Today") { weekAnchor = .now.startOfDay }
                                .plType(.footnote, .semibold).plActionLabel().plTapTarget()
                        }
                        .plChrome().padding(.horizontal, 24).padding(.vertical, 8)
                        MonthPlannerView(anchor: $weekAnchor, askTheTable: askTheTable)
                    }
                } else {
                    portraitPlan
                }
            }
            // NavigationStack hosts its content separately from the shell's
            // opacity-hidden tabs. Hide the actual content from accessibility.
            .accessibilityHidden(activeAppTab != .week)
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .plSwipeBack()
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                case .household: HouseholdHomeView(embedded: true)
                case .person(let person):
                    PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID, authorID: person.authorID)
                        .navigationTransition(.zoom(sourceID: ZoomID.host, in: zoom))
                case .recipe(let recipe):
                    RecipeDetailView(recipe: recipe, meal: dinner(on: weekAnchor))
                case .day(let day):
                    DayDetailView(date: day, askTheTable: askTheTable)
                        .navigationTransition(.zoom(sourceID: day, in: zoom))
                }
            }
        }
        .sheet(item: plannerSheet) { destination in
            switch destination {
            case .calendar:
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Choose a date").plType(.title); Spacer(); DesignIconButton(symbol: "xmark", label: "Close calendar") { calendarShown = false } }
                    DatePicker("Dinner date", selection: $weekAnchor, displayedComponents: .date).datePickerStyle(.graphical).tint(Color.accentText)
                    PrimaryActionButton(title: "View this date") { calendarShown = false }
                }.padding(24).presentationDetents([.large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
            case .groceries: GrocerySheet()
            case .night(let date): PlanNightSheet(date: date, askTheTable: askTheTable)
            case .move(let meal): MoveMealSheet(meal: meal) { weekAnchor = $0 }
            case .reuse(let meal): PlanAgainSheet(meal: meal)
            }
        }
        .onChange(of: openGrocery.wrappedValue, initial: true) { _, requested in
            guard requested else { return }
            openGrocery.wrappedValue = false
            groceryPresented = true
        }
        // Tapping Plan while a day, a person or a pushed screen is open
        // returns to the plan itself. See TabPopRequest.
        .onChange(of: tabPop) { _, request in
            guard request.tab == .week else { return }
            pushed = nil
            returnToTonight()
        }
        .onAppear { updatePlanPresence() }
        .onChange(of: activeAppTab) { _, _ in updatePlanPresence() }
        .onChange(of: pushed) { _, _ in updatePlanPresence() }
        .onDisappear {
            if Presence.shared.planVisible { Presence.shared.planVisible = false }
        }
        .task {
            await forecast.refresh(days: 10)
            if showCalendarEvents { events.refresh() }
            Notifier.nudgeTurnIfNeeded(meals: meals, members: members, into: context)
            // Rebuilt here too, not only where a night is planned: meals get
            // moved and cooks get swapped from several places, and a
            // reminder for a dish nobody is making any more is worse than
            // no reminder. No-ops when notifications aren't authorised.
            await NotificationScheduler.rebuild(meals: meals)
        }
        // A notice about a night lands on that night. Parked by the shell,
        // collected here or on appear if the week was not on screen.
        .onReceive(NotificationCenter.default.publisher(for: LinkRelay.dayRequested)) { _ in
            if let day = LinkRelay.takeDay() { withAnimation(.plSnap) { weekAnchor = day } }
        }
        .onReceive(NotificationCenter.default.publisher(for: LinkRelay.activityRequested)) { _ in
            if LinkRelay.takeActivity() { pushed = .activity }
        }
        .onReceive(NotificationCenter.default.publisher(for: LinkRelay.householdRequested)) { _ in
            if LinkRelay.takeHousehold() { pushed = .household }
        }
        .task {
            // The household's standing lives in the app group, which no
            // SwiftUI body observes. Read it while the plan is on screen:
            // the line answers within a few seconds of the root arriving.
            while !Task.isCancelled {
                readHouseholdStanding()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        // A meal planned on this week settles the removal notice at once,
        // without waiting for the next poll.
        .onChange(of: meals.count) { _, _ in readHouseholdStanding() }
        .onChange(of: weekAnchor) { _, _ in readHouseholdStanding() }
        .onAppear {
            if let day = LinkRelay.takeDay() { weekAnchor = day }
            if LinkRelay.takeActivity() { pushed = .activity }
            if LinkRelay.takeHousehold() { pushed = .household }
            if forceMonth { showMonth = true }
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
            if ProcessInfo.processInfo.arguments.contains("-plated-open-stats") {
                pushed = .household
            }
            if let planFlag = LaunchFlags.consume("-plated-open-plan-day") ? weekDates.first(where: { !isPast($0) && dinner(on: $0) == nil }) : nil {
                planDay = planFlag
            }
            if LaunchFlags.consume("-plated-review-plan-night") {
                // Stable route for the recipe picker and gathering review
                // fixtures, even when every upcoming night is already full.
                planDay = weekDates.first ?? Calendar.current.startOfDay(for: .now)
            }
            if LaunchFlags.consume("-plated-review-move-meal"),
               let sample = meals.first(where: { !$0.isCooked }) {
                mealToMove = sample
            }
            if !showMonth, LaunchFlags.consume("-plated-reveal-plan-actions") {
                swipedDay = weekDates.first(where: { !isPast($0) && dinner(on: $0) != nil })
            }
            #endif
        }
        .fullScreenCover(item: $cookRequest) { request in
            CookingFocusView(recipe: request.recipe, meal: request.meal, servings: request.servings, remotePlanID: request.remotePlanID)
        }
        .confirmationDialog("Start a new cooking session?", isPresented: Binding(get: { pendingCookRequest != nil }, set: { if !$0 { pendingCookRequest = nil } }), titleVisibility: .visible) {
            Button("End current session and start this recipe", role: .destructive) {
                for recipe in recipes where cookLedger.isCooking(recipe) { cookLedger.forget(recipe) }
                NotificationScheduler.cancelCookTimer()
                CookTimerLive.end()
                cookRequest = pendingCookRequest
                pendingCookRequest = nil
            }
            Button("Keep current session", role: .cancel) { pendingCookRequest = nil }
        } message: {
            Text("Your place and timer in the current recipe will be cleared. The recipe and meal plan stay saved.")
        }
    }

    private func updatePlanPresence() {
        Presence.shared.planVisible = activeAppTab == .week && pushed == nil
    }

    private enum PlannerSheet: Identifiable {
        case groceries, calendar, night(Date), move(PlannedMeal), reuse(PlannedMeal)
        var id: String { switch self { case .calendar: "calendar"; case .groceries: "groceries"; case .night(let date): "night-\(date.timeIntervalSince1970)"; case .move(let meal): "move-\(meal.persistentModelID)"; case .reuse(let meal): "reuse-\(meal.persistentModelID)" } }
    }
    private var plannerSheet: Binding<PlannerSheet?> {
        Binding(get: { if calendarShown { return .calendar }; if let mealToMove { return .move(mealToMove) }; if let reusingMeal { return .reuse(reusingMeal) }; if let planDay { return .night(planDay) }; return groceryPresented ? .groceries : nil },
                set: { if $0 == nil { planDay = nil; mealToMove = nil; reusingMeal = nil; groceryPresented = false; calendarShown = false } })
    }

    private var portraitPlan: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tonightHeader
                        .id(Self.timelineAnchor)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24).padding(.top, 12)
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            VStack(alignment: .leading, spacing: 24) {
                                if let arrivingHost {
                                    Text(arrivingHost.isEmpty ? "Still arriving from the organizer's phone." : "Still arriving from \(arrivingHost)'s phone.")
                                        .plType(.footnote).foregroundStyle(Color.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                featuredDinner
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.fill, in: Radius.shape(Radius.hero))
                                additionalMealsForSelectedDay
                                PlanContextView(date: weekAnchor, forecast: forecast,
                                    history: PlanDinnerHistory(local: meals, shared: PlanLedger.shared.all))
                                Divider().accessibilityHidden(true)
                                PlanHouseholdView(members: members, meals: meals) { member in
                                    pushed = .person(PersonRef(name: member.name, colorHex: member.colorHex,
                                        memberID: member.persistentModelID, authorID: member.identityKey ?? ""))
                                } openHousehold: {
                                    pushed = .household
                                }
                            }
                            .frame(maxWidth: 760)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.bottom, Layout.floatingChromeInset)
                        } header: {
                            dateNavigation
                                .frame(maxWidth: 760)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(Color.canvas)
                        }
                    }
                }
            }
            .accessibilityIdentifier("plan-selected-day-content")
            .alert("Dinner didn’t save", isPresented: $dinnerSaveFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your plan hasn’t changed. Please try again.")
            }
            .scrollIndicators(.hidden)
            .clipped()
            .onChange(of: weekAnchor) { _, _ in
                scroll.scrollTo(Self.timelineAnchor, anchor: .top)
            }
            .onChange(of: tabPop) { _, request in
                guard request.tab == .week else { return }
                withAnimation(.plSnap) { scroll.scrollTo(Self.timelineAnchor, anchor: .top) }
            }
        }
    }

    private var dateNavigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !Calendar.current.isDateInToday(weekAnchor) {
                Button("Back to tonight") { returnToTonight() }
                    .plType(.footnote, .semibold).plActionLabel().plTapTarget()
                    .foregroundStyle(Color.accentText)
            }
            PlanDateStrip(
                selection: $weekAnchor,
                dropHoverDay: $dropHoverDay,
                hasDinner: hasAnyDinner,
                canAcceptDrop: { !isPast($0) && PlanOccupancy.shared(on: $0, slot: .dinner) == nil && dinner(on: $0)?.isCooked != true },
                moveMeal: { moveMeal(from: $0, to: $1) },
                selectionChanged: { swipedDay = nil },
                navigationRevision: dateNavigationRevision,
                shiftWeek: { delta in
                    guard let date = Calendar.current.date(byAdding: .day, value: delta * 7, to: weekAnchor) else { return }
                    weekAnchor = date
                }
            )
        }
        .plChrome()
    }

    @ViewBuilder
    private var additionalMealsForSelectedDay: some View {
        let featuredLocal = dinner(on: weekAnchor)
        let featuredRemote = featuredLocal == nil ? PlanLedger.shared.dinner(on: weekAnchor) : nil
        let otherLocal = meals.filter {
            Calendar.current.isDate($0.date, inSameDayAs: weekAnchor)
                && $0.persistentModelID != featuredLocal?.persistentModelID
        }.sorted { $0.slotValue.sortOrder < $1.slotValue.sortOrder }
        let otherRemote = MealSlot.allCases.sorted { $0.sortOrder < $1.sortOrder }.flatMap {
            PlanLedger.shared.plans(on: weekAnchor, slot: $0)
        }.filter { $0.recordName != featuredRemote?.recordName }
        if !otherLocal.isEmpty || !otherRemote.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Also on this day").plType(.heading).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
                ForEach(otherLocal) { meal in
                    Button { pushed = .day(weekAnchor) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            MicroLabel(meal.slotValue.title)
                            Text(meal.title).plType(.body, .semibold).foregroundStyle(Color.ink)
                            Text("Serves \(meal.servings)").plType(.footnote).foregroundStyle(Color.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.pressable)
                }
                ForEach(otherRemote) { entry in
                    RemotePlanRow(entry: entry, date: weekAnchor, members: members) { pushed = .day(weekAnchor) }
                }
            }
        }
    }

    private var tonightHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PlatedWordmark(size: 24)
                Spacer(minLength: 8)
                EditorialAddButton()
                ActivityBellButton(size: 44) { pushed = .activity }
                AccountButton()
            }.plChrome()
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Text(greeting).plType(.heading).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button { showMonth = true } label: {
                    Label("Calendar", systemImage: "calendar")
                        .plType(.footnote, .semibold).plActionLabel().plTapTarget()
                }.foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private var greeting: String {
        let name = members.me?.name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init)
        guard let name, !HouseholdIdentity.isPlaceholder(name) else { return "Welcome home" }
        return "Hi, \(name)"
    }

    private func returnToTonight() {
        weekAnchor = .now.startOfDay
        dateNavigationRevision += 1
        showMonth = false
        swipedDay = nil
    }

    private struct PlanCookRequest: Identifiable {
        let recipe: Recipe
        let meal: PlannedMeal?
        let servings: Int
        var remotePlanID: String? = nil
        var id: PersistentIdentifier { recipe.persistentModelID }
    }

    private func startCooking(_ recipe: Recipe, meal: PlannedMeal? = nil, remote: PlanLedger.Entry? = nil) {
        let request = PlanCookRequest(recipe: recipe, meal: meal, servings: meal?.servings ?? remote?.servings ?? recipe.servings, remotePlanID: remote?.recordName)
        if recipes.contains(where: { $0.persistentModelID != recipe.persistentModelID && cookLedger.isCooking($0) }) {
            pendingCookRequest = request
        } else { cookRequest = request }
    }

    private var historySections: some View {
        ForEach(cookedHistory) { section in
            if !section.dates.isEmpty {
                MicroLabel(section.label)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(section.dates, id: \.self) { date in dayRow(date) }
                }
            }
        }
    }

    private var futureWeekSections: some View {
        ForEach(futureWeeks, id: \.self) { week in
            let visibleDates = week.filter { !isPast($0) }
            if !visibleDates.isEmpty {
                weekHeader(week, count: week.filter { hasAnyDinner(on: $0) }.count)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(visibleDates, id: \.self) { date in dayRow(date) }
                }
            }
        }
    }

    /// A newly selected day starts at its heading even when the previous
    /// day's content needed scrolling at a large text size.
    private static let timelineAnchor = "plan-current"

    private func weekHeader(_ week: [Date], count: Int) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
        return layout {
            Text(weekSectionLabel(week)).plType(.title, .semibold)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer() }
            Text("\(count) planned").plType(.footnote).foregroundStyle(Color.inkSecondary)
        }
    }

    private var featuredDinner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MicroLabel((Calendar.current.isDateInToday(weekAnchor) ? "Tonight" : weekAnchor.formatted(.dateTime.weekday(.wide))) + " · " + weekAnchor.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                if dinner(on: weekAnchor) != nil || PlanLedger.shared.dinner(on: weekAnchor) != nil {
                    Menu { nightMenu(weekAnchor) } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Color.ink).plTapTarget()
                    }.accessibilityLabel("Dinner options")
                }
            }
            if let meal = dinner(on: weekAnchor), meal.hasDish {
                let who = whoCaption(for: meal)
                Button { Haptic.tap(); pushed = .day(weekAnchor) } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(meal.title).plType(.title, .semibold).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !PlanRowVoice.isEatingOut(title: meal.title, hasRecipe: meal.recipe != nil) {
                            RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 2.5)
                                .frame(maxHeight: 180).clipped()
                        }
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.pressable)
                    .modifier(PlannerMealDrag(meal: meal))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(meal.title)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("featured-dinner-card")
                    .accessibilityHint("Tap to open the day. Hold and drag to another date to move dinner.")
                if who.line != PlanRowVoice.whoLine(for: meal, members: members) {
                    Text(who.line).plType(.footnote).foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if PlanRowVoice.isEatingOut(title: meal.title, hasRecipe: meal.recipe != nil) {
                    Text("No cooking needed").plType(.body, .medium).foregroundStyle(Color.inkSecondary)
                } else {
                    localCookPicker(for: meal)
                    Button { planDay = weekAnchor } label: {
                        Label("Serves \(meal.servings)", systemImage: "person.2")
                            .plType(.footnote)
                            .plActionLabel()
                            .foregroundStyle(Color.ink).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(Color.fill, in: Radius.shape(Radius.chip))
                    }.buttonStyle(.pressable).accessibilityLabel("Change servings")
                }
                if let recipe = meal.recipe {
                    PrimaryActionButton(title: meal.isCooked ? "View recipe" : cookLedger.isCooking(recipe) ? "Resume cooking" : "Start cooking", systemImage: "fork.knife") {
                        if meal.isCooked { pushed = .recipe(recipe) } else { startCooking(recipe, meal: meal) }
                    }
                } else {
                    Button("Edit dinner") { planDay = weekAnchor }.plType(.body, .semibold).foregroundStyle(Color.accentText).plTapTarget()
                }
            } else if let remote = PlanLedger.shared.dinner(on: weekAnchor) {
                remoteFeatured(remote)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let removedNotice, !isPast(weekAnchor) {
                        // The first empty week after a removal says what
                        // happened instead of inviting (docs/household.md
                        // §8). A heading, not the display size: it is two
                        // sentences, and it has to be read whole.
                        Text(removedNotice)
                            .plType(.heading, .semibold).foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let took = RemovedNights.removedHeading(on: weekAnchor), !isPast(weekAnchor) {
                        // This night is empty because the household took the
                        // dinner off, not because nobody has got to it. The
                        // author has no bell row and no push for that, so the
                        // hero and the week row are the only places they can
                        // learn it. An invitation here would be the app
                        // claiming the night was never planned.
                        Text(took)
                            .plType(.heading, .semibold).foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Calendar.current.isDateInToday(weekAnchor)
                             ? "Nothing is planned for tonight."
                             : "Nothing is planned for this night.")
                            .plType(.body).foregroundStyle(Color.inkSecondary)
                    } else {
                        // Slice 2 hard empties — EDIT-PROFILE-AND-PLAN-EMPTY copy stamp.
                        // Kill soft ambient posters; dense title + useful subcopy.
                        Text(Calendar.current.isDateInToday(weekAnchor) ? "What’s for dinner?" : PlanEmptyCopy.heroTitle(past: isPast(weekAnchor)))
                            .plType(.title, .medium).foregroundStyle(Color.ink)
                            .accessibilityAddTraits(.isHeader)
                        if isPast(weekAnchor) {
                            Text(PlanEmptyCopy.detailBody).plType(.footnote).foregroundStyle(Color.inkSecondary)
                        }
                    }
                    localCookPicker(for: dinner(on: weekAnchor))
                    let actions = typeSize >= .xxLarge
                        ? AnyLayout(VStackLayout(spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 8))
                    actions {
                        PrimaryActionButton(title: Calendar.current.isDateInToday(weekAnchor) ? "Plan tonight" : PlanEmptyCopy.planNight) { planDay = weekAnchor }
                        SecondaryActionButton(title: "Eating out") { markEatingOut(on: weekAnchor) }
                            .accessibilityHint("Marks dinner on the selected date as eating out")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func localCookPicker(for meal: PlannedMeal?) -> some View {
        // A rotation is a suggestion until a plan exists. An explicit nil cook
        // must not quietly fall back to the rotation when a recipe is chosen.
        let cook = meal == nil && !isPast(weekAnchor)
            ? CookRotation.cook(for: weekAnchor, members: members, meals: meals) : meal?.cook
        let suggested = meal == nil && cook != nil
        let name: String = {
            guard let cook else { return "No cook assigned" }
            if cook.seat == .invited { return "Waiting for \(cook.firstName) to join" }
            if meal?.isCooked == true { return cook.isMe ? "Cooked by you" : "Cooked by \(cook.name)" }
            if suggested { return cook.isMe ? "You · from your rotation" : "\(cook.name) · from your rotation" }
            return cook.isMe ? "You’re cooking" : "\(cook.name) is cooking"
        }()
        return Menu {
            Button("No cook assigned") { assignCook(nil, on: weekAnchor) }
            ForEach(members.assignableCooks) { member in
                Button(member.isMe ? "You" : member.name) { assignCook(member, on: weekAnchor) }
            }
        } label: {
            PlanCookLabel(heading: suggested ? "Suggested cook" : meal?.isCooked == true ? "Dinner made" : "Cook", name: name, member: cook)
        }
        .accessibilityLabel(suggested ? "Suggested dinner cook" : "Dinner cook")
        .accessibilityValue(name)
        .accessibilityHint("Change who is cooking on the selected date")
        .accessibilityIdentifier("plan-cook-assignment")
    }

    private func assignCook(_ cook: HouseholdMember?, on date: Date) {
        let original = dinner(on: date)
        let previous = original?.cook
        let meal = original ?? PlannedMeal(date: date, slot: .dinner)
        if original == nil { context.insert(meal) }
        meal.cook = cook
        guard Persist.save(context, "assign dinner cook") else {
            if original == nil { context.delete(meal) } else { meal.cook = previous }
            dinnerSaveFailed = true
            return
        }
        Haptic.select()
    }

    /// A shared night keeps the same editorial hierarchy as a local one.
    /// Cooking requires the recipe to exist in this phone's cookbook.
    @ViewBuilder
    private func remoteFeatured(_ entry: PlanLedger.Entry) -> some View {
        let ledger = PlanLedger.shared
        let honesty = entry.isGoing || entry.pendingLine != nil
        let title = entry.hasDish ? entry.title : Calendar.current.isDateInToday(weekAnchor) ? "What’s for dinner?" : PlanEmptyCopy.heroTitle(past: isPast(weekAnchor))
        Button { Haptic.tap(); pushed = .day(weekAnchor) } label: {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).plType(.title, .semibold).foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.hasDish && !PlanRowVoice.isEatingOut(title: entry.title, hasRecipe: entry.hasRecipe) {
                    RecipeArtwork(data: ledger.photo(for: entry.recordName), title: entry.title, ratio: 2.5)
                        .frame(maxHeight: 180).clipped()
                }
                if honesty || entry.cooked {
                    Text(honesty ? RemotePlanRow.caption(for: entry) : "Dinner made")
                        .plType(.footnote).foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.pressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(honesty ? RemotePlanRow.caption(for: entry) : (entry.cooked ? "Dinner made" : ledger.whoLine(for: entry)))
            .accessibilityIdentifier("featured-remote-dinner-card")
            .accessibilityHint("Opens the day")
        // A change made on this phone that the household has not got yet.
        // The card above already shows it, so this sentence is what keeps
        // the card from being a claim that everybody can see it. A night on
        // its way off the plan says that instead, in the same quiet line and
        // in the ledger's own words, so the hero and the row cannot drift:
        // the hero is the largest drawing of a night in the app, and a
        // delete still sitting on this phone must not look like a settled
        // dinner from across the kitchen.
        if let pending = entry.pendingSentence {
            Text(pending)
                .plType(.footnote).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !entry.isGoing {
            if PlanRowVoice.isEatingOut(title: entry.title, hasRecipe: entry.hasRecipe) {
                Text("No cooking needed").plType(.body, .medium).foregroundStyle(Color.inkSecondary)
            } else {
                let name = entry.cooked
                    ? (ledger.isMine(cook: entry) ? "Cooked by you" : entry.hasCook ? "Cooked by \(entry.cookName)" : "Cook not recorded")
                    : (ledger.cookLine(for: entry) ?? "No cook assigned")
                Button { planDay = weekAnchor } label: {
                    PlanCookLabel(heading: "Cook", name: name, member: PlanRowVoice.member(id: entry.cookID, in: members.readable), fallbackName: entry.hasCook ? entry.cookName : nil)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Dinner cook")
                .accessibilityValue(name)
                .accessibilityHint("Opens this household dinner to change its cook")
                .accessibilityIdentifier("plan-cook-assignment")
            }
        }
        // No Let's cook on a night that is going. The pill is an invitation
        // to start a cook session on a dinner this phone has just taken off
        // the plan for everybody.
        if !entry.hasDish && !entry.isGoing {
            PrimaryActionButton(title: Calendar.current.isDateInToday(weekAnchor) ? "Plan tonight" : PlanEmptyCopy.planNight) { planDay = weekAnchor }
        } else if let recipe = cookbookRecipe(for: entry), !entry.isGoing {
            PrimaryActionButton(title: entry.cooked ? "View recipe" : cookLedger.isCooking(recipe) ? "Resume cooking" : "Start cooking", systemImage: "fork.knife") {
                if entry.cooked { pushed = .recipe(recipe) } else { startCooking(recipe, remote: entry) }
            }
        } else {
            // "Not in your cookbook" is a fact about this cookbook, and on a
            // night that is going the pill is missing for a different reason
            // entirely. Saying it there would be false whenever the recipe
            // IS here, which is exactly when the pill would have shown.
            Text(entry.hasRecipe && !entry.isGoing
                 ? "Planned by \(entry.authorFirstName). Not in your cookbook."
                 : "Planned by \(entry.authorFirstName).")
                .plType(.footnote).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The recipe this cookbook holds for a remote night, by origin only.
    /// An empty key never matches: every home-written recipe has one.
    private func cookbookRecipe(for entry: PlanLedger.Entry) -> Recipe? {
        guard !entry.recipeOriginKey.isEmpty else { return nil }
        return recipes.first { $0.planningKey == entry.recipeOriginKey || (!$0.originID.isEmpty && $0.originID == entry.recipeOriginKey) }
    }

    /// The local dinner as always, then every night somebody else planned
    /// for the day beneath it. Both when both exist: two nights on one day
    /// is the truth. A day with only a remote night draws only that: the
    /// counts above already call it planned, so a "Plan dinner" invitation
    /// or a "No dinner planned" line on the same day would be the app
    /// contradicting itself. Planning this phone's own night on top of it
    /// stays a tap away, on the day page and in the hero's menu.
    @ViewBuilder
    private func dayRow(_ date: Date) -> some View {
        let remote = PlanLedger.shared.plans(on: date)
        let local = dinner(on: date)
        // Slice 3: empty past is retroactively plannable (same empty row +
        // long-press verbs as future). Filled past stays history.
        if isPast(date), local != nil {
            pastRow(date)
        } else if let meal = local {
            plannedRow(meal, date: date)
        } else if remote.isEmpty {
            emptyRow(date: date)
        }
        ForEach(remote) { entry in
            // The zoom source for the day lives on the local row when there
            // is one; two sources may not share an id. A remote-only night
            // hands it to its first row so the day still opens from the
            // thing that was tapped.
            if local == nil, !isPast(date), entry.id == remote.first?.id {
                RemotePlanRow(entry: entry, date: date, members: members) { pushed = .day(date) }
                    .matchedTransitionSource(id: date, in: zoom)
            } else {
                RemotePlanRow(entry: entry, date: date, members: members) { pushed = .day(date) }
            }
        }
    }

    // MARK: Rows

    private func plannedRow(_ meal: PlannedMeal, date: Date) -> some View {
        let today = Calendar.current.isDateInToday(date)
        return SwipeRow(isOpen: swipeBinding(date), actions: planActions(for: meal), actionLabel: "Actions for \(meal.title)") {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                dateColumn(date)
                filledMealCard(meal, featured: false, today: today)
            }
            .padding(.vertical, 12)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            // Floor, not a target: the dish square grows with the title +
            // who-line stack so a wrapped line never letterboxes the photo.
            .frame(minHeight: 76)
            .background(dropHoverDay == date ? Color.oliveTint : Color.canvas, in: Radius.shape(Radius.row))
            .overlay {
                if dropHoverDay == date {
                    Radius.shape(Radius.row).strokeBorder(Color.olive, lineWidth: 1.5)
                } else {
                    VStack { Spacer(); Rectangle().fill(Color.hairline).frame(height: 0.5) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptic.tap()
                pushed = .day(date)
            }
            // A gesture announces nothing: without this the row's swipe
            // actions scattered onto each child text and the tap itself
            // was invisible to VoiceOver. Home's member rows do the same.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the day")
            .accessibilityIdentifier(Self.mealAccessibilityIdentifier(for: date))
        }
        .modifier(PlannerMealDrag(meal: meal))
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
        .matchedTransitionSource(id: date, in: zoom)
    }

    /// The whole empty row plans dinner; its other actions stay available
    /// through swipe, the context menu and accessibility actions.
    private func emptyRow(date: Date) -> some View {
        SwipeRow(isOpen: swipeBinding(date), actions: [
            SwipeAction(symbol: "plus", label: "Plan the night") { planDay = date },
            SwipeAction(symbol: "fork.knife", label: "Eat out") { markEatingOut(on: date) }
        ]) {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            dateColumn(date)
            if !typeSize.isAccessibilitySize {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            }
            // An empty night that knows why it is empty. The household took
            // this dinner off, the meal was deleted here, and nothing else on
            // this phone remembers it existed: the digest cannot speak,
            // because it needs an already-read bell row and the author never
            // has one for a night they planned themselves. So this line and
            // the hero are the only way the person learns their dinner went.
            VStack(alignment: .leading, spacing: 2) {
                // Slice 2: title is the empty fact; Plan is the verb (stamp §B).
                Text(RemovedNights.removedLine(on: date) ?? PlanEmptyCopy.rowTitle(past: isPast(date)))
                    .plType(.body, .semibold)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if RemovedNights.removedLine(on: date) == nil {
                    Text(PlanEmptyCopy.noOneAssigned)
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(PlanEmptyCopy.rowAction)
                .plType(.caption, .semibold)
                .foregroundStyle(Color.accentText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 76)
        // Same hover geometry as plannedRow: Radius.shape, not a bare
        // RoundedRectangle, so the lean matches the planned peer beside it.
        .background(dropHoverDay == date ? Color.oliveTint : Color.canvas, in: Radius.shape(Radius.row))
        .overlay {
            if dropHoverDay == date {
                Radius.shape(Radius.row).strokeBorder(Color.olive, lineWidth: 1.5)
            } else {
                VStack { Spacer(); Rectangle().fill(Color.hairline).frame(height: 0.5) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            planDay = date
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(dayName(date).capitalized), \(openLine(date))")
        .accessibilityHint(PlanEmptyCopy.planNightA11y)
        .accessibilityAction(named: "Open day") { pushed = .day(date) }
        .accessibilityAction(named: "Eating out") { markEatingOut(on: date) }
        .contextMenu {
            Button {
                Haptic.tap()
                pushed = .day(date)
            } label: {
                Label("Open day", systemImage: "calendar")
            }
            nightMenu(date)
        }
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
        .matchedTransitionSource(id: date, in: zoom)
        }
    }

    private func planActions(for meal: PlannedMeal) -> [SwipeAction] {
        var actions = [SwipeAction(symbol: "pencil", label: "Edit") { planDay = meal.date }]
        if !meal.isCooked { actions.append(SwipeAction(symbol: "calendar", label: "Move") { mealToMove = meal }) }
        actions.append(.remove { remove(on: meal.date) })
        return actions
    }

    /// Nights already gone. They stay on screen so the week keeps its real
    /// shape, but they collapse to a history strip. Tapping opens the day;
    /// an empty row can also record a retrospective plan or dinner out. The
    /// compression is what keeps tonight on screen come Saturday, when six
    /// of these sit above it.
    private func pastRow(_ date: Date) -> some View {
        let meal = dinner(on: date)
        var actions = meal.map { planActions(for: $0) } ?? [
            SwipeAction(symbol: "plus", label: "Plan the night") { planDay = date },
            SwipeAction(symbol: "fork.knife", label: "Eat out") { markEatingOut(on: date) }
        ]
        if let meal, meal.recipe != nil {
            actions.append(SwipeAction(symbol: "arrow.clockwise", label: "Plan again") {
                reusingMeal = meal
            })
        }
        return SwipeRow(isOpen: swipeBinding(date), actions: actions, actionLabel: meal.map { "Actions for \($0.title)" }) {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            dateColumn(date)

            if let meal {
                RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 1, radius: Radius.small).frame(width: 60)
                Text(meal.title)
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(emptyMealLine(for: date))
                        .plType(.footnote, .semibold)
                        .foregroundStyle(Color.ink)
                    Text(assignmentLine(for: date))
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 54)
        .background(Color.canvas)
        .overlay {
            VStack { Spacer(); Rectangle().fill(Color.hairline).frame(height: 0.5) }
        }
        // History answers questions — "what was that thing we ate Monday?"
        // — so it opens the day like every other row. Empty history also
        // exposes Plan and Eat out through swipe and the context menu.
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            pushed = .day(date)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the day")
        .contextMenu { nightMenu(date) }
        }
    }

    /// Long press a night and the things you actually do to one are right
    /// there. Eating out sat four taps down: add a meal, choose a slot,
    /// scroll, tap. That is the most common answer there is to "what's for
    /// dinner", which is "we aren't cooking".
    @ViewBuilder
    private func nightMenu(_ date: Date) -> some View {
        let planned = dinner(on: date)
        let eatingOut = planned?.recipe == nil
            && planned?.customTitle.localizedCaseInsensitiveContains("eating out") == true

        if !eatingOut {
            Button {
                markEatingOut(on: date)
            } label: {
                Label(PlanEmptyCopy.eatOutAction, systemImage: "fork.knife")
            }
        }
        if !recipes.isEmpty {
            Button {
                pickForMe(on: date)
            } label: {
                Label("Pick for me", systemImage: "wand.and.stars")
            }
        }
        Button {
            Haptic.tap()
            planDay = date
        } label: {
            Label(planned == nil ? PlanEmptyCopy.planMealAction : "Change the dish",
                  systemImage: planned == nil ? "plus.circle" : "arrow.2.squarepath")
        }
        if planned == nil, let me = members.me {
            Button {
                Haptic.tap()
                markIllCook(on: date, cook: me)
            } label: {
                Label(PlanEmptyCopy.illCookAction, systemImage: "person.fill")
            }
        }

        if planned != nil {
            if let meal = planned {
                Menu {
                    Button("Unassigned") { meal.cook = nil; Persist.save(context) }
                    ForEach(members.assignableCooks) { member in
                        Button(member.isMe ? "You" : member.name) { meal.cook = member; Persist.save(context) }
                    }
                } label: { Label(PlanEmptyCopy.assignSomeoneAction, systemImage: "person.crop.circle") }
            }
            // Dragging a plate from one night to another was the only way to
            // move a dinner. That is a gesture nobody is told about and a
            // gesture VoiceOver cannot perform, and `moveMeal` was already
            // sitting here doing the work for the drop target.
            Menu {
                if let planned, !planned.isCooked {
                    Button("Choose a date…") { mealToMove = planned }
                }
                ForEach(movableNights(excluding: date), id: \.self) { target in
                    Button(nightLabel(target)) {
                        _ = moveMeal(from: DayTransfer.token(for: date), to: target)
                    }
                }
            } label: {
                Label("Move to another night", systemImage: "calendar")
            }
            .disabled(planned?.isCooked == true)
            Button(role: .destructive) {
                remove(on: date)
            } label: {
                Label(PlanEmptyCopy.clearNightAction, systemImage: "trash")
            }
        }
    }

    /// Nights this dinner could move to: the rest of this week and the
    /// weeks already on screen, today onward, minus the one it is on.
    private func movableNights(excluding date: Date) -> [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (weekDates + futureWeeks.flatMap { $0 })
            .filter { $0 >= today && !Calendar.current.isSameDay($0, date) }
    }

    /// "Tonight", "Tomorrow", then the weekday, then the date once a
    /// weekday name would be ambiguous.
    private func nightLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Tonight" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        let withinTheWeek = weekDates.contains { calendar.isSameDay($0, date) }
        formatter.dateFormat = withinTheWeek ? "EEEE" : "EEEE, MMM d"
        return formatter.string(from: date)
    }

    /// Empty nights keep the same promise while changing their flavor. The
    /// date makes future nights stable; today also moves with the part of day,
    /// so returning at dinner does not repeat the line seen over breakfast.
    private func emptyHeroTitle(for date: Date) -> String {
        let words = ["delicious", "savory", "cozy", "bright", "spicy", "fresh", "comforting"]
        let calendar = Calendar.current
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let time = calendar.isDateInToday(date) ? calendar.component(.hour, from: .now) / 6 : 0
        let word = words[(day + time) % words.count]
        return isPast(date) ? "Was it something \(word)?" : "Something \(word) starts here."
    }

    /// The same rotation that will be written when a recipe is chosen, said
    /// before the choice so an open night still answers who is up to cook.
    private func assignmentLine(for date: Date) -> String {
        guard let cook = CookRotation.cook(for: date, members: members, meals: meals) else {
            return "No cook assigned yet"
        }
        return cook.isMe ? "You're assigned to cook" : "\(cook.firstName) is assigned to cook"
    }

    /// Dinner is the week row's subject. If another occasion is already on
    /// the day, do not erase it with the ordinary all-day empty sentence.
    private func emptyMealLine(for date: Date) -> String {
        otherSlots(on: date).isEmpty ? "No meal planned yet" : "No dinner planned yet"
    }

    /// A night off the stove still counts as a plan for the week.
    /// Slice 3: past + future long-press "I'll cook" — plan the night with me assigned.
    private func markIllCook(on date: Date, cook: HouseholdMember) {
        Haptic.plate()
        withAnimation(.plPop) {
            if let meal = dinner(on: date) {
                meal.cook = cook
            } else {
                let meal = PlannedMeal(date: date, slot: .dinner, customTitle: "")
                meal.cook = cook
                context.insert(meal)
            }
            bounceDay = date
        }
        Persist.save(context)
    }

    private func markEatingOut(on date: Date) {
        Haptic.plate()
        let original = dinner(on: date)
        let previousRecipe = original?.recipe
        let previousTitle = original?.customTitle ?? ""
        let previousTagline = original?.tagline ?? ""
        let previousCook = original?.cook
        var inserted: PlannedMeal?
        withAnimation(.plPop) {
            if let meal = original {
                meal.recipe = nil
                meal.customTitle = "Eating out"
                meal.tagline = "Night off the stove"
                meal.cook = nil
            } else {
                let meal = PlannedMeal(date: date, slot: .dinner, customTitle: "Eating out")
                meal.tagline = "Night off the stove"
                context.insert(meal)
                inserted = meal
            }
            bounceDay = date
        }
        if !Persist.save(context, "plan eating out") {
            // Revert only this action, preserving unrelated drafts in context.
            if let inserted { context.delete(inserted) }
            if let original {
                original.recipe = previousRecipe; original.customTitle = previousTitle
                original.tagline = previousTagline; original.cook = previousCook
            }
            dinnerSaveFailed = true
        }
    }

    /// The same engine the night sheet uses, with the same forecast it can
    /// see, skipping anything already on this week so the menu never hands
    /// back Tuesday's dinner.
    private func pickForMe(on date: Date) {
        let engine = SuggestionEngine(recipes: recipes, members: members)
        let thisWeek = Set(weekDates.compactMap { dinner(on: $0)?.recipe?.persistentModelID })
        let ranked = engine.suggestions(
            for: date, forecast: forecast.forecast(for: date), limit: recipes.count
        )
        guard let pick = ranked.first(where: { !thisWeek.contains($0.recipe.persistentModelID) })
                ?? ranked.first
        else {
            Haptic.warn()
            return
        }
        Haptic.plate()
        let why = pick.reason.components(separatedBy: ", ").first ?? ""
        let line = why.isEmpty ? "Picked for you" : "Picked for you · \(why)"
        withAnimation(.plPop) {
            if let meal = dinner(on: date) {
                meal.recipe = pick.recipe
                meal.customTitle = ""
                meal.servings = pick.recipe.servings
                meal.tagline = line
            } else {
                context.insert(PlannedMeal(
                    date: date, slot: .dinner, recipe: pick.recipe,
                    servings: pick.recipe.servings,
                    cook: CookRotation.cook(for: date, members: members, meals: meals),
                    tagline: line
                ))
            }
            bounceDay = date
        }
        Persist.save(context, "picked meal")
    }

    /// Dates are a column, not miniature cards. Only today's numeral wears
    /// the brand color; the weekday stays on the same baseline all week.
    /// `PlanDateColumn` is the drawing, shared with `RemotePlanRow` so a
    /// remote night's column can never be a point off a local one's.
    private func dateColumn(_ date: Date) -> some View {
        PlanDateColumn(date: date)
    }

    /// Dish square spanning title top → who-line avatar bottom. Featured
    /// Tonight sits on fill; list rows sit on canvas with the date column.
    @ViewBuilder
    private func filledMealCard(_ meal: PlannedMeal, featured: Bool, today: Bool = false) -> some View {
        let who = whoCaption(for: meal)
        let eatingOut = PlanRowVoice.isEatingOut(title: meal.title, hasRecipe: meal.recipe != nil)
        let stack = PlanFilledMealStack(
            photo: meal.recipe?.photoData,
            title: meal.title,
            eatingOut: eatingOut,
            whoLine: who.line,
            onFill: featured,
            featured: featured,
            today: today
        ) {
            if let member = who.member {
                AvatarCircle(member: member, size: featured ? 26 : 22)
            }
        }
        if featured {
            stack
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fill, in: Radius.shape(Radius.hero))
        } else {
            stack
        }
    }

    /// Honesty lines take the caption when the household has moved on;
    /// otherwise the stamp who-line. One line, never two.
    private func whoCaption(for meal: PlannedMeal) -> (line: String, member: HouseholdMember?) {
        if let held = RemovedNights.heldRowLine(shoppingID: meal.shoppingID ?? "") {
            return (held, nil)
        }
        if let id = meal.shoppingID, let change = HouseholdEdits.pending(shoppingID: id) {
            return (
                HouseholdEdits.rowLine(
                    for: change, me: TableIdentity.cached,
                    currentCookID: PlanNightSheet.cookID(of: meal)
                ),
                nil
            )
        }
        return (
            PlanRowVoice.whoLine(for: meal, members: members),
            PlanRowVoice.faceMember(for: meal, members: members)
        )
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
            if let first = members.first(where: { !$0.isMe && !$0.cookWeekdays.isEmpty }) {
                AvatarCircle(member: first, size: 26)
            }
            Text(cooksLine)
                .plType(.caption, .semibold)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    // MARK: Data

    /// What remains in the selected week around the featured card. The card
    /// already draws the selected date, so the agenda never repeats it.
    private func aheadThisWeek(skipping selected: Date) -> [Date] {
        weekDates.filter { date in
            if isPast(date) { return false }
            if Calendar.current.isSameDay(date, selected) { return false }
            return true
        }
    }

    struct HistorySection: Identifiable {
        let start: Date
        let label: String
        let dates: [Date]
        var id: Date { start }
    }

    /// The weeks behind you, whole, oldest first.
    ///
    /// This used to be only the nights that had a dinner on them, which on a
    /// household that has cooked twice is two rows floating above tonight
    /// with no shape to them. History is a timeline, not a filtered list:
    /// scrolling back should read like a calendar, so the weeks come back
    /// whole and the gaps are part of the record. Which nights you did not
    /// cook is as much of the rhythm as which nights you did.
    ///
    /// Starts at the first dinner this phone or the household remembers, and
    /// always includes earlier days in this week. A new household should still
    /// be able to reach Sunday from Thursday. It stops at twelve weeks because
    /// the rows are drawn eagerly and a year is hundreds of views built to
    /// show a handful.
    private var cookedHistory: [HistorySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let localPast = meals
            .filter { $0.slotValue == .dinner && $0.date < today }
            .map(\.date)
        let householdPast = PlanLedger.shared.all
            .filter { $0.slotValue == .dinner && $0.date < today && !$0.isGoing }
            .map(\.date)

        let thisWeek = calendar.startOfWeek(for: today)
        let floor = calendar.date(byAdding: .day, value: -7 * 12, to: thisWeek) ?? thisWeek
        let earliest = (localPast + householdPast).min()
        var weekStart = max(earliest.map { calendar.startOfWeek(for: $0) } ?? thisWeek, floor)

        var sections: [HistorySection] = []
        while weekStart <= thisWeek {
            // Stable while the strip is scrubbed. Removing the selected past
            // row here changed the height above the strip under the finger.
            let days = calendar.weekDays(for: weekStart).filter { $0 < today }
            if !days.isEmpty {
                sections.append(HistorySection(start: weekStart,
                                               label: historyLabel(weekStart: weekStart),
                                               dates: days))
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return sections
    }

    private func historyLabel(weekStart: Date) -> String {
        timelineWeekLabel(starting: weekStart)
    }

    /// One calendar vocabulary everywhere in the timeline. A selected week
    /// is not called "This week" after the date strip has moved elsewhere.
    private func timelineWeekLabel(starting weekStart: Date) -> String {
        let calendar = Calendar.current
        let thisWeek = calendar.startOfWeek(for: .now)
        if calendar.isSameDay(weekStart, thisWeek) { return "Earlier this week" }
        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: thisWeek),
           calendar.isSameDay(weekStart, nextWeek) { return "Next week" }
        if let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek),
           calendar.isSameDay(weekStart, lastWeek) { return "Last week" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: weekStart))"
    }

    private func dinner(on date: Date) -> PlannedMeal? {
        meals.first {
            Calendar.current.isSameDay($0.date, date) && $0.slotValue == .dinner
        }
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
        // The same sentence the row draws, so a reader hears why the night
        // is empty rather than "Nothing plated yet" over a dinner that was
        // taken off ten minutes ago.
        //
        // Said even when another slot is planned, because the ROW says it in
        // that case too: gated on `others.isEmpty`, the screen stated the
        // removal and VoiceOver stated the lunch, which is two answers to
        // one question. The other slots follow it rather than replacing it.
        if let removed = RemovedNights.removedLine(on: date) {
            guard !others.isEmpty else { return removed }
            let joined = ListFormatter.localizedString(byJoining: others.map { $0.title.lowercased() })
            return "\(removed). \(joined.prefix(1).uppercased() + joined.dropFirst()) planned"
        }
        guard !others.isEmpty else { return PlanEmptyCopy.rowTitle(past: isPast(date)) }
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

    private func weekSectionLabel(_ week: [Date]) -> String {
        guard let first = week.first else { return "" }
        let start = Calendar.current.startOfWeek(for: first)
        let label = timelineWeekLabel(starting: start)
        return label == "Earlier this week" ? "This week" : label
    }

    private func dayName(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "tonight" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private var hostInitial: String {
        members.me?.firstInitial ?? "?"
    }

    private var cooksLine: String {
        let names = DateFormatter()
        names.dateFormat = "EEE"
        let parts: [String] = members.filter { !$0.isMe && !$0.cookWeekdays.isEmpty }.map { member in
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
                    return "\(member.name) cooks \(full.string(from: date))"
                }
            }
            return "\(member.name) cooks \(days.joined(separator: " & "))"
        }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Nobody has a regular cook night" : parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func openOwnProfile() {
        guard let owner = members.me else { return }
        pushed = .person(PersonRef(name: owner.name, colorHex: owner.colorHex, memberID: owner.persistentModelID))
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
        Persist.save(context)
    }

    /// Drag a plate to another night. Dropping on a planned night swaps the
    /// two dinners rather than eating one.
    private func moveMeal(from token: String?, to target: Date) -> Bool {
        guard MealPlanMove.perform(token, to: target, meals: meals, context: context) else { return false }
        Haptic.plate()
        withAnimation(.plPop) {
            weekAnchor = target
            swipedDay = nil
            bounceDay = target
            dropHoverDay = nil
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            if bounceDay == target { bounceDay = nil }
        }
        return true
    }

    private static func mealAccessibilityIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "week-meal-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

/// Reuse a past recipe on an open future night without replacing a plan.
private struct PlanAgainSheet: View {
    let meal: PlannedMeal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [PlannedMeal]
    @State private var targetDate: Date
    @State private var saveProblem: String?

    init(meal: PlannedMeal) {
        self.meal = meal
        _targetDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 1, to: Date.now.startOfDay) ?? Date.now.startOfDay)
    }

    private var occupied: Bool {
        meals.contains { Calendar.current.isSameDay($0.date, targetDate) && $0.slotValue == meal.slotValue }
            || PlanLedger.shared.plans(on: targetDate, slot: meal.slotValue).contains { !$0.isGoing }
    }

    private var dateRange: ClosedRange<Date> {
        let start = Calendar.current.date(byAdding: .day, value: 1, to: Date.now.startOfDay) ?? Date.now.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 365, to: start) ?? start
        return start...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Plan this dinner again").plType(.title, .semibold).foregroundStyle(Color.ink)
            Text(meal.title).plType(.body, .semibold).foregroundStyle(Color.ink)
            Text("Choose an open date. The original dinner stays in your history.")
                .plType(.footnote).foregroundStyle(Color.inkSecondary)
            DatePicker("Dinner date", selection: $targetDate, in: dateRange, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Color.accentText)
            if occupied {
                Text("There’s already a dinner planned for this date. Choose an open date to keep everyone’s plan intact.")
                    .plType(.footnote).foregroundStyle(Color.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let saveProblem {
                Text(saveProblem).plType(.footnote).foregroundStyle(Color.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryActionButton(title: occupied ? "Choose an open date" : "Add to plan", systemImage: "calendar.badge.plus") {
                guard !occupied else { return }
                let copy = PlannedMeal(
                    date: targetDate,
                    slot: meal.slotValue,
                    recipe: meal.recipe,
                    customTitle: meal.customTitle,
                    servings: meal.servings,
                    cook: meal.cook,
                    tagline: meal.tagline
                )
                context.insert(copy)
                guard Persist.save(context, "plan a past dinner again") else {
                    context.delete(copy)
                    saveProblem = "Couldn't save this night. Your choices are still here. Try again."
                    return
                }
                Haptic.plate()
                dismiss()
            }
            .disabled(occupied)
        }
        .padding(24)
        .plFitsOrScrolls()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .plTapOutsideToDismiss()
    }
}

/// Date-based payloads retained for the night menu and older drag sources.
/// New card drags use MealPlanTransfer's stable meal identity.
enum DayTransfer {
    static func token(for date: Date) -> String {
        "plated-day:\(Int(date.startOfDay.timeIntervalSince1970))"
    }

    static func date(from token: String?) -> Date? {
        guard let token, token.hasPrefix("plated-day:"),
              let seconds = TimeInterval(token.dropFirst("plated-day:".count)), seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

#Preview {
    MainShellView().modelContainer(SampleData.previewContainer)
}
