import SwiftUI
import SwiftData

/// The cookbook — every dish the household knows, as plates on a white
/// table. Circles are dishes; the photo does the talking.
struct CookbookView: View {
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @State private var selected: Recipe?

    private var ordered: [Recipe] {
        recipes.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel("\(recipes.count) dishes")
                    Text("Cookbook")
                        .font(.gabarito(25, .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.ink)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], spacing: 26) {
                    ForEach(ordered, id: \.persistentModelID) { recipe in
                        recipeTile(recipe)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 110)
            }
        }
        .sheet(item: $selected) { recipe in
            RecipeDetailSheet(recipe: recipe)
        }
    }

    private func recipeTile(_ recipe: Recipe) -> some View {
        Button {
            Haptic.tap()
            selected = recipe
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    dishImage(recipe)
                    if recipe.isFavorite {
                        Circle()
                            .fill(Color.canvas)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.tomato)
                            }
                            .plDishShadow()
                            .offset(x: -4, y: 2)
                    }
                }
                VStack(spacing: 2) {
                    Text(recipe.title)
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(metaLine(recipe))
                        .font(.jakarta(12, .semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dishImage(_ recipe: Recipe) -> some View {
        Group {
            if let data = recipe.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
            } else {
                DishView(recipe: recipe, diameter: 140)
            }
        }
        .plDishShadow()
    }

    private func metaLine(_ recipe: Recipe) -> String {
        var parts: [String] = []
        if recipe.totalMinutes > 0 { parts.append("\(recipe.totalMinutes) min") }
        parts.append("Serves \(recipe.servings)")
        return parts.joined(separator: " · ")
    }
}

/// One dish, up close — photo hero, the facts, and "Plate it" to land it
/// on a night.
struct RecipeDetailSheet: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [PlannedMeal]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var dayPickerShown = false
    @State private var plateConfirmation: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .topLeading) {
                    heroImage
                    if recipe.photoData != nil {
                        Text("YOUR PHOTO")
                            .font(.jakarta(11, .extraBold))
                            .tracking(0.7)
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(12)
                    }
                }

                Text(recipe.title)
                    .font(.gabarito(27, .extraBold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.ink)

                HStack(spacing: 8) {
                    factCard("Time", recipe.totalMinutes > 0 ? "\(recipe.totalMinutes) min" : "—")
                    factCard("Serves", "\(recipe.servings)")
                    factCard("Effort", effortLabel)
                }

                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.jakarta(14, .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .lineSpacing(4)
                }

                HStack(spacing: 6) {
                    Image(systemName: visibilityIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(visibilityLine)
                        .font(.jakarta(12, .semibold))
                }
                .foregroundStyle(Color.inkFaint)

                if !recipe.sortedIngredients.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel("Ingredients")
                        ForEach(recipe.sortedIngredients, id: \.persistentModelID) { ingredient in
                            HStack {
                                Text(ingredient.name)
                                    .font(.jakarta(14, .semibold))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text(quantityText(ingredient))
                                    .font(.jakarta(13, .medium))
                                    .foregroundStyle(Color.inkSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 4)
                }

                TomatoPillButton(title: plateConfirmation ?? "Plate it") {
                    dayPickerShown = true
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .confirmationDialog("Which night?", isPresented: $dayPickerShown, titleVisibility: .visible) {
            ForEach(openNights, id: \.self) { date in
                Button(nightLabel(date)) { plate(on: date) }
            }
        }
    }

    private var heroImage: some View {
        Group {
            if let data = recipe.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
                    .plCardShadow()
            } else {
                HStack {
                    Spacer()
                    DishView(recipe: recipe, diameter: 200)
                    Spacer()
                }
            }
        }
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
    }

    private var effortLabel: String {
        switch recipe.totalMinutes {
        case 0: return "Easy"
        case ..<30: return "Easy"
        case ..<60: return "Weekend"
        default: return "Project"
        }
    }

    private var visibilityIcon: String {
        recipe.visibility == "private" ? "lock" : (recipe.visibility == "table" ? "person.3" : "house")
    }

    private var visibilityLine: String {
        switch recipe.visibility {
        case "private": return "Just you can see this"
        case "table": return "Your whole table can see this"
        default:
            return recipe.householdCanEdit
                ? "Household can see & edit"
                : "Household can see it"
        }
    }

    private func quantityText(_ ingredient: Ingredient) -> String {
        let qty = ingredient.quantity == ingredient.quantity.rounded()
            ? String(Int(ingredient.quantity))
            : String(format: "%.1f", ingredient.quantity)
        return ingredient.unit.isEmpty ? qty : "\(qty) \(ingredient.unit)"
    }

    private var openNights: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            .filter { date in
                !meals.contains { Calendar.current.isSameDay($0.date, date) && $0.slotValue == .dinner }
            }
    }

    private func nightLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func plate(on date: Date) {
        Haptic.plate()
        let cook = members.first { $0.cookWeekdays.contains(Calendar.current.component(.weekday, from: date)) }
            ?? members.first(where: \.isOwner)
        context.insert(PlannedMeal(
            date: date, slot: .dinner, recipe: recipe,
            servings: recipe.servings, cook: cook
        ))
        withAnimation(.plSnap) { plateConfirmation = "Plated for \(nightLabel(date))" }
        Task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }
}

/// Grid picker used from an open night's "Cookbook" chip.
struct RecipePickerSheet: View {
    let date: Date
    let onPick: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    var body: some View {
        VStack(spacing: 0) {
            Text(titleLine)
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(Color.ink)
                .padding(.top, 22)
                .padding(.bottom, 6)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(recipes, id: \.persistentModelID) { recipe in
                        Button {
                            onPick(recipe)
                            dismiss()
                        } label: {
                            VStack(spacing: 7) {
                                Group {
                                    if let data = recipe.photoData, let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 88, height: 88)
                                            .clipShape(Circle())
                                    } else {
                                        DishView(recipe: recipe, diameter: 88)
                                    }
                                }
                                .plDishShadow()
                                Text(recipe.title)
                                    .font(.jakarta(12, .bold))
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private var titleLine: String {
        if Calendar.current.isDateInToday(date) { return "What's for tonight?" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "What's for \(formatter.string(from: date))?"
    }
}
