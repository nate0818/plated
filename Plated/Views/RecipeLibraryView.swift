import SwiftUI
import SwiftData

struct RecipeLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var newRecipe: Recipe?

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredRecipes) { recipe in
                    NavigationLink(value: recipe) {
                        RecipeRow(recipe: recipe)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .searchable(text: $searchText, prompt: "Search recipes and ingredients")
            .overlay {
                if filteredRecipes.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No recipes yet" : "No matches",
                        systemImage: "book",
                        description: Text(searchText.isEmpty
                            ? "Add the dishes you actually cook. They become the building blocks of your week."
                            : "Nothing matched \"\(searchText)\".")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Favorites", systemImage: showFavoritesOnly ? "heart.fill" : "heart", isOn: $showFavoritesOnly)
                        .toggleStyle(.button)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add recipe", systemImage: "plus", action: addRecipe)
                }
            }
            .sheet(item: $newRecipe) { recipe in
                NavigationStack {
                    RecipeEditorView(recipe: recipe)
                }
            }
        }
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(filteredRecipes[index])
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
                if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
            }
            HStack(spacing: 8) {
                if recipe.totalMinutes > 0 {
                    Label("\(recipe.totalMinutes) min", systemImage: "clock")
                }
                Label("\(recipe.servings)", systemImage: "person.2")
                if recipe.timesCooked > 0 {
                    Text("· cooked \(recipe.timesCooked)×")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RecipeLibraryView()
        .modelContainer(SampleData.previewContainer)
}
