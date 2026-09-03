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
                // Unknown effort ranks last rather than winning: an untimed
                // recipe derives "Easy" from a zero and used to take the top
                // of a sort it has told us nothing about.
                if lhs.difficultyIsKnown != rhs.difficultyIsKnown {
                    return lhs.difficultyIsKnown
                }
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
/// What the shelf keys its animation on.
///
/// `filter` and `total` alone left two orderings unaccounted for: a pin
/// outranks the sort and a favourite drives the default one, so toggling
/// either reorders the grid — while this key does not change, the scoped
/// `.animation(_:value:)` finds nothing to animate, and the tile teleports to
/// position zero with every tile below it jumping down. That the scoped
/// animation wins over an outer `withAnimation` in this subtree is measured
/// in this file's own history: keying on `filter` alone is what stopped
/// add/delete/import animating.
///
/// Both counts are computed over the `@Query` array, so neither runs
/// `filter.apply` and the performance constraint that shaped this key holds.
private struct FilterKey: Equatable {
    let filter: RecipeFilter
    let total: Int
    let pinned: Int
    let favorites: Int
}

/// A dish's name under its plate, in either grid.
///
/// Two reserved lines while there is a neighbour to line up with: reserving
/// is what keeps tiles on one baseline whether or not a name needs the second
/// line. At accessibility sizes the grid is a single column, so there is no
/// neighbour and no reason to stop at two — the name takes the lines it needs
/// rather than ending in an ellipsis with the whole width to itself.
///
/// File scope because two grids draw it. `RecipePickerSheet` never inherited
/// the shelf's version and stayed at one hard-limited line, on the one screen
/// whose entire job is choosing a dish by its name: at accessibility sizes a
/// 12pt caption sets near 37pt in a ~103pt column, which is two characters
/// and an ellipsis.
@ViewBuilder
func RecipeTileTitle(_ title: String, size: TypeScale, typeSize: DynamicTypeSize) -> some View {
    let text = Text(title)
        .plType(size, .bold)
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
    if typeSize.isAccessibilitySize {
        text.lineLimit(nil)
    } else {
        text.lineLimit(2, reservesSpace: true)
    }
}

/// The cookbook — every dish the household knows, as plates on a white
/// table. The "All dishes" chip is the whole control surface: tap it for
/// search, filters, and sort in one sheet.
struct CookbookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var recipes: [Recipe]
    @Environment(\.tabPop) private var tabPop
    @State private var selected: Recipe?
    @Environment(\.dynamicTypeSize) private var typeSize
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
    /// What this phone actually knows about the cookbook, as opposed to what
    /// it can draw. "Nothing in the cookbook yet" was asserted the instant
    /// the @Query came back empty, which on a second device is also the
    /// window while the mirror is still importing — and it is the one screen
    /// where being wrong reads as "your recipes are gone". Same machine as
    /// TableFeedView.Reach, same three states.
    @State private var reach: Reach = .looking

    private enum Reach { case looking, reached, unreachable }

    private var shown: [Recipe] { filter.apply(to: recipes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if !countLabel.isEmpty { MicroLabel(countLabel) }
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
                // Two chips in a header row are furniture: they hold a
                // fixed capsule and have nowhere to reflow, so uncapped
                // they grew until "Search and filter" read as "Searc...".
                // A chip that truncates its own verb is worse than a small
                // one. The grid below is content and keeps growing.
                .plChrome()
                .padding(.horizontal, 24)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    // Two columns is about 170pt a tile, and at AX5 a
                    // dish name sets at 47pt: "Sheet-pan chicken with
                    // charred lemon" could not fit two lines of that in
                    // half a screen, so the tile truncated to "Sheet...".
                    // A grid that cannot hold its own content is the wrong
                    // grid; at accessibility sizes it becomes one column
                    // and the name gets the whole width.
                    LazyVGrid(columns: tileColumns, spacing: 26) {
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
                    .animation(.plSnap, value: FilterKey(
                        filter: filter,
                        total: recipes.count,
                        pinned: recipes.reduce(0) { $0 + ($1.isPinned ? 1 : 0) },
                        favorites: recipes.reduce(0) { $0 + ($1.isFavorite ? 1 : 0) }
                    ))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, Layout.floatingChromeInset)

                    if shown.isEmpty {
                        // Two different nothings. A filter that matched
                        // nothing is a dead end you back out of; a cookbook
                        // with nothing in it is an invitation — and the old
                        // state answered both with one line and a filter
                        // glyph, the wrong icon for "you own no recipes".
                        //
                        // The corpus is tested first. `isFiltering` never
                        // consults `recipes`, and the filter chip is drawn
                        // whether or not there is anything to filter, so one
                        // tap on an empty cookbook turned the invitation into
                        // "Nothing matches that filter" whose only exit was
                        // "Clear filters" — losing both real ways in.
                        if recipes.isEmpty || !filter.isFiltering {
                            switch reach {
                            case .looking: stillLooking
                            case .reached: emptyCookbook
                            case .unreachable: cannotReach
                            }
                        } else {
                            noMatches
                        }
                    }
                }
            }
            .background(Color.canvas)
            .task { await look() }
            // A recipe arriving mid-import settles the question on its own.
            .onChange(of: recipes.count) { _, count in
                if count > 0 { reach = .reached }
            }
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
        // See TabPopRequest: tapping Recipes from inside a recipe returns
        // to the shelf.
        .onChange(of: tabPop) { _, request in
            guard request.tab == .cookbook else { return }
            selected = nil
            activityShown = false
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
            // "Deletes it for everyone" was a claim about a record that has
            // never left this account: recipes live in the private database,
            // and delete(_:) is a context.delete plus a title stamp onto the
            // nights it was planned for. Posting to the Table makes an
            // independent TablePost, which this does not touch, so the
            // sentence was false in both directions — and it contradicted
            // "Only you can see this" two taps away, in the direction that
            // implies the household had been reading your cookbook all along.
            Text("Nights it's planned on keep the name.")
        }
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.inkFaint)
            Text("Nothing matches that filter")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
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
    /// Still asking. A spinner and no words: the screen has no claim to make
    /// yet. `waitForImport` floors at 450ms, so this is a beat, not a wait.
    private var stillLooking: some View {
        ProgressView()
            .controlSize(.large)
            .padding(.top, 60)
            .accessibilityLabel("Looking for your recipes")
    }

    /// Asked and could not get an answer. Says so, rather than reporting the
    /// absence of an answer as an answer.
    private var cannotReach: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.inkFaint)
            Text("Couldn't check for your recipes")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text("What's here is what's on this phone.")
                .plType(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            Button {
                Haptic.tap()
                reach = .looking
                Task { await look() }
            } label: {
                Text("Try again")
                    .plType(.footnote, .semibold)
                    .foregroundStyle(Color.ink)
                    .plTapTarget()
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    /// One pass at the mirror, so the empty state knows which of the three it
    /// is. Recipes already on this phone are drawn immediately; this only
    /// decides what to say when there are none.
    private func look() async {
        guard recipes.isEmpty else { reach = .reached; return }
        switch await CloudSync.waitForImport() {
        case .arrived, .quiet: reach = .reached
        case .failed: reach = .unreachable
        }
    }

    private var emptyCookbook: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.inkFaint)
            Text("Nothing in the cookbook yet")
                // .body/.bold, like the other six empty headlines in the
                // app, including the identical sentence one sheet away in
                // RecipePickerSheet. This was the only one set a step up.
                .plType(.body, .bold)
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
                    // 56 and .callout, matching the TomatoPillButton
                    // directly above it. These are peers in one stack and
                    // the fill-versus-outline already carries which is
                    // primary; the 8pt height gap and the type step down
                    // carried nothing. Discover and the seats sheet already
                    // pair this filled/outlined couple at matched heights.
                    Text("Paste or scan")
                        .plType(.callout)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
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

    /// Empty when there is nothing to count.
    ///
    /// DESIGN.md retires the mounted zero by name — "0 plates", "COMMENTS ·
    /// 0" — because in a room this small a zero is not neutral, it is a
    /// verdict. "0 DISHES" over the word Recipes was the same shape, and it
    /// was the first thing a new cookbook said about itself. The empty state
    /// below already says it, warmly and with somewhere to go.
    private var countLabel: String {
        // Emptiness first. The filtering branch used to run before this test
        // and answered an empty cookbook with "0 of 0 dishes" — the mounted
        // zero this screen's own history says was removed for being a verdict
        // rather than a fact.
        guard !recipes.isEmpty else { return "" }
        if filter.isFiltering {
            return "\(shown.count) of \(recipes.count.things("dish", "dishes"))"
        }
        return recipes.count.things("dish", "dishes")
    }

    private var tileColumns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 20), GridItem(.flexible())]
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
                    RecipeTileTitle(recipe.title, size: .body, typeSize: typeSize)
                    Text(metaLine(recipe))
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .buttonStyle(.pressable)
        // Pinned and favourite decide this grid's order and were carried by
        // two unlabelled badges. A Button already combines its label, so an
        // explicit one is all this needs.
        .accessibilityLabel(
            [recipe.title, metaLine(recipe),
             recipe.isPinned ? "Pinned" : nil,
             recipe.isFavorite ? "Favorite" : nil]
                .compactMap { $0 }.joined(separator: ", ")
        )
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
    /// The masthead, the scroll content and the footer, measured separately
    /// and added. See the detent at the bottom of this view.
    @State private var mastheadHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mastheadHeight = $0 }

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
                                    // A bare 14pt glyph with no frame was
                                    // tappable across about 17pt, and a miss
                                    // fell through to the well's own
                                    // tap-to-focus and raised the keyboard
                                    // over the results.
                                    .plTapTarget()
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 14)
                    // A floor, not a height: `.body` reaches past 46 at
                    // accessibility sizes and the text separated from the
                    // stroke drawn around it. A search field is content, so
                    // it is not capped with .plChrome().
                    .frame(minHeight: 46)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    // A 46pt well whose tap target was the ~20pt text line
                    // inside it: the padding, the glyph and the bands above
                    // and below all swallowed the tap. `searchFocused` was
                    // declared and bound here and never once assigned, so
                    // nothing outside the text could raise the keyboard.
                    .plTapToFocus { searchFocused = true }

                    chipGroup("Meal", options: RecipeMealType.allCases, selection: $filter.mealType) { $0.rawValue }

                    if !presentGenres.isEmpty {
                        chipGroup("Kind of dish", options: presentGenres, selection: $filter.genre) { $0.rawValue }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Source")
                        // A bare HStack until now, so these three had nowhere
                        // to go when the type grew. Every other group on this
                        // sheet wraps.
                        FlowChips(items: RecipeFilter.Source.allCases.map(\.rawValue)) { label in
                            let source = RecipeFilter.Source.allCases.first { $0.rawValue == label } ?? .all
                            return chip(label, active: filter.source == source) {
                                filter.source = source
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
                // The scroll content is the only thing here whose height is
                // not already decided by the detent, so it is the only honest
                // thing to measure. Measuring a sibling of the ScrollView
                // measures the detent's own answer coming back around, and
                // the sheet walks itself taller every pass.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        // Sized to its own content. `.large` on a panel of three short chip
        // groups opened with five hundred points of nothing under the last
        // row, which reads as a page that failed to load rather than as a
        // filter. `.large` stays available for the type sizes that need it,
        // and the sheet grows into it on its own.
        .presentationDetents([.height(mastheadHeight + contentHeight + footerHeight), .large])
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
        SelectChip(active: active, action: action) {
            Text(label).plType(.footnote, .bold)
        }
    }
}

/// Wraps chips onto as many rows as they need.
struct FlowChips<Chip: View>: View {
    let items: [String]
    @ViewBuilder let chip: (String) -> Chip

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                chip(item)
            }
        }
    }
}

/// Rows of subviews, wrapped at whatever width they are given.
///
/// This used to be arithmetic: `CGFloat(item.count) * 8 + 34` measured
/// against a literal `330`. Both numbers describe a 13pt font on a 375pt
/// phone, and the chips are `.fixedSize()` so they cannot compress when the
/// guess is wrong. `plType` resolves through `Font.custom(_:relativeTo:
/// .body)`, whose range runs to 3.118x, so at accessibility sizes a footnote
/// chip sets near 40pt and a per-character estimate is out by a factor of
/// three. The overflow ran off the right edge of a vertical ScrollView, with
/// no horizontal scroll to reach what fell off it.
///
/// A Layout measures the real subviews against the real proposal, so both
/// magic numbers go away and Dynamic Type is handled for nothing.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, within: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: LayoutSubviews, within limit: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            // One chip wider than the whole row still gets a row of its own.
            // A chip that overflows can at least be read; a chip that is
            // never placed cannot.
            if !row.indices.isEmpty, needed > limit {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
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
                    // Answers the same way "Time" does when the number
                    // behind both of them is missing.
                    CountBlock(
                        value: recipe.difficultyIsKnown ? recipe.difficultyValue.rawValue : "Not set",
                        label: "Effort"
                    )
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
                // The pill fires its own haptic before running the action,
                // so opening the action with a second impact was two buzzes
                // for one press. It takes the parameter that exists for this.
                TomatoPillButton(title: "Cooked it", systemImage: "checkmark",
                                 haptic: Haptic.plate) {
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
            IconDiscButton(systemName: "chevron.left", label: "Back") {
                dismiss()
            }
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

            IconDiscButton(systemName: "square.and.arrow.up", label: "Share recipe") {
                sharePresented = true
            }

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
                // A floor. A hard 38 drew the capsule smaller than the label
                // inside it once footnote outgrew it.
                .frame(minHeight: 38)
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Edit recipe")

        }
        // A masthead's icon cluster is furniture with nowhere to reflow, the
        // same as the shelf header two hundred lines up, which caps itself
        // for exactly this reason. It changes what is drawn, never what
        // VoiceOver reads, and every control here already has a label.
        .plChrome()
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
    /// One answer to "which photo is showing", used by the hero and by the
    /// strip's selection ring.
    ///
    /// The hero read `shownPhoto ?? recipe.photoData` and never consulted the
    /// extras, while the strip only draws itself at two or more photos. So a
    /// recipe with no hero and one extra showed neither: a dashed "Add a
    /// photo" over a photograph already in the store. With two extras it drew
    /// the recipe's own photographs in a strip directly beneath the invitation
    /// to add one. The editor makes it a one-step mistake — the hero well and
    /// the extras well are independent, and nothing asks for a hero first.
    private var heroData: Data? {
        shownPhoto ?? recipe.photoData ?? recipe.sortedExtraPhotos.first?.photoData
    }

    private var heroImage: some View {
        Group {
            let data = heroData
            if let data, let image = UIImage(data: data) {
                PhotoWell(image: image, height: 260, cornerRadius: Radius.hero)
                    .plCardShadow()
            } else {
                Button {
                    Haptic.tap()
                    editorShown = true
                } label: {
                    // The words are the content and the dashes are drawn
                    // around them, not the other way round. A hard 210 with
                    // the text in an overlay clipped the caption to "It shows
                    // on your pla…" at accessibility sizes: a fixed height
                    // that exactly fits its content overflows on a real
                    // device, so this is a floor and the sentence wraps.
                    VStack(spacing: 12) {
                        DishView(recipe: recipe, diameter: 92)
                        VStack(spacing: 3) {
                            Text("Add a photo")
                                .plType(.body, .bold)
                                .foregroundStyle(Color.inkSecondary)
                            Text("It shows on your plan and on the tile.")
                                .plType(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 210)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                            .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
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
                    ForEach(Array(all.enumerated()), id: \.offset) { index, data in
                        if let image = UIImage(data: data) {
                            // Compared against the same value the hero draws,
                            // so the ringed thumbnail is the one on screen.
                            let isCurrent = heroData == data
                            Button {
                                Haptic.tap()
                                withAnimation(.plSnap) { shownPhoto = data }
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                            .strokeBorder(
                                                isCurrent ? Color.ink : Color.hairline,
                                                lineWidth: isCurrent ? 2 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.pressable)
                            // Which one is showing was carried by a 1pt
                            // hairline becoming a 2pt ink stroke, and by
                            // nothing else.
                            .accessibilityLabel("Photo \(index + 1) of \(all.count)")
                            .accessibilityAddTraits(isCurrent ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private var byline: String {
        var parts: [String] = [recipe.mealTypeValue.rawValue]
        if let genre = recipe.categoryValue { parts.append(genre.rawValue) }
        // Recipes are saved from Discover too, which is other households'
        // open tables — not this household's Table.
        if recipe.isImported { parts.append("Saved from a post") }
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

    // A recipe has never left this account, so this is a constant rather
    // than a lookup. There is no code path that puts a Recipe in a shared
    // zone, and the row used to say "Everyone on the Table can see this"
    // about a record living in the private database — the honesty rule in
    // DESIGN.md, and the most expensive kind of break because the reader has
    // no way to notice.
    //
    // The editor's Visibility picker wrote `visibility` and nothing read it;
    // it has been removed for the same reason. The property stays on the
    // model, written "private" on every save, because dropping a mirrored
    // property is not CloudKit-safe.
    private var visibilityIcon: String { "lock" }

    private var visibilityLine: String { "Only you can see this" }

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
                // A title wraps; it does not truncate. `.title` is 23pt, so
                // an ordinary dish name ran out of room on a 393pt phone at
                // the default size — and when the chosen night is occupied
                // the button reads "Replace <the displaced dish>", so with
                // this truncated nothing on the sheet named the dish being
                // planted. Both sibling sheets already omit the line limit.
                Text(recipe.title)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A single line never reached the edges; a wrapped one does.
            .padding(.horizontal, 24)
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
                        // The same predicate CookRotation opens with. This
                        // row was unfiltered, so it offered the pan to the
                        // people that file refuses to hand a night to, and
                        // then a push announced them as tonight's cook.
                        // Scrolls because six chips already walk off a 402pt
                        // screen, and two do at AX5.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(cookCandidates, id: \.persistentModelID) { member in
                                    cookChip(member)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollClipDisabled()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Once it reads "Plated for Tuesday" it is a receipt, not a
            // button — a second tap in the closing beat plated (and rang the
            // bell) twice. Disabling it said that, but `.disabled` is how
            // TomatoPillButton is told to wear "plainly not ready":
            // inkSecondary on fill. So the app's payoff beat spent its whole
            // closing second looking greyed out, and DESIGN.md names a seat
            // turning real as a moment that earns colour.
            //
            // A receipt is a different view, not a disabled button. The page
            // already owns this one, in basil, for the same kind of moment.
            // (`.contentTransition(.numericText())` went with the swap: it
            // spanned "Plan for Tuesday" → "Plated for Tuesday" and morphs
            // nothing that is not a numeral.)
            Group {
                if let confirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                        Text(confirmation)
                            .plType(.callout)
                    }
                    .foregroundStyle(Color.basil)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.basilTint, in: Capsule())
                    .accessibilityLabel(confirmation)
                } else {
                    TomatoPillButton(title: plateLabel) {
                        plate()
                    }
                    .disabled(chosenDate == nil)
                }
            }
            .animation(.plSnap, value: confirmation)
            .animation(.plSnap, value: chosenDate == nil)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .onAppear {
            chosenCook = cookCandidates.first(where: \.isOwner) ?? cookCandidates.first
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

    private var cookCandidates: [HouseholdMember] { members.filter(\.cooks) }

    /// A button is a verb that names the outcome. This one said "Plan for
    /// Saturday" over a Saturday that already had a dinner on it, and
    /// pressing it took that dinner away without ever having said so.
    private var plateLabel: String {
        guard let chosenDate else { return "Pick a night" }
        if let taken = dinner(on: chosenDate) { return "Replace \(taken.title)" }
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
        let cook = chosenCook ?? cookCandidates.first(where: \.isOwner) ?? cookCandidates.first
        if let existing = dinner(on: date) {
            // A gathering names the night and counts its guests; the recipe
            // is only what is being cooked at it. Blanking both turned
            // "Anna's birthday · Cooking for 12" into the dish's own title
            // while leaving the Gathering attached, so the night quietly
            // stopped looking like a party it was still hosting.
            let occasion = existing.gathering != nil
            existing.recipe = recipe
            existing.cook = cook
            if !occasion {
                existing.customTitle = ""
                existing.servings = recipe.servings
                existing.tagline = ""
            }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    private var pickerColumns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 18), GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(spacing: 0) {
            // The masthead the app's other seven sheets wear: an eyebrow
            // over a .title. This was a bare .heading with nothing above
            // it, and it opens from PlanNightSheet, which does it the
            // standard way — so one tap swapped the masthead for a
            // different one.
            VStack(spacing: 2) {
                MicroLabel("Your cookbook")
                Text(titleLine)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

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
                // Three across normally; one at accessibility sizes, where a
                // third of the width cannot hold a dish's name.
                LazyVGrid(columns: pickerColumns, spacing: 20) {
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
                                RecipeTileTitle(recipe.title, size: .caption, typeSize: typeSize)
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
