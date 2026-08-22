import SwiftUI
import SwiftData

/// The planning page for one night — every way to fill (or free) a plate
/// in one place: pick for me, your recipes, a brand-new recipe, eating
/// out, asking the table (with a poll), or a full gathering. Opened from
/// any open night, any planned night, and any month-view day.
struct PlanNightSheet: View {
    let date: Date
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
        meals.first { Calendar.current.isSameDay($0.date, date) && $0.slotValue == .dinner }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                MicroLabel(meal == nil ? "Plan the night" : "The plan so far")
                Text(dayTitle)
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
                if let context = contextLine {
                    Text(context)
                        .font(.jakarta(12, .semibold))
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
                        MicroLabel("Change it")
                    }

                    actionRow(
                        icon: "wand.and.stars", tint: Color.tomato,
                        title: "Pick for me",
                        caption: "The engine knows the weather and the hard no's."
                    ) { pickForMe() }

                    actionRow(
                        icon: "book.closed", tint: Color.ink,
                        title: "From your recipes",
                        caption: "\(recipes.count) dishes the household already knows."
                    ) { pickerShown = true }

                    actionRow(
                        icon: "plus.circle", tint: Color.ink,
                        title: "New recipe",
                        caption: "Photograph it, file it, and plate it right here."
                    ) { newRecipeShown = true }

                    actionRow(
                        icon: "fork.knife.circle", tint: Color.ink,
                        title: "Eating out",
                        caption: "A night off is a plan too. The ring agrees."
                    ) { markEatingOut() }

                    actionRow(
                        icon: "hand.raised", tint: Color.ink,
                        title: "Ask the table",
                        caption: "Post an open ask — with a poll if you have options."
                    ) { askShown = true }

                    actionRow(
                        icon: "party.popper", tint: Color.ink,
                        title: "Plan a gathering",
                        caption: "Guests, a menu, and a spot on the Apple Calendar."
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
            RecipePickerSheet(date: date) { recipe in
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
            GatheringSheet(date: date, attachedMeal: meal) {
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
                    .font(.jakarta(15, .bold))
                    .foregroundStyle(Color.ink)
                if let cook = meal.cook {
                    Text(cook.isOwner ? "You cook" : "\(cook.name) cooks")
                        .font(.jakarta(12, .semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
            Button {
                Haptic.plate()
                withAnimation(.plSnap) { context.delete(meal) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.row))
        .overlay(RoundedRectangle(cornerRadius: Radius.row).strokeBorder(Color.navHairline))
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
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.ink)
                    Text(caption)
                        .font(.jakarta(12, .medium))
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
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
        let ranked = engine.suggestions(for: date, forecast: nil, limit: recipes.count)
        guard let recipe = (ranked.first { !thisWeek.contains($0.recipe.persistentModelID) } ?? ranked.first)?.recipe
        else { return }
        let minutes = recipe.totalMinutes
        // The magic move earns the plate-weight thump, not a chrome tick.
        Haptic.plate()
        plate(recipe, tagline: minutes > 0 ? "Picked for you · \(minutes) min" : "Picked for you")
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
                let meal = PlannedMeal(date: date, slot: .dinner, customTitle: "Eating out")
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
                    date: date, slot: .dinner, recipe: recipe,
                    servings: recipe.servings, cook: cook, tagline: tagline
                ))
            }
        }
        let cookName = (cook?.isOwner ?? true) ? "you" : (cook?.name ?? "someone")
        Notifier.post(
            .mealPlanned, actor: cook?.name ?? "",
            body: "\(recipe.title) is plated for \(dayTitle.lowercased()) — \(cookName) cook\(cookName == "you" ? "" : "s").",
            into: context
        )
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
                MicroLabel("Ask the table")
                Text(dayName)
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(defaultCaption, text: $caption, axis: .vertical)
                        .font(.jakarta(15, .medium))
                        .lineLimit(2...4)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Poll · optional")
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            HStack {
                                Image(systemName: "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.inkFaint)
                                Text(option)
                                    .font(.jakarta(14, .semibold))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Button {
                                    Haptic.tap()
                                    withAnimation(.plSnap) { options.remove(at: index) }
                                } label: {
                                    Image(systemName: "xmark")
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
                                TextField("Add a choice — “Tacos”", text: $optionEntry)
                                    .font(.jakarta(14, .medium))
                                    .padding(.horizontal, 14)
                                    .frame(height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                                    .onSubmit(addOption)
                                Button {
                                    addOption()
                                } label: {
                                    Circle()
                                        .strokeBorder(Color.hairline, lineWidth: 1.5)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            Image(systemName: "plus")
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
                            MicroLabel("Ring someone")
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
                                            AvatarCircle(initials: member.firstInitial, tone: member.tone, size: 22)
                                            Text("@\(member.name)")
                                                .font(.jakarta(12, .bold))
                                        }
                                        .foregroundStyle(active ? Color.canvas : Color.ink)
                                        .padding(.horizontal, 10)
                                        .frame(height: 36)
                                        .background {
                                            if active {
                                                Capsule().fill(Color.ink)
                                            } else {
                                                Capsule().strokeBorder(Color.hairline)
                                            }
                                        }
                                    }
                                    .buttonStyle(.pressable)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(title: options.isEmpty ? "Post the ask" : "Post with poll") {
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

    private var dayName: String {
        Calendar.current.isDateInToday(date) ? "Tonight" : {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }()
    }

    private var defaultCaption: String {
        "What should we plate \(dayName.lowercased())? Open to ideas."
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
                ? "\(owner?.name ?? "Someone") asked the table what to plate \(dayName.lowercased())."
                : "\(owner?.name ?? "Someone") started a poll for \(dayName.lowercased()) — \(options.count) choices.",
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
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var guests = 4
    @State private var startTime: Date
    @State private var syncToCalendar = true
    @State private var syncResult: String?

    init(date: Date, attachedMeal: PlannedMeal? = nil, onDone: @escaping () -> Void = {}) {
        self.date = date
        self.attachedMeal = attachedMeal
        self.onDone = onDone
        let evening = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        _startTime = State(initialValue: evening)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Plan a gathering")
                Text(dayLabel)
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Name it — “Sunday dinner party”", text: $title)
                        .font(.jakarta(16, .semibold))
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

                    TextField("Where — “Our place”", text: $location)
                        .font(.jakarta(14, .medium))
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

                    HStack {
                        Text("Guests")
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        HStack(spacing: 14) {
                            stepperButton("minus") { if guests > 1 { guests -= 1 } }
                            Text("\(guests)")
                                .font(.gabarito(19, .bold))
                                .foregroundStyle(Color.ink)
                                .frame(minWidth: 30)
                                .contentTransition(.numericText())
                            stepperButton("plus") { guests += 1 }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))

                    DatePicker("Sitting down at", selection: $startTime, displayedComponents: .hourAndMinute)
                        .font(.jakarta(14, .bold))
                        .tint(Color.tomato)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))

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
                                .font(.jakarta(14, .bold))
                                .foregroundStyle(Color.ink)
                            Text("The event lands in Calendar — invite guests from there.")
                                .font(.jakarta(12, .medium))
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
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))

                    if let syncResult {
                        Text(syncResult)
                            .font(.jakarta(12, .semibold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(title: "Set the table", systemImage: "party.popper") {
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

    private func stepperButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: symbol)
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
        let gathering = Gathering(
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: startTime,
            guestCount: guests,
            location: location.trimmingCharacters(in: .whitespaces)
        )
        context.insert(gathering)
        if let attachedMeal {
            attachedMeal.gathering = gathering
        }
        Notifier.post(
            .mealPlanned, actor: "",
            body: "\(gathering.title) is on for \(dayLabel) — cooking for \(guests).",
            into: context
        )
        if syncToCalendar {
            Task {
                do {
                    try await CalendarSync.shared.sync(gathering)
                    syncResult = "Added to your calendar"
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                    onDone()
                } catch {
                    syncResult = error.localizedDescription
                }
            }
        } else {
            dismiss()
            onDone()
        }
    }
}
