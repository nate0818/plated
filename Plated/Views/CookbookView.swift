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
        case all = "All"
        case mine = "Mine"
        case imported = "Saved"
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
        return parts.isEmpty ? "Search and filter" : parts.joined(separator: " · ")
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
            // A pin outranks the sort. Choosing "A to Z" and finding your
            // pinned dish somewhere under S would defeat the point of
            // pinning it, so this sits outside the switch.
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
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

/// What the shelf's resettle animation keys on: the filter, and how many
/// dishes exist at all. Both change the layout; neither costs a filter pass.
private struct FilterKey: Equatable {
    let filter: RecipeFilter
    let total: Int
}

/// The cookbook — every dish the household knows, as plates on a white
/// table. The "All dishes" chip is the whole control surface: tap it for
/// search, filters, and sort in one sheet.
struct CookbookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @State private var selected: Recipe?
    @State private var filter = RecipeFilter()
    @State private var filterSheetShown = false
    @State private var importShown = false
    @State private var newRecipeShown = false
    @State private var activityShown = false
    /// Long-press destinations. A grid of plates can't be swiped — the rows
    /// are two wide — so the menu is where a tile's actions live.
    @State private var plating: Recipe?
    @State private var editing: Recipe?
    @State private var pendingDelete: Recipe?
    /// The dish you tapped is the dish that opens. Without a matched source
    /// the recipe page slid in from the right with no relationship to the
    /// plate under your finger, which is the single loudest way an app
    /// reads as a stack of screens rather than one place.
    @Namespace private var zoom

    private var shown: [Recipe] { filter.apply(to: recipes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        MicroLabel(countLabel)
                        Text("Recipes")
                            .plType(.display)
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
                                .plType(.footnote, .bold)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .accessibilityHidden(true)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(filter.isFiltering ? Color.canvas : Color.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
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
                                .accessibilityLabel("Clear filters")
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

                    // The tab bar's + can add a recipe, but it asks a
                    // question first and it is not on this screen when you
                    // are standing in front of a shelf thinking "I want to
                    // put a dish on here". Labelled rather than a bare
                    // glyph: a lone + beside a filter chip is read as "add a
                    // filter" at least as often as "add a recipe".
                    Button {
                        Haptic.tap()
                        newRecipeShown = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("Add")
                                .plType(.footnote, .bold)
                        }
                        // Outlined, not tomato. The tab bar's + is eight
                        // points below this and already wearing the accent;
                        // two red create buttons on one screen is two
                        // answers to the same question.
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Add a recipe")
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], spacing: 26) {
                        ForEach(shown, id: \.persistentModelID) { recipe in
                            recipeTile(recipe)
                                .transition(.plArrive)
                        }
                    }
                    // Filtering resettles the shelf — dishes fade and slide
                    // to their new seats instead of teleporting.
                    // Keyed on the FILTER, not on the result. Measured:
                    // `shown.count` re-ran the whole filter-and-sort exactly
                    // as `shown.map(\.persistentModelID)` did — three full
                    // passes per body pass on both — because `shown` is
                    // computed. The filter is the thing that actually
                    // changes when the shelf should resettle, and it is a
                    // cheap Equatable value.
                    // Filter AND the unfiltered count. Keying on `filter`
                    // alone removed a full filter-and-sort pass per body and
                    // fixed the same-count-different-dishes swap, but stopped
                    // animating add/delete/import — the shelf teleported.
                    // `recipes.count` is the @Query array's own count, so it
                    // costs nothing: it never runs `filter.apply`.
                    .animation(.plSnap, value: FilterKey(filter: filter, total: recipes.count))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, Layout.floatingChromeInset)

                    if shown.isEmpty {
                        // Two different nothings. A filter that matched
                        // nothing is a dead end you back out of; a cookbook
                        // with nothing in it is an invitation — and the old
                        // state answered both with one line and a filter
                        // glyph, the wrong icon for "you own no recipes".
                        if filter.isFiltering {
                            noMatches
                        } else {
                            emptyCookbook
                        }
                    }
                }
            }
            .background(Color.canvas)
            .navigationDestination(item: $selected) { recipe in
                RecipeDetailView(recipe: recipe)
                    .navigationTransition(.zoom(sourceID: recipe.persistentModelID, in: zoom))
            }
            .navigationDestination(isPresented: $activityShown) {
                NotificationsView()
            }
            .toolbar(.hidden, for: .navigationBar)
            .plSwipeBack()
        }
        .sheet(isPresented: $importShown) { RecipeImportSheet() }
        .sheet(isPresented: $newRecipeShown) { RecipeEditorView() }
        .sheet(isPresented: $filterSheetShown) {
            RecipeFilterSheet(filter: $filter, recipes: recipes)
        }
        .sheet(item: $plating) { recipe in
            PlateAssignSheet(recipe: recipe)
        }
        .sheet(item: $editing) { recipe in
            RecipeEditorView(editing: recipe)
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.title)?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let recipe = pendingDelete {
                Button("Delete", role: .destructive) { delete(recipe) }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("Deletes it for everyone. Nights it's planned on keep the name.")
        }
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.inkFaint)
            Text("Nothing matches that filter")
                .plType(.body, .bold)
                .foregroundStyle(Color.inkSecondary)
            Button {
                Haptic.tap()
                withAnimation(.plSnap) { filter = RecipeFilter() }
            } label: {
                Text("Clear filters")
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.top, 40)
    }

    /// An empty cookbook is the first thing a new household sees here, and
    /// "No recipes yet" only told them what they already knew. It now says
    /// what to do, why it's worth doing, and offers both ways in — the paste
    /// route included, which is why that no longer needs a button loitering
    /// in the header on every screen, full or empty.
    private var emptyCookbook: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.inkFaint)
            Text("Nothing in the cookbook yet")
                .plType(.heading)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text("Start with the one your household asks for most.")
                .plType(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                TomatoPillButton(title: "Add a recipe") { newRecipeShown = true }
                Button {
                    Haptic.tap()
                    importShown = true
                } label: {
                    Text("Paste or scan")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 34)
        .padding(.top, 44)
    }

    private var countLabel: String {
        filter.isFiltering
            ? "\(shown.count) of \(recipes.count) \(recipes.count == 1 ? "dish" : "dishes")"
            : "\(recipes.count) \(recipes.count == 1 ? "dish" : "dishes")"
    }

    private func recipeTile(_ recipe: Recipe) -> some View {
        Button {
            Haptic.tap()
            selected = recipe
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    dishImage(recipe)
                        .overlay(alignment: .topLeading) {
                            if recipe.isPinned {
                                Circle()
                                    .fill(Color.canvas)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.ink)
                                            .rotationEffect(.degrees(45))
                                    }
                                    .plDishShadow()
                                    .offset(x: 4, y: 2)
                            }
                        }
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
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(metaLine(recipe))
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .buttonStyle(.pressable)
        .matchedTransitionSource(id: recipe.persistentModelID, in: zoom)
        .contextMenu {
            Button {
                Haptic.plate()
                withAnimation(.plSnap) { recipe.isPinned.toggle() }
                Persist.save(context)
            } label: {
                Label(
                    recipe.isPinned ? "Unpin" : "Pin to top",
                    systemImage: recipe.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                plating = recipe
            } label: {
                Label("Plan it", systemImage: "circle.circle")
            }
            Button {
                Haptic.tap()
                withAnimation(.plSnap) { recipe.isFavorite.toggle() }
            } label: {
                Label(
                    recipe.isFavorite ? "Remove from favorites" : "Add to favorites",
                    systemImage: recipe.isFavorite ? "heart.slash" : "heart"
                )
            }
            Button {
                editing = recipe
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = recipe
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Planned nights keep a nullify rule, so a deleted dish would leave a
    /// blank row on the week. Stamp its name down first — the plan still
    /// says what everyone ate, it just stops linking to a dish that's gone.
    private func delete(_ recipe: Recipe) {
        Haptic.plate()
        for meal in recipe.plannedMeals ?? [] where meal.customTitle.isEmpty {
            meal.customTitle = recipe.title
        }
        withAnimation(.plSnap) {
            pendingDelete = nil
            context.delete(recipe)
        }
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
        if recipe.totalMinutes > 0 { parts.append(recipe.timeText) }
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
                MicroLabel("Your cookbook")
                Text("Search and filters")
                    .plType(.title)
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
                            .plType(.body, .medium)
                            .focused($searchFocused)
                        if !filter.searchText.isEmpty {
                            Button {
                                filter.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .accessibilityLabel("Clear search")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))

                    chipGroup("Meal", options: RecipeMealType.allCases, selection: $filter.mealType) { $0.rawValue }

                    if !presentGenres.isEmpty {
                        chipGroup("Kind of dish", options: presentGenres, selection: $filter.genre) { $0.rawValue }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Source")
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
                InkPillButton(title: "Done") { dismiss() }
                if filter.isFiltering {
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) { filter = RecipeFilter() }
                    } label: {
                        Text("Clear filters")
                            .plType(.footnote, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                            .plTapTarget()
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
                .plType(.footnote, .bold)
                .fixedSize()
                .foregroundStyle(active ? Color.canvas : Color.ink)
                .padding(.horizontal, 13)
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
/// ingredients, the numbered steps. "Plan it" rides the bottom edge,
/// always in reach, and asks who's cooking and when.
struct RecipeDetailView: View {
    let recipe: Recipe
    /// The plated night this page was opened from, when it was. A recipe
    /// reached from the cookbook is being considered — its job is "Plan it".
    /// The same recipe reached from a day it's already plated on is being
    /// cooked — offering to plate it again is a circle. With a meal in hand
    /// the page scales ingredients to that night's servings and the docked
    /// CTA becomes the one thing left to say: it got cooked.
    var meal: PlannedMeal? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var editorShown = false
    @State private var sharePresented = false
    @State private var assignShown = false
    @State private var swapShown = false
    @State private var shownPhoto: Data?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heroImage
                gallery

                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .plType(.display)
                        .foregroundStyle(Color.ink)
                    Text(byline)
                        .plType(.caption, .bold)
                        .foregroundStyle(Color.inkSecondary)
                }

                // The shared atoms, not a fourth dialect. A hairline box
                // around a number reads as a button that isn't one, and the
                // all-caps micro-type this used to wear is dashboard voice.
                HStack(spacing: 0) {
                    CountBlock(
                        value: recipe.totalMinutes > 0 ? recipe.timeText : "Not set",
                        label: "Time"
                    )
                    CountDivider()
                    CountBlock(value: "\(meal?.servings ?? recipe.servings)", label: "Serves")
                    CountDivider()
                    CountBlock(value: recipe.difficultyValue.rawValue, label: "Effort")
                }

                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                }

                if !ingredientRows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        MicroLabel(ingredientsLabel)
                        ForEach(ingredientRows, id: \.ingredient.persistentModelID) { row in
                            HStack {
                                Text(row.ingredient.name)
                                    .plType(.body)
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text(quantityText(row.ingredient, quantity: row.quantity))
                                    .plType(.footnote)
                                    .foregroundStyle(Color.inkSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 4)
                }

                if !recipe.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        MicroLabel("Steps")
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .plType(.callout, .bold, family: .display)
                                    .foregroundStyle(Color.inkSecondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(minWidth: 22, alignment: .trailing)
                                Text(step)
                                    .plType(.body, .medium)
                                    .foregroundStyle(Color.ink)
                            }
                        }
                    }
                    .padding(.top, 4)
                } else if !recipe.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Steps")
                        Text(recipe.instructions)
                            .plType(.body, .medium)
                            .foregroundStyle(Color.ink)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: visibilityIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(visibilityLine)
                        .plType(.caption, .semibold)
                }
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) {
            // Flush to the bottom, every screen size, never scrolled away.
            dockedCTA
                .padding(.horizontal, 24)
                .padding(.top, 8)
                // The bar rides over pushed pages and occupies the 4…72pt band;
                // a 6pt inset put the one committing CTA on this page directly
                // underneath it. `.hidesProngsbyPerch()` below clears the perch
                // but never touched the bar. Pre-existing — the last docked
                // control the token family hadn't reached.
                .padding(.bottom, Layout.tabBarInset)
                .background(Color.canvas.opacity(0.94))
        }
        // This page docks its own tomato CTA across the bottom; the perch
        // would sit right on top of it.
        .hidesProngsbyPerch()
        .sheet(isPresented: $sharePresented) {
            RecipeShareSheet(recipe: recipe)
        }
        .sheet(isPresented: $editorShown) {
            RecipeEditorView(editing: recipe)
        }
        .sheet(isPresented: $assignShown) {
            PlateAssignSheet(recipe: recipe)
        }
        .sheet(isPresented: $swapShown) {
            if let meal {
                PlanNightSheet(date: meal.date, slot: meal.slotValue)
            }
        }
    }

    /// One docked action, chosen by why you're here. Browse → "Plan it".
    /// Tonight's (or an unmarked past night's) plate → "Cooked it", which is
    /// the first and only writer of `cookedAt` this page has. A cooked plate
    /// → a quiet basil receipt that can take it back. A future night → the
    /// honest secondary, swapping the plate, in ink not tomato.
    @ViewBuilder
    private var dockedCTA: some View {
        if let meal {
            if meal.isCooked {
                Button {
                    Haptic.plate()
                    withAnimation(.plSnap) { meal.cookedAt = nil }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Cooked")
                            .plType(.callout)
                    }
                    .foregroundStyle(Color.basil)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.basilTint, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Cooked")
                .accessibilityHint("Marks it not cooked")
            } else if nightHasArrived {
                TomatoPillButton(title: "Cooked it", systemImage: "checkmark") {
                    Haptic.plate()
                    withAnimation(.plSnap) { meal.cookedAt = .now }
                }
            } else {
                InkPillButton(title: "Change the dish", systemImage: "arrow.2.squarepath") {
                    swapShown = true
                }
            }
        } else {
            TomatoPillButton(title: "Plan it", systemImage: "circle.circle") {
                assignShown = true
            }
        }
    }

    private var nightHasArrived: Bool {
        guard let meal else { return false }
        return meal.date <= Calendar.current.startOfDay(for: .now)
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
                            .accessibilityLabel("Back")
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
                            .accessibilityLabel(recipe.isFavorite ? "Remove from favorites" : "Add to favorites")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(recipe.isFavorite ? Color.tomato : Color.ink)
                            // The fill pours in. It does NOT thump: a
                            // symbol may morph into its own opposite, which
                            // is the state, and may not perform a flourish
                            // about the tap, which is not. See DESIGN.md.
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            Button {
                Haptic.tap()
                sharePresented = true
            } label: {
                Circle()
                    .strokeBorder(Color.hairline, lineWidth: 1.5)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel("Share recipe")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            // Labelled, not a lone pencil in a circle.
            //
            // It sat fourth in a row of four identical discs, so the only
            // thing distinguishing "change this recipe" from "share this
            // recipe" was a 14pt glyph, and a bare pencil is read as
            // "draw", "annotate" or "write a note" at least as often as
            // "edit". The other three are back, favourite and share, which
            // every phone has taught everybody. Edit had not earned the
            // same shorthand, so it says the word.
            Button {
                Haptic.tap()
                editorShown = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Edit")
                        .plType(.footnote, .bold)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Edit recipe")

        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .background(Color.canvas.opacity(0.94))
    }

    /// The photo, or an invitation to take one.
    ///
    /// A 200pt generated plate used to stand in for a missing photo, and at
    /// that size it is the page's whole first impression: a big abstract
    /// disc of colour derived from a hash of the title, which reads as an
    /// image of nothing. That is fine at thumbnail size in a list, where it
    /// is a marker distinguishing one row from the next — and it is exactly
    /// what a freshly imported recipe gets, because a recipe pasted from
    /// text has no photo by definition.
    ///
    /// So the empty state says what it is instead of pretending. The plate
    /// stays, small, as the mark; the well is hero-shaped so the page keeps
    /// its proportions whether or not there is a picture; and the whole
    /// thing is a button, because "there's no photo" and "add a photo" are
    /// the same thought.
    private var heroImage: some View {
        Group {
            let data = shownPhoto ?? recipe.photoData
            if let data, let image = UIImage(data: data) {
                PhotoWell(image: image, height: 260, cornerRadius: Radius.hero)
                    .plCardShadow()
            } else {
                Button {
                    Haptic.tap()
                    editorShown = true
                } label: {
                    RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)
                        .overlay {
                            VStack(spacing: 12) {
                                DishView(recipe: recipe, diameter: 92)
                                VStack(spacing: 3) {
                                    Text("Add a photo")
                                        .plType(.body, .bold)
                                        .foregroundStyle(Color.inkSecondary)
                                    Text("It shows on your plan and on the Table.")
                                        .plType(.caption)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }
                        }
                }
                .buttonStyle(.pressable)
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
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        if let meal {
            parts.append(platedLine(meal))
            if let cook = meal.cook {
                parts.append(cook.isOwner ? "You cook" : "\(cook.name) cooks")
            }
        } else if let next = nextPlannedNight {
            // Opened from the cookbook, so "Plan it" is still the right
            // offer — you may well want it twice. But the page said nothing
            // about the night this dish is already cooking on, which is the
            // one fact a reader standing here would most want.
            parts.append(platedLine(next))
        }
        return parts.joined(separator: " · ")
    }

    /// The soonest night this recipe is already plated on, today onward.
    /// Nights that have been and gone are history, not a heads-up.
    private var nextPlannedNight: PlannedMeal? {
        let today = Calendar.current.startOfDay(for: .now)
        return (recipe.plannedMeals ?? [])
            .filter { $0.date >= today }
            .min { $0.date < $1.date }
    }

    private func platedLine(_ meal: PlannedMeal) -> String {
        if Calendar.current.isDateInToday(meal.date) { return "Plated for tonight" }
        if Calendar.current.isDateInTomorrow(meal.date) { return "Plated for tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "Plated for \(formatter.string(from: meal.date))"
    }

    /// Quantities for the night actually being cooked. `scaledIngredients`
    /// existed on PlannedMeal from the start and nothing ever read it for
    /// display — the cook was silently shown the recipe's base servings no
    /// matter what the plan said.
    private var ingredientRows: [(ingredient: Ingredient, quantity: Double)] {
        if let meal, meal.recipe === recipe, meal.servings != recipe.servings,
           !meal.scaledIngredients.isEmpty {
            return meal.scaledIngredients
        }
        return recipe.sortedIngredients.map { ($0, $0.quantity) }
    }

    private var ingredientsLabel: String {
        if let meal, meal.recipe === recipe, meal.servings != recipe.servings {
            return "Ingredients · scaled for \(meal.servings)"
        }
        return "Ingredients"
    }

    private var visibilityIcon: String {
        recipe.visibility == "private" ? "lock" : (recipe.visibility == "table" ? "person.3" : "house")
    }

    private var visibilityLine: String {
        switch recipe.visibility {
        case "private": return "Only you can see this"
        case "table": return "Everyone on the Table can see this"
        default:
            return recipe.householdCanEdit
                ? "Your household can see and edit this"
                : "Your household can see this"
        }
    }

    private func quantityText(_ ingredient: Ingredient, quantity: Double) -> String {
        var parts: [String] = []
        if quantity > 0 { parts.append(Ingredient.format(quantity)) }
        let unit = Ingredient.unitText(ingredient.unit, for: quantity)
        if !unit.isEmpty { parts.append(unit) }
        return parts.joined(separator: " ")
    }
}

/// "Plan it" grown up: pick the night, pick the cook (you by default),
/// land the dish. Occupied nights swap the dish and keep their cook.
struct PlateAssignSheet: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [PlannedMeal]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var chosenDate: Date?
    @State private var chosenCook: HouseholdMember?
    /// A cook tapped by hand stays chosen. Without this, picking the cook
    /// first and the night second silently threw the hand-pick away in
    /// favour of the rotation's guess.
    @State private var cookPickedByHand = false
    @State private var confirmation: String?

    private var nights: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Plan a night")
                Text(recipe.title)
                    .plType(.title)
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
            // Once it reads "Plated for Tuesday" it is a receipt, not a
            // button — a second tap in the closing beat plated (and rang
            // the bell) twice.
            .disabled(chosenDate == nil || confirmation != nil)
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
                // The header promises occupied nights keep their cook — so
                // swapping Tuesday's dish must not move Tuesday off Maya.
                // The rotation only speaks when nobody else has.
                if !cookPickedByHand {
                    if let keeper = occupied?.cook {
                        chosenCook = keeper
                    } else if let suggested = CookRotation.cook(for: date, members: members, meals: meals) {
                        chosenCook = suggested
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(nightLabel(date))
                    .plType(.body, .bold)
                    .foregroundStyle(active ? Color.canvas : Color.ink)
                Spacer()
                if let occupied {
                    Text("\(occupied.title) planned")
                        .plType(.micro, .semibold)
                        .foregroundStyle(active ? Color.canvas.opacity(0.8) : Color.inkSecondary)
                        .lineLimit(1)
                } else {
                    Text("Open")
                        .plType(.micro)
                        .foregroundStyle(active ? Color.canvas.opacity(0.8) : Color.basil)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Color.ink)
                } else {
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func cookChip(_ member: HouseholdMember) -> some View {
        let active = chosenCook?.persistentModelID == member.persistentModelID
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) {
                chosenCook = member
                cookPickedByHand = true
            }
        } label: {
            VStack(spacing: 4) {
                AvatarCircle(initials: member.firstInitial, tone: member.isOwner ? .neutralPair : member.tone, size: 44,
                             photo: member.photoData)
                    .overlay {
                        if active {
                            Circle().strokeBorder(Color.ink, lineWidth: 2)
                        }
                    }
                Text(member.isOwner ? "You" : member.name)
                    .plType(.micro, active ? .extraBold : .semibold)
                    .foregroundStyle(active ? Color.ink : Color.inkSecondary)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var plateLabel: String {
        guard let chosenDate else { return "Pick a night" }
        return "Plan for \(nightLabel(chosenDate))"
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
            body: "\(nightLabel(date)): \(recipe.title). \(cookName.capitalized) cook\(cookName == "you" ? "" : "s").",
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
    /// Offered when the cookbook is empty. Without it this sheet is a title
    /// over a void whose only exit is a downward drag, reached from a row
    /// that promised "1 dish your household already knows".
    var onWriteNew: () -> Void = {}
    let onPick: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    var body: some View {
        VStack(spacing: 0) {
            Text(titleLine)
                .plType(.heading, .bold)
                .foregroundStyle(Color.ink)
                .padding(.top, 22)
                .padding(.bottom, 6)

            if recipes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                    Text("Nothing in the cookbook yet")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text("Add one and you can plan it in a tap.")
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    TomatoPillButton(title: "Add a recipe") {
                        dismiss()
                        onWriteNew()
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 34)
                .padding(.top, 36)
                Spacer()
            } else {
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
                                    .plType(.caption, .bold)
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
