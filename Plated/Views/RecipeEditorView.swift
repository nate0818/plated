import SwiftUI
import SwiftData

struct RecipeEditorView: View {
    @Bindable var recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var tagText = ""

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Title", text: $recipe.title)
                TextField("One-line summary", text: $recipe.summary, axis: .vertical)
                TextField("Source URL", text: $recipe.sourceURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            Section("Timing") {
                Stepper("Serves \(recipe.servings)", value: $recipe.servings, in: 1...50)
                Stepper("Prep \(recipe.prepMinutes) min", value: $recipe.prepMinutes, in: 0...480, step: 5)
                Stepper("Cook \(recipe.cookMinutes) min", value: $recipe.cookMinutes, in: 0...720, step: 5)
            }

            Section {
                ForEach(recipe.sortedIngredients) { ingredient in
                    IngredientEditorRow(ingredient: ingredient)
                }
                .onDelete(perform: deleteIngredients)

                Button("Add ingredient", systemImage: "plus", action: addIngredient)
            } header: {
                Text("Ingredients")
            } footer: {
                Text("Mark pantry staples so they stay off the shopping list unless you ask for them.")
            }

            Section("Instructions") {
                TextField("Steps", text: $recipe.instructions, axis: .vertical)
                    .lineLimit(4...20)
            }

            Section("Good for") {
                ForEach(WeatherMood.allCases) { mood in
                    Toggle(isOn: moodBinding(mood)) {
                        Label(mood.title, systemImage: mood.symbolName)
                    }
                }
            }

            Section("Tags") {
                TextField("Comma separated", text: $tagText)
                    .onAppear { tagText = recipe.tags.joined(separator: ", ") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .tint(.tomato)
        .navigationTitle("Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    recipe.tags = tagText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    dismiss()
                }
            }
        }
    }

    private func moodBinding(_ mood: WeatherMood) -> Binding<Bool> {
        Binding(
            get: { recipe.weatherMoods.contains(mood.rawValue) },
            set: { isOn in
                if isOn {
                    if !recipe.weatherMoods.contains(mood.rawValue) {
                        recipe.weatherMoods.append(mood.rawValue)
                    }
                } else {
                    recipe.weatherMoods.removeAll { $0 == mood.rawValue }
                }
            }
        )
    }

    private func addIngredient() {
        let ingredient = Ingredient(sortIndex: (recipe.ingredients?.count ?? 0))
        ingredient.recipe = recipe
        context.insert(ingredient)
    }

    private func deleteIngredients(at offsets: IndexSet) {
        let sorted = recipe.sortedIngredients
        for index in offsets {
            context.delete(sorted[index])
        }
    }
}

private struct IngredientEditorRow: View {
    @Bindable var ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Ingredient", text: $ingredient.name)
            HStack {
                TextField("Qty", value: $ingredient.quantity, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 60)
                TextField("Unit", text: $ingredient.unit)
                    .frame(width: 80)
                Picker("Aisle", selection: Binding(
                    get: { ingredient.aisleValue },
                    set: { ingredient.aisleValue = $0 }
                )) {
                    ForEach(GroceryAisle.allCases) { aisle in
                        Text(aisle.rawValue).tag(aisle)
                    }
                }
                .labelsHidden()
            }
            .font(.callout)
            Toggle("Pantry staple", isOn: $ingredient.isPantryStaple)
                .font(.caption)
        }
    }
}
