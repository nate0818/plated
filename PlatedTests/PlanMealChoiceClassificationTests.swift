import XCTest
@testable import Plated

/// Foundation-only cases can also run on the host against the exact
/// production PlanMealChoice.swift when a simulator is unavailable.
final class PlanMealChoiceClassificationTests: XCTestCase {
    func testCanonicalLeftoversAcceptsCaseAndSurroundingWhitespace() {
        for title in ["Leftovers", "leftovers", "LEFTOVERS", "  Leftovers  ", "\n\tLeFtOvErS\r\n"] {
            XCTAssertTrue(PlanMealChoice.isLeftovers(title: title, hasRecipe: false), title)
        }
    }

    func testOrdinaryFreeformMealNamesAreNotAccidentallyChangedIntoLeftovers() {
        for title in ["", " ", "Dinner to choose", "Eating out", "Leftovers soup", "Use the leftovers",
                      "Leftover", "Leftovers!", "Left overs"] {
            XCTAssertFalse(PlanMealChoice.isLeftovers(title: title, hasRecipe: false), title)
        }
    }

    func testARealRecipeAlwaysRetainsItsCookingSemantics() {
        for title in ["Leftovers", " LEFTOVERS ", "Leftovers soup"] {
            XCTAssertFalse(PlanMealChoice.isLeftovers(title: title, hasRecipe: true), title)
        }
    }
}
