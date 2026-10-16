import XCTest
@testable import Plated

final class CompetitiveUpgradeTests: XCTestCase {
    func testReplacingKeepsCurrentServingCountAndUsesRecipeDefaultForNewNight() {
        XCTAssertEqual(PlanReplacement.servings(current: 6, defaultValue: 4), 6)
        XCTAssertEqual(PlanReplacement.servings(current: nil, defaultValue: 4), 4)
        XCTAssertEqual(PlanReplacement.servings(current: 0, defaultValue: 4), 4)
        XCTAssertEqual(PlanReplacement.servings(current: nil, defaultValue: 0), 1)
    }

    func testNutritionMetadataDecodesOlderAndPartiallyWrittenPayloads() throws {
        let old = try JSONDecoder().decode(RecipePlanningMetadata.self, from: Data("{}".utf8))
        XCTAssertEqual(old, .empty)

        let partial = try JSONDecoder().decode(
            RecipePlanningMetadata.self,
            from: Data(#"{"equipment":["oven"],"caloriesPerServing":420}"#.utf8)
        )
        XCTAssertEqual(partial.equipment, ["oven"])
        XCTAssertEqual(partial.caloriesPerServing, 420)
        XCTAssertTrue(partial.nutritionSource.isEmpty)
    }

    func testBasketEstimateUsesWholePackagesAndRequiresFreshSameStoreData() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let package = IngredientPackage(
            size: 1, unit: "lb", price: 4.50, store: "Market",
            source: "Receipt", updatedAt: now.addingTimeInterval(-86_400)
        )
        let line = GroceryCostEstimate.InputLine(
            name: "Chicken", quantity: 17, unit: "oz", package: package
        )

        let result = GroceryCostEstimate.calculate(lines: [line], store: "Market", now: now)
        XCTAssertEqual(try XCTUnwrap(result.total), 9.0, accuracy: 0.001)
        XCTAssertEqual(result.packageCount, 2)
        XCTAssertEqual(result.missingLines, 0)

        let wrongStore = GroceryCostEstimate.calculate(lines: [line], store: "Other", now: now)
        XCTAssertNil(wrongStore.total)
        XCTAssertEqual(wrongStore.missingLines, 1)

        let stale = IngredientPackage(
            size: 1, unit: "lb", price: 4.50, store: "Market",
            source: "Receipt", updatedAt: now.addingTimeInterval(-60 * 24 * 60 * 60)
        )
        let staleResult = GroceryCostEstimate.calculate(
            lines: [.init(name: "Chicken", quantity: 17, unit: "oz", package: stale)],
            store: "Market", now: now
        )
        XCTAssertNil(staleResult.total)
    }

    func testOneUnpricedLineSuppressesBasketTotalInsteadOfShowingPartialPrice() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let known = IngredientPackage(
            size: 500, unit: "g", price: 2.20, store: "Market",
            source: "Shelf label", updatedAt: now
        )
        let result = GroceryCostEstimate.calculate(
            lines: [
                .init(name: "Rice", quantity: 250, unit: "g", package: known),
                .init(name: "Salt", quantity: 1, unit: "tsp", package: nil)
            ],
            store: "Market", now: now
        )
        XCTAssertNil(result.total)
        XCTAssertEqual(result.pricedLines, 1)
        XCTAssertEqual(result.missingLines, 1)
    }
}
