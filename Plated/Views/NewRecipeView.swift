import SwiftUI
import SwiftData
import PhotosUI

/// Recipe permissions are author-based, with one compatibility exception:
/// rows created before authorship was recorded belong to this device. Recipes
/// are household records, but their creator can still choose whether another
/// household member may change them. Deletion remains creator-only.
extension Recipe {
    var isAuthoredByCurrentDevice: Bool {
        authorID.isEmpty || authorID == TableIdentity.cached
    }

    var isEditableByCurrentDevice: Bool {
        isAuthoredByCurrentDevice || householdCanEdit
    }
}

private struct RecipeStepFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// The recipe editor — one surface for three doors: the + button (blank),
/// "edit" on a dish you can change, and "save" on a table post (prefilled, tweak
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
    @State private var prepMinutes = 0
    @State private var cookMinutes = 0
    @State private var serves = 4
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoLoading = false
    @State private var extraItems: [PhotosPickerItem] = []
    @State private var extraPhotoData: [Data] = []
    @State private var category: RecipeCategory?
    @State private var mealType: RecipeMealType = .dinner
    @State private var difficultyOverride: RecipeDifficulty?
    @State private var draftIngredients: [DraftIngredient] = []
    /// The steps, each one a thing rather than a position.
    ///
    /// `[String]` driving `ForEach(…enumerated(), id: \.offset)` made identity
    /// the index. These rows are editable fields with a live cursor, so that
    /// is not a cosmetic problem: removing a middle step moved everybody
    /// else's text up under an unchanged view.
    @State private var draftSteps: [DraftStep] = []
    /// What this kitchen learned cooking it. Captured at the receipt on the
    /// recipe page; changed here.
    @State private var cookNotes = ""
    @State private var equipmentText = ""
    @State private var dietaryLabelsText = ""
    @State private var allergenText = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbohydrateText = ""
    @State private var fatText = ""
    @State private var nutritionSource = ""
    /// Which field the keyboard is in. `AnyHashable` because the rows are
    /// addressed by their own ids and the fixed fields by name.
    @FocusState private var focused: AnyHashable?
    @State private var draggingStep: UUID?
    @State private var stepDragOffset: CGSize = .zero
    @State private var stepDropTarget: UUID?
    @State private var stepFrames: [UUID: CGRect] = [:]
    /// Filing and extra photography should never stand between a cook and
    /// the actual recipe. They stay available in one quiet disclosure after
    /// the ingredients and method instead of becoming four required-looking
    /// decisions before the first ingredient can be typed.
    @State private var detailsExpanded = false
    /// A saved recipe whose optional grocery addition still needs a retry.
    @State private var pendingGroceryRecipe: Recipe?
    @State private var saveProblem: String?

    /// The row the keyboard is currently in, if it is one that can move.
    private var movableRow: (list: RowList, index: Int)? {
        if let id = focused as? UUID {
            if let i = draftIngredients.firstIndex(where: { $0.id == id }) {
                return (.ingredients, i)
            }
            if let i = draftSteps.firstIndex(where: { $0.id == id }) {
                return (.steps, i)
            }
        }
        return nil
    }

    private enum RowList { case ingredients, steps }

    /// Commit only on release. Cancelling a lift leaves the draft untouched;
    /// Save remains the only writer to the stored recipe.
    private func receiveStep(_ id: UUID, at target: UUID) {
        guard
              let from = draftSteps.firstIndex(where: { $0.id == id }),
              let to = draftSteps.firstIndex(where: { $0.id == target }),
              from != to
        else { return }
        Haptic.plate()
        withAnimation(.plSnap) {
            let step = draftSteps.remove(at: from)
            draftSteps.insert(step, at: to)
        }
    }

    /// A dedicated handle gesture keeps the text field's first-responder
    /// state intact. SwiftUI's transferable drag session cancels its drop
    /// while a field in the same row owns the keyboard; this gesture gives
    /// the cook continuous lift and target feedback without moving the caret
    /// or collapsing the editor around the keyboard.
    private func stepDragGesture(_ id: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.32, maximumDistance: 14)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("recipe-steps")))
            .onChanged { phase in
                switch phase {
                case .first(true):
                    guard draggingStep == nil else { return }
                    draggingStep = id
                    stepDropTarget = id
                    Haptic.plate()
                case .second(true, let drag?):
                    if draggingStep == nil {
                        draggingStep = id
                        Haptic.plate()
                    }
                    stepDragOffset = drag.translation
                    let nearest = stepFrames.min { lhs, rhs in
                        abs(lhs.value.midY - drag.location.y) < abs(rhs.value.midY - drag.location.y)
                    }?.key
                    if let nearest, nearest != stepDropTarget {
                        stepDropTarget = nearest
                        Haptic.select()
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let target = stepDropTarget
                withAnimation(.plSnap) {
                    draggingStep = nil
                    stepDragOffset = .zero
                    stepDropTarget = nil
                }
                if let target { receiveStep(id, at: target) }
            }
    }

    private func moveStep(_ id: UUID, by offset: Int) {
        guard let from = draftSteps.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard draftSteps.indices.contains(to) else { return }
        Haptic.select()
        withAnimation(.plSnap) { draftSteps.swapAt(from, to) }
    }

    /// What sits above the keyboard while a line is being edited.
    ///
    /// It replaces the Save bar rather than joining it: with the keyboard up,
    /// the Save button was pushed straight onto the row being typed in, so
    /// the sentence you were editing was behind a olive pill.
    ///
    /// `ToolbarItemGroup(placement: .keyboard)` would be the idiomatic home
    /// for this, and it draws nothing here — the editor is a sheet with its
    /// own masthead and no navigation container for a toolbar to attach to.
    ///
    /// Move up and move down rather than a drag: a drag on these rows would
    /// fight the caret, which SwipeRow already records happening, and
    /// DESIGN.md wants a non-gesture equivalent for every gesture anyway.
    private var editingBar: some View {
        HStack(spacing: 8) {
            if movableRow != nil {
                barButton("arrow.up", label: "Move up", enabled: canMove(-1)) { move(-1) }
                barButton("arrow.down", label: "Move down", enabled: canMove(1)) { move(1) }
            }
            Spacer()
            Button("Done") {
                Haptic.tap()
                focused = nil
            }
            .plType(.callout, .semibold)
            .foregroundStyle(Color.ink)
            .plTapTarget()
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .background(Color.canvas)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.navHairline).frame(height: 1)
        }
    }

    private func barButton(
        _ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                // A disabled control changes colour; it does not fade.
                .foregroundStyle(enabled ? Color.ink : Color.inkSecondary)
                .plTapTarget()
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Reordering without a drag.
    ///
    /// A drag on these rows would fight the caret — SwipeRow already records
    /// a `.draggable` lift stealing a touch — and DESIGN.md wants a
    /// non-gesture equivalent for any gesture anyway. So the move lives in
    /// the keyboard bar, where it appears the moment you tap the row you want
    /// to move and costs no chrome on the other twenty rows.
    private func move(_ by: Int) {
        guard let row = movableRow else { return }
        let to = row.index + by
        switch row.list {
        case .ingredients:
            guard draftIngredients.indices.contains(to) else { return }
            Haptic.select()
            withAnimation(.plSnap) { draftIngredients.swapAt(row.index, to) }
        case .steps:
            guard draftSteps.indices.contains(to) else { return }
            Haptic.select()
            withAnimation(.plSnap) { draftSteps.swapAt(row.index, to) }
        }
    }

    private func canMove(_ by: Int) -> Bool {
        guard let row = movableRow else { return false }
        let to = row.index + by
        return row.list == .ingredients
            ? draftIngredients.indices.contains(to)
            : draftSteps.indices.contains(to)
    }
    @State private var stepEntry = ""
    @State private var addToGroceries = true
    @State private var initialDraft: EditorDraft?
    @State private var loaded = false
    /// What the dial showed when the sheet opened. The dial floors at 15,
    /// so comparing against the recipe's own total let an untouched save
    /// rewrite a 10-minute dish into a fabricated 7/8 split.
    @State private var discardAsked = false


    struct DraftIngredient: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: String
        /// What the row's field shows once somebody has typed in it, and the
        /// only thing that field writes.
        ///
        /// The first version kept `name`/`quantity`/`unit` in step with the
        /// text through an `onChange` on the row's own state. That hop has to
        /// land between the last keystroke and Save, and it did not: typing
        /// "boneless" and saving stored "boneles", one character short, every
        /// time. A field that writes straight through its binding, the way
        /// the steps below do, cannot lose a keystroke.
        ///
        /// Nil until somebody edits, so an ingredient loaded from an existing
        /// recipe is written back exactly as it was rather than round-tripping
        /// through the parser because some other field on the screen changed.
        var edited: String?
        /// The store section this ingredient arrived filed under, and whether
        /// it is a staple.
        ///
        /// Save rebuilds every `Ingredient` wholesale, which is the simple
        /// thing and worth keeping — but it used to rebuild them from three
        /// fields, so an untouched "Save changes" overwrote a model-assigned
        /// aisle with a keyword guess that falls back to Other, and reset
        /// `isPantryStaple` to false. The import writes an aisle straight from
        /// the Foundation Models draft, which the ~130-entry table here cannot
        /// reproduce.
        var aisle: GroceryAisle?
        var isPantryStaple = false
        var package = IngredientPackage()

        /// The line as somebody would write it down: "2 cups flour".
        var text: String {
            if let edited { return edited }
            var parts: [String] = []
            if quantity > 0 { parts.append(Ingredient.format(quantity)) }
            let unitText = Ingredient.unitText(unit, for: quantity)
            if !unitText.isEmpty { parts.append(unitText) }
            parts.append(name)
            return parts.joined(separator: " ")
        }

        /// What to save: the typed line read once, or the untouched parts.
        var resolved: (
            name: String, quantity: Double, unit: String,
            aisle: GroceryAisle, isPantryStaple: Bool, package: IngredientPackage
        ) {
            guard let edited else {
                return (name, quantity, unit,
                        aisle ?? RecipeImporter.aisle(for: name), isPantryStaple, package)
            }
            let parsed = RecipeImporter
                .parseIngredientLine(edited.trimmingCharacters(in: .whitespacesAndNewlines))
            // A retyped row is a different food, so it is re-guessed rather
            // than carrying the previous row's section.
            return (parsed.name, parsed.quantity, parsed.unit,
                    RecipeImporter.aisle(for: parsed.name), isPantryStaple,
                    parsed.name.caseInsensitiveCompare(name) == .orderedSame ? package : IngredientPackage())
        }
    }

    struct DraftStep: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    /// Its place in the list as a person counts it.
    private func stepNumber(_ step: DraftStep) -> Int {
        (draftSteps.firstIndex { $0.id == step.id } ?? 0) + 1
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    photoWell

                    TextField("Name the dish", text: $title)
                        .focused($focused, equals: "title")
                        .plType(.display)
                        .foregroundStyle(Color.ink)
                        .tint(Color.olive)
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.hairline).frame(height: 2)
                        }

                    TextField("One line about it", text: $summary, axis: .vertical)
                        .plType(.body, .medium)
                        .lineLimit(1...3)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .focused($focused, equals: "summary")
                        .plTapToFocus { focused = "summary" }

                    // Prep and cook are two numbers on the model and were
                    // written by halving one picker's answer, so every recipe
                    // carried a 50/50 split nobody typed — which Prongsby then
                    // read aloud. Two fields, each typed, neither invented.
                    // One per row. Four number fields across one row is too
                    // tight at xxLarge, and these are the two facts the whole
                    // screen was wrong about.
                    DurationField(label: "Prep", minutes: $prepMinutes)
                    DurationField(label: "Cook", minutes: $cookMinutes)

                    VStack(alignment: .leading, spacing: 6) {
                        MicroLabel("Serves")
                        HStack(spacing: 10) {
                            servesStep("minus", enabled: serves > 1) { serves -= 1 }
                            Text("\(serves)")
                                .plType(.heading)
                                .foregroundStyle(Color.ink)
                                .monospacedDigit()
                                .frame(minWidth: 44)
                                .accessibilityHidden(true)
                            servesStep("plus", enabled: true) { serves += 1 }
                            Spacer()
                            Text("what these quantities make")
                                .plType(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Serves \(serves)")
                    }

                    ingredientsSection
                    stepsSection

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Notes")
                        EditableLine(
                            text: $cookNotes,
                            placeholder: "Anything worth remembering next time.",
                            focus: $focused, focusID: "notes"
                        )
                    }

                    moreDetailsSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            // The row you are typing in comes up above the keyboard. Nothing
            // did this before, so you edited the fourth ingredient with the
            // keyboard sitting on top of it.
            .scrollDismissesKeyboard(.interactively)
            // Once a handle has lifted, the row owns the vertical gesture.
            // Freezing the containing scroll view prevents its interactive
            // keyboard pan from cancelling the reorder on the first move.
            .scrollDisabled(draggingStep != nil)
            .disabled(pendingGroceryRecipe != nil)

            if focused != nil {
                editingBar
            } else {
            VStack(spacing: 10) {
                if let saveProblem {
                    Text(saveProblem)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.dangerText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryActionButton(
                    title: pendingGroceryRecipe != nil
                        ? "Retry groceries"
                        : (isEditing ? "Save changes" : "Save to cookbook"),
                    systemImage: "circle.circle"
                ) {
                    save(plating: nil)
                }
                .disabled(!canSave)
                if pendingGroceryRecipe == nil, !isEditing, !hidePlateShortcut, let night = nextOpenNight {
                    Button {
                        save(plating: night)
                    } label: {
                        // A disabled control changes colour; it does not
                        // fade. `inkSecondary` at 0.4 composites to about
                        // 1.68:1 on canvas, and `canSave` is false while the
                        // title is empty — which is how this sheet opens, so
                        // the one sentence explaining the shortcut was
                        // unreadable until the recipe was already written.
                        // Full-strength label on a `fill` capsule instead:
                        // 4.11:1 light, 5.83:1 dark, plainly present and
                        // plainly not ready. Never inkFaint on a word.
                        Text("Save and plan for \(nightLabel(night))")
                            .plType(.footnote, .semibold)
                            .plActionLabel(0.72)
                            .foregroundStyle(Color.inkSecondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background {
                                if !canSave { Capsule().fill(Color.fill) }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!canSave)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 16)
            // The scroll view runs under this bar, so the last row was drawn
            // through the Save button.
            .background(Color.canvas)
            }
        }
        .animation(.plSnap, value: focused == nil)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .interactiveDismissDisabled(hasDraftContent)
        .alert("Discard this recipe?", isPresented: $discardAsked) {
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
        if let recipe = editing {
            title = recipe.title
            summary = recipe.summary
            prepMinutes = recipe.prepMinutes
            cookMinutes = recipe.cookMinutes
            serves = recipe.servings
            photoData = recipe.photoData
            category = recipe.categoryValue
            mealType = recipe.mealTypeValue
            if !recipe.difficulty.isEmpty { difficultyOverride = recipe.difficultyValue }
            draftSteps = recipe.steps.map { DraftStep(text: $0) }
            cookNotes = recipe.cookNotes
            equipmentText = recipe.equipment.joined(separator: ", ")
            dietaryLabelsText = recipe.dietaryLabels.joined(separator: ", ")
            allergenText = recipe.knownAllergens.joined(separator: ", ")
            caloriesText = recipe.caloriesPerServing > 0 ? String(recipe.caloriesPerServing) : ""
            proteinText = recipe.proteinGramsPerServing > 0 ? String(recipe.proteinGramsPerServing) : ""
            carbohydrateText = recipe.carbohydrateGramsPerServing > 0 ? String(recipe.carbohydrateGramsPerServing) : ""
            fatText = recipe.fatGramsPerServing > 0 ? String(recipe.fatGramsPerServing) : ""
            nutritionSource = recipe.nutritionSource
            extraPhotoData = recipe.sortedExtraPhotos.compactMap(\.photoData)
            draftIngredients = recipe.sortedIngredients.map {
                DraftIngredient(
                    name: $0.name, quantity: $0.quantity, unit: $0.unit,
                    aisle: $0.aisleValue, isPantryStaple: $0.isPantryStaple,
                    package: $0.package
                )
            }
            addToGroceries = false
        } else if let prefill {
            title = prefill.title
            summary = prefill.summary
            photoData = prefill.photo
            addToGroceries = false
        }
        initialDraft = currentDraft
    }

    // MARK: Pieces

    private struct EditorDraft: Equatable {
        var strings: [String]
        var numbers: [Int]
        var photo: Data?
        var extraPhotos: [Data]
        var ingredients: [DraftIngredient]
        var steps: [DraftStep]
        var groceries: Bool
    }
    private var currentDraft: EditorDraft {
        EditorDraft(strings: [title, summary, cookNotes, equipmentText, dietaryLabelsText,
            allergenText, caloriesText, proteinText, carbohydrateText, fatText, nutritionSource,
            stepEntry, category?.rawValue ?? "", mealType.rawValue, difficultyOverride?.rawValue ?? ""],
            numbers: [prepMinutes, cookMinutes, serves], photo: photoData, extraPhotos: extraPhotoData,
            ingredients: draftIngredients, steps: draftSteps, groceries: addToGroceries)
    }
    private var hasDraftContent: Bool {
        photoLoading || pendingGroceryRecipe != nil || (initialDraft != nil && currentDraft != initialDraft)
            || (editing == nil && (!title.isEmpty || !summary.isEmpty || photoData != nil))
    }

    private var header: some View {
        HStack {
            Button {
                if let pendingGroceryRecipe { onSaved(pendingGroceryRecipe); dismiss() }
                else if hasDraftContent { discardAsked = true } else { dismiss() }
            } label: {
                Text("Cancel")
                    .plType(.body, .bold)
                    .plActionLabel()
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

    /// One step of the serves stepper. A stepper, not a twelve-row menu: a
    /// number you nudge by one is not a list you choose from, and the menu had
    /// a ceiling of twelve for no reason anybody recorded.
    private func servesStep(
        _ symbol: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptic.select()
            withAnimation(.plSnap) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                // A disabled control changes colour; it does not fade.
                .foregroundStyle(enabled ? Color.ink : Color.inkSecondary)
                .frame(width: 44, height: 44)
                .background {
                    Circle().strokeBorder(Color.hairline)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "One more" : "One fewer")
    }

    private func selectChip(_ label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        SelectChip(active: active, action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .plType(.footnote, .bold)
            }
        }
    }

    private var detailsSummary: String {
        var parts = [mealType.rawValue]
        if let difficultyOverride { parts.append(difficultyOverride.rawValue) }
        if let category { parts.append(category.rawValue) }
        if !extraPhotoData.isEmpty { parts.append(extraPhotoData.count.things("extra photo")) }
        return parts.joined(separator: " · ")
    }

    private var moreDetailsSection: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("Meal")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RecipeMealType.allCases) { option in
                                selectChip(
                                    option.rawValue,
                                    icon: option.symbolName,
                                    active: mealType == option
                                ) {
                                    mealType = option
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("Effort")
                    // Effort is a judgement, not a fact with a number behind
                    // it. Leaving it blank is more honest than deriving a
                    // verdict from the clock.
                    FlowChips(items: RecipeDifficulty.allCases.map(\.rawValue)) { label in
                        let level = RecipeDifficulty.allCases.first { $0.rawValue == label } ?? .easy
                        return SelectChip(active: difficultyOverride == level) {
                            difficultyOverride = difficultyOverride == level ? nil : level
                        } label: {
                            Text(label).plType(.footnote, .bold)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("Kind of dish")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RecipeCategory.allCases) { option in
                                selectChip(
                                    option.rawValue,
                                    icon: option.symbolName,
                                    active: category == option
                                ) {
                                    category = category == option ? nil : option
                                }
                            }
                        }
                    }
                }

                planningMetadataFields

                VStack(alignment: .leading, spacing: 8) {
                    MicroLabel("More photos")
                    Text("Keep the process, the finished plate, or what you’d change next time.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    extraPhotoStrip
                }
            }
            .padding(.top, 16)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("More details")
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                Text(detailsSummary)
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
            }
        }
        .tint(Color.inkSecondary)
        .padding(16)
        .background(Color.fill, in: Radius.shape(Radius.card))
    }

    private var planningMetadataFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            metadataTextField("Equipment", placeholder: "Oven, stovetop, air fryer…", text: $equipmentText)
            metadataTextField("Dietary labels", placeholder: "Vegetarian, vegan, gluten-free…", text: $dietaryLabelsText)
            Text("Separate labels with commas. Add them only when the recipe supports the claim.")
                .plType(.caption).foregroundStyle(Color.inkSecondary)

            metadataTextField("Known allergens", placeholder: "Peanuts, milk, sesame…", text: $allergenText)
            Text("This is recipe information, not an allergy-safety guarantee. Check the original ingredients and packaging.")
                .plType(.caption).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Nutrition per serving")
                HStack(spacing: 8) {
                    nutritionField("Calories", value: $caloriesText, unit: "kcal")
                    nutritionField("Protein", value: $proteinText, unit: "g")
                }
                HStack(spacing: 8) {
                    nutritionField("Carbs", value: $carbohydrateText, unit: "g")
                    nutritionField("Fat", value: $fatText, unit: "g")
                }
                metadataTextField("Nutrition source", placeholder: "Recipe label or data source", text: $nutritionSource)
                Text("Leave values blank when you do not have reliable nutrition data.")
                    .plType(.caption).foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private func metadataTextField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(label)
            TextField(placeholder, text: text, axis: .vertical)
                .plType(.body)
                .lineLimit(1...2)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                .focused($focused, equals: "metadata-\(label)")
                .plTapToFocus { focused = "metadata-\(label)" }
        }
    }

    private func nutritionField(_ label: String, value: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).plType(.caption, .semibold).foregroundStyle(Color.inkSecondary)
            HStack(spacing: 6) {
                TextField("Optional", text: value)
                    .keyboardType(.decimalPad)
                    .focused($focused, equals: "nutrition-\(label)")
                    .plType(.body)
                    .accessibilityLabel("\(label) per serving")
                Text(unit).plType(.caption).foregroundStyle(Color.inkSecondary)
            }
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Quick ingredient capture — "2 lb chicken thighs" in one line, parsed
    /// on the way in, so the grocery list has something real to build from.
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Ingredients")

            ForEach($draftIngredients) { $draft in
                IngredientRow(draft: $draft, focus: $focused) {
                    Haptic.tap()
                    withAnimation(.plSnap) {
                        draftIngredients.removeAll { $0.id == draft.id }
                    }
                }
                .id(draft.id)
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
                Toggle(isOn: $addToGroceries) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to this week's grocery list")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Text("\(draftIngredients.count == 1 ? "This" : "These") \(draftIngredients.count.things("ingredient")) \(draftIngredients.count == 1 ? "goes" : "go") on the list when you save.")
                            .plType(.caption)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Add ingredients to this week's grocery list")
                .sensoryFeedback(.selection, trigger: addToGroceries)
                .tint(Color.basil)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
                .transition(.plUnfold)
            }
        }
        .animation(.plSnap, value: draftIngredients.count)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MicroLabel("The steps")
                Spacer()
                Text("Hold to reorder").plType(.caption).foregroundStyle(Color.inkSecondary)
            }
            Text("Write what to add, the heat to use, how it should look, and how long it takes. Those details become the cook’s guide and timer shortcuts.")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach($draftSteps) { $step in
                let index = stepNumber(step) - 1
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 3) {
                        Text("\(index + 1)").plType(.footnote, .extraBold, family: .display)
                        Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .monospacedDigit().lineLimit(1).fixedSize()
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    .padding(.top, 4)
                    // Own the handle's drag before the scroll view's
                    // interactive keyboard-dismiss pan can claim it.
                    .highPriorityGesture(stepDragGesture(step.id))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Reorder step \(index + 1)")
                    .accessibilityIdentifier("recipe-step-handle-\(index + 1)")
                    .accessibilityHint("Hold and drag to another step. Move up and Move down are also available.")
                    .accessibilityActions {
                        Button("Move up") { moveStep(step.id, by: -1) }
                        Button("Move down") { moveStep(step.id, by: 1) }
                    }
                    EditableLine(text: $step.text, placeholder: "Step \(index + 1)", focus: $focused, focusID: step.id)
                        .accessibilityLabel("Step \(index + 1)")
                        .accessibilityIdentifier("recipe-step-field-\(index + 1)")
                    RemoveLineButton(label: "Remove step \(index + 1)") {
                        draftSteps.removeAll { $0.id == step.id }
                    }
                }
                .padding(.horizontal, 4)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: RecipeStepFrameKey.self,
                            value: [step.id: proxy.frame(in: .named("recipe-steps"))]
                        )
                    }
                }
                .background(stepDropTarget == step.id && draggingStep != step.id ? Color.oliveTint : Color.clear, in: Radius.shape(Radius.chip))
                .scaleEffect(draggingStep == step.id ? 1.015 : 1)
                .offset(y: draggingStep == step.id ? stepDragOffset.height : 0)
                .shadow(color: draggingStep == step.id ? Color.shadowInk.opacity(0.16) : .clear, radius: 14, y: 7)
                .zIndex(draggingStep == step.id ? 1 : 0)
                .id(step.id)
            }
            HStack(spacing: 8) {
                TextField(draftSteps.isEmpty ? "Heat the oil over medium for 2 minutes…" : "What happens next?", text: $stepEntry, axis: .vertical)
                    .plType(.body, .medium).lineLimit(1...3)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .onSubmit(addStep)
                    .focused($focused, equals: "new-step")
                    .plTapToFocus { focused = "new-step" }
                addRoundButton(disabled: stepEntry.trimmingCharacters(in: .whitespaces).isEmpty, label: "Add step", action: addStep)
            }
        }
        .coordinateSpace(name: "recipe-steps")
        .onPreferenceChange(RecipeStepFrameKey.self) { stepFrames = $0 }
        .animation(.plSnap, value: draftSteps.map(\.id))
    }

    private func addRoundButton(disabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        AddCircleButton(label: label, disabled: disabled, action: action)
    }

    private func addStep() {
        // Newlines, not just spaces. The entry field is `axis: .vertical`, so
        // Return both submits and leaves its newline in the text: every step
        // added by pressing Return carried a trailing blank line into the
        // recipe. Invisible while a step was drawn as `Text`; a step is a
        // field now, and the empty line is a hole in the middle of the list.
        let entry = stepEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        Haptic.tap()
        draftSteps.append(DraftStep(text: entry))
        stepEntry = ""
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
                    .background(.ultraThinMaterial, in: Radius.shape(Radius.chip))
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
                                    _ = withAnimation(.plSnap) {
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

    /// Saving waits for the photo to finish processing so a picked photo is
    /// never silently dropped.
    private var canSave: Bool {
        if pendingGroceryRecipe != nil { return true }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !photoLoading
            && (editing?.isEditableByCurrentDevice != false)
    }

    private var nextOpenNight: Date? {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            .first { date in
                !PlanOccupancy.isOccupied(on: date, slot: .dinner, local: meals)
            }
    }

    private func nightLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func commaSeparated(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: Save

    private func save(plating night: Date?) {
        // The buttons that open this editor enforce the same rule. Keep the
        // write guarded too in case permission changes while the sheet is
        // open, or a future route presents the editor directly.
        guard editing?.isEditableByCurrentDevice != false else { return }

        if let pendingGroceryRecipe {
            if addGroceries(for: pendingGroceryRecipe) { onSaved(pendingGroceryRecipe); dismiss() }
            return
        }

        if let night, PlanOccupancy.isOccupied(on: night, slot: .dinner, local: meals) {
            saveProblem = "That night has just been planned. Save the recipe, then choose another night."
            return
        }

        // Text still sitting in the step field is work the user typed and
        // believes is in — "type the last step, hit Save" used to drop it,
        // and the loss surfaced days later at the stove.
        addStep()
        Haptic.plate()
        let insertedBefore = Set(context.insertedModelsArray.map(\.persistentModelID))
        let recipe = editing ?? Recipe()
        let original = editing.map(RecipeEditSnapshot.init)
        recipe.title = title.trimmingCharacters(in: .whitespaces)
        recipe.summary = summary.trimmingCharacters(in: .whitespaces)
        recipe.servings = serves
        // Only when the dial actually moved. Comparing against the
        // recipe's own total wasn't enough: the dial floors at 15, so a
        // 10-minute dish loaded as 15 and an untouched save fabricated a
        // 7/8 split. Prongsby then reads those numbers back aloud.
        // What was typed, and nothing else. These used to be one picker's
        // answer halved, so a 25-minute dish stored prep 12 / cook 13 and
        // Prongsby read those invented halves out loud.
        recipe.prepMinutes = prepMinutes
        recipe.cookMinutes = cookMinutes
        // Recipes are mirrored through the household zone. Keep the stored
        // visibility aligned with where the record actually travels. A new
        // household recipe is collaborative by default; editing an existing
        // one preserves the creator's collaboration choice.
        recipe.visibility = "household"
        if editing == nil { recipe.householdCanEdit = true }
        recipe.photoData = photoData
        recipe.categoryValue = category
        recipe.mealTypeValue = mealType
        // Editing a step can leave it blank, and a blank step is not a step.
        // Nothing else in the app can produce one, so this is the only place
        // it has to be caught.
        recipe.steps = draftSteps
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        recipe.cookNotes = cookNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let nutritionAttribution = nutritionSource.trimmingCharacters(in: .whitespacesAndNewlines)
        RecipePlanningMetadata(
            equipment: Self.commaSeparated(equipmentText),
            dietaryLabels: Self.commaSeparated(dietaryLabelsText),
            knownAllergens: Self.commaSeparated(allergenText),
            caloriesPerServing: nutritionAttribution.isEmpty ? 0 : (Int(caloriesText) ?? 0),
            proteinGramsPerServing: nutritionAttribution.isEmpty ? 0 : (Double(proteinText) ?? 0),
            carbohydrateGramsPerServing: nutritionAttribution.isEmpty ? 0 : (Double(carbohydrateText) ?? 0),
            fatGramsPerServing: nutritionAttribution.isEmpty ? 0 : (Double(fatText) ?? 0),
            nutritionSource: nutritionAttribution
        ).apply(to: recipe)
        if let difficultyOverride {
            recipe.difficultyValue = difficultyOverride
        }
        if let prefill { recipe.originID = prefill.originID }

        // Rebuild children wholesale — simpler than diffing, and cascade
        // delete keeps the store clean.
        recipe.ingredients = []
        // An edited row can be left blank, and a blank row is not an
        // ingredient.
        recipe.ingredients = draftIngredients
            .map(\.resolved)
            .filter { !$0.name.isEmpty }
            .enumerated().map { index, item in
                let ingredient = Ingredient(
                    name: item.name, quantity: item.quantity, unit: item.unit,
                    aisle: item.aisle, isPantryStaple: item.isPantryStaple,
                    sortIndex: index
                )
                ingredient.package = item.package
                return ingredient
            }
        recipe.extraPhotos = []
        recipe.extraPhotos = extraPhotoData.enumerated().map { index, data in
            RecipePhoto(photoData: data, sortIndex: index)
        }

        if !isEditing {
            context.insert(recipe)
            // Save-from-table announces via .saveReceived in the feed's
            // finishSave — a second "joined the cookbook" line would double
            // the bell for one action.
            if prefill == nil {
                let owner = members.me?.name ?? "Someone"
                Notifier.post(
                    .recipeAdded, actor: owner,
                    body: "You added \(recipe.title) to the cookbook.",
                    into: context
                )
            }
        }

        if let night {
            let cook = members.first { $0.cookWeekdays.contains(Calendar.current.component(.weekday, from: night)) }
                ?? members.me
            context.insert(PlannedMeal(
                date: night, slot: .dinner, recipe: recipe,
                servings: serves, cook: cook
            ))
        }
        guard Persist.save(context, "save recipe") else {
            if let original { original.restore(in: context) }
            else {
                let inserted = context.insertedModelsArray.filter { !insertedBefore.contains($0.persistentModelID) }
                for model in inserted { context.delete(model) }
            }
            let message = "Couldn't save the recipe yet. Your work is still here."
            saveProblem = message
            Haptic.warn()
            AccessibilityNotification.Announcement(message).post()
            return
        }
        original?.retireReplacedChildren(in: context)
        if !isEditing && addToGroceries && night == nil && !hidePlateShortcut {
            guard addGroceries(for: recipe) else { pendingGroceryRecipe = recipe; return }
        }
        onSaved(recipe)
        dismiss()
    }

    private func addGroceries(for recipe: Recipe) -> Bool {
        do {
            _ = try RecipeGroceryWriter.add(recipe: recipe, in: context)
            saveProblem = nil
            return true
        } catch {
            saveProblem = "The recipe is saved. Groceries couldn't be added yet. Retry, or close and add them from the recipe later."
            return false
        }
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
        // Scale 1, explicitly. `UIGraphicsImageRenderer(size:)` with no format
        // takes the device's default, whose scale is the screen's — 3 on these
        // phones — while `UIImage(data:)` comes back at scale 1, so `size` is
        // already in pixels and the renderer multiplied them again. A photo
        // this function promises to hold at 1200px was written at 3600,
        // roughly six to nine times the bytes, into external storage and on to
        // CloudKit, with a ~39MB transient bitmap on the way. The Table's
        // composer borrows this function, so the inflated blobs crossed the
        // shared zone too. Every other renderer in the app sets this.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}

/// One ingredient, editable as the line somebody would type.
///
/// The list used to be a `Text` and an `xmark`, so a wrong quantity meant
/// deleting the row and retyping the whole thing — the same complaint the
/// steps earned, one section up.
///
/// It edits as a single line rather than as three fields because that is the
/// shape these arrive in: pasted, "2 cups flour". A correction goes back
/// through `parseIngredientLine`, the same parser the entry field below runs,
/// so a fixed line and a fresh one end up in identical shape.
///
/// The field writes the text and nothing else, straight through the binding.
/// Parsing on the way in would fight the person typing: "2 c" would round-trip
/// into something else under the cursor. Parsing on the way out, through a
/// second hop, drops the last keystroke. So the line is what gets stored, and
/// `DraftIngredient.resolved` reads it once, at save.
private struct IngredientRow: View {
    @Binding var draft: RecipeEditorView.DraftIngredient
    var focus: FocusState<AnyHashable?>.Binding
    var onRemove: () -> Void
    @State private var packageExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                EditableLine(text: Binding(
                    get: { draft.text },
                    set: { draft.edited = $0 }
                ), placeholder: "Ingredient", focus: focus, focusID: draft.id)
                RemoveLineButton(
                    label: "Remove \(draft.resolved.name.isEmpty ? "ingredient" : draft.resolved.name)",
                    action: onRemove
                )
            }
            DisclosureGroup(isExpanded: $packageExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        numericField("Package size", text: packageSize)
                        TextField("Unit (g, ml, each)", text: packageUnit)
                            .plType(.body)
                            .textInputAutocapitalization(.never)
                            .padding(10)
                            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    }
                    HStack(spacing: 8) {
                        numericField("Price", text: packagePrice)
                        TextField("Store", text: packageStore)
                            .plType(.body)
                            .padding(10)
                            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    }
                    TextField("Price source (label, receipt, catalog)", text: packageSource)
                        .plType(.body)
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    HStack {
                        Text(draft.package.updatedAt.map { "Price checked \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No current price date")
                            .plType(.caption)
                            .foregroundStyle(Color.inkSecondary)
                        Spacer()
                        Button("Mark current") {
                            draft.package.updatedAt = .now
                        }
                        .plType(.caption, .bold)
                        .foregroundStyle(Color.accentText)
                        .disabled(!packageFieldsAreComplete)
                    }
                    Text("Optional package data enables a store-specific estimate. Plated will not infer a price from recipe quantities.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            } label: {
                Text("Package and price info")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            .tint(Color.inkSecondary)
        }
        .padding(.horizontal, 4)
    }

    private var packageSize: Binding<String> {
        Binding(
            get: { draft.package.size.map { String($0) } ?? "" },
            set: { draft.package.size = Double($0) }
        )
    }

    private var packagePrice: Binding<String> {
        Binding(
            get: { draft.package.price.map { String($0) } ?? "" },
            set: { draft.package.price = Double($0) }
        )
    }

    private var packageUnit: Binding<String> {
        Binding(get: { draft.package.unit }, set: { draft.package.unit = $0 })
    }

    private var packageStore: Binding<String> {
        Binding(get: { draft.package.store }, set: { draft.package.store = $0 })
    }

    private var packageSource: Binding<String> {
        Binding(get: { draft.package.source }, set: { draft.package.source = $0 })
    }

    private var packageFieldsAreComplete: Bool {
        guard let size = draft.package.size, size > 0,
              let price = draft.package.price, price >= 0 else { return false }
        return !draft.package.unit.isEmpty && !draft.package.store.isEmpty && !draft.package.source.isEmpty
    }

    private func numericField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .plType(.body)
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
            .frame(maxWidth: .infinity)
    }
}
