import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @State private var isEditing = false

    var body: some View {
        List {
            if !recipe.summary.isEmpty {
                Section { Text(recipe.summary) }
            }

            Section("At a glance") {
                LabeledContent("Servings", value: "\(recipe.servings)")
                if recipe.prepMinutes > 0 { LabeledContent("Prep", value: "\(recipe.prepMinutes) min") }
                if recipe.cookMinutes > 0 { LabeledContent("Cook", value: "\(recipe.cookMinutes) min") }
                if let last = recipe.lastCookedAt {
                    LabeledContent("Last cooked", value: last.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("Times cooked", value: "\(recipe.timesCooked)")
            }

            if !recipe.moods.isEmpty {
                Section("Good for") {
                    ForEach(recipe.moods) { mood in
                        Label(mood.title, systemImage: mood.symbolName)
                    }
                }
            }

            Section("Ingredients") {
                if recipe.sortedIngredients.isEmpty {
                    Text("No ingredients yet").foregroundStyle(.secondary)
                } else {
                    ForEach(recipe.sortedIngredients) { ingredient in
                        HStack {
                            Text(ingredient.displayText)
                            Spacer()
                            if ingredient.isPantryStaple {
                                Text("staple")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !recipe.instructions.isEmpty {
                Section("Instructions") {
                    Text(recipe.instructions)
                }
            }

            if !recipe.tags.isEmpty {
                Section("Tags") {
                    Text(recipe.tags.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(recipe.isFavorite ? "Unfavorite" : "Favorite",
                       systemImage: recipe.isFavorite ? "heart.fill" : "heart") {
                    recipe.isFavorite.toggle()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                RecipeEditorView(recipe: recipe)
            }
        }
    }
}
