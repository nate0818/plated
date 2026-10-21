import XCTest
@testable import Plated

@MainActor
final class RecipeDurationFilterTests: XCTestCase {
    private func boundaryRecipes() -> [Recipe] {
        [0, 29, 30, 31].map { minutes in
            Recipe(title: "Dinner \(minutes)", prepMinutes: 0, cookMinutes: minutes)
        }
    }

    func testUnderThirtyExcludesUnknownAndTheThirtyMinuteBoundary() {
        var filter = RecipeFilter()
        filter.collection = .underThirty
        XCTAssertEqual(filter.apply(to: boundaryRecipes()).map(\.totalMinutes), [29])
        XCTAssertTrue(filter.isFiltering)
    }

    func testWeeknightStillIncludesThirtyMinutes() {
        var filter = RecipeFilter()
        filter.collection = .weeknight
        XCTAssertEqual(Set(filter.apply(to: boundaryRecipes()).map(\.totalMinutes)), [29, 30])
    }

    func testClearingUnderThirtyRestoresAllDurations() {
        var filter = RecipeFilter()
        filter.collection = .underThirty
        filter.clearSheetOptions()
        XCTAssertEqual(filter.collection, .all)
        XCTAssertFalse(filter.isFiltering)
        XCTAssertEqual(Set(filter.apply(to: boundaryRecipes()).map(\.totalMinutes)), [0, 29, 30, 31])
    }
}
