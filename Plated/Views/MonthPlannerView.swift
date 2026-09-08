import SwiftUI
import SwiftData

/// One calendar in either orientation. The grid selects a date; the agenda
/// underneath names every meal on that date before opening or changing it.
struct MonthPlannerView: View {
    @Binding var anchor: Date
    var askTheTable: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Query private var meals: [PlannedMeal]
    /// For the cook's face on a night somebody else planned.
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @State private var planDay: Date?
    @State private var dayShown: Date?
    @State private var planSlot: MealSlot = .dinner
    @State private var mealToMove: PlannedMeal?
    @State private var swipedMeal: PersistentIdentifier?
    @State private var emptyActionsOpen = false
    @State private var dropTargetDay: Date?
    @Namespace private var zoom

    /// Where VoiceOver should land after a month action. A shift rebuilds
    /// the grid from scratch, so focus otherwise sits on a cell that no
    /// longer exists and the reader is dropped back at the top of the page.
    @AccessibilityFocusState private var focusedDay: Date?

    /// How far the grid has given under a sideways drag.
    ///
    /// `@GestureState` rather than `@State`, and that is the whole point: it
    /// is the only one guaranteed to come back to zero when the gesture is
    /// CANCELLED rather than ended. The scroll view claiming the touch, a
    /// meal being lifted out of the agenda, the app going to the background:
    /// none of those reach `onEnded`, and a plain offset would be left
    /// holding a shift nobody asked for.
    @GestureState private var monthNudge: CGFloat = 0

    /// Before this it is not a gesture. The same floor `SwipeRow` uses for
    /// the other horizontal drag on this screen, which is already proven on
    /// a phone; two different numbers for one thumb is how a screen starts
    /// feeling arbitrary.
    private static let swipeBegins: CGFloat = 24

    /// And before this it is not a month. `EdgeBack` already calls 60pt a
    /// drag that means it, so the two horizontal commitments a thumb can
    /// make on this screen agree with each other.
    private static let swipeCommits: CGFloat = 60

    /// How much the grid gives. Enough to see, far too little to read as a
    /// page being dragged, which it is not: the month turns at the end of
    /// the gesture or not at all.
    private static let monthGive: CGFloat = 14

    /// The mark stands three points OUTSIDE the grid, in the page's own 24pt
    /// gutter, where the week strip's three points inside would be wrong.
    /// The strip's cells scroll edge to edge under a fade; these do not move
    /// and nothing is clipped, so there is no content for a mark to sit on.
    /// Measured: a column is (width - 48)/7, which is 46.7pt on the smallest
    /// phone, and the selected day's 34pt tomato disc is centred in it,
    /// leaving 6.36pt. An inset mark would end 0.36pt from that disc, and
    /// `shift` lands on the 1st, which is often the first column, so it
    /// would graze the tomato exactly when a month has just been chosen.
    private static let markGutter: CGFloat = PlanEdgeMark.size.width + 3
    private var calendar: Calendar { .current }
    private var first: Date { calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor }
    private var days: [Date] { calendar.range(of: .day, in: .month, for: anchor)?.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) } ?? [] }
    private var leading: Int { (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7 }
    private var selectedMeals: [PlannedMeal] { meals.filter { calendar.isDate($0.date, inSameDayAs: anchor) }.sorted { $0.slotValue.sortOrder < $1.slotValue.sortOrder } }
    /// Nights somebody else planned on a day, every slot, read-only.
    private func remotePlans(on day: Date) -> [PlanLedger.Entry] {
        MealSlot.allCases.sorted { $0.sortOrder < $1.sortOrder }.flatMap { PlanLedger.shared.plans(on: day, slot: $0) }
    }
    private var selectedRemote: [PlanLedger.Entry] { remotePlans(on: anchor) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // No month arrows, matching the week strip. The grid is the
                // control: it takes a sideways drag and a quiet mark at each
                // end says so, with the words living on as accessibility
                // actions on every day below. The visible non-gesture route
                // is already on screen one row above this view, because
                // WeekView draws its planner controls outside the week and
                // month branch: "Choose a date" opens a calendar onto any
                // month, "Today" comes home, and both are there in month
                // mode. That is why this can be an accelerator rather than
                // the only door.
                Text(anchor.formatted(.dateTime.month(.wide).year()))
                    .plType(.title, .bold)
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { offset in
                            Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7])
                                .plType(.caption, .bold)
                                .foregroundStyle(Color.inkSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                        ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 48) }
                        ForEach(days, id: \.self) { day in dayCell(day) }
                    }
                    // offset, never padding or a spacer: the give has to be
                    // a rendering effect. Anything that changes the grid's
                    // LAYOUT width hands the enclosing vertical ScrollView
                    // horizontal content to scroll, and the page starts
                    // sliding sideways on its own.
                    //
                    // The seven weekday letters above deliberately stay put.
                    // They are the same letters in every month; it is the
                    // month that is moving.
                    .offset(x: monthNudge)
                    // @GestureState snaps back to zero the instant the
                    // gesture ends or is cancelled, so the return needs an
                    // animation or it is a jump. Reduce Motion is answered
                    // inside plSnap, not here.
                    .animation(.plSnap, value: monthNudge)
                }
                .plChrome()
                // The whole block drags, including the gaps between cells and
                // the letters above them. This shadows nothing: children are
                // still hit-tested first, so every day Button and every drop
                // target keeps its own shape.
                .contentShape(Rectangle())
                .simultaneousGesture(monthSwipe)
                .overlay(alignment: .leading) { PlanEdgeMark().offset(x: -Self.markGutter) }
                .overlay(alignment: .trailing) { PlanEdgeMark().offset(x: Self.markGutter) }
                // No container hint, unlike the week strip. That strip is one
                // scrollable element a reader can land on; this is a grid of
                // 31 buttons, so the route that matters is the named actions
                // on each of them, and a hint here would be read out once for
                // a gesture the reader has a better door for.
                Divider()
                HStack {
                    Text(calendar.isDateInToday(anchor) ? "Today" : anchor.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .plType(.body, .bold)
                    Spacer()
                    Button { planSlot = .dinner; planDay = anchor } label: {
                        Label("Plan", systemImage: "plus")
                            .plActionLabel()
                            .plTapTarget()
                    }
                        .plType(.footnote, .bold)
                        .disabled(anchor < Date.now.startOfDay)
                }
                // A day with only a remote night is not empty: the Plan
                // button in the line above still offers this phone's own
                // night, and "Nothing planned" would be untrue.
                if selectedMeals.isEmpty, selectedRemote.isEmpty {
                    if anchor >= Date.now.startOfDay {
                        SwipeRow(isOpen: $emptyActionsOpen, actions: [
                            SwipeAction(symbol: "plus", label: "Plan") { planSlot = .dinner; planDay = anchor },
                            SwipeAction(symbol: "fork.knife", label: "Eat out") { planEatingOut() }
                        ], actionLabel: "Actions for this day") {
                            Button { planSlot = .dinner; planDay = anchor } label: {
                                Label("Plan dinner", systemImage: "plus")
                                    .plType(.body)
                                    .plActionLabel()
                                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    } else {
                        Text("Nothing planned for this day.").plType(.body).foregroundStyle(Color.inkSecondary).padding(.vertical, 12)
                    }
                } else {
                    ForEach(selectedMeals) { meal in
                        SwipeRow(isOpen: Binding(get: { swipedMeal == meal.persistentModelID }, set: { open in swipedMeal = open ? meal.persistentModelID : (swipedMeal == meal.persistentModelID ? nil : swipedMeal) }), actions: actions(for: meal), actionLabel: "Actions for \(meal.title)") {
                        Button { dayShown = anchor } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.slotValue.rawValue.capitalized).plType(.caption, .semibold).foregroundStyle(Color.inkSecondary)
                                    Text(meal.title).plType(.body, .bold)
                                    Text("\(meal.servings) servings" + (meal.cook.map { " · \($0.isMe ? "You cook" : $0.name + " cooks")" } ?? ""))
                                        .plType(.caption).foregroundStyle(Color.inkSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .matchedTransitionSource(id: meal.persistentModelID, in: zoom)
                        }
                        .modifier(PlannerMealDrag(meal: meal))
                        .accessibilityIdentifier("month-meal-\(meal.slot)")
                    }
                    ForEach(selectedRemote) { entry in
                        RemotePlanRow(entry: entry, date: anchor, members: members) { dayShown = anchor }
                    }
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 24)
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .sheet(item: sheet) { route in
            switch route {
            case .plan(let date): PlanNightSheet(date: date, slot: planSlot, askTheTable: askTheTable)
            case .move(let meal): MoveMealSheet(meal: meal) { anchor = $0 }
            }
        }
        .onChange(of: anchor) { swipedMeal = nil; emptyActionsOpen = false }
        .onAppear {
            #if DEBUG
            if LaunchFlags.consume("-plated-reveal-plan-actions") {
                swipedMeal = selectedMeals.first?.persistentModelID
            }
            #endif
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { swipedMeal = nil; emptyActionsOpen = false }
        }
        .navigationDestination(item: $dayShown) { day in DayDetailView(date: day, askTheTable: askTheTable) }
    }

    private enum Sheet: Identifiable {
        case plan(Date), move(PlannedMeal)
        var id: String { switch self { case .plan(let day): "plan-\(day)"; case .move(let meal): "move-\(meal.persistentModelID)" } }
    }
    private var sheet: Binding<Sheet?> {
        Binding(get: { if let mealToMove { return .move(mealToMove) }; return planDay.map { .plan($0) } },
                set: { if $0 == nil { planDay = nil; mealToMove = nil } })
    }
    private func actions(for meal: PlannedMeal) -> [SwipeAction] {
        var actions = [SwipeAction(symbol: "pencil", label: "Edit") { planSlot = meal.slotValue; planDay = meal.date }]
        if !meal.isCooked { actions.append(SwipeAction(symbol: "calendar", label: "Move") { mealToMove = meal }) }
        actions.append(.remove { context.delete(meal); Persist.save(context) })
        return actions
    }
    private func dropMeal(_ tokens: [String], on target: Date) -> Bool {
        guard MealPlanMove.perform(tokens.first, to: target, meals: meals, context: context) else { return false }
        Haptic.plate()
        withAnimation(.plSnap) { anchor = target; dropTargetDay = nil }
        return true
    }
    private func planEatingOut() {
        guard !meals.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: anchor) && $0.slotValue == .dinner }) else { return }
        context.insert(PlannedMeal(date: anchor, customTitle: "Eating out"))
        Persist.save(context)
        Haptic.plate()
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: anchor)
        let today = calendar.isDateInToday(day)
        // A night is a night: one somebody else planned earns the marker.
        let count = meals.filter { calendar.isDate($0.date, inSameDayAs: day) }.count + remotePlans(on: day).count
        return Button {
            Haptic.select()
            withAnimation(.plSnap) { anchor = day }
        } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.day())
                    .plType(.body, .bold)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(selected ? Color.onTomato : (today ? Color.tomato : Color.ink))
                    .background(selected ? Color.tomato : Color.clear, in: Circle())
                Circle().fill(count > 0 ? Color.inkSecondary : Color.clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(dropTargetDay == day ? Color.tomatoTint : Color.clear, in: RoundedRectangle(cornerRadius: Radius.chip))
            .overlay {
                if dropTargetDay == day {
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(Color.tomato, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { tokens, _ in dropMeal(tokens, on: day) } isTargeted: { targeted in
            withAnimation(.plSnap) {
                if targeted, day >= Date.now.startOfDay { dropTargetDay = day; Haptic.select() }
                else if dropTargetDay == day { dropTargetDay = nil }
            }
        }
        .scaleEffect(dropTargetDay == day ? 1.05 : 1)
        .animation(.plSnap, value: dropTargetDay)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (today ? ", today" : "") + ", \(count) meals planned")
        .accessibilityIdentifier("month-date-\(day.formattedDayNumber())")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityFocused($focusedDay, equals: day)
        // On the button, not on the block: a ScrollView is not an element
        // VoiceOver lands on, so actions hung on the container may never be
        // offered, and this pair is the whole non-gesture route for a reader
        // who cannot swipe. Voice Control and Switch Control read the same
        // list.
        .accessibilityAction(named: "Previous month") { shift(-1) }
        .accessibilityAction(named: "Next month") { shift(1) }
    }

    /// A month is one swipe wide.
    ///
    /// **`simultaneousGesture`, not `gesture`.** The grid sits inside this
    /// screen's vertical ScrollView, and an exclusive drag here would take
    /// the scroll away from every thumb that starts on the calendar. This is
    /// the arrangement `SwipeRow` already runs in this same scroll view on a
    /// real phone, down to the 24pt floor and the dominance test, rather
    /// than a fresh guess about how SwiftUI arbitrates with UIScrollView.
    ///
    /// **Scoped to the calendar block, never to the screen.** Below the grid
    /// the meal rows own a horizontal drag of their own through `SwipeRow`
    /// and a lift through the planner's drag; a wider gesture would fight
    /// both, which is the reasoning `EdgeBack` records for why the tab-back
    /// swipe is a UIKit edge recogniser and not this.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: Self.swipeBegins)
            .updating($monthNudge) { value, nudge, _ in
                // Simultaneous means this closure runs for the scroll's
                // touches too, so nothing may move until the drag has proven
                // it is sideways. The diagonal belongs to the page.
                guard Self.isSideways(value.translation) else {
                    nudge = 0
                    return
                }
                nudge = Self.give(value.translation.width)
            }
            .onEnded { value in
                // Predicted, not raw: a fast flick leaves the glass before it
                // has travelled, and it is still a flick. Same reading
                // `SwipeRow` takes of the same gesture.
                //
                // Dominance is re-measured here rather than latched in a
                // `@GestureState` flag during the drag. That was tried and is
                // silently broken: `@GestureState` resets to its initial
                // value the moment a gesture ends, so a flag read inside
                // `onEnded` is always back to false and no swipe ever turns
                // a month. The total translation is the honest test anyway,
                // since a mostly-sideways drag that curves at the last
                // moment still has the width to prove it.
                guard Self.isSideways(value.translation),
                      abs(value.predictedEndTranslation.width) > Self.swipeCommits
                else { return }
                shift(value.predictedEndTranslation.width < 0 ? 1 : -1)
            }
    }

    /// A drag is the month's only while it is mostly sideways.
    private static func isSideways(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }

    /// The grid gives a little and stops. Asymptotic, so there is no point
    /// where resistance ends and the grid starts sliding freely: it is a
    /// surface saying it can move, not a page being carried.
    private static func give(_ dx: CGFloat) -> CGFloat {
        let travel = monthGive * (1 - 1 / (abs(dx) / 40 + 1))
        return dx < 0 ? -travel : travel
    }

    private func shift(_ amount: Int) {
        Haptic.select()
        let target = calendar.date(byAdding: .month, value: amount, to: first) ?? first
        withAnimation(.plSnap) {
            anchor = target
        } completion: {
            // Matched by calendar day rather than by ==. The month start
            // computed here and the one the grid builds its cells from come
            // from two different Calendar calls, and a zone that moves its
            // clocks at midnight on the first can hand them two instants.
            focusedDay = days.first { calendar.isDate($0, inSameDayAs: target) }
        }
        // Silent unless something is listening, so a sighted swipe pays
        // nothing for it. Every route into this function that a VoiceOver,
        // Voice Control or Switch Control reader takes is a jump they chose
        // and cannot see, and the phrasing matches the week strip's so the
        // two granularities speak alike.
        let spoken: String
        if calendar.isDate(target, equalTo: .now, toGranularity: .month) {
            spoken = "This month"
        } else if calendar.isDate(target, equalTo: .now, toGranularity: .year) {
            spoken = target.formatted(.dateTime.month(.wide))
        } else {
            spoken = target.formatted(.dateTime.month(.wide).year())
        }
        AccessibilityNotification.Announcement(spoken).post()
    }
}
