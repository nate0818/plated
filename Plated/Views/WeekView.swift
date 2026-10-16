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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.activeAppTab) private var activeAppTab
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false

    @State private var weekAnchor = Calendar.current.startOfDay(for: Date.now)
    @State private var showMonth = false
    @State private var dateNavigationRevision = 0
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
    /// Once per appearance of the view, not once per redraw. History lives
    /// above the selected night, so the first frame has to land where the
    /// plan starts rather than on the oldest week SwiftUI materialized.
    @State private var landedOnTimeline = false
    @State private var lastLandedType: DynamicTypeSize?
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
                VStack(spacing: 0) {
                    header.padding(.horizontal, 24).padding(.top, 6)
                    Text(typeSize.isAccessibilitySize ? weekAnchor.formatted(.dateTime.month(.abbreviated).day()) : weekAnchor.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .plType(.caption).foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    plannerControls.padding(.horizontal, 24).padding(.bottom, 12)
                    if !showMonth {
                        PlanDateStrip(
                            selection: $weekAnchor,
                            dropHoverDay: $dropHoverDay,
                            hasDinner: { hasAnyDinner(on: $0) },
                            canAcceptDrop: { !isPast($0) },
                            moveMeal: { moveMeal(from: $0, to: $1) },
                            selectionChanged: { swipedDay = nil },
                            navigationRevision: dateNavigationRevision,
                            shiftWeek: { shiftWeek($0) }
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    }
                    if let arrivingHost {
                        // One quiet line, no spinner: the plan below is
                        // real, there is simply more of it on its way.
                        Text(arrivingHost.isEmpty
                                ? "Still arriving from the organizer's phone."
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
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                case .household: HouseholdHomeView(embedded: true)
                case .person(let person):
                    PersonProfileView(personName: person.name, colorHex: person.colorHex, memberID: person.memberID)
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
        .onChange(of: showMonth) { _, monthIsShowing in
            // The week scroll is rebuilt after Month. Re-arm its landing or
            // the fresh ScrollView opens at the oldest history above the
            // current-plan anchor.
            if monthIsShowing { landedOnTimeline = false }
        }
        .onAppear {
            if let day = LinkRelay.takeDay() { weekAnchor = day }
            if LinkRelay.takeActivity() { pushed = .activity }
            if LinkRelay.takeHousehold() { pushed = .household }
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
        .onChange(of: verticalSizeClass) { _, size in
            if size == .compact { showMonth = true }
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
            ScrollView(showsIndicators: false) {
                Group {
                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 28) {
                            VStack(alignment: .leading, spacing: 18) {
                                featuredDinner.id(Self.timelineAnchor)
                                historySections
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 18) {
                                weekHeader(weekDates, count: plannedCount)
                                VStack(spacing: 0) {
                                    ForEach(aheadThisWeek(skipping: weekAnchor), id: \.self) { date in dayRow(date) }
                                }
                                futureWeekSections
                                cooksFooter
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: 1120)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            historySections
                            featuredDinner.id(Self.timelineAnchor)
                            weekHeader(weekDates, count: plannedCount)
                            VStack(spacing: 0) {
                                ForEach(aheadThisWeek(skipping: weekAnchor), id: \.self) { date in dayRow(date) }
                            }
                            futureWeekSections
                            cooksFooter
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, Layout.floatingChromeInset)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { withAnimation(.plSnap) { swipedDay = nil } }
            }
            .task(id: typeSize) {
                guard !landedOnTimeline || lastLandedType != typeSize else { return }
                // Text reflow changes historical row heights above the selected dinner.
                await Task.yield()
                guard !Task.isCancelled else { return }
                scroll.scrollTo(Self.timelineAnchor, anchor: .top)
                landedOnTimeline = true
                lastLandedType = typeSize
            }
        }
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

    /// The scroll's resting place. The pinned date strip is outside this
    /// scroll view, so prior weeks remain above the selected night's content.
    private static let timelineAnchor = "plan-current"

    private func weekHeader(_ week: [Date], count: Int) -> some View {
        HStack {
            Text(weekSectionLabel(week)).plType(.title, .semibold)
            Spacer()
            Text("\(count) planned").plType(.footnote).foregroundStyle(Color.inkSecondary)
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
                Button { Haptic.tap(); pushed = .day(weekAnchor) } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 1.55)
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
                            .background(Color.fill, in: Radius.shape(Radius.chip))
                    }.buttonStyle(.pressable).accessibilityLabel("Change servings and cook")
                }
                if meal.recipe != nil {
                    PrimaryActionButton(title: meal.isCooked ? "View recipe" : "Start cooking", systemImage: "fork.knife") {
                        if let recipe = meal.recipe { pushed = .recipe(recipe) }
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
                        Text(emptyHeroTitle(for: weekAnchor))
                            .plType(.title, .semibold).foregroundStyle(Color.ink)
                        Text(isPast(weekAnchor)
                             ? "Add what you ate, cooked, or picked up."
                             : "Choose a favorite, try a new recipe, or take the night off.")
                            .plType(.body).foregroundStyle(Color.inkSecondary)
                    }
                    PrimaryActionButton(title: "Plan the night", systemImage: "plus") { planDay = weekAnchor }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
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
        Button { Haptic.tap(); pushed = .day(weekAnchor) } label: {
            VStack(alignment: .leading, spacing: 16) {
                RecipeArtwork(data: ledger.photo(for: entry.recordName), title: entry.title, ratio: 1.55)
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
            PrimaryActionButton(title: entry.cooked ? "View recipe" : "Start cooking", systemImage: "fork.knife") {
                pushed = .recipe(recipe)
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
            EditorialSegments(options: [false, true], selection: $showMonth, label: { $0 ? "Month" : "Week" })
            .accessibilityLabel("Calendar view")
            .frame(maxWidth: 148)
            Spacer(minLength: 0)
            Button { calendarShown = true } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Choose a date")
            .accessibilityValue(weekAnchor.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
            Button("Today") {
                Haptic.select()
                dateNavigationRevision &+= 1
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
                RemotePlanRow(entry: entry, date: date, members: members) { pushed = .day(date) }
                    .matchedTransitionSource(id: date, in: zoom)
            } else {
                RemotePlanRow(entry: entry, date: date, members: members) { pushed = .day(date) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        PlatedMasthead(title: showMonth ? "The month ahead" : Calendar.current.isDateInToday(weekAnchor) ? "At home, tonight." : "The dinner plan", wordmarkSize: 20) {
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
                        .lineLimit(2)
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

    /// The whole empty row plans dinner. Swipe, the context menu and
    /// accessibility actions keep the alternatives without drawing a plus,
    /// a sentence and an ellipsis that all mean the same thing.
    private func emptyRow(date: Date) -> some View {
        SwipeRow(isOpen: swipeBinding(date), actions: [
            SwipeAction(symbol: "plus", label: "Plan the night") { planDay = date },
            SwipeAction(symbol: "fork.knife", label: "Eat out") { markEatingOut(on: date) }
        ]) {
        HStack(spacing: 10) {
            dateColumn(date)
            VStack(alignment: .leading, spacing: 3) {
                // A removed night names what happened; an ordinary open night
                // says what is missing rather than repeating its button.
                Text(RemovedNights.removedLine(on: date) ?? emptyMealLine(for: date))
                    .plType(.body, .semibold)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(assignmentLine(for: date))
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
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
        .accessibilityLabel("\(dayName(date).capitalized), \(openLine(date)). \(assignmentLine(for: date))")
        .accessibilityHint("Plans dinner")
        .accessibilityAction(named: "Open day") { pushed = .day(date) }
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
        HStack(spacing: 12) {
            dateColumn(date)

            if let meal {
                RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 1, radius: Radius.small).frame(width: 60)
                Text(meal.title)
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
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
            Label(planned == nil ? "Plan the night" : "Change the dish",
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
        Persist.save(context, "plan eating out")
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
        let servings = meal.recipe == nil ? nil : "Serves \(max(1, meal.servings))"
        let details = [base, servings].compactMap { $0 }.filter { !$0.isEmpty }
        let detailLine = details.joined(separator: " · ")
        // The week row shows dinner; a day can now hold breakfast, lunch,
        // dessert and a snack too, and hiding them here would make the day
        // page a surprise.
        let others = otherSlots(on: date).count
        let withOthers = others > 0 ? "\(detailLine) · +\(others) more" : detailLine
        return withOthers
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
        guard !others.isEmpty else { return "No meal planned yet" }
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
                Persist.save(context, "plan a past dinner again")
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
