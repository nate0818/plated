import SwiftUI
import SwiftData
import PhotosUI

/// The + sheet. A recipe here is a photo you took, a name, three facts,
/// and a decision about who gets to see it. Ninety seconds, tops.
struct NewRecipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var meals: [PlannedMeal]

    @State private var title = ""
    @State private var minutes = 25
    @State private var serves = 4
    @State private var visibility = "household"
    @State private var householdCanEdit = true
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoLoading = false
    @State private var category: RecipeCategory?
    @State private var difficultyOverride: RecipeDifficulty?
    @State private var draftIngredients: [DraftIngredient] = []
    @State private var ingredientEntry = ""
    @State private var addToGroceries = true

    private let minuteChoices = [15, 25, 40, 60, 90]

    struct DraftIngredient: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("New recipe")
                    .font(.gabarito(19, .extraBold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    photoWell

                    TextField("Name the dish", text: $title)
                        .font(.gabarito(27, .extraBold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.ink)
                        .tint(Color.tomato)
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.hairline).frame(height: 2)
                        }

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(minuteChoices, id: \.self) { choice in
                                Button("\(choice) min") { minutes = choice }
                            }
                        } label: {
                            factCard("Time", "\(minutes) min")
                        }
                        Menu {
                            ForEach(1...12, id: \.self) { count in
                                Button("\(count)") { serves = count }
                            }
                        } label: {
                            factCard("Serves", "\(serves)")
                        }
                        Menu {
                            ForEach(RecipeDifficulty.allCases) { level in
                                Button(level.rawValue) { difficultyOverride = level }
                            }
                        } label: {
                            factCard("Effort", effectiveDifficulty.rawValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("What kind of dish")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(RecipeCategory.allCases) { option in
                                    categoryChip(option)
                                }
                            }
                        }
                    }

                    ingredientsSection

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Who can see it")
                        visibilityPicker
                        HStack {
                            Text("Household can edit")
                                .font(.jakarta(14, .semibold))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Toggle("", isOn: $householdCanEdit)
                                .labelsHidden()
                                .tint(Color.basil)
                        }
                        .padding(.horizontal, 4)
                        .opacity(visibility == "private" ? 0.35 : 1)
                        .disabled(visibility == "private")
                        Text(editCaption)
                            .font(.jakarta(12, .medium))
                            .foregroundStyle(Color.inkFaint)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                TomatoPillButton(title: "Save to cookbook", systemImage: "circle.circle") {
                    save(plating: nil)
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
                if let night = nextOpenNight {
                    Button {
                        save(plating: night)
                    } label: {
                        Text("Save & plate it for \(nightLabel(night))")
                            .font(.jakarta(13, .semibold))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
    }

    // MARK: Pieces

    private var effectiveDifficulty: RecipeDifficulty {
        difficultyOverride ?? RecipeDifficulty.from(minutes: minutes)
    }

    private func categoryChip(_ option: RecipeCategory) -> some View {
        let active = category == option
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) { category = active ? nil : option }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 11, weight: .bold))
                Text(option.rawValue)
                    .font(.jakarta(13, .bold))
            }
            .fixedSize()
            .foregroundStyle(active ? Color.canvas : Color.ink)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background {
                if active {
                    Capsule().fill(Color.ink)
                } else {
                    Capsule().strokeBorder(Color.hairline)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Quick ingredient capture — "2 lb chicken thighs" in one line, parsed
    /// on the way in, so the grocery list has something real to build from.
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Ingredients")

            ForEach(draftIngredients) { draft in
                HStack {
                    Text(draft.name)
                        .font(.jakarta(14, .semibold))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text(draftQuantityText(draft))
                        .font(.jakarta(13, .medium))
                        .foregroundStyle(Color.inkSecondary)
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) {
                            draftIngredients.removeAll { $0.id == draft.id }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.inkFaint)
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 8) {
                TextField("Add one — “2 lb chicken thighs”", text: $ingredientEntry)
                    .font(.jakarta(14, .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                    .onSubmit(addIngredient)
                Button {
                    addIngredient()
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
                .buttonStyle(.plain)
                .disabled(ingredientEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !draftIngredients.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to this week's grocery list")
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.ink)
                        Text("These \(draftIngredients.count) items land in the basket when you save.")
                            .font(.jakarta(12, .medium))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $addToGroceries)
                        .labelsHidden()
                        .tint(Color.basil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.plSnap, value: draftIngredients.count)
    }

    private func addIngredient() {
        let entry = ingredientEntry.trimmingCharacters(in: .whitespaces)
        guard !entry.isEmpty else { return }
        Haptic.tap()
        draftIngredients.append(Self.parseIngredient(entry))
        ingredientEntry = ""
    }

    private func draftQuantityText(_ draft: DraftIngredient) -> String {
        var parts: [String] = []
        if draft.quantity > 0 { parts.append(Ingredient.format(draft.quantity)) }
        if !draft.unit.isEmpty { parts.append(draft.unit) }
        return parts.joined(separator: " ")
    }

    /// "2 lb chicken thighs" → (2, "lb", "chicken thighs"). Forgiving on
    /// purpose — anything unparseable is just a name.
    static func parseIngredient(_ entry: String) -> DraftIngredient {
        var tokens = entry.split(separator: " ").map(String.init)
        var quantity: Double = 0
        var unit = ""
        if let first = tokens.first, let value = Double(first) {
            quantity = value
            tokens.removeFirst()
            let knownUnits: Set<String> = [
                "lb", "lbs", "oz", "g", "kg", "cup", "cups", "tbsp", "tsp",
                "clove", "cloves", "can", "cans", "jar", "bottle", "bunch",
                "pint", "quart", "ball", "balls", "slice", "slices"
            ]
            if let next = tokens.first, knownUnits.contains(next.lowercased()) {
                unit = next
                tokens.removeFirst()
            }
        }
        let name = tokens.joined(separator: " ")
        return DraftIngredient(name: name.isEmpty ? entry : name, quantity: quantity, unit: unit)
    }

    private var photoWell: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
                        .plCardShadow()
                        .overlay(alignment: .topLeading) {
                            Text("YOUR PHOTO")
                                .font(.jakarta(11, .extraBold))
                                .tracking(0.7)
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(12)
                        }
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Retake")
                            .font(.jakarta(12, .bold))
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                } else {
                    RoundedRectangle(cornerRadius: Radius.hero)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "camera")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(Color.inkFaint)
                                Text("Add a photo of the plate")
                                    .font(.jakarta(15, .bold))
                                    .foregroundStyle(Color.inkSecondary)
                                Text("Your photo, your dish — no stock food here.")
                                    .font(.jakarta(12, .medium))
                                    .foregroundStyle(Color.inkFaint)
                            }
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func factCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.jakarta(10, .extraBold))
                .tracking(0.6)
                .foregroundStyle(Color.inkFaint)
            Text(value)
                .font(.jakarta(15, .bold))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
        .contentShape(Rectangle())
    }

    private var visibilityPicker: some View {
        HStack(spacing: 0) {
            visibilitySegment("private", label: "Just me", icon: "lock")
            visibilitySegment("household", label: "Household", icon: nil)
            visibilitySegment("table", label: "My Table", icon: nil)
        }
        .padding(2)
        .background(Color.hairlineSoft, in: Capsule())
    }

    private func visibilitySegment(_ value: String, label: String, icon: String?) -> some View {
        let active = visibility == value
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) { visibility = value }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold))
                }
                Text(label).font(.jakarta(13, .bold))
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
                        .shadow(color: Color.shadowWarm.opacity(0.12), radius: 4, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var editCaption: String {
        if visibility == "private" { return "Only you can see or change it." }
        let names = members.filter { !$0.isOwner }.map(\.name)
        guard householdCanEdit, !names.isEmpty else { return "Only you can change it." }
        let list = names.count > 1
            ? names.dropLast().joined(separator: ", ") + " and " + names.last!
            : names[0]
        return "\(list) can tweak it. Only you can delete it."
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
        Haptic.plate()
        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespaces),
            servings: serves,
            prepMinutes: minutes / 2,
            cookMinutes: minutes - minutes / 2
        )
        recipe.visibility = visibility
        recipe.householdCanEdit = visibility == "private" ? false : householdCanEdit
        recipe.photoData = photoData
        recipe.categoryValue = category
        if let difficultyOverride {
            recipe.difficultyValue = difficultyOverride
        }
        recipe.ingredients = draftIngredients.enumerated().map { index, draft in
            Ingredient(
                name: draft.name, quantity: draft.quantity, unit: draft.unit,
                aisle: Self.guessAisle(for: draft.name), sortIndex: index
            )
        }
        context.insert(recipe)

        // The ask that used to be a surprise: new ingredients go straight to
        // this week's basket when the cook says so. Manual lines survive the
        // auto-rebuild by design.
        if addToGroceries {
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
        }

        if let night {
            let cook = members.first { $0.cookWeekdays.contains(Calendar.current.component(.weekday, from: night)) }
                ?? members.first(where: \.isOwner)
            context.insert(PlannedMeal(
                date: night, slot: .dinner, recipe: recipe,
                servings: serves, cook: cook
            ))
        }
        dismiss()
    }

    /// A few obvious keywords beat asking the cook to file groceries by hand.
    /// Everything unrecognized lands in Other, which is where it would have
    /// gone anyway.
    static func guessAisle(for name: String) -> GroceryAisle {
        let lowered = name.lowercased()
        let table: [(GroceryAisle, [String])] = [
            (.meat, ["chicken", "beef", "steak", "pork", "salmon", "fish", "tuna", "shrimp", "turkey", "sausage", "bacon"]),
            (.dairy, ["milk", "butter", "cheese", "egg", "yogurt", "cream", "mozzarella", "parmesan"]),
            (.produce, ["lemon", "lime", "onion", "garlic", "pepper", "tomato", "avocado", "lettuce", "cucumber", "basil", "cilantro", "spinach", "carrot", "potato", "broccoli", "asparagus", "berries", "apple", "banana"]),
            (.bakery, ["bread", "dough", "bun", "tortilla", "bagel", "roll"]),
            (.frozen, ["frozen", "ice cream"]),
            (.beverages, ["juice", "soda", "wine", "beer", "coffee", "tea"]),
            (.pantry, ["rice", "pasta", "flour", "sugar", "oil", "sauce", "beans", "chickpea", "quinoa", "stock", "broth", "spice", "salt", "syrup", "vinegar", "can "])
        ]
        for (aisle, keywords) in table where keywords.contains(where: lowered.contains) {
            return aisle
        }
        return .other
    }

    /// Downscale to ~1200px and recompress — CloudKit charges by the byte.
    private static func processed(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
