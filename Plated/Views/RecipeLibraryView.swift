import SwiftUI
import SwiftData

struct RecipeLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var newRecipe: Recipe?
    @Namespace private var zoomNamespace

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Masthead(eyebrow: "The cookbook", title: "Recipes") {
                        Text(mastheadDatum)
                            .font(.caption.weight(.semibold))
                            .fontWidth(.condensed)
                            .tracking(1)
                            .monospacedDigit()
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.top, 8)

                    if filteredRecipes.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredRecipes) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeCard(recipe: recipe)
                                }
                                .buttonStyle(PressableCardStyle())
                                .matchedTransitionSource(id: recipe.persistentModelID, in: zoomNamespace)
                            }
                            InvitationCell(onAdd: addRecipe)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .scrollIndicators(.hidden)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
                    .navigationTransition(.zoom(sourceID: recipe.persistentModelID, in: zoomNamespace))
            }
            .searchable(text: $searchText, prompt: "Search recipes and ingredients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.appSnappy) { showFavoritesOnly.toggle() }
                    } label: {
                        Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(showFavoritesOnly ? Color.tomato : Color.ink)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add recipe", systemImage: "plus", action: addRecipe)
                        .foregroundStyle(Color.ink)
                }
            }
            .toolbarBackground(Color.canvas, for: .navigationBar)
            .tint(.ink)
            .sheet(item: $newRecipe) { recipe in
                NavigationStack {
                    RecipeEditorView(recipe: recipe)
                }
                .presentationCornerRadius(Radius.sheet)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(searchText.isEmpty ? "Your cookbook starts here." : "Nothing matched \"\(searchText)\".")
                .font(.cardTitle)
                .foregroundStyle(Color.ink)
            if searchText.isEmpty {
                Text("Add the dishes you actually cook — they become the building blocks of your week.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                Button("Add your first recipe", action: addRecipe)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tomato)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .padding(.top, 8)
    }

    private var mastheadDatum: String {
        let favorites = recipes.filter(\.isFavorite).count
        var parts = ["\(recipes.count) DISH\(recipes.count == 1 ? "" : "ES")"]
        if favorites > 0 { parts.append("\(favorites) FAVORITE\(favorites == 1 ? "" : "S")") }
        return parts.joined(separator: " · ")
    }

    private var filteredRecipes: [Recipe] {
        recipes.filter { recipe in
            if showFavoritesOnly && !recipe.isFavorite { return false }
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            if recipe.title.lowercased().contains(needle) { return true }
            if recipe.tags.contains(where: { $0.lowercased().contains(needle) }) { return true }
            return recipe.sortedIngredients.contains { $0.normalizedName.contains(needle) }
        }
    }

    private func addRecipe() {
        let recipe = Recipe(title: "")
        context.insert(recipe)
        newRecipe = recipe
    }
}

private struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DishView(recipe: recipe, diameter: 140)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tomato)
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                }
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(metadata)
                    .font(.system(size: 11, weight: .semibold))
                    .fontWidth(.condensed)
                    .tracking(1)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(14)
        }
        .cardSurface(radius: Radius.card)
    }

    private var metadata: String {
        var parts: [String] = []
        if recipe.totalMinutes > 0 { parts.append("\(recipe.totalMinutes) MIN") }
        parts.append("SERVES \(recipe.servings)")
        return parts.joined(separator: " · ")
    }
}

/// The grid's last cell is always an invitation, dashed like Plan's empty days.
private struct InvitationCell: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 12) {
                PlateView(state: .empty, diameter: 96)
                Text("Add a recipe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecipeLibraryView()
        .modelContainer(SampleData.previewContainer)
}
