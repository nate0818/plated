#if DEBUG
import Foundation
import SwiftData

/// One row of every model, written once so CloudKit's Development schema
/// learns every record type the app can produce.
///
/// CloudKit mints a record type the first time a record of that type
/// exports, and Production cannot invent types on demand. A container whose
/// app has never saved a gathering therefore carries no `CD_Gathering`, and
/// a tester's gatherings would save locally and then silently never sync —
/// which reads as data loss, not as a missing schema. Priming walks the
/// whole model list so what gets deployed to Production is the complete
/// schema rather than whatever features happened to be exercised first.
///
/// Relationships are wired and blob fields carry bytes on purpose: *fields*
/// are minted from what actually exports too, so a nil reference or an empty
/// `Data?` leaves its field unminted even when the record type appears.
///
/// Debug-only by construction. `unprime` clears the rows afterwards; that is
/// deliberately not `-plated-purge-cloud`, which drops the whole zone — the
/// right tool for a clean slate and the wrong one for tidying up.
@MainActor
enum SchemaPrimer {
    /// The marker every primed row carries, so cleanup can find them again
    /// without touching anything a person actually made.
    static let marker = "Schema primer"

    /// A few bytes standing in for a photo — enough to make an
    /// external-storage blob field real. Also how the primed
    /// `HouseholdProfile` is identified, since it has no name to mark.
    private static let blob = Data([0xFF, 0xD8, 0xFF, 0xD9])

    static func prime(into context: ModelContext) throws {
        let recipe = Recipe(title: marker, summary: "Delete me")
        recipe.photoData = blob

        let ingredient = Ingredient(name: marker, quantity: 1, unit: "ea")
        ingredient.recipe = recipe

        let photo = RecipePhoto(photoData: blob, caption: marker)
        photo.recipe = recipe

        let member = HouseholdMember(name: marker)
        // Every household-sync field, populated: a field that is nil or
        // empty while priming does not exist in Production, and the first
        // real join then fails on it (docs/household.md §12).
        member.userRecordName = "primer-\(marker)"
        member.bio = "Delete me"
        member.authorID = "primer"
        member.shareModifiedAt = .now
        member.shareFingerprint = marker
        member.leftAt = .now
        let meal = PlannedMeal(date: .now, slot: .dinner, recipe: recipe, cook: member)
        meal.cookReaction = 3
        meal.actualMinutes = 42
        // No share fields: a night is not a household record (see
        // `PlannedMeal`), so there is nothing here for a zone to learn.
        meal.authorID = "primer"
        recipe.authorID = "primer"
        recipe.shareModifiedAt = .now
        recipe.shareFingerprint = marker
        recipe.sharePhotoHash = marker
        let gathering = Gathering(title: marker, notes: "Delete me")
        gathering.authorID = "primer"
        gathering.shareModifiedAt = .now
        gathering.shareFingerprint = marker
        let grocery = GroceryItem(name: marker, quantity: 1, unit: "ea", isManual: true)
        grocery.authorID = "primer"
        grocery.shareModifiedAt = .now
        grocery.shareFingerprint = marker

        let post = TablePost(authorName: marker, dishTitle: marker)
        post.photoData = blob
        let comment = TableComment(authorName: marker, text: "Delete me")
        comment.post = post

        let message = DirectMessage(peerName: marker, text: "Delete me")
        let notification = PlatedNotification(kind: .recipeAdded, actorName: marker)
        let profile = HouseholdProfile(bannerPhotoData: blob)
        profile.shareModifiedAt = .now

        let rows: [any PersistentModel] = [
            recipe, ingredient, photo, member, meal, gathering,
            grocery, post, comment, message, notification, profile
        ]
        rows.forEach { context.insert($0) }
        try context.save()
    }

    /// Deletes exactly what `prime` wrote, and nothing else.
    ///
    /// Planned meals go first: the recipe relationship nullifies rather than
    /// cascades, so deleting the primed recipe out from under its meal would
    /// leave an untitled dinner sitting on a real week.
    static func unprime(from context: ModelContext) throws {
        var deleted = 0
        func sweep<T: PersistentModel>(_ type: T.Type, _ isPrimed: (T) -> Bool) {
            guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
            for row in rows where isPrimed(row) {
                context.delete(row)
                deleted += 1
            }
        }
        sweep(PlannedMeal.self) { $0.recipe?.title == marker || $0.cook?.name == marker }
        sweep(Recipe.self) { $0.title == marker }
        sweep(Ingredient.self) { $0.name == marker }
        sweep(RecipePhoto.self) { $0.caption == marker }
        sweep(HouseholdMember.self) { $0.name == marker }
        sweep(Gathering.self) { $0.title == marker }
        sweep(GroceryItem.self) { $0.name == marker }
        sweep(TableComment.self) { $0.authorName == marker }
        sweep(TablePost.self) { $0.authorName == marker }
        sweep(DirectMessage.self) { $0.peerName == marker }
        sweep(PlatedNotification.self) { $0.actorName == marker }
        sweep(HouseholdProfile.self) { $0.bannerPhotoData == blob }
        try context.save()
        print("PLATED UNPRIME: \(deleted) rows deleted")
    }
}
#endif
