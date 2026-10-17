import Foundation
import SwiftData

/// Restores only this recipe, preserving unrelated pending work and child identities.
/// Old children stay attached to the snapshot until the replacement commits.
@MainActor
final class RecipeEditSnapshot {
    private var restoreFields: [() -> Void] = []
    private let recipe: Recipe
    private let ingredients: [Ingredient]
    private let photos: [RecipePhoto]

    init(_ recipe: Recipe) {
        self.recipe = recipe
        ingredients = recipe.ingredients ?? []
        photos = recipe.extraPhotos ?? []
        remember(\Recipe.title)
        remember(\Recipe.summary)
        remember(\Recipe.instructions)
        remember(\Recipe.sourceURL)
        remember(\Recipe.sourceName)
        remember(\Recipe.sourceText)
        remember(\Recipe.importMethod)
        remember(\Recipe.category)
        remember(\Recipe.difficulty)
        remember(\Recipe.mealType)
        remember(\Recipe.visibility)
        remember(\Recipe.originID)
        remember(\Recipe.cookNotes)
        remember(\Recipe.servings)
        remember(\Recipe.prepMinutes)
        remember(\Recipe.cookMinutes)
        remember(\Recipe.steps)
        remember(\Recipe.photoData)
        remember(\Recipe.importedAt)
        remember(\Recipe.householdCanEdit)
        let metadata = RecipePlanningMetadata(recipe: recipe)
        restoreFields.append { metadata.apply(to: recipe) }
    }

    private func remember<Value>(_ key: ReferenceWritableKeyPath<Recipe, Value>) {
        let value = recipe[keyPath: key]
        restoreFields.append { [recipe] in recipe[keyPath: key] = value }
    }

    func restore(in context: ModelContext) {
        let addedIngredients = (recipe.ingredients ?? []).filter { row in
            !ingredients.contains { $0 === row }
        }
        let addedPhotos = (recipe.extraPhotos ?? []).filter { row in !photos.contains { $0 === row } }
        restoreFields.forEach { $0() }
        recipe.ingredients = ingredients
        recipe.extraPhotos = photos
        addedIngredients.forEach(context.delete)
        addedPhotos.forEach(context.delete)
    }

    /// Called only after the new values are durable. Cleanup cannot alter the recipe.
    func retireReplacedChildren(in context: ModelContext) {
        ingredients.filter { old in !(recipe.ingredients ?? []).contains { $0 === old } }.forEach(context.delete)
        photos.filter { old in !(recipe.extraPhotos ?? []).contains { $0 === old } }.forEach(context.delete)
        Persist.save(context, "clean up replaced recipe rows")
    }
}
