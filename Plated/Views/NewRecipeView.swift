import SwiftUI
import SwiftData
import PhotosUI

/// The recipe editor — one surface for three doors: the + button (blank),
/// "edit" on a dish you own, and "save" on a table post (prefilled, tweak
/// before it joins your cookbook). Photo, facts, filing, ingredients, and
/// real steps — the NYT-cooking shape without the paywall.
struct RecipeEditorView: View {
    /// Existing recipe to edit; nil means create.
    var editing: Recipe?
    /// Prefill for save-from-table: (title, summary, heroPhoto, originID).
    var prefill: (title: String, summary: String, photo: Data?, originID: String)?
    /// Set when the caller plates the recipe itself (PlanNightSheet) — the
    /// editor's own "Save & plate it" shortcut would double-plate.
    var hidePlateShortcut = false
    var onSaved: (Recipe) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var meals: [PlannedMeal]

    @State private var title = ""
    @State private var summary = ""
    @State private var minutes = 25
    @State private var serves = 4
    @State private var visibility = "household"
    @Namespace private var visibilityPill
    @State private var householdCanEdit = true
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoLoading = false
    @State private var extraItems: [PhotosPickerItem] = []
    @State private var extraPhotoData: [Data] = []
    @State private var category: RecipeCategory?
    @State private var mealType: RecipeMealType = .dinner
    @State private var difficultyOverride: RecipeDifficulty?
    @State private var draftIngredients: [DraftIngredient] = []
    @State private var steps: [String] = []
    @State private var stepEntry = ""
    @State private var addToGroceries = true
    @State private var loaded = false
    /// What the dial showed when the sheet opened. The dial floors at 15,
    /// so comparing against the recipe's own total let an untouched save
    /// rewrite a 10-minute dish into a fabricated 7/8 split.
    @State private var initialMinutes = -1
    @State private var discardAsked = false

    private let minuteChoices = [15, 25, 40, 60, 90]

    struct DraftIngredient: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: String
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    photoWell
                    extraPhotoStrip

                    TextField("Name the dish", text: $title)
                        .plType(.display)
                        .foregroundStyle(Color.ink)
                        .tint(Color.tomato)
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.hairline).frame(height: 2)
                        }

                    TextField("One line about it", text: $summary, axis: .vertical)
                        .plType(.body, .medium)
                        .lineLimit(1...3)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(minuteChoices, id: \.self) { choice in
                                Button("\(choice) min") { minutes = choice }
                            }
                        } label: {
                            factPicker("Time", "\(minutes) min")
                        }
                        Menu {
                            ForEach(1...12, id: \.self) { count in
                                Button("\(count)") { serves = count }
                            }
                        } label: {
                            factPicker("Serves", "\(serves)")
                        }
                        Menu {
                            ForEach(RecipeDifficulty.allCases) { level in
                                Button(level.rawValue) { difficultyOverride = level }
                            }
                        } label: {
                            factPicker("Effort", effectiveDifficulty.rawValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Meal")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(RecipeMealType.allCases) { option in
                                    selectChip(option.rawValue, icon: option.symbolName, active: mealType == option) {
                                        mealType = option
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Kind of dish")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(RecipeCategory.allCases) { option in
                                    selectChip(option.rawValue, icon: option.symbolName, active: category == option) {
                                        category = category == option ? nil : option
                                    }
                                }
                            }
                        }
                    }

                    ingredientsSection
                    stepsSection

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Visibility")
                        visibilityPicker
                        HStack {
                            Text("Household can edit")
                                .plType(.body)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Toggle("", isOn: $householdCanEdit)
                                .labelsHidden()
                                .sensoryFeedback(.selection, trigger: householdCanEdit)
                                .tint(Color.basil)
                        }
                        .padding(.horizontal, 4)
                        .opacity(visibility == "private" ? 0.35 : 1)
                        .disabled(visibility == "private")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                TomatoPillButton(
                    title: isEditing ? "Save changes" : "Save to cookbook",
                    systemImage: "circle.circle"
                ) {
                    save(plating: nil)
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
                if !isEditing, !hidePlateShortcut, let night = nextOpenNight {
                    Button {
                        save(plating: night)
                    } label: {
                        Text("Save and plan it for \(nightLabel(night))")
                            .plType(.footnote, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        // A filled draft doesn't die to one accidental swipe. Only fresh
        // drafts guard — an edit that's dragged away loses deltas, but it
        // was opened onto a saved recipe and reads as safe, and asking on
        // every look-then-leave would be nagging.
        .interactiveDismissDisabled(hasDraftContent)
        .confirmationDialog("Discard this recipe?", isPresented: $discardAsked, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep writing", role: .cancel) {}
        }
        .onAppear(perform: loadOnce)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoLoading = true
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    photoData = Self.processed(raw)
                }
                photoLoading = false
            }
        }
        .onChange(of: extraItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if extraPhotoData.count >= 5 { break }
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let processed = Self.processed(raw) {
                        extraPhotoData.append(processed)
                    }
                }
                extraItems = []
            }
        }
    }

    // MARK: Load

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        defer { initialMinutes = minutes }
        if let recipe = editing {
            title = recipe.title
            summary = recipe.summary
            minutes = max(recipe.totalMinutes, 15)
            serves = recipe.servings
            visibility = recipe.visibility
            householdCanEdit = recipe.householdCanEdit
            photoData = recipe.photoData
            category = recipe.categoryValue
            mealType = recipe.mealTypeValue
            if !recipe.difficulty.isEmpty { difficultyOverride = recipe.difficultyValue }
            steps = recipe.steps
            extraPhotoData = recipe.sortedExtraPhotos.compactMap(\.photoData)
            draftIngredients = recipe.sortedIngredients.map {
                DraftIngredient(name: $0.name, quantity: $0.quantity, unit: $0.unit)
            }
            addToGroceries = false
        } else if let prefill {
            title = prefill.title
            summary = prefill.summary
            photoData = prefill.photo
            addToGroceries = false
        }
    }

    // MARK: Pieces

    /// A fresh draft with real typing in it — the thing an accidental
    /// dismissal would destroy.
    private var hasDraftContent: Bool {
        editing == nil && (
            !title.trimmingCharacters(in: .whitespaces).isEmpty
                || !summary.trimmingCharacters(in: .whitespaces).isEmpty
                || !steps.isEmpty
                || !stepEntry.trimmingCharacters(in: .whitespaces).isEmpty
                || !draftIngredients.isEmpty
                || photoData != nil
        )
    }

    private var header: some View {
        HStack {
            Button {
                if hasDraftContent { discardAsked = true } else { dismiss() }
            } label: {
                Text("Cancel")
                    .plType(.body, .bold)
                    .foregroundStyle(Color.inkSecondary)
                    .plTapTarget()
            }
            .buttonStyle(.pressable)
            Spacer()
            Text(isEditing ? "Edit recipe" : (prefill == nil ? "New recipe" : "Save to your cookbook"))
                .plType(.heading, .bold)
                .foregroundStyle(Color.ink)
            Spacer()
            Color.clear.frame(width: 48, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var effectiveDifficulty: RecipeDifficulty {
        difficultyOverride ?? RecipeDifficulty.from(minutes: minutes)
    }

    private func selectChip(_ label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .plType(.footnote, .bold)
            }
            .fixedSize()
            .foregroundStyle(active ? Color.canvas : Color.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
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

    /// Quick ingredient capture — "2 lb chicken thighs" in one line, parsed
    /// on the way in, so the grocery list has something real to build from.
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Ingredients")

            ForEach(draftIngredients) { draft in
                HStack {
                    Text(draft.name)
                        .plType(.body)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text(draftQuantityText(draft))
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) {
                            draftIngredients.removeAll { $0.id == draft.id }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Remove \(draft.name)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.inkFaint)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, 4)
            }

            // The same field the import review uses, and for the same
            // reason: the natural move is to copy the whole ingredient list
            // and paste it in one go.
            IngredientEntryField { added in
                draftIngredients.append(contentsOf: added.map {
                    DraftIngredient(name: $0.name, quantity: $0.quantity, unit: $0.unit)
                })
            }

            if !isEditing && !draftIngredients.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to this week's grocery list")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Text("These \(draftIngredients.count) ingredients go on the list when you save.")
                            .plType(.caption)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $addToGroceries)
                        .labelsHidden()
                        .sensoryFeedback(.selection, trigger: addToGroceries)
                        .tint(Color.basil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
                .transition(.plUnfold)
            }
        }
        .animation(.plSnap, value: draftIngredients.count)
    }

    /// Numbered steps, one line each — added in order, removable, honest.
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("The steps")

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .plType(.footnote, .extraBold, family: .display)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(step)
                        .plType(.body, .medium)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) {
                            steps.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Remove step \(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.inkFaint)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 8) {
                TextField(steps.isEmpty ? "Step 1. What happens first?" : "Step \(steps.count + 1)…", text: $stepEntry, axis: .vertical)
                    .plType(.body, .medium)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .onSubmit(addStep)
                    .plTappableField()
                addRoundButton(disabled: stepEntry.trimmingCharacters(in: .whitespaces).isEmpty, label: "Add step", action: addStep)
            }
        }
        .animation(.plSnap, value: steps.count)
    }

    private func addRoundButton(disabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "plus")
                        .accessibilityLabel(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.ink)
                }
                .plTapTarget()
        }
        .buttonStyle(.pressable)
        .disabled(disabled)
    }

    private func addStep() {
        let entry = stepEntry.trimmingCharacters(in: .whitespaces)
        guard !entry.isEmpty else { return }
        Haptic.tap()
        steps.append(entry)
        stepEntry = ""
    }

    private func draftQuantityText(_ draft: DraftIngredient) -> String {
        var parts: [String] = []
        if draft.quantity > 0 { parts.append(Ingredient.format(draft.quantity)) }
        let unit = Ingredient.unitText(draft.unit, for: draft.quantity)
        if !unit.isEmpty { parts.append(unit) }
        return parts.joined(separator: " ")
    }

    private var photoWell: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                if let photoData, let image = UIImage(data: photoData) {
                    PhotoWell(image: image, height: 240, cornerRadius: Radius.hero)
                        .plCardShadow()
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Change")
                            .plType(.micro)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                } else {
                    RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 240)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "camera")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(Color.inkFaint)
                                Text("Add a photo of the plate")
                                    .plType(.body, .bold)
                                    .foregroundStyle(Color.inkSecondary)
                                Text("Your photo, your dish. No stock food here.")
                                    .plType(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                }
            }
        }
        .buttonStyle(.pressable)
    }

    /// The extra shots — process, plating, chaos. Up to five.
    private var extraPhotoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(extraPhotoData.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Haptic.tap()
                                    withAnimation(.plSnap) {
                                        extraPhotoData.remove(at: index)
                                    }
                                } label: {
                                    Circle()
                                        .fill(Color.scrim)
                                        .frame(width: 20, height: 20)
                                        .overlay {
                                            Image(systemName: "xmark")
                                                .accessibilityLabel("Remove photo")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Color.onScrim)
                                        }
                                        .frame(width: 44, height: 44, alignment: .topTrailing)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.pressable)
                            }
                    }
                }
                if extraPhotoData.count < 5 {
                    PhotosPicker(selection: $extraItems, maxSelectionCount: 5 - extraPhotoData.count, matching: .images) {
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            .frame(width: 72, height: 72)
                            .overlay {
                                VStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Add")
                                        .plType(.micro)
                                }
                                .foregroundStyle(Color.inkSecondary)
                            }
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .animation(.plSnap, value: extraPhotoData.count)
    }

    /// A picker wearing a fact, NOT a count atom — the box is here because
    /// this one is genuinely tappable, which is the whole distinction the
    /// count law draws. Read-only facts use CountBlock/CountDivider; copying
    /// this for a display number would put a border round something that
    /// isn't a button. Named for what it is so that mistake is harder.
    private func factPicker(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .plType(.heading)
                .foregroundStyle(Color.ink)
            // Sentence case, matching CountBlock. The all-caps tracked
            // micro-type this used to wear is dashboard voice, and a
            // household is not a dashboard.
            Text(label)
                .plType(.micro, .semibold)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
        .contentShape(Rectangle())
    }

    private var visibilityPicker: some View {
        HStack(spacing: 0) {
            visibilitySegment("private", label: "Only me", icon: "lock")
            visibilitySegment("household", label: "Household", icon: nil)
            visibilitySegment("table", label: "The Table", icon: nil)
        }
        .padding(2)
        .background(Color.hairlineSoft, in: Capsule())
    }

    private func visibilitySegment(_ value: String, label: String, icon: String?) -> some View {
        let active = visibility == value
        return Button {
            Haptic.select()
            withAnimation(.plSnap) { visibility = value }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold))
                }
                Text(label).plType(.footnote, .bold)
            }
            .foregroundStyle(active ? Color.ink : Color.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .background {
                if active {
                    Capsule()
                        .fill(Color.raisedFill)
                        .overlay(Capsule().strokeBorder(Color.navHairline))
                        .plTileShadow()
                        // One pill, three seats — it slides, never blinks.
                        .matchedGeometryEffect(id: "visibilityPill", in: visibilityPill)
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// Saving waits for the photo to finish processing so a picked photo is
    /// never silently dropped.
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !photoLoading
    }

    private var nextOpenNight: Date? {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            .first { date in
                !meals.contains { Calendar.current.isSameDay($0.date, date) && $0.slotValue == .dinner }
            }
    }

    private func nightLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    // MARK: Save

    private func save(plating night: Date?) {
        // Text still sitting in the step field is work the user typed and
        // believes is in — "type the last step, hit Save" used to drop it,
        // and the loss surfaced days later at the stove.
        addStep()
        Haptic.plate()
        let recipe = editing ?? Recipe()
        recipe.title = title.trimmingCharacters(in: .whitespaces)
        recipe.summary = summary.trimmingCharacters(in: .whitespaces)
        recipe.servings = serves
        // Only when the dial actually moved. Comparing against the
        // recipe's own total wasn't enough: the dial floors at 15, so a
        // 10-minute dish loaded as 15 and an untouched save fabricated a
        // 7/8 split. Prongsby then reads those numbers back aloud.
        if minutes != initialMinutes || editing == nil {
            recipe.prepMinutes = minutes / 2
            recipe.cookMinutes = minutes - minutes / 2
        }
        recipe.visibility = visibility
        recipe.householdCanEdit = visibility == "private" ? false : householdCanEdit
        recipe.photoData = photoData
        recipe.categoryValue = category
        recipe.mealTypeValue = mealType
        recipe.steps = steps
        if let difficultyOverride {
            recipe.difficultyValue = difficultyOverride
        }
        if let prefill { recipe.originID = prefill.originID }

        // Rebuild children wholesale — simpler than diffing, and cascade
        // delete keeps the store clean.
        (recipe.ingredients ?? []).forEach(context.delete)
        recipe.ingredients = draftIngredients.enumerated().map { index, draft in
            Ingredient(
                name: draft.name, quantity: draft.quantity, unit: draft.unit,
                aisle: Self.guessAisle(for: draft.name), sortIndex: index
            )
        }
        (recipe.extraPhotos ?? []).forEach(context.delete)
        recipe.extraPhotos = extraPhotoData.enumerated().map { index, data in
            RecipePhoto(photoData: data, sortIndex: index)
        }

        if !isEditing {
            context.insert(recipe)
            // Save-from-table announces via .saveReceived in the feed's
            // finishSave — a second "joined the cookbook" line would double
            // the bell for one action.
            if prefill == nil {
                let owner = members.first(where: \.isOwner)?.name ?? "Someone"
                Notifier.post(
                    .recipeAdded, actor: owner,
                    body: "\(owner) added \(recipe.title) to the cookbook.",
                    into: context
                )
            }
        }

        // The ask that used to be a surprise: new ingredients go straight to
        // this week's basket when the cook says so. Manual lines survive the
        // auto-rebuild by design.
        if !isEditing && addToGroceries {
            let weekStart = Calendar.current.startOfDay(for: .now)
            for draft in draftIngredients {
                let item = GroceryItem(
                    name: draft.name, quantity: draft.quantity, unit: draft.unit,
                    aisle: Self.guessAisle(for: draft.name),
                    weekStart: weekStart, isManual: true
                )
                item.originTitle = recipe.title
                context.insert(item)
            }
            if !draftIngredients.isEmpty {
                let owner = members.first(where: \.isOwner)?.name ?? "Someone"
                Notifier.post(
                    .groceriesAdded, actor: owner,
                    body: "\(draftIngredients.count) ingredients from \(recipe.title) added to the grocery list.",
                    into: context
                )
            }
        }

        if let night {
            let cook = members.first { $0.cookWeekdays.contains(Calendar.current.component(.weekday, from: night)) }
                ?? members.first(where: \.isOwner)
            context.insert(PlannedMeal(
                date: night, slot: .dinner, recipe: recipe,
                servings: serves, cook: cook
            ))
        }
        onSaved(recipe)
        dismiss()
    }

    /// A few obvious keywords beat asking the cook to file groceries by hand.
    /// Everything unrecognized lands in Other, which is where it would have
    /// gone anyway.
    static func guessAisle(for name: String) -> GroceryAisle {
        RecipeImporter.aisle(for: name)
    }

    /// Downscale to ~1200px and recompress — CloudKit charges by the byte.
    /// The Table composer borrows this too; every photo pays the same toll.
    static func processed(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
