import SwiftUI
import SwiftData

/// What the cookbook is currently showing. One value drives the "All
/// dishes" chip, the sheet, and the grid.
struct RecipeFilter: Equatable {
    var searchText = ""
    var mealType: RecipeMealType?
    var genre: RecipeCategory?
    var source: Source = .all
    var sort: Sort = .favoritesFirst

    enum Source: String, CaseIterable, Identifiable {
        case all = "Everything"
        case mine = "My recipes"
        case imported = "Saved from others"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case favoritesFirst = "Favorites first"
        case newest = "Newest"
        case quickest = "Quickest"
        case easiest = "Easiest"
        case mostLoved = "Most loved"
        case alphabetical = "A to Z"
        var id: String { rawValue }
    }

    var isFiltering: Bool {
        !searchText.isEmpty || mealType != nil || genre != nil || source != .all
    }

    /// What the header chip reads: the filter summary or the calm default.
    var chipLabel: String {
        var parts: [String] = []
        if let mealType { parts.append(mealType.rawValue) }
        if let genre { parts.append(genre.rawValue) }
        if source != .all { parts.append(source == .mine ? "Mine" : "Saved") }
        if !searchText.isEmpty { parts.append("“\(searchText)”") }
        return parts.isEmpty ? "All dishes" : parts.joined(separator: " · ")
    }

    func apply(to recipes: [Recipe]) -> [Recipe] {
        var result = recipes.filter { recipe in
            (mealType == nil || recipe.mealTypeValue == mealType)
                && (genre == nil || recipe.categoryValue == genre)
                && (source == .all
                    || (source == .mine && !recipe.isImported)
                    || (source == .imported && recipe.isImported))
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.summary.localizedCaseInsensitiveContains(searchText)
                    || $0.sortedIngredients.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result.sorted { lhs, rhs in
            switch sort {
            case .favoritesFirst:
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                return lhs.createdAt > rhs.createdAt
            case .newest: return lhs.createdAt > rhs.createdAt
            case .quickest: return lhs.totalMinutes < rhs.totalMinutes
            case .easiest:
                let l = lhs.difficultyValue.sortOrder, r = rhs.difficultyValue.sortOrder
                return l == r ? lhs.totalMinutes < rhs.totalMinutes : l < r
            case .mostLoved:
                let l = lhs.loveScore, r = rhs.loveScore
                return l == r ? lhs.createdAt > rhs.createdAt : l > r
            case .alphabetical:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

/// The cookbook — every dish the household knows, as plates on a white
/// table. The "All dishes" chip is the whole control surface: tap it for
/// search, filters, and sort in one sheet.
struct CookbookView: View {
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @State private var selected: Recipe?
    @State private var filter = RecipeFilter()
    @State private var filterSheetShown = false
    @State private var activityShown = false

    private var shown: [Recipe] { filter.apply(to: recipes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        MicroLabel(countLabel)
                        Text("Recipes")
                            .font(.gabarito(25, .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.ink)
                    }
                    Spacer()
                    ActivityBellButton {
                        activityShown = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)

                HStack(spacing: 8) {
                    Button {
                        Haptic.tap()
                        filterSheetShown = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .bold))
                            Text(filter.chipLabel)
                                .font(.jakarta(13, .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(filter.isFiltering ? Color.canvas : Color.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background {
                            if filter.isFiltering {
                                Capsule().fill(Color.ink)
                            } else {
                                Capsule().strokeBorder(Color.hairline, lineWidth: 1.5)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)

                    if filter.isFiltering {
                        Button {
                            Haptic.tap()
                            withAnimation(.plSnap) { filter = RecipeFilter() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.inkSecondary)
                                .frame(width: 38, height: 38)
                                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1.5))
                                .frame(minHeight: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.pressable)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], spacing: 26) {
                        ForEach(shown, id: \.persistentModelID) { recipe in
                            recipeTile(recipe)
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                    // Filtering resettles the shelf — dishes fade and slide
                    // to their new seats instead of teleporting.
                    .animation(.plSnap, value: shown.map(\.persistentModelID))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, Layout.floatingChromeInset)

                    if shown.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(Color.inkFaint)
                                .plBreathing()
                            Text(filter.isFiltering ? "Nothing matches that filter" : "No recipes yet")
                                .font(.jakarta(15, .bold))
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .padding(.top, 40)
                    }
                }
            }
            .background(Color.canvas)
            .navigationDestination(item: $selected) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .navigationDestination(isPresented: $activityShown) {
                NotificationsView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $filterSheetShown) {
            RecipeFilterSheet(filter: $filter, recipes: recipes)
        }
    }

    private var countLabel: String {
        filter.isFiltering ? "\(shown.count) of \(recipes.count) dishes" : "\(recipes.count) dishes"
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
        .buttonStyle(.pressable)
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
        parts.append(recipe.categoryValue?.rawValue ?? recipe.mealTypeValue.rawValue)
        return parts.joined(separator: " · ")
    }
}

/// Search, filter, and sort in one place — opened from the "All dishes"
/// chip, applied live, dismissed when done.
struct RecipeFilterSheet: View {
    @Binding var filter: RecipeFilter
    let recipes: [Recipe]

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    private var presentGenres: [RecipeCategory] {
        RecipeCategory.allCases.filter { option in
            recipes.contains { $0.categoryValue == option }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Find a dish")
                Text("Filter & sort")
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.inkFaint)
                        TextField("Search dishes and ingredients", text: $filter.searchText)
                            .font(.jakarta(14, .medium))
                            .focused($searchFocused)
                        if !filter.searchText.isEmpty {
                            Button {
                                filter.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))

                    chipGroup("Meal", options: RecipeMealType.allCases, selection: $filter.mealType) { $0.rawValue }

                    if !presentGenres.isEmpty {
                        chipGroup("Genre", options: presentGenres, selection: $filter.genre) { $0.rawValue }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Whose")
                        HStack(spacing: 8) {
                            ForEach(RecipeFilter.Source.allCases) { source in
                                chip(source.rawValue, active: filter.source == source) {
                                    filter.source = source
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Sort by")
                        FlowChips(items: RecipeFilter.Sort.allCases.map(\.rawValue)) { label in
                            let sort = RecipeFilter.Sort.allCases.first { $0.rawValue == label } ?? .favoritesFirst
                            return chip(label, active: filter.sort == sort) {
                                filter.sort = sort
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            VStack(spacing: 8) {
                InkPillButton(title: "Show dishes") { dismiss() }
                if filter.isFiltering {
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) { filter = RecipeFilter() }
                    } label: {
                        Text("Clear everything")
                            .font(.jakarta(13, .semibold))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    private func chipGroup<Option: Identifiable & Equatable>(
        _ label: String, options: [Option],
        selection: Binding<Option?>, title: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel(label)
            FlowChips(items: options.map { title($0) }) { name in
                let option = options.first { title($0) == name }
                return chip(name, active: selection.wrappedValue == option) {
                    selection.wrappedValue = selection.wrappedValue == option ? nil : option
                }
            }
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            Text(label)
                .font(.jakarta(13, .bold))
                .fixedSize()
                .foregroundStyle(active ? Color.canvas : Color.ink)
                .padding(.horizontal, 13)
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

/// Wraps chips onto as many rows as they need.
struct FlowChips<Chip: View>: View {
    let items: [String]
    @ViewBuilder let chip: (String) -> Chip

    var body: some View {
        var width: CGFloat = 0
        var rows: [[String]] = [[]]
        // Rough measure: 13pt bold Jakarta ≈ 8pt/char + 26 padding + 8 gap.
        for item in items {
            let itemWidth = CGFloat(item.count) * 8 + 34
            if width + itemWidth > 330 {
                rows.append([item])
                width = itemWidth
            } else {
                rows[rows.count - 1].append(item)
                width += itemWidth
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        chip(item)
                    }
                }
            }
        }
    }
}

/// One dish, the NYT-cooking way — hero and gallery, the facts, the
/// ingredients, the numbered steps. "Plate it" rides the bottom edge,
/// always in reach, and asks who's cooking and when.
struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var editorShown = false
    @State private var assignShown = false
    @State private var shownPhoto: Data?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heroImage
                gallery

                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(.gabarito(27, .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.ink)
                    Text(byline)
                        .font(.jakarta(12, .bold))
                        .foregroundStyle(Color.inkSecondary)
                }

                HStack(spacing: 8) {
                    factCard("Time", recipe.totalMinutes > 0 ? "\(recipe.totalMinutes) min" : "—")
                    factCard("Serves", "\(recipe.servings)")
                    factCard("Effort", recipe.difficultyValue.rawValue)
                }

                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.jakarta(14, .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .lineSpacing(4)
                }

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

                if !recipe.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        MicroLabel("The steps")
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.gabarito(17, .bold))
                                    .foregroundStyle(Color.inkFaint)
                                    .frame(width: 22, alignment: .trailing)
                                Text(step)
                                    .font(.jakarta(14, .medium))
                                    .foregroundStyle(Color.ink)
                                    .lineSpacing(3)
                            }
                        }
                    }
                    .padding(.top, 4)
                } else if !recipe.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("The method")
                        Text(recipe.instructions)
                            .font(.jakarta(14, .medium))
                            .foregroundStyle(Color.ink)
                            .lineSpacing(4)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: visibilityIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(visibilityLine)
                        .font(.jakarta(12, .semibold))
                }
                .foregroundStyle(Color.inkFaint)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) {
            // Flush to the bottom, every screen size, never scrolled away.
            TomatoPillButton(title: "Plate it", systemImage: "circle.circle") {
                assignShown = true
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(Color.canvas.opacity(0.94))
        }
        // This page docks its own tomato CTA across the bottom; the perch
        // would sit right on top of it.
        .hidesProngsbyPerch()
        .sheet(isPresented: $editorShown) {
            RecipeEditorView(editing: recipe)
        }
        .sheet(isPresented: $assignShown) {
            PlateAssignSheet(recipe: recipe)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptic.tap()
                dismiss()
            } label: {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            Spacer()

            Button {
                Haptic.tap()
                withAnimation(.plPop) { recipe.isFavorite.toggle() }
            } label: {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(recipe.isFavorite ? Color.tomato : Color.ink)
                            // The fill pours in and the heart gives a
                            // little thump — the plPop finally has a body.
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: recipe.isFavorite)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            ShareLink(item: shareText) {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            Button {
                Haptic.tap()
                editorShown = true
            } label: {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .background(Color.canvas.opacity(0.94))
    }

    private var heroImage: some View {
        Group {
            let data = shownPhoto ?? recipe.photoData
            if let data, let image = UIImage(data: data) {
                PhotoWell(image: image, height: 260, cornerRadius: Radius.hero)
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

    /// Every photo the dish has — tap one to make it the hero.
    @ViewBuilder
    private var gallery: some View {
        let all: [Data] = [recipe.photoData].compactMap { $0 } + recipe.sortedExtraPhotos.compactMap(\.photoData)
        if all.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(all.enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) {
                            Button {
                                Haptic.tap()
                                withAnimation(.plSnap) { shownPhoto = data }
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                (shownPhoto ?? recipe.photoData) == data ? Color.ink : Color.hairline,
                                                lineWidth: (shownPhoto ?? recipe.photoData) == data ? 2 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }
        }
    }

    private var byline: String {
        var parts: [String] = [recipe.mealTypeValue.rawValue]
        if let genre = recipe.categoryValue { parts.append(genre.rawValue) }
        if recipe.isImported { parts.append("Saved from the Table") }
        return parts.joined(separator: " · ").uppercased()
    }

    private var shareText: String {
        var lines: [String] = ["\(recipe.title) — from our Plated cookbook"]
        if !recipe.summary.isEmpty { lines.append(recipe.summary) }
        lines.append("Time: \(recipe.totalMinutes) min · Serves \(recipe.servings)")
        let ingredients = recipe.sortedIngredients
        if !ingredients.isEmpty {
            lines.append("")
            lines.append("Ingredients:")
            lines.append(contentsOf: ingredients.map { "• \($0.displayText)" })
        }
        if !recipe.steps.isEmpty {
            lines.append("")
            lines.append("Steps:")
            lines.append(contentsOf: recipe.steps.enumerated().map { "\($0 + 1). \($1)" })
        }
        return lines.joined(separator: "\n")
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
}

/// "Plate it" grown up: pick the night, pick the cook (you by default),
/// land the dish. Occupied nights swap the dish and keep their cook.
struct PlateAssignSheet: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [PlannedMeal]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var chosenDate: Date?
    @State private var chosenCook: HouseholdMember?
    @State private var confirmation: String?

    private var nights: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Plate it")
                Text(recipe.title)
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Which night")
                        ForEach(nights.prefix(10), id: \.self) { date in
                            nightRow(date)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Who cooks")
                        HStack(spacing: 10) {
                            ForEach(members, id: \.persistentModelID) { member in
                                cookChip(member)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(title: confirmation ?? plateLabel) {
                plate()
            }
            // "Plate it for Tuesday" → "Plated for Tuesday" morphs in place.
            .contentTransition(.numericText())
            .animation(.plSnap, value: confirmation)
            .disabled(chosenDate == nil)
            .opacity(chosenDate == nil ? 0.4 : 1)
            .animation(.plSnap, value: chosenDate == nil)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .onAppear {
            chosenCook = members.first(where: \.isOwner)
        }
    }

    private func nightRow(_ date: Date) -> some View {
        let occupied = dinner(on: date)
        let active = chosenDate == date
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) {
                chosenDate = date
                if let suggested = CookRotation.cook(for: date, members: members, meals: meals) {
                    chosenCook = suggested
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(nightLabel(date))
                    .font(.jakarta(14, .bold))
                    .foregroundStyle(active ? Color.canvas : Color.ink)
                Spacer()
                if let occupied {
                    Text("Swaps \(occupied.title)")
                        .font(.jakarta(11, .semibold))
                        .foregroundStyle(active ? Color.canvas.opacity(0.8) : Color.inkFaint)
                        .lineLimit(1)
                } else {
                    Text("Open")
                        .font(.jakarta(11, .bold))
                        .foregroundStyle(active ? Color.canvas.opacity(0.8) : Color.basil)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: Radius.chip).fill(Color.ink)
                } else {
                    RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private func cookChip(_ member: HouseholdMember) -> some View {
        let active = chosenCook?.persistentModelID == member.persistentModelID
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) { chosenCook = member }
        } label: {
            VStack(spacing: 4) {
                AvatarCircle(initials: member.firstInitial, tone: member.isOwner ? .neutralPair : member.tone, size: 44)
                    .overlay {
                        if active {
                            Circle().strokeBorder(Color.ink, lineWidth: 2)
                        }
                    }
                Text(member.isOwner ? "You" : member.name)
                    .font(.jakarta(11, active ? .extraBold : .semibold))
                    .foregroundStyle(active ? Color.ink : Color.inkSecondary)
            }
        }
        .buttonStyle(.pressable)
    }

    private var plateLabel: String {
        guard let chosenDate else { return "Pick a night" }
        return "Plate for \(nightLabel(chosenDate))"
    }

    private func dinner(on date: Date) -> PlannedMeal? {
        meals.first { Calendar.current.isSameDay($0.date, date) && $0.slotValue == .dinner }
    }

    private func nightLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func plate() {
        guard let date = chosenDate else { return }
        Haptic.plate()
        let cook = chosenCook ?? members.first(where: \.isOwner)
        if let existing = dinner(on: date) {
            existing.recipe = recipe
            existing.customTitle = ""
            existing.servings = recipe.servings
            existing.cook = cook
            existing.tagline = ""
        } else {
            context.insert(PlannedMeal(
                date: date, slot: .dinner, recipe: recipe,
                servings: recipe.servings, cook: cook
            ))
        }
        let cookName = (cook?.isOwner ?? true) ? "you" : (cook?.name ?? "someone")
        Notifier.post(
            .mealPlanned, actor: cook?.name ?? "",
            body: "\(recipe.title) is plated for \(nightLabel(date).lowercased()) — \(cookName) cook\(cookName == "you" ? "" : "s").",
            into: context
        )
        withAnimation(.plSnap) { confirmation = "Plated for \(nightLabel(date))" }
        Task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }
}

/// Grid picker used from an open night's "Your recipes" chip.
struct RecipePickerSheet: View {
    let date: Date
    let onPick: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    var body: some View {
        VStack(spacing: 0) {
            Text(titleLine)
                .font(.gabarito(19, .bold))
                .foregroundStyle(Color.ink)
                .padding(.top, 22)
                .padding(.bottom, 6)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(recipes, id: \.persistentModelID) { recipe in
                        Button {
                            Haptic.tap()
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
                        .buttonStyle(.pressable)
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
