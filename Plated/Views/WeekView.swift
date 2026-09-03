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
                    .navigationTransition(.zoom(sourceID: ZoomID.host, in: zoom))
            }
            .navigationDestination(item: $pushed) { destination in
                switch destination {
                case .activity: NotificationsView()
                }
            }
            .navigationDestination(item: $dayShown) { day in
                DayDetailView(date: day, askTheTable: askTheTable)
                    .navigationTransition(.zoom(sourceID: day, in: zoom))
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

            ScrollViewReader { scroll in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    // Everything already cooked, oldest first, so the plan is
                    // one timeline you are standing in the middle of: scroll
                    // up for what you ate, down for what is coming. The view
                    // opens anchored on tonight, so none of it is in the way
                    // until somebody reaches for it.
                    ForEach(cookedHistory) { section in
                        HStack {
                            MicroLabel(section.label)
                            Spacer()
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 2)
                        ForEach(section.dates, id: \.self) { date in
                            dayRow(date)
                        }
                    }

                    let tonight = TonightAnswer.state(meals: meals,
                                                       hasRecipes: !recipes.isEmpty)
                    if let tonight {
                        TonightCard(
                            state: tonight,
                            zoom: zoom,
                            onOpenDish: { meal in dayShown = meal.date },
                            onPlanTonight: { planDay = Calendar.current.startOfDay(for: .now) },
                            dayLoad: showCalendarEvents
                                ? events.load(on: Calendar.current.startOfDay(for: .now))
                                : nil
                        )
                        .padding(.bottom, 4)
                        .id(Self.tonightAnchor)
                    }
                    // Tonight is the card, so it is not also a row. Drawn
                    // both ways it appeared twice in one scroll, and the
                    // second time was underneath four nights already eaten,
                    // which reads as the week having lost its order.
                    ForEach(aheadThisWeek(skippingToday: tonight != nil), id: \.self) { date in
                        dayRow(date)
                    }
                    ForEach(Array(futureWeeks.enumerated()), id: \.offset) { index, week in
                        HStack {
                            MicroLabel(weekSectionLabel(week, index: index))
                            Spacer()
                            Text("\(week.filter { dinner(on: $0) != nil }.count) of 7")
                                .plType(.micro)
                                .foregroundStyle(Color.inkSecondary)
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
            // Land on tonight, not on the oldest thing the household ever
            // cooked. Without an anchor a timeline that grows upwards opens
            // further from the answer every week it is used.
            .onAppear {
                guard !landedOnTonight else { return }
                landedOnTonight = true
                scroll.scrollTo(Self.tonightAnchor, anchor: .top)
            }
            }
        }
    }

    /// The scroll's resting place.
    private static let tonightAnchor = "tonight"


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
        // Aligned on the discs, not the blocks: the avatar carries a caption
        // and the bell does not, so centring the blocks left the face
        // sitting about 8pt high. See VerticalAlignment.discCentre.
        HStack(alignment: .discCentre, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // "Aug 30 to Sep 5" is wider than a cross-month range has
                // any right to be, and the header's icons leave it under
                // half the screen. It shrinks to fit; wrapping pushed the
                // title down and broke the masthead.
                MicroLabel(weekRangeLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    // Squeezed by four icon buttons, so it truncated to
                    // "AUG 3..." at accessibility sizes. An eyebrow beside
                    // a title is chrome; the title below it is not.
                    .plChrome()
                Text("Your week")
                    // A step down from display and a weight lighter. At 27pt
                    // semibold it needed two lines beside four icon buttons,
                    // so the masthead stood taller than the answer under it.
                    // The card below is where that size belongs now.
                    .plType(.title, .medium)
                    .foregroundStyle(Color.ink)
                    // Two lines, not one. At normal sizes the title never
                    // reaches the second, so nothing moves; at accessibility
                    // sizes it wraps the way an iOS large title wraps instead
                    // of truncating "Your week" to "Your...". A title is
                    // content, so it keeps growing; the icons beside it are
                    // chrome and hold at xxLarge.
                    .lineLimit(2)
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
                        .plType(.micro)
                        .foregroundStyle(Color.inkSecondary)
                        // One line, always. This sits in a squeezed masthead
                        // HStack, so at XXXL it wrapped and broke the word
                        // across two lines: "HO" over "ST".
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .matchedTransitionSource(id: ZoomID.host, in: zoom)
            .plDiscAligned(42)
            .plChrome()
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
                .plType(.micro, .extraBold)
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
        return SwipeRow(isOpen: swipeBinding(date), actions: [.remove { remove(on: date) }]) {
            HStack(spacing: 10) {
                dateCard(date, dimmed: false)

                // The dish is back, and in the same slot the open night puts
                // its dashed plate: one skeleton down the list instead of
                // two. It went away when the date card took the width, which
                // left the week — the screen this app is mostly looked at —
                // with no photograph on it at all.
                dishCircle(for: meal, diameter: 48)
                    // The cook belongs to the dish, not to the far edge of
                    // the row. Moving them here also hands the title back the
                    // 38pt that an edge avatar was costing it, which is the
                    // difference between "Creamy Tuscan Chicken" and
                    // "Creamy Tuscan Chick…".
                    .overlay(alignment: .bottomTrailing) {
                        // Not the owner: the tagline already refuses to say
                        // "Nate cooks" to Nate, and your own face on your own
                        // dish every night is decoration, not information.
                        if let cook = meal.cook, !cook.isOwner, !eatingOut {
                            AvatarCircle(member: cook, size: 22)
                                // A face on a photograph needs its own edge
                                // or it reads as part of the dish.
                                .overlay { Circle().strokeBorder(Color.cardFill, lineWidth: 2) }
                                .offset(x: 3, y: 3)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.title)
                        .plType(.body, .bold)
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
            .accessibilityHint("Opens the day")
            .contextMenu { nightMenu(date) }
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
        .matchedTransitionSource(id: date, in: zoom)
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
                    // 48, matching the planned night's dish. An empty plate
                    // that is a different size from a full one makes the two
                    // rows read as two lists.
                    .frame(width: 48, height: 48)
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
                // Uppercase to match the live day's card. The scale's own
                // micro tracking is set for caps, and two cases one row
                // apart read as two different labels.
                Text(date.formattedWeekday().uppercased())
                    .plType(.micro)
                Text(date.formattedDayNumber())
                    .plType(.heading, .bold)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.inkSecondary)
            // Same width as a live day's card, so the whole left column
            // holds one line down the list — history is shorter, not
            // narrower.
            // Floored, not fixed: both lines grew with the scale and this
            // held 38pt of text in a 38pt box. A hard height around type
            // that now answers Dynamic Type is the overflow already logged
            // in CLAUDE.md.
            .plChrome()
            .frame(width: 66)
            .frame(minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.chipFill)
            }

            if let meal {
                dishCircle(for: meal, diameter: 34)
                    .opacity(0.65)
                Text(meal.title)
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            } else {
                // Past tense on purpose: "yet" promises a night you can
                // still cook.
                Text("Nothing plated")
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(minHeight: 54)
        // The same container as the rows above and below it. A past night is
        // still a row in this list, and it had neither their fill nor their
        // border: `hairlineSoft` measures 1.105:1 on canvas against
        // `navHairline`'s 1.178, so history read as loose text between two
        // cards rather than as a shorter card. Being past is carried by the
        // things that belong to the content — the compression from 76pt to
        // 54, the smaller type, no plate, no forecast, no plus — not by
        // taking the container away.
        .background(Color.cardFill, in: Radius.shape(Radius.row))
        .overlay {
            Radius.shape(Radius.row)
                .strokeBorder(Color.navHairline, lineWidth: 1.5)
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
            // Dragging a plate from one night to another was the only way to
            // move a dinner. That is a gesture nobody is told about and a
            // gesture VoiceOver cannot perform, and `moveMeal` was already
            // sitting here doing the work for the drop target.
            Menu {
                ForEach(movableNights(excluding: date), id: \.self) { target in
                    Button(nightLabel(target)) {
                        _ = moveMeal(from: DayTransfer.token(for: date), to: target)
                    }
                }
            } label: {
                Label("Move to another night", systemImage: "calendar")
            }
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

    private func dateCard(_ date: Date, dimmed: Bool) -> some View {
        let today = Calendar.current.isDateInToday(date)
        return VStack(spacing: 1) {
            HStack(spacing: 4) {
                // Today is today whether or not the night is planned.
                Text(date.formattedWeekday().uppercased())
                    .plType(.micro)
                    .foregroundStyle(today ? Color.tomato : Color.inkSecondary)
                if showCalendarEvents && events.hasEvent(on: date) {
                    Circle().fill(Color.grape).frame(width: 5, height: 5)
                }
            }

            // A date is a fact whether or not the night is planned, so an
            // open night no longer reads as disabled — the dashed plate and
            // the faint copy carry the emptiness on their own.
            Text(date.formattedDayNumber())
                .plType(.display, .medium)
                .monospacedDigit()
                .foregroundStyle(dimmed && !today ? Color.inkSecondary : Color.ink)
                // Gabarito's line box leaves the numeral floating below the
                // weekday; Apple sets them almost touching.
                .padding(.top, -2)

            // Weather always occupies its line, even when the forecast
            // can't answer, so a day without one is not a shorter card.
            Group {
                if let day = forecast.forecast(for: date) {
                    HStack(spacing: 4) {
                        Image(systemName: day.symbolName)
                            .font(.system(size: 10, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(Int(day.highF.rounded()))°")
                            .plType(.micro)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.inkSecondary)
                    // The row combines its children, so a bare "72°" would
                    // read as a stray number. Say the condition the way
                    // Weather does.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.conditionDescription), high \(Int(day.highF.rounded())) degrees")
                } else {
                    Text(" ")
                        .plType(.micro)
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 2)
        }
        // Wide enough that the temperature is a temperature rather than a
        // footnote, and no wider. 84x76 with a 32pt numeral was a card for
        // somebody who has been told to hold the phone further away.
        .padding(.vertical, 7)
        // A 66pt chip is furniture: at AX5 it set "MON" as "M" over "O"
        // over "N". The dish name beside it has a whole row to grow into
        // and keeps going. See plChrome in Theme.swift.
        .plChrome()
        .frame(width: 66)
        .frame(minHeight: 62)
        .background {
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(today ? Color.tomatoTint : Color.cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
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

    /// Every dinner already cooked, grouped by its week, oldest first.
    ///
    /// Only nights that have a dinner on them. An empty past night is not
    /// history: `pastRow` disables it so it cannot be planned, and it
    /// records nothing, so a wall of "Nothing plated" above tonight would
    /// be scrollback with nothing in it.
    ///
    /// Not bounded to a fixed number of weeks. It is exactly as long as the
    /// household has cooked: nothing on a new install, a year after a year.
    private var cookedHistory: [HistorySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let past = meals.filter { $0.slotValue == .dinner && $0.date < today }
        guard !past.isEmpty else { return [] }

        let grouped = Dictionary(grouping: past) { calendar.startOfWeek(for: $0.date) }
        return grouped.keys.sorted().map { start in
            var seen = Set<Date>()
            let dates = grouped[start, default: []]
                .map { calendar.startOfDay(for: $0.date) }
                .filter { seen.insert($0).inserted }
                .sorted()
            return HistorySection(start: start,
                                  label: historyLabel(weekStart: start),
                                  dates: dates)
        }
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
        let base: String
        if today {
            // Tonight names its cook like every other night does. This
            // branch returned before it could reach the cook clause four
            // lines below, so the one night the answer matters most was the
            // only night the app would not give it — while the Home Screen
            // widget beside it drew the cook's face the whole time.
            var parts: [String] = ["Tonight"]
            if let cook = meal.cook {
                parts.append(cook.isOwner ? "you cook" : "\(cook.name) cooks")
            }
            let minutes = meal.recipe?.totalMinutes ?? 0
            if minutes > 0 { parts.append(Recipe.durationText(minutes)) }
            base = parts.joined(separator: " · ")
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
                    return "\(member.name) cooks \(full.string(from: date))"
                }
            }
            return "\(member.name) cooks \(days.joined(separator: " & "))"
        }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Nobody has a regular cook night" : parts.joined(separator: " · ")
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
