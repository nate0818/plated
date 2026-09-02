import SwiftUI
import SwiftData

/// The planning page for one night — every way to fill (or free) a plate
/// in one place: pick for me, your recipes, a brand-new recipe, eating
/// out, asking the table (with a poll), or a full gathering. Opened from
/// any open night, any planned night, and any month-view day.
struct PlanNightSheet: View {
    let date: Date
    /// Which eating occasion is being filled. Dinner is the week's spine and
    /// stays the default, so every existing caller is unchanged; the day
    /// view passes breakfast, lunch, dessert and snack through the same page.
    var slot: MealSlot = .dinner
    var askTheTable: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @State private var pickerShown = false
    @State private var newRecipeShown = false
    @State private var askShown = false
    @State private var gatheringShown = false
    @State private var events = DayEventsProvider.shared
    @State private var forecast = ForecastProvider.shared

    private var meal: PlannedMeal? {
        meals.first { Calendar.current.isSameDay($0.date, date) && $0.slotValue == slot }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                MicroLabel(meal == nil ? planLabel : "Planned")
                Text(dayTitle)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                if let context = contextLine {
                    Text(context)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if let meal {
                        currentMealCard(meal)
                            .padding(.bottom, 6)
                        MicroLabel("Something else")
                    }

                    if !recipes.isEmpty {
                        actionRow(
                            icon: "wand.and.stars", tint: Color.tomato,
                            title: "Pick for me",
                            caption: "Matched to the weather and what your household eats."
                        ) { pickForMe() }
                    }

                    actionRow(
                        icon: "book.closed", tint: Color.ink,
                        title: "Choose a recipe",
                        caption: "\(recipes.count) \(recipes.count == 1 ? "dish" : "dishes") your household already knows."
                    ) { pickerShown = true }

                    actionRow(
                        icon: "plus.circle", tint: Color.ink,
                        title: "Add a recipe",
                        caption: "Save it and plan it in one go."
                    ) { newRecipeShown = true }

                    actionRow(
                        icon: "fork.knife.circle", tint: Color.ink,
                        title: "Eating out",
                        caption: "Counts as a planned night."
                    ) { markEatingOut() }

                    actionRow(
                        icon: "bubble.and.pencil", tint: Color.ink,
                        title: "Ask the Table",
                        caption: "Ask what everyone wants, or put up a poll."
                    ) { askShown = true }

                    actionRow(
                        icon: "party.popper", tint: Color.ink,
                        title: "Plan a gathering",
                        caption: "Guests, a time, and an event in your calendar."
                    ) { gatheringShown = true }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .sheet(isPresented: $pickerShown) {
            RecipePickerSheet(date: date, onWriteNew: { newRecipeShown = true }) { recipe in
                plate(recipe, tagline: "")
                dismiss()
            }
        }
        .sheet(isPresented: $newRecipeShown) {
            RecipeEditorView(hidePlateShortcut: true) { recipe in
                plate(recipe, tagline: "")
                dismiss()
            }
        }
        .sheet(isPresented: $askShown) {
            AskComposerSheet(date: date) {
                dismiss()
                askTheTable()
            }
        }
        .sheet(isPresented: $gatheringShown) {
            GatheringSheet(date: date, attachedMeal: meal, slot: slot) {
                dismiss()
            }
        }
    }

    // MARK: Pieces

    private func currentMealCard(_ meal: PlannedMeal) -> some View {
        HStack(spacing: 12) {
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
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 2)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "fork.knife.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                }
            }
            .plDishShadow()
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                if let cook = meal.cook {
                    Text(cook.isOwner ? "You cook" : "\(cook.name) cooks")
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
            Button {
                Haptic.plate()
                withAnimation(.plSnap) { context.delete(meal) }
            } label: {
                Image(systemName: "trash")
                    .accessibilityLabel("Remove this meal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Color.navHairline))
    }

    private func actionRow(
        icon: String, tint: Color, title: String, caption: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.fill)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(tint)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text(caption)
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// "Plan the night" is dinner's line and stays dinner's line; the other
    /// slots say what they are.
    private var planLabel: String {
        slot == .dinner ? "Plan the night" : "Plan \(slot.title.lowercased())"
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(date) { return "Tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private var contextLine: String? {
        var parts: [String] = []
        if let day = forecast.forecast(for: date) {
            parts.append("\(day.conditionDescription), high \(Int(day.highF.rounded()))°")
        }
        if showCalendarEvents, let event = events.firstEventTitle(on: date) {
            parts.append("On the calendar: \(event)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func pickForMe() {
        let engine = SuggestionEngine(recipes: recipes, members: members)
        let thisWeek = Set(
            meals.filter {
                let delta = Calendar.current.dateComponents([.day], from: .now.startOfDay, to: $0.date).day ?? 99
                return (0..<7).contains(delta)
            }.compactMap { $0.recipe?.persistentModelID }
        )
        // The row promises "something that suits the weather" and the header
        // right above shows the forecast — passing nil here made the engine's
        // biggest weight dead code and the promise a coin toss.
        let day = forecast.forecast(for: date)
        let ranked = engine.suggestions(for: date, forecast: day, limit: recipes.count)
        guard let pick = ranked.first(where: { !thisWeek.contains($0.recipe.persistentModelID) }) ?? ranked.first
        else {
            // The row is hidden when there is nothing to pick, so reaching
            // here means something else went wrong. Say so with a buzz
            // rather than looking like a dead button.
            Haptic.warn()
            return
        }
        let recipe = pick.recipe
        let minutes = recipe.totalMinutes
        // The magic move earns the plate-weight thump, not a chrome tick.
        Haptic.plate()
        // Say why — "Picked for you · grill weather" proves the engine
        // looked out the window.
        let why = pick.reason.components(separatedBy: ", ").first ?? ""
        let tagline = !why.isEmpty ? "Picked for you · \(why)"
            : (minutes > 0 ? "Picked for you · \(Recipe.durationText(minutes))" : "Picked for you")
        plate(recipe, tagline: tagline)
        dismiss()
    }

    private func markEatingOut() {
        Haptic.plate()
        withAnimation(.plPop) {
            if let meal {
                meal.recipe = nil
                meal.customTitle = "Eating out"
                meal.tagline = "Night off the stove"
                meal.cook = nil
            } else {
                let meal = PlannedMeal(date: date, slot: slot, customTitle: "Eating out")
                meal.tagline = "Night off the stove"
                context.insert(meal)
            }
        }
        dismiss()
    }

    private func plate(_ recipe: Recipe, tagline: String) {
        Haptic.plate()
        let cook = CookRotation.cook(for: date, members: members, meals: meals)
        withAnimation(.plPop) {
            if let meal {
                meal.recipe = recipe
                meal.customTitle = ""
                meal.servings = recipe.servings
                meal.cook = cook
                meal.tagline = tagline
            } else {
                context.insert(PlannedMeal(
                    date: date, slot: slot, recipe: recipe,
                    servings: recipe.servings, cook: cook, tagline: tagline
                ))
            }
        }
        let cookName = (cook?.isOwner ?? true) ? "you" : (cook?.name ?? "someone")
        Notifier.post(
            .mealPlanned, actor: cook?.name ?? "",
            body: "\(dayTitle): \(recipe.title). \(cookName.capitalized) cook\(cookName == "you" ? "" : "s").",
            into: context
        )
        // The moment to ask, and the only one. They have just said they
        // intend to cook on a given night, so "shall I remind you" continues
        // their own thought instead of interrupting it. iOS grants exactly
        // one prompt, and one spent at launch is one spent before the app
        // has done anything worth being reminded about.
        Task {
            await NotificationScheduler.askOnceAfterFirstPlan()
            await NotificationScheduler.rebuild(
                meals: meals, ownerName: members.first(where: \.isOwner)?.name ?? ""
            )
        }
    }
}

/// An open ask for the table, optionally with a poll — give the household
/// choices and let the votes cook.
struct AskComposerSheet: View {
    let date: Date
    var onPosted: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var caption = ""
    @State private var options: [String] = []
    @State private var optionEntry = ""
    @State private var tagged: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Ask the Table")
                Text(dayName)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(defaultCaption, text: $caption, axis: .vertical)
                        .plType(.body, .medium)
                        .lineLimit(2...4)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Poll · optional")
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            HStack {
                                Image(systemName: "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.inkFaint)
                                Text(option)
                                    .plType(.body)
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Button {
                                    Haptic.tap()
                                    withAnimation(.plSnap) { options.remove(at: index) }
                                } label: {
                                    Image(systemName: "xmark")
                                        .accessibilityLabel("Remove option")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.inkFaint)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.pressable)
                            }
                            .padding(.horizontal, 4)
                        }
                        if options.count < 4 {
                            HStack(spacing: 8) {
                                TextField("Add an option", text: $optionEntry)
                                    .plType(.body, .medium)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                                    .onSubmit(addOption)
                                    .plTappableField()
                                Button {
                                    addOption()
                                } label: {
                                    Circle()
                                        .strokeBorder(Color.hairline, lineWidth: 1.5)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            Image(systemName: "plus")
                                                .accessibilityLabel("Add option")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color.ink)
                                        }
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.pressable)
                                .disabled(optionEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    if members.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel("Tag someone")
                            HStack(spacing: 8) {
                                ForEach(members.filter { !$0.isOwner }, id: \.persistentModelID) { member in
                                    let active = tagged.contains(member.name)
                                    Button {
                                        Haptic.tap()
                                        withAnimation(.plSnap) {
                                            if active { tagged.remove(member.name) } else { tagged.insert(member.name) }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            AvatarCircle(member: member, size: 22)
                                            Text("@\(member.name)")
                                                .plType(.micro)
                                        }
                                        .foregroundStyle(active ? Color.canvas : Color.ink)
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 36)
                                        .background {
                                            if active {
                                                Capsule().fill(Color.ink)
                                            } else {
                                                Capsule().strokeBorder(Color.hairline)
                                            }
                                        }
                                    }
                                    .buttonStyle(.pressable)
                                    .accessibilityAddTraits(active ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(title: options.isEmpty ? "Post" : "Post with poll") {
                post()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    /// The night is only baked into the caption text, so the words have to
    /// carry the date — a bare "friday" three weeks of scrollback later
    /// means the wrong Friday to every voter.
    private var dayName: String {
        if Calendar.current.isDateInToday(date) { return "Tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private var defaultCaption: String {
        if Calendar.current.isDateInToday(date) { return "What should we make tonight?" }
        if Calendar.current.isDateInTomorrow(date) { return "What should we make tomorrow?" }
        return "What should we make on \(dayName)?"
    }

    private func addOption() {
        let entry = optionEntry.trimmingCharacters(in: .whitespaces)
        guard !entry.isEmpty, options.count < 4 else { return }
        Haptic.tap()
        withAnimation(.plSnap) { options.append(entry) }
        optionEntry = ""
    }

    private func post() {
        Haptic.plate()
        let owner = members.first(where: \.isOwner)
        let post = TablePost(
            authorName: owner?.name ?? "Me",
            authorColorHex: owner?.colorHex ?? "FF5A3C",
            caption: caption.isEmpty ? defaultCaption : caption,
            kind: "ask"
        )
        post.pollOptions = options
        post.pollCounts = Array(repeating: 0, count: options.count)
        post.taggedNames = Array(tagged)
        context.insert(post)
        // The household hears about it — that's the point of asking.
        Notifier.post(
            .askPosted, actor: owner?.name ?? "Me",
            body: options.isEmpty
                ? "\(owner?.name ?? "Someone") asked the Table about \(dayName)."
                : "\(owner?.name ?? "Someone") started a poll for \(dayName).",
            into: context
        )
        dismiss()
        onPosted()
    }
}

/// A gathering — dinner party, holiday, friends over. Lands in the plan
/// and mirrors into Apple Calendar so the rest of life can see it.
struct GatheringSheet: View {
    let date: Date
    var attachedMeal: PlannedMeal?
    var slot: MealSlot = .dinner
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var guests = 4
    @State private var startTime: Date
    @State private var syncToCalendar = true
    @State private var syncResult: String?
    /// Set once the gathering lands in the store. A calendar failure used to
    /// leave "Save gathering" live over a save the user believed failed —
    /// tapping again threw a second party and rang the bell twice.
    @State private var savedGathering: Gathering?

    init(date: Date, attachedMeal: PlannedMeal? = nil, slot: MealSlot = .dinner, onDone: @escaping () -> Void = {}) {
        self.date = date
        self.attachedMeal = attachedMeal
        self.slot = slot
        self.onDone = onDone
        let evening = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        _startTime = State(initialValue: evening)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Plan a gathering")
                Text(dayLabel)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Sunday dinner party", text: $title)
                        .plType(.body)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    TextField("Our place", text: $location)
                        .plType(.body, .medium)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    HStack {
                        Text("Guests")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        HStack(spacing: 14) {
                            stepperButton("minus", "One fewer guest") { if guests > 1 { guests -= 1 } }
                            Text("\(guests)")
                                .plType(.heading, .bold)
                                .foregroundStyle(Color.ink)
                                .frame(minWidth: 30)
                                .contentTransition(.numericText())
                            stepperButton("plus", "One more guest") { guests += 1 }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))

                    DatePicker("Starts at", selection: $startTime, displayedComponents: .hourAndMinute)
                        .plType(.body, .bold)
                        .tint(Color.tomato)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))

                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.fill)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.ink)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add to Apple Calendar")
                                .plType(.body, .bold)
                                .foregroundStyle(Color.ink)
                            Text("Adds an event you can invite guests from.")
                                .plType(.caption)
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $syncToCalendar)
                            .labelsHidden()
                            .sensoryFeedback(.selection, trigger: syncToCalendar)
                            .tint(Color.basil)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))

                    if let syncResult {
                        Text(syncResult)
                            .plType(.caption, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(
                title: savedGathering == nil ? "Save gathering" : "Add to calendar",
                systemImage: savedGathering == nil ? "party.popper" : "calendar.badge.plus"
            ) {
                save()
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private func stepperButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: symbol)
                        .accessibilityLabel(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ink)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func save() {
        Haptic.plate()
        let gathering: Gathering
        if let existing = savedGathering {
            // Second pass only ever means "the calendar didn't take" — the
            // party itself is already saved and on the plan.
            gathering = existing
        } else {
            gathering = Gathering(
                title: title.trimmingCharacters(in: .whitespaces),
                startDate: startTime,
                guestCount: guests,
                location: location.trimmingCharacters(in: .whitespaces)
            )
            context.insert(gathering)
            if let attachedMeal {
                attachedMeal.gathering = gathering
            } else {
                // A gathering planned on an open night used to save into a
                // record no screen shows — the plate haptic fired, the bell
                // rang, and the night still read "Nothing plated" everywhere.
                // The party occupies the night it's on.
                let meal = PlannedMeal(date: date, slot: slot, customTitle: gathering.title)
                meal.gathering = gathering
                meal.tagline = "Cooking for \(guests)"
                context.insert(meal)
            }
            Notifier.post(
                .mealPlanned, actor: "",
                body: "\(gathering.title), \(dayLabel). Cooking for \(guests).",
                into: context
            )
            savedGathering = gathering
        }
        if syncToCalendar {
            Task {
                do {
                    try await CalendarSync.shared.sync(gathering)
                    syncResult = "Added to your calendar"
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                    onDone()
                } catch {
                    // The raw EventKit error read like the save failed.
                    // It didn't — say what's true, in our voice.
                    syncResult = "The gathering is saved. Your calendar wasn't updated."
                }
            }
        } else {
            dismiss()
            onDone()
        }
    }
}
