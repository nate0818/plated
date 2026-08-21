import SwiftUI
import SwiftData

/// Sheet for filling an empty slot on the week plan — pick a recipe, or type a
/// freeform entry for takeout and leftovers.
struct RecipePickerView: View {
    let date: Date
    let slot: MealSlot

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query private var members: [HouseholdMember]

    @State private var searchText = ""
    @State private var customTitle = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Something else") {
                    HStack {
                        TextField("Takeout, leftovers, out to dinner…", text: $customTitle)
                        Button("Add") { addCustom() }
                            .disabled(customTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Recipes") {
                    ForEach(filteredRecipes) { recipe in
                        Button {
                            add(recipe)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.title)
                                    .foregroundStyle(.primary)
                                if !conflicts(for: recipe).isEmpty {
                                    Label(conflicts(for: recipe), systemImage: "exclamationmark.triangle")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                } else if recipe.totalMinutes > 0 {
                                    Text("\(recipe.totalMinutes) min · serves \(recipe.servings)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas)
            .searchable(text: $searchText, prompt: "Search recipes")
            .navigationTitle("\(slot.title) · \(date.formatted(.dateTime.weekday(.abbreviated).month().day()))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
    }

    private var filteredRecipes: [Recipe] {
        guard !searchText.isEmpty else { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private func conflicts(for recipe: Recipe) -> String {
        members.compactMap { member -> String? in
            let hits = recipe.conflicts(for: member)
            return hits.isEmpty ? nil : "\(member.name): \(hits.joined(separator: ", "))"
        }.joined(separator: " · ")
    }

    private func add(_ recipe: Recipe) {
        let meal = PlannedMeal(date: date, slot: slot, recipe: recipe, servings: recipe.servings)
        context.insert(meal)
        dismiss()
    }

    private func addCustom() {
        let meal = PlannedMeal(date: date, slot: slot, customTitle: customTitle.trimmingCharacters(in: .whitespaces))
        context.insert(meal)
        dismiss()
    }
}
