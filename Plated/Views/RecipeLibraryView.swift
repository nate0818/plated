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
                    Text("Recipes")
                        .font(.heroTitle)
                        .foregroundStyle(Color.ink)
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
            RecipeArt(recipe: recipe)
                .aspectRatio(4 / 3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: Radius.card,
                        topTrailingRadius: Radius.card,
                        style: .continuous
                    )
                )
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
                    .font(.system(.body, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(metadata)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(12)
        }
        .cardSurface(radius: Radius.card)
    }

    private var metadata: String {
        var parts: [String] = []
        if recipe.totalMinutes > 0 { parts.append("\(recipe.totalMinutes) min") }
        parts.append("Serves \(recipe.servings)")
        if recipe.timesCooked > 0 { parts.append("\(recipe.timesCooked)×") }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    RecipeLibraryView()
        .modelContainer(SampleData.previewContainer)
}
