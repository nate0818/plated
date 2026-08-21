import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecipeArt(recipe: recipe)
                    .aspectRatio(4 / 3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
                        .font(.screenTitle)
                        .foregroundStyle(Color.ink)

                    if !recipe.summary.isEmpty {
                        Text(recipe.summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                    }

                    HStack(spacing: 8) {
                        if recipe.totalMinutes > 0 {
                            MetaChip(icon: "clock", text: "\(recipe.totalMinutes) min")
                        }
                        MetaChip(icon: "person.2", text: "Serves \(recipe.servings)")
                        if recipe.timesCooked > 0 {
                            MetaChip(icon: "flame", text: "Cooked \(recipe.timesCooked)×")
                        }
                    }
                    .padding(.top, 4)

                    if !recipe.moods.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(recipe.moods) { mood in
                                HStack(spacing: 4) {
                                    Image(systemName: mood.symbolName)
                                        .font(.system(size: 10, weight: .medium))
                                    Text(mood.title)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(Color.basil)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.basil.wash(), in: Capsule())
                            }
                        }
                    }
                }

                if !recipe.sortedIngredients.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Ingredients")
                        VStack(spacing: 0) {
                            ForEach(Array(recipe.sortedIngredients.enumerated()), id: \.element.persistentModelID) { index, ingredient in
                                if index > 0 { Divider().overlay(Color.hairline) }
                                IngredientLine(ingredient: ingredient)
                            }
                        }
                        .padding(.horizontal, 16)
                        .cardSurface()
                    }
                }

                if !recipe.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Instructions")
                        Text(recipe.instructions)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .cardSurface()
                    }
                }

                if let last = recipe.lastCookedAt {
                    Text("Last cooked \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(Color.inkTertiary)
                }

                if !recipe.tags.isEmpty {
                    Text(recipe.tags.map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.appSnappy) { recipe.isFavorite.toggle() }
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(recipe.isFavorite ? Color.tomato : Color.ink)
                }
                .sensoryFeedback(.impact(weight: .light), trigger: recipe.isFavorite)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .foregroundStyle(Color.ink)
            }
        }
        .toolbarBackground(Color.canvas, for: .navigationBar)
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                RecipeEditorView(recipe: recipe)
            }
            .presentationCornerRadius(Radius.sheet)
        }
    }
}

private struct MetaChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(Color.inkSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.ink.opacity(0.05), in: Capsule())
    }
}

/// Semantic ingredient typography: quantity + unit semibold, name regular.
private struct IngredientLine: View {
    let ingredient: Ingredient

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if ingredient.quantity > 0 || !ingredient.unit.isEmpty {
                Text(quantityText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                    .frame(minWidth: 64, alignment: .leading)
            }
            Text(ingredient.name)
                .font(.subheadline)
                .foregroundStyle(Color.ink)
            Spacer()
            if ingredient.isPantryStaple {
                Text("staple")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .padding(.vertical, 10)
    }

    private var quantityText: String {
        var parts: [String] = []
        if ingredient.quantity > 0 { parts.append(Ingredient.format(ingredient.quantity)) }
        if !ingredient.unit.isEmpty { parts.append(ingredient.unit) }
        return parts.joined(separator: " ")
    }
}
