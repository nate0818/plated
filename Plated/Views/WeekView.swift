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

    @State private var weekAnchor = Calendar.current.startOfDay(for: Date.now)
    @State private var showMonth = false
    @State private var bounceDay: Date?
    /// The day a dragged plate is hovering over — it leans in to receive.
    @State private var dropHoverDay: Date?
    @State private var groceryPresented = false
    @State private var planDay: Date?
    @State private var mealToMove: PlannedMeal?
    @State private var featuredRecipe: Recipe?
    @State private var calendarShown = false
    /// The day whose detail page is pushed. Tapping a day used to raise a
    /// change/remove dialog; those two are swipe actions inside the day now.
    @Environment(\.tabPop) private var tabPop
    @State private var dayShown: Date?
    /// Once per appearance of the view, not once per redraw.
    @State private var landedOnTonight = false
    @State private var swipedDay: Date?
    @State private var personShown: PersonRef?
    @State private var pushed: PlanDestination?
    /// The night you tapped is the night that opens, and your own face is
    /// the door to your own profile. See CookbookView for the reasoning.
    @Namespace private var zoom

    enum PlanDestination: String, Identifiable {
        case activity
        var id: String { rawValue }
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
                VStack(spacing: 0) {
                    header.padding(.horizontal, 24).padding(.top, 6)
                    plannerControls.padding(.horizontal, 24).padding(.vertical, 12)
                    if let arrivingHost {
                        // One quiet line, no spinner: the plan below is
                        // real, there is simply more of it on its way.
                        Text(arrivingHost.isEmpty
                             ? "Still arriving from the host's phone."
                             : "Still arriving from \(arrivingHost)'s phone.")
                            .plType(.caption, .medium)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)
                            .transition(.plUnfold)
                    }
                    if showMonth {
                        MonthPlannerView(anchor: $weekAnchor, askTheTable: askTheTable)
                    } else {
                        portraitPlan
                    }
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .plSwipeBack()
            .navigationDestination(item: $personShown) { person in
                PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
                    .navigationTransition(.zoom(sourceID: ZoomID.host, in: zoom))
            }
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                }
            }
            .navigationDestination(item: $featuredRecipe) { recipe in
                RecipeDetailView(recipe: recipe, meal: dinner(on: weekAnchor))
            }
            .navigationDestination(item: $dayShown) { day in
                DayDetailView(date: day, askTheTable: askTheTable)
                    .navigationTransition(.zoom(sourceID: day, in: zoom))
            }
        }
        .sheet(item: plannerSheet) { destination in
            switch destination {
            case .calendar:
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Choose a date").plType(.title); Spacer(); DesignIconButton(symbol: "xmark", label: "Close calendar") { calendarShown = false } }
                    DatePicker("Dinner date", selection: $weekAnchor, displayedComponents: .date).datePickerStyle(.graphical).tint(Color.accentText)
                    TomatoPillButton(title: "View this date") { calendarShown = false }
                }.padding(24).presentationDetents([.large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
            case .groceries: GrocerySheet()
            case .night(let date): PlanNightSheet(date: date, askTheTable: askTheTable)
            case .move(let meal): MoveMealSheet(meal: meal) { weekAnchor = $0 }
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
            dayShown = nil
            personShown = nil
            pushed = nil
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
        .onDisappear { Presence.shared.planVisible = false }
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
            Presence.shared.planVisible = true
            if let day = LinkRelay.takeDay() { weekAnchor = day }
            if forceMonth || verticalSizeClass == .compact { showMonth = true }
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
            if !showMonth, LaunchFlags.consume("-plated-reveal-plan-actions") {
                swipedDay = weekDates.first(where: { !isPast($0) && dinner(on: $0) != nil })
            }
            #endif
        }
        .onChange(of: verticalSizeClass) { _, size in
            if size == .compact { showMonth = true }
        }
    }

    private enum PlannerSheet: Identifiable {
        case groceries, calendar, night(Date), move(PlannedMeal)
        var id: String { switch self { case .calendar: "calendar"; case .groceries: "groceries"; case .night(let date): "night-\(date.timeIntervalSince1970)"; case .move(let meal): "move-\(meal.persistentModelID)" } }
    }
    private var plannerSheet: Binding<PlannerSheet?> {
        Binding(get: { if calendarShown { return .calendar }; if let mealToMove { return .move(mealToMove) }; if let planDay { return .night(planDay) }; return groceryPresented ? .groceries : nil },
                set: { if $0 == nil { planDay = nil; mealToMove = nil; groceryPresented = false; calendarShown = false } })
    }

    private var portraitPlan: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                PlanDateStrip(
                    selection: $weekAnchor,
                    dropHoverDay: $dropHoverDay,
                    hasDinner: { hasAnyDinner(on: $0) },
                    canAcceptDrop: { !isPast($0) },
                    moveMeal: { moveMeal(from: $0, to: $1) },
                    selectionChanged: { swipedDay = nil },
                    shiftWeek: { shiftWeek($0) }
                )
                featuredDinner
                HStack {
                    Text("This week").plType(.title, .semibold)
                    Spacer()
                    Text("\(plannedCount) planned").plType(.footnote).foregroundStyle(Color.inkSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(weekDates, id: \.self) { date in dayRow(date) }
                }
                cooksFooter
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { withAnimation(.plSnap) { swipedDay = nil } }
        }
    }

    private var featuredDinner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MicroLabel((Calendar.current.isDateInToday(weekAnchor) ? "Tonight" : weekAnchor.formatted(.dateTime.weekday(.wide))) + " · " + weekAnchor.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                Menu { nightMenu(weekAnchor) } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Color.ink).plTapTarget()
                }.accessibilityLabel("Dinner options")
            }
            if let meal = dinner(on: weekAnchor) {
                Button { Haptic.tap(); dayShown = weekAnchor } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 1.95)
                        Text(meal.title).plType(.display, .semibold).foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.pressable)
                    .modifier(PlannerMealDrag(meal: meal))
                    .accessibilityIdentifier("featured-dinner-card")
                    .accessibilityHint("Tap to open the day. Hold and drag to another date to move dinner.")
                HStack(spacing: 8) {
                    if let cook = meal.cook { AvatarCircle(member: cook, size: 26) }
                    Text(meal.cook.map { $0.isMe ? "You're cooking" : "\($0.firstName) is cooking" } ?? "Cook unassigned")
                        .plType(.footnote).foregroundStyle(Color.inkSecondary)
                    Spacer()
                    Button { planDay = weekAnchor } label: {
                        Label("Serves \(meal.servings)", systemImage: "person.2")
                            .plType(.footnote)
                            .plActionLabel()
                            .foregroundStyle(Color.ink).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(Color.fill, in: Capsule())
                    }.buttonStyle(.pressable).accessibilityLabel("Change servings and cook")
                }
                if meal.recipe != nil {
                    TomatoPillButton(title: meal.isCooked ? "View recipe" : "Let's cook", systemImage: "fork.knife") {
                        featuredRecipe = meal.recipe
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
                        Text(isPast(weekAnchor) ? "A night off the menu" : "Something good starts here.")
                            .plType(.display, .medium).foregroundStyle(Color.ink)
                        Text(isPast(weekAnchor) ? "No dinner was planned for this date." : "Choose a favorite, try a new recipe, or take the night off.")
                            .plType(.body).foregroundStyle(Color.inkSecondary)
                    }
                    if !isPast(weekAnchor) {
                        TomatoPillButton(title: "Plan this night", systemImage: "plus") { planDay = weekAnchor }
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.fill, in: Radius.shape(Radius.hero))
            }
        }
    }

    /// The hero's third state: nobody planned tonight on this phone, but
    /// somebody else did. Same card as the local hero, photo from the
    /// ledger, and the cook line the ledger writes. Let's cook only when a
    /// recipe in this cookbook carries the same non-empty `originID`; there
    /// is no title fallback, because this phone's own "Tacos" is not the
    /// night Nate planned. Where the button would be, the caption says whose
    /// night it is and, when there is a recipe somewhere, that it is not
    /// here. The header's ellipsis keeps its empty-night items, which are
    /// honest on a night this phone has not planned.
    @ViewBuilder
    private func remoteFeatured(_ entry: PlanLedger.Entry) -> some View {
        let ledger = PlanLedger.shared
        let cookLine = ledger.cookLine(for: entry)
        Button { Haptic.tap(); dayShown = weekAnchor } label: {
            VStack(alignment: .leading, spacing: 16) {
                RecipeArtwork(data: ledger.photo(for: entry.recordName), title: entry.title, ratio: 1.95)
                Text(entry.title).plType(.display, .semibold).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }.buttonStyle(.pressable)
            .accessibilityIdentifier("featured-remote-dinner-card")
            .accessibilityHint("Opens the day")
        // No line when the ledger has none. "Cook unassigned" is true of a
        // local night; here it would be a claim about what Nate did, and
        // Nate may well have put an invited Riley down, whose name the
        // writer blanks on purpose. `RemotePlanRow` omits it the same way.
        if let cookLine {
            HStack(spacing: 8) {
                RemoteCookFace(entry: entry, members: members, size: 26)
                Text(cookLine)
                    .plType(.footnote).foregroundStyle(Color.inkSecondary)
                Spacer()
            }
        }
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
        // No Let's cook on a night that is going. The pill is an invitation
        // to start a cook session on a dinner this phone has just taken off
        // the plan for everybody.
        if let recipe = cookbookRecipe(for: entry), !entry.isGoing {
            TomatoPillButton(title: entry.cooked ? "View recipe" : "Let's cook", systemImage: "fork.knife") {
                featuredRecipe = recipe
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
        return recipes.first { $0.originID == entry.recipeOriginKey }
    }

    private var plannerControls: some View {
        HStack(spacing: 12) {
            Picker("Calendar view", selection: $showMonth) {
                Text("Week").tag(false)
                Text("Month").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 148)
            Spacer(minLength: 0)
            Button { calendarShown = true } label: {
                Text(weekAnchor.formatted(.dateTime.month(.abbreviated).day())).plType(.footnote, .semibold)
            }.plTapTarget().accessibilityLabel("Choose a date")
            Button("Today") {
                Haptic.select()
                withAnimation(.plSnap) { weekAnchor = .now.startOfDay }
            }
            .plType(.footnote, .bold)
            .plActionLabel()
            .foregroundStyle(Color.ink)
            .plTapTarget()
            // No week arrows. Nate asked for them to go: the strip itself
            // is the control, it swipes, and its edges say so. The words
            // "Previous week" and "Next week" live on as accessibility
            // actions on every day of the strip, so the gesture is never
            // the only door.
        }
        .foregroundStyle(Color.ink)
        .plChrome()
    }

    private func shiftWeek(_ delta: Int) {
        Haptic.select()
        withAnimation(.plSnap) {
            weekAnchor = Calendar.current.date(byAdding: .day, value: delta * 7, to: weekAnchor) ?? weekAnchor
            swipedDay = nil
        }
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
        if isPast(date) {
            if local != nil || remote.isEmpty { pastRow(date) }
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
                RemotePlanRow(entry: entry, date: date, members: members) { dayShown = date }
                    .matchedTransitionSource(id: date, in: zoom)
            } else {
                RemotePlanRow(entry: entry, date: date, members: members) { dayShown = date }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        PlatedMasthead(title: showMonth ? "Your month" : "Your week") {
            HStack(spacing: 8) {
                ActivityBellButton(size: 36) { pushed = .activity }
                AccountButton()
            }
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
                .fill(Color.clear)
                .frame(width: 36, height: 36)
                .plFloatingGlass()
                .overlay { content() }
                // 44 in BOTH axes. It was 40 wide, and this is the only
                // route to the shopping list.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    // MARK: Rows

    private func plannedRow(_ meal: PlannedMeal, date: Date) -> some View {
        let today = Calendar.current.isDateInToday(date)
        let eatingOut = meal.recipe == nil && meal.customTitle.localizedCaseInsensitiveContains("eating out")
        return SwipeRow(isOpen: swipeBinding(date), actions: planActions(for: meal), actionLabel: "Actions for \(meal.title)") {
            HStack(spacing: 10) {
                dateColumn(date)

                RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 1, radius: Radius.small).frame(width: 60)
                    // The cook belongs to the dish, not to the far edge of
                    // the row. Moving them here also hands the title back the
                    // 38pt that an edge avatar was costing it, which is the
                    // difference between "Creamy Tuscan Chicken" and
                    // "Creamy Tuscan Chick…".
                    .overlay(alignment: .bottomTrailing) {
                        // Not the owner: the tagline already refuses to say
                        // "Nate cooks" to Nate, and your own face on your own
                        // dish every night is decoration, not information.
                        if let cook = meal.cook, !cook.isMe, !eatingOut {
                            AvatarCircle(member: cook, size: 22)
                                // A face on a photograph needs its own edge
                                // or it reads as part of the dish.
                                .overlay { Circle().strokeBorder(Color.cardFill, lineWidth: 2) }
                                .offset(x: 3, y: 3)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.title)
                        .plType(.callout, .semibold)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                    Text(tagLine(for: meal, today: today, date: date))
                        .plType(.caption, .semibold)
                        .foregroundStyle(today ? Color.ink : Color.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 12)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            // 72 was tight enough that "Creamy Tuscan Chicken" and
            // "Alessandra Fitzgerald cooks" both ended in an ellipsis on the
            // one screen the app is mostly looked at. The height and the
            // reclaimed 18pt of width are what let the row say the thing.
            .frame(minHeight: 76)
            .background(dropHoverDay == date ? Color.tomatoTint : Color.canvas, in: Radius.shape(Radius.row))
            .overlay {
                if dropHoverDay == date {
                    Radius.shape(Radius.row).strokeBorder(Color.tomato, lineWidth: 1.5)
                } else {
                    VStack { Spacer(); Rectangle().fill(Color.hairline).frame(height: 0.5) }
                }
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

    /// The plus plans dinner directly; the rest of the row opens every meal
    /// on that day. VoiceOver offers both actions on the combined row.
    private func emptyRow(date: Date) -> some View {
        SwipeRow(isOpen: swipeBinding(date), actions: [
            SwipeAction(symbol: "plus", label: "Plan") { planDay = date },
            SwipeAction(symbol: "fork.knife", label: "Eat out") { markEatingOut(on: date) }
        ], actionLabel: "Actions for \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))") {
        HStack(spacing: 10) {
            dateColumn(date)
            Button {
                Haptic.tap()
                planDay = date
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            // The row speaks for both targets below; a second announcement
            // here would just be the same night read twice.
            .accessibilityHidden(true)
            // An empty night that knows why it is empty. The household took
            // this dinner off, the meal was deleted here, and nothing else on
            // this phone remembers it existed: the digest cannot speak,
            // because it needs an already-read bell row and the author never
            // has one for a night they planned themselves. So this line and
            // the hero are the only way the person learns their dinner went.
            // The plus beside it still plans the night, which is what they
            // are most likely to want next.
            Text(RemovedNights.removedLine(on: date) ?? "Plan dinner")
                .plType(.body)
                .foregroundStyle(Color.inkSecondary)
                // No limit, the way the past row's own "Nothing plated"
                // already has none. This is the app's copy, not a dish
                // somebody named, and at AX5 one line turned "Nothing plated
                // yet" into "Nothing...", which is the whole sentence gone.
                // The row's 76pt is a floor, so it grows to hold it.
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 76)
        .background(Color.canvas)
        .overlay {
            // A hovering plate turns the dashed invitation solid. Same
            // corner and weight as a planned row — see plannedRow.
            if dropHoverDay == date {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(Color.tomatoTint)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .strokeBorder(Color.tomato, lineWidth: 1.5)
                    }
            } else {
                VStack { Spacer(); Rectangle().fill(Color.hairline).frame(height: 0.5) }
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
        .accessibilityHint("Opens the day")
        .accessibilityAction(named: "Plan dinner") { planDay = date }
        .accessibilityAction(named: "Eating out") { markEatingOut(on: date) }
        .contextMenu { nightMenu(date) }
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
    /// shape, but they collapse to a history strip. Tapping still opens the
    /// day for reference; planning and dragging are unavailable. The compression is
    /// what keeps tonight on screen come Saturday, when six of these sit
    /// above it.
    private func pastRow(_ date: Date) -> some View {
        let meal = dinner(on: date)
        return SwipeRow(isOpen: swipeBinding(date), actions: meal.map { planActions(for: $0) } ?? [], actionLabel: meal.map { "Actions for \($0.title)" }) {
        HStack(spacing: 12) {
            dateColumn(date)

            if let meal {
                RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 1, radius: Radius.small).frame(width: 60)
                Text(meal.title)
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            } else {
                // Past tense on purpose: "yet" promises a night you can
                // still cook.
                Image(systemName: "minus").font(.footnote).foregroundStyle(Color.inkSecondary).frame(width: 48, height: 48)
                Text("No dinner planned")
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
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
                Label("Eating out", systemImage: "fork.knife")
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
            Label(planned == nil ? "Plan this night" : "Change the dish",
                  systemImage: planned == nil ? "plus.circle" : "arrow.2.squarepath")
        }
        if planned != nil {
            if let meal = planned {
                Menu {
                    Button("Unassigned") { meal.cook = nil; Persist.save(context) }
                    ForEach(members.assignableCooks) { member in
                        Button(member.isMe ? "You" : member.name) { meal.cook = member; Persist.save(context) }
                    }
                } label: { Label("Who's cooking", systemImage: "person.crop.circle") }
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
                Label("Clear the night", systemImage: "trash")
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

    /// A night off the stove still counts as a plan for the week.
    private func markEatingOut(on date: Date) {
        Haptic.plate()
        withAnimation(.plPop) {
            if let meal = dinner(on: date) {
                meal.recipe = nil
                meal.customTitle = "Eating out"
                meal.tagline = "Night off the stove"
                meal.cook = nil
            } else {
                let meal = PlannedMeal(date: date, slot: .dinner, customTitle: "Eating out")
                meal.tagline = "Night off the stove"
                context.insert(meal)
            }
            bounceDay = date
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
    }

    /// Dates are a column, not miniature cards. Only today's numeral wears
    /// the brand color; the weekday stays on the same baseline all week.
    /// `PlanDateColumn` is the drawing, shared with `RemotePlanRow` so a
    /// remote night's column can never be a point off a local one's.
    private func dateColumn(_ date: Date) -> some View {
        PlanDateColumn(date: date)
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

    /// What is left of this week. `weekDates` itself is untouched, because
    /// the ring, the counts and the week label all measure the whole week
    /// including tonight; it is only the list that reorders around the card.
    private func aheadThisWeek(skippingToday: Bool) -> [Date] {
        weekDates.filter { date in
            if isPast(date) { return false }
            if skippingToday, Calendar.current.isDateInToday(date) { return false }
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
    /// Starts at the first dinner the household ever planned, so a new
    /// install has no history rather than an empty scrollback, and stops at
    /// twelve weeks because the rows are drawn eagerly and a year of them is
    /// three hundred and sixty-four views built to show four.
    private var cookedHistory: [HistorySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let past = meals.filter { $0.slotValue == .dinner && $0.date < today }
        guard let earliest = past.map(\.date).min() else { return [] }

        let thisWeek = calendar.startOfWeek(for: today)
        let floor = calendar.date(byAdding: .day, value: -7 * 12, to: thisWeek) ?? thisWeek
        var weekStart = max(calendar.startOfWeek(for: earliest), floor)

        var sections: [HistorySection] = []
        while weekStart <= thisWeek {
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
        let calendar = Calendar.current
        let thisWeek = calendar.startOfWeek(for: .now)
        if calendar.isSameDay(weekStart, thisWeek) { return "Earlier this week" }
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

    private func tagLine(for meal: PlannedMeal, today: Bool, date: Date) -> String {
        // A night the household took off that is still standing here, which
        // is the two hold-backs: it was cooked, or it is being cooked now.
        // This takes the whole caption rather than being appended to it,
        // because "Tonight · you cook" beside a dinner the rest of the
        // household has already dropped is the row answering a question
        // nobody is asking. The cook and the timing are still on the day
        // page; what is not anywhere else is that the household let it go.
        // The row's short form. The sentence version belongs on a page with
        // room; this line clips at one.
        if let held = RemovedNights.heldRowLine(shoppingID: meal.shoppingID ?? "") {
            return held
        }
        // The household changed this night and nobody has answered yet.
        // Takes the caption for the same reason the hold-back does: the cook
        // and the timing on this row are this phone's answer to a question
        // the rest of the house has already moved on from, and being put
        // down to cook is the one fact here with a consequence attached.
        // The decision itself lives on the page this row opens.
        if let id = meal.shoppingID, let change = HouseholdEdits.pending(shoppingID: id) {
            return HouseholdEdits.rowLine(
                for: change, me: TableIdentity.cached,
                currentCookID: PlanNightSheet.cookID(of: meal)
            )
        }
        let base: String
        if today {
            // Tonight names its cook like every other night does. This
            // branch returned before it could reach the cook clause four
            // lines below, so the one night the answer matters most was the
            // only night the app would not give it — while the Home Screen
            // widget beside it drew the cook's face the whole time.
            var parts: [String] = ["Tonight"]
            if let cook = meal.cook {
                parts.append(cook.isMe ? "you cook" : "\(cook.name) cooks")
            }
            let minutes = meal.recipe?.totalMinutes ?? 0
            if minutes > 0 { parts.append(Recipe.durationText(minutes)) }
            base = parts.joined(separator: " · ")
        } else if !meal.tagline.isEmpty {
            base = meal.tagline
        } else if let cook = meal.cook, !cook.isMe {
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

/// A day picker, not a disguised pair of week buttons. The old strip stayed
/// perfectly still under the finger and replaced all seven dates only after a
/// swipe ended. That made a direct manipulation feel like clicking a carousel.
///
/// This strip uses the system scroll physics, keeps the selected day centered,
/// and adopts the date crossing that center line while the finger is moving.
/// Each crossed day gets the quiet selection tick used by native pickers.
private struct PlanDateStrip: View {
    @Binding var selection: Date
    @Binding var dropHoverDay: Date?

    let hasDinner: (Date) -> Bool
    let canAcceptDrop: (Date) -> Bool
    let moveMeal: (String?, Date) -> Bool
    let selectionChanged: () -> Void
    /// The seven-day jump the header arrows used to make. WeekView owns it
    /// so the strip never grows a second copy of the week arithmetic.
    let shiftWeek: (Int) -> Void

    @State private var dates: [Date]
    @State private var scrollPosition: Date?
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var centeredIndex: Int?
    @State private var userIsScrubbing = false
    /// Set by a week action and consumed by the scroll that follows it, so
    /// VoiceOver's focus lands on the new day rather than staying on a cell
    /// that just scrolled off the screen.
    @State private var focusFollowsSelection = false
    @AccessibilityFocusState private var focusedDay: Date?
    @Environment(\.colorSchemeContrast) private var contrast

    private let cellWidth: CGFloat = 46
    private let cellSpacing: CGFloat = 2

    /// The sheet grabber turned on its side and stood at each end of the
    /// strip. iOS has taught everyone that a short grey capsule means "this
    /// surface moves in the direction I am thin"; on a sheet that is down,
    /// here it is sideways. It is a stroke, not a glyph, so inkFaint is the
    /// paint DESIGN.md allows it. It never moves: a grabber does not animate
    /// on a sheet either, and the claim it makes, that there is more strip
    /// in that direction, is kept true by the runway rebuild below, so there
    /// is no state for it to perform.
    private static let edgeMarkSize = CGSize(width: 3, height: 20)
    private static let edgeMarkInset: CGFloat = 3

    /// The scroll content dissolves under each mark rather than being cut
    /// off beside it. A grabber sits on the sheet, not on the sheet's words;
    /// on a 430pt phone the strip's hard edge otherwise lands on half a "Su".
    private static let edgeFade: CGFloat = 12

    /// Rebuild the runway before a thumb can reach its end. A year each way
    /// is generous, but the marks promise more strip in both directions and
    /// a hard stop under one of them would make that a lie.
    private static let runwayMargin = 7

    init(
        selection: Binding<Date>,
        dropHoverDay: Binding<Date?>,
        hasDinner: @escaping (Date) -> Bool,
        canAcceptDrop: @escaping (Date) -> Bool,
        moveMeal: @escaping (String?, Date) -> Bool,
        selectionChanged: @escaping () -> Void,
        shiftWeek: @escaping (Int) -> Void
    ) {
        self._selection = selection
        self._dropHoverDay = dropHoverDay
        self.hasDinner = hasDinner
        self.canAcceptDrop = canAcceptDrop
        self.moveMeal = moveMeal
        self.selectionChanged = selectionChanged
        self.shiftWeek = shiftWeek

        let day = Calendar.current.startOfDay(for: selection.wrappedValue)
        let initialDates = Self.makeDates(around: day)
        self._dates = State(initialValue: initialDates)
        // Start nil and assign after the scroll view exists. Supplying an ID
        // before the lazy stack's first layout leaves that ID as the first
        // materialized cell, with an empty half-strip to its left.
        self._scrollPosition = State(initialValue: nil)
        self._centeredIndex = State(initialValue: initialDates.firstIndex(of: day))
    }

    var body: some View {
        GeometryReader { proxy in
            let centerInset = max(0, (proxy.size.width - cellWidth) / 2)
            // Increase Contrast softens nothing a person reads: the marks
            // stay, the dissolve goes.
            let fadeWidth = contrast == .increased ? 0 : Self.edgeFade

            ScrollView(.horizontal) {
                // Materialize only the visible runway. Building 731 buttons
                // eagerly bloats the accessibility tree and can exhaust a
                // phone during a drag. The scroll position starts nil and is
                // assigned after layout, avoiding the old half-empty initial
                // frame while retaining native continuous physics.
                LazyHStack(spacing: cellSpacing) {
                    ForEach(dates, id: \.self) { date in
                        dayButton(date)
                            .frame(width: cellWidth)
                            .id(date)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, centerInset, for: .scrollContent)
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByFew))
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
                if phase == .tracking {
                    userIsScrubbing = true
                    Haptic.prepare()
                }

                // A very short drag can move through the final threshold as
                // the view snaps. Commit the resting date even when there was
                // no deceleration callback between the two geometry samples.
                if phase == .idle,
                   userIsScrubbing,
                   let centeredIndex,
                   dates.indices.contains(centeredIndex) {
                    adopt(dates[centeredIndex], haptic: false)
                    userIsScrubbing = false

                    // Keep the edge marks honest: a thumb nearing either end
                    // of the runway gets a fresh year on both sides of where
                    // it stopped. Only after a real scrub: the first idle
                    // callback arrives while the geometry still reads index
                    // zero, and rebuilding there put the selected day at the
                    // far end of a runway that began a year earlier.
                    if centeredIndex < Self.runwayMargin || centeredIndex > dates.count - 1 - Self.runwayMargin {
                        let day = dates[centeredIndex]
                        dates = Self.makeDates(around: day)
                        self.centeredIndex = dates.firstIndex(of: day)
                        scrollPosition = day
                    }
                }
            }
            .onScrollGeometryChange(for: Int?.self) { geometry in
                let stride = cellWidth + cellSpacing
                guard stride > 0, !dates.isEmpty else { return nil }
                let offset = geometry.contentOffset.x + geometry.contentInsets.leading
                let index = Int((offset / stride).rounded())
                return min(max(index, dates.startIndex), dates.index(before: dates.endIndex))
            } action: { oldIndex, newIndex in
                centeredIndex = newIndex
                guard newIndex != oldIndex,
                      scrollPhase == .interacting || scrollPhase == .decelerating,
                      let newIndex,
                      dates.indices.contains(newIndex)
                else { return }
                adopt(dates[newIndex], haptic: true)
            }
            .onChange(of: selection) { _, value in
                let day = Calendar.current.startOfDay(for: value)
                guard scrollPhase == .idle else { return }

                if !dates.contains(day) {
                    dates = Self.makeDates(around: day)
                    centeredIndex = dates.firstIndex(of: day)
                }
                let follow = focusFollowsSelection
                focusFollowsSelection = false
                guard scrollPosition != day else {
                    if follow { focusedDay = day }
                    return
                }
                withAnimation(.plSnap) {
                    scrollPosition = day
                } completion: {
                    if follow { focusedDay = day }
                }
            }
            .onAppear {
                scrollPosition = Calendar.current.startOfDay(for: selection)
            }
            // Painted over the strip rather than masked into it: a mask on
            // the ScrollView left the lazy stack's first layout half empty,
            // every cell right of the selected day missing until a scroll.
            // The strip stands on canvas, so a canvas gradient at each edge
            // is the same dissolve without touching the scroll view at all.
            .overlay(alignment: .leading) { edgeFade(fadeWidth) }
            .overlay(alignment: .trailing) { edgeFade(fadeWidth).scaleEffect(x: -1) }
            .overlay(alignment: .leading) { edgeMark }
            .overlay(alignment: .trailing) { edgeMark }
        }
        .frame(height: 76)
        .plChrome()
        .accessibilityHint("Swipe left or right to choose a date")
    }

    /// The dissolve under each mark. Drawn for the leading edge and
    /// mirrored for the trailing one, so the two can never drift apart.
    private func edgeFade(_ width: CGFloat) -> some View {
        LinearGradient(colors: [Color.canvas, Color.canvas.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// One view drawn twice here, and a third time on the month grid, so it
    /// lives in Theme.swift rather than in either screen.
    private var edgeMark: some View {
        PlanEdgeMark().padding(.horizontal, Self.edgeMarkInset)
    }

    /// The jump the header arrows used to make, for readers who cannot
    /// swipe the strip: VoiceOver's actions rotor, Voice Control's "Show
    /// actions for Monday, September 7", Switch Control's actions menu.
    /// The marks are silent and "Monday, September 14" alone does not tell
    /// a listener that a week moved, so the week is spoken as well.
    private func weekAction(_ delta: Int) {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: delta * 7, to: selection) ?? selection
        focusFollowsSelection = true
        shiftWeek(delta)

        let spoken: String
        if calendar.isDate(target, equalTo: .now, toGranularity: .weekOfYear) {
            spoken = "This week"
        } else {
            let start = calendar.startOfWeek(for: target)
            let sameYear = calendar.isDate(start, equalTo: .now, toGranularity: .year)
            spoken = "Week of " + start.formatted(sameYear ? .dateTime.month(.wide).day() : .dateTime.month(.wide).day().year())
        }
        AccessibilityNotification.Announcement(spoken).post()
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selection)
        let hovering = dropHoverDay.map { Calendar.current.isDate($0, inSameDayAs: date) } == true

        return Button {
            Haptic.select()
            selectionChanged()
            withAnimation(.plSnap) {
                selection = date
                scrollPosition = date
            }
        } label: {
            VStack(spacing: 5) {
                Text(date.formattedWeekday())
                    .plType(.caption, .medium)
                Text(date.formattedDayNumber())
                    .plType(.heading, .semibold)
                    .monospacedDigit()
                Circle()
                    .fill(hasDinner(date) ? (selected ? Color.onTomato : Color.inkSecondary) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(selected ? Color.onTomato : Color.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                selected ? Color.tomato : hovering ? Color.tomatoTint : Color.clear,
                in: Radius.shape(Radius.chip)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
        // The strip spans two years. A day-of-month identifier produced up
        // to 24 indistinguishable controls for Voice Control and UI tests.
        // Keep the spoken label human and make the programmatic identity a
        // complete calendar date.
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: date))
        .accessibilityFocused($focusedDay, equals: date)
        // On the button itself, not the container: a ScrollView is not an
        // element VoiceOver lands on, so actions hung there may never be
        // offered, and this pair has to be certain.
        .accessibilityAction(named: "Previous week") { weekAction(-1) }
        .accessibilityAction(named: "Next week") { weekAction(1) }
        .dropDestination(for: String.self) { tokens, _ in
            moveMeal(tokens.first, date)
        } isTargeted: { over in
            if over, canAcceptDrop(date) {
                dropHoverDay = date
            } else if dropHoverDay.map({ Calendar.current.isDate($0, inSameDayAs: date) }) == true {
                dropHoverDay = nil
            }
        }
    }

    private func adopt(_ date: Date, haptic: Bool) {
        let day = Calendar.current.startOfDay(for: date)
        guard !Calendar.current.isDate(day, inSameDayAs: selection) else { return }
        if haptic { Haptic.select() }
        selectionChanged()

        // Rebuilding the featured card at every crossed day must not queue a
        // train of animations behind the finger. The strip itself supplies
        // all the movement; the content simply stays truthful to its center.
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { selection = day }
    }

    private static func makeDates(around center: Date) -> [Date] {
        let calendar = Calendar.current
        let center = calendar.startOfDay(for: center)
        // A full year in either direction is a generous continuous runway;
        // the date picker, a week action and a thumb nearing either end all
        // rebuild it around wherever they land.
        return (-365...365).compactMap {
            calendar.date(byAdding: .day, value: $0, to: center)
        }
    }

    private static func accessibilityIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "week-date-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
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
