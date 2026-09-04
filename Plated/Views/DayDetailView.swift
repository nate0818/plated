import SwiftUI
import SwiftData

/// Everything about one day, in one place. The week list answers "what's for
/// dinner"; this answers "what's happening today" — every slot from breakfast
/// to dessert, who's cooking each one, what the weather is doing, what's
/// already on the calendar, and the way through to the recipe when it's your
/// turn at the stove.
///
/// Tapping a day used to raise a two-button dialog — change what's for
/// dinner, remove it. Those two live here now, on a swipe, which is where
/// edits belong: they're things you do to a meal, not the reason you opened
/// the day.
struct DayDetailView: View {
    let date: Date
    /// Forwarded into PlanNightSheet — "Ask the Table" hops tabs, and only
    /// the shell knows how. Without it the row is a dead tap.
    var askTheTable: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var meals: [PlannedMeal]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false

    @State private var planning: SlotPlan?
    /// One row open at a time, same contract as the week's plan rows.
    @State private var swipedSlot: MealSlot?
    @State private var openMeal: PlannedMeal?
    /// The dish you tapped is the dish that opens. See CookbookView.
    @Namespace private var zoom
    @State private var events = DayEventsProvider.shared
    @State private var forecast = ForecastProvider.shared

    /// `sheet(item:)` needs one identifiable value, and planning a day needs
    /// two — which day, which slot.
    struct SlotPlan: Identifiable {
        let date: Date
        let slot: MealSlot
        var id: String { "\(date.timeIntervalSince1970)-\(slot.rawValue)" }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isPast: Bool { date < Calendar.current.startOfDay(for: .now) }

    private var dayMeals: [PlannedMeal] {
        meals.filter { Calendar.current.isSameDay($0.date, date) }
    }

    private func meal(in slot: MealSlot) -> PlannedMeal? {
        dayMeals.first { $0.slotValue == slot }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plannedSlots) { slot in
                        plannedSection(slot)
                    }
                    addMeal
                        .padding(.top, plannedSlots.isEmpty ? 0 : 16)
                    if let line = cooksLine {
                        Text(line)
                            .plType(.caption, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                // Pushed pages clear the floating tab bar themselves.
                .padding(.bottom, Layout.floatingChromeInset)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting, swipedSlot != nil {
                    withAnimation(.plSnap) { swipedSlot = nil }
                }
            }
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .navigationDestination(item: $openMeal) { meal in
            // The whole point of arriving from a day: the recipe page knows
            // which night it's cooking for.
            if let recipe = meal.recipe {
                RecipeDetailView(recipe: recipe, meal: meal)
                    .navigationTransition(.zoom(sourceID: meal.persistentModelID, in: zoom))
            }
        }
        .sheet(item: $planning) { plan in
            PlanNightSheet(date: plan.date, slot: plan.slot, askTheTable: askTheTable)
        }
        .task {
            // The only place Plated raises the location prompt. This
            // screen shows the forecast and the suggestion that reads it,
            // so the ask arrives with its answer already on screen.
            await forecast.refresh(days: 10, mayAsk: true)
            if showCalendarEvents { events.refresh() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconDiscButton(systemName: "chevron.left", label: "Back") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel(fullDateLabel)
                    Text(dayTitle)
                        .plType(.display)
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
                Spacer(minLength: 6)
                AccountButton()
                if let day = forecast.forecast(for: date) {
                    // Plated shows the one fact that changes dinner — how
                    // hot it will be. Anyone who wants the hour-by-hour
                    // wants Weather, not a forecast screen we would have to
                    // build and keep honest.
                    Button {
                        Haptic.tap()
                        openWeatherApp()
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: day.symbolName)
                                .font(.system(size: 19, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text("\(Int(day.highF.rounded()))°")
                                .plType(.micro)
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("\(day.conditionDescription), high \(Int(day.highF.rounded())) degrees")
                    .accessibilityHint("Opens the Weather app")
                }
            }
            if let line = contextLine {
                Text(line)
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 6)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // MARK: Slots

    /// Only the slots this day actually has, earliest first. Laying out all
    /// five occasions whether or not anyone eats them turns a day into a
    /// form to fill in; a day should show what's on it.
    private var plannedSlots: [MealSlot] {
        Array(Set(dayMeals.map(\.slotValue)))
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var openSlots: [MealSlot] {
        MealSlot.allCases
            .filter { slot in !plannedSlots.contains(slot) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @ViewBuilder
    private func plannedSection(_ slot: MealSlot) -> some View {
        if let meal = meal(in: slot) {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel(slot.title)
                SwipeRow(isOpen: swipeBinding(slot), actions: actions(for: meal, slot: slot), actionLabel: "Actions for \(meal.title)") {
                    mealCard(meal, slot: slot)
                }
            }
            .padding(.top, 8)
        }
    }

    /// One door to every other occasion — breakfast, lunch, a snack, dessert
    /// — instead of five standing invitations. A day that has already
    /// happened doesn't get invited to plan.
    @ViewBuilder
    private var addMeal: some View {
        if isPast {
            if plannedSlots.isEmpty {
                Text("Nothing plated")
                    .plType(.body)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 8)
            }
        } else if !openSlots.isEmpty {
            Menu {
                ForEach(openSlots) { slot in
                    Button {
                        planning = SlotPlan(date: date, slot: slot)
                    } label: {
                        Label(slot.title, systemImage: slot.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        // 52, the same as a real dish in this column. An
                        // empty plate of a different size from a full one
                        // starts its label 8pt off every label above it.
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.inkFaint)
                        }
                    Text(plannedSlots.isEmpty ? "Add a meal" : "Add another meal")
                        .plType(.body)
                        .foregroundStyle(Color.inkSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // The same container the meal cards use, not a dashed ghost
                // among solid rows. WeekView removed exactly this from the
                // identical stack one screen away: an open row drawn as a
                // failed card makes the list read as two lists, and the
                // dashed plate inside is enough to carry the emptiness.
                // One dashed thing per row.
                .frame(minHeight: 72)
                .background(Color.canvas, in: Radius.shape(Radius.row))
                .overlay {
                    Radius.shape(Radius.row)
                        .strokeBorder(Color.navHairline, lineWidth: 1.5)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(plannedSlots.isEmpty ? "Add a meal" : "Add another meal")
            .accessibilityHint("Choose a meal")
        }
    }

    /// Everything you can do to a plated meal, on a swipe. The cooked mark
    /// belongs here rather than on a button inside the card: a button living
    /// under a swipe gesture fires as the finger travels over it, which
    /// marked dinner cooked every time you reached for Remove.
    private func actions(for meal: PlannedMeal, slot: MealSlot) -> [SwipeAction] {
        var actions: [SwipeAction] = []
        if !isFuture {
            actions.append(
                SwipeAction(
                    symbol: meal.isCooked ? "arrow.uturn.backward" : "checkmark",
                    label: meal.isCooked ? "Not cooked" : "Mark cooked"
                ) { toggleCooked(meal) }
            )
        }
        actions.append(
            SwipeAction(symbol: "arrow.2.squarepath", label: "Change") {
                swipedSlot = nil
                planning = SlotPlan(date: date, slot: slot)
            }
        )
        actions.append(.remove { remove(meal) })
        return actions
    }

    private func mealCard(_ meal: PlannedMeal, slot: MealSlot) -> some View {
        HStack(spacing: 12) {
            dish(for: meal)
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.title)
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let line = mealMeta(meal) {
                    Text(line)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // Not you. The meta line already says "You cook"; your own face
            // beside it is the same fact twice. Same rule as the week's
            // rows — see WeekView.plannedRow.
            if let cook = meal.cook, !cook.isOwner {
                AvatarCircle(member: cook, size: 30)
            }
            if meal.recipe != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 72)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Color.navHairline, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.tap()
            // The recipe is the point when there is one — this is the screen
            // you stand at the stove with. Without one there's nothing to
            // read, so the tap goes where it can still help: changing it.
            if meal.recipe != nil {
                openMeal = meal
            } else {
                planning = SlotPlan(date: date, slot: slot)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .matchedTransitionSource(id: meal.persistentModelID, in: zoom)
    }

    @ViewBuilder
    private func dish(for meal: PlannedMeal) -> some View {
        Group {
            if let data = meal.recipe?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            } else if let recipe = meal.recipe {
                DishView(recipe: recipe, diameter: 52)
            } else if meal.customTitle.localizedCaseInsensitiveContains("eating out") {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 2)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "fork.knife.circle")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                    }
            } else {
                DishView(title: meal.title, diameter: 52)
            }
        }
        .plDishShadow()
        .opacity(meal.isCooked ? 0.75 : 1)
        .overlay(alignment: .bottomTrailing) {
            // Nothing wrote `cookedAt` before this screen existed, so
            // "times cooked" in Insights and the grocery list's skip of
            // already-cooked meals were both reading a field the app never
            // set. A plate that happened earns the basil tick.
            if meal.isCooked {
                Circle()
                    .fill(Color.basil)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.onTomato)
                    }
                    .overlay { Circle().strokeBorder(Color.canvas, lineWidth: 2) }
                    .accessibilityHidden(true)
            }
        }
    }

    private func toggleCooked(_ meal: PlannedMeal) {
        Haptic.plate()
        withAnimation(.plSnap) {
            swipedSlot = nil
            meal.cookedAt = meal.isCooked ? nil : .now
        }
    }

    // MARK: Data

    private var isFuture: Bool { date > Calendar.current.startOfDay(for: .now) }

    /// Apple's Weather app. `weather://` is not a documented scheme, so
    /// this is offered rather than promised: if it doesn't open, the tap
    /// does nothing rather than bouncing the user to a Safari error.
    private func openWeatherApp() {
        guard let url = URL(string: "weather://") else { return }
        openURL(url) { accepted in
            if !accepted { print("PLATED WEATHER: no Weather app to open") }
        }
    }

    private func swipeBinding(_ slot: MealSlot) -> Binding<Bool> {
        Binding(
            get: { swipedSlot == slot },
            set: { swipedSlot = $0 ? slot : nil }
        )
    }

    private func remove(_ meal: PlannedMeal) {
        Haptic.warn()
        withAnimation(.plSnap) {
            swipedSlot = nil
            context.delete(meal)
        }
    }

    private func mealMeta(_ meal: PlannedMeal) -> String? {
        var parts: [String] = []
        if let minutes = meal.recipe?.totalMinutes, minutes > 0 {
            parts.append(Recipe.durationText(minutes))
        }
        if let cook = meal.cook {
            parts.append(cook.isOwner ? "You cook" : "\(cook.name) cooks")
        }
        if meal.gathering != nil { parts.append("Gathering") }
        if meal.isCooked { parts.append("Cooked") }
        if parts.isEmpty, !meal.tagline.isEmpty { return meal.tagline }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private var fullDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }

    /// How full the day is, and nothing else.
    ///
    /// The forecast used to lead this line, which set "Clear · Busy day"
    /// under a header already showing a sun and 97°: the same fact twice,
    /// and the second time in a word the calendar also uses, so there was no
    /// way to tell whether "clear" meant the sky or the schedule. The symbol
    /// and the high carry the weather. This line is the calendar's.
    private var contextLine: String? {
        // How full the day is, not the name of one thing on it. A day with
        // six entries was being described by whichever one came back first.
        guard showCalendarEvents else { return nil }
        return events.load(on: date)
    }

    /// Whose night it is by the household's rota, when nobody has been named
    /// on the meal itself.
    private var cooksLine: String? {
        let weekday = Calendar.current.component(.weekday, from: date)
        let rostered = members.filter { $0.cookWeekdays.contains(weekday) }
        guard !rostered.isEmpty else { return nil }
        let names = rostered.map { $0.isOwner ? "you" : $0.name }
        return "Usually \(names.joined(separator: " and ")) on \(weekdayName)s"
    }

    private var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
