import XCTest
import SwiftData
@testable import Plated

/// Groceries across the household, held to docs/household.md 3.5.
///
/// Nate asked for groceries to be part of the shared workspace. Before
/// this, `GroceryListBuilder` fetched `PlannedMeal` and nothing else, and a
/// night somebody else planned is a `PlanLedger.Entry` and never a
/// `PlannedMeal` (3.2), so a housemate's ragu put no beef on this phone's
/// list and their mark on that beef arrived at a phone with no row to carry
/// it. These are the pure pieces of the fix: minting a night's ingredients
/// on the author's phone, carrying them over the wire, and folding both
/// halves of the plan into one list whose keys match on both phones.
@MainActor
final class SharedGroceriesTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    private static let calendar = Calendar.current
    private static var today: Date { calendar.startOfDay(for: .now) }
    private static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    override func setUp() async throws {
        container = try ModelContainer(
            for: PlatedStore.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }

    override func tearDown() async throws { container = nil }

    private func ragu(servings: Int = 4) -> Recipe {
        let recipe = Recipe(title: "Ragu")
        recipe.servings = servings
        let beef = Ingredient(name: "Beef mince", quantity: 500, unit: "g", aisle: .meat)
        let salt = Ingredient(name: "Salt", quantity: 1, unit: "tsp", aisle: .pantry, isPantryStaple: true)
        beef.recipe = recipe
        salt.recipe = recipe
        context.insert(recipe); context.insert(beef); context.insert(salt)
        return recipe
    }

    // MARK: Minting

    func testANightsIngredientsAreScaledToItsServings() {
        let meal = PlannedMeal(date: Self.day(1), recipe: ragu(servings: 4), customTitle: "Ragu")
        context.insert(meal)
        // Against itself rather than against a number, because the wire
        // carries the CANONICAL amount and `GroceryMeasure.canonical` moves
        // 500 g into ounces. Asserting 1000 here tested the unit table.
        meal.servings = 4
        let single = PlanShare.groceryLines(for: meal).first { $0.normalizedName == "beef mince" }
        meal.servings = 8
        let double = PlanShare.groceryLines(for: meal).first { $0.normalizedName == "beef mince" }
        XCTAssertEqual(double?.quantity ?? 0, (single?.quantity ?? 0) * 2, accuracy: 0.0001,
                       "doubling the servings doubles the mince")
        XCTAssertEqual(double?.unit, single?.unit, "and does not change the unit it is measured in")
        XCTAssertEqual(double?.aisle, GroceryAisle.meat.rawValue)
    }

    func testAPantryStapleIsCarriedAndFlaggedRatherThanDropped() {
        // Whether staples are shown is the reader's setting, so the author
        // may not decide it for them by leaving them off the wire.
        let meal = PlannedMeal(date: Self.day(1), recipe: ragu(), customTitle: "Ragu")
        context.insert(meal)
        let salt = PlanShare.groceryLines(for: meal).first { $0.normalizedName == "salt" }
        XCTAssertEqual(salt?.isPantryStaple, true)
    }

    func testANightWithNoRecipeCarriesNoIngredients() {
        let meal = PlannedMeal(date: Self.day(1), recipe: nil, customTitle: "Leftovers")
        context.insert(meal)
        XCTAssertEqual(PlanShare.groceryLines(for: meal).count, 0)
    }

    func testTheIngredientsAreInTheFingerprint() {
        // Editing a recipe has to republish the nights that use it, or a
        // member's list keeps quantities nobody cooks any more.
        let recipe = ragu()
        let meal = PlannedMeal(date: Self.day(1), recipe: recipe, customTitle: "Ragu")
        context.insert(meal)
        let before = PlanShare.plan(for: meal, me: "_me").fingerprint
        recipe.sortedIngredients.first { $0.normalizedName == "beef mince" }?.quantity = 750
        let after = PlanShare.plan(for: meal, me: "_me").fingerprint
        XCTAssertNotEqual(before, after, "a changed ingredient changes the night's fingerprint")
    }

    func testTheOrderIngredientsComeBackInDoesNotChangeTheFingerprint() {
        let meal = PlannedMeal(date: Self.day(1), recipe: ragu(), customTitle: "Ragu")
        context.insert(meal)
        var plan = PlanShare.plan(for: meal, me: "_me")
        let forwards = plan.fingerprint
        plan.lines.reverse()
        XCTAssertEqual(forwards, plan.fingerprint, "the key is sorted, so fetch order cannot republish a window")
    }

    // MARK: The wire

    func testTheIngredientsRoundTripThroughTheRecordsStringField() {
        let lines = [PlanShare.Line(name: "Beef mince", normalizedName: "beef mince",
                                    unit: "g", quantity: 500, aisle: "Meat & Seafood",
                                    isPantryStaple: false)]
        let json = TableShare.encodeLines(lines)
        XCTAssertEqual(TableShare.decodeLines(json), lines)
    }

    func testAnAbsentOrUnreadableFieldIsNoIngredientsRatherThanAFailure() {
        // Every record written before groceries were shared has no field at
        // all. Dropping the whole delivery over that would be far worse
        // than a night that contributes nothing to a list.
        XCTAssertEqual(TableShare.decodeLines(nil), [])
        XCTAssertEqual(TableShare.decodeLines("not json"), [])
        XCTAssertEqual(TableShare.decodeLines("[]"), [])
    }

    // MARK: One list from both halves of the plan

    private func remote(title: String, day: Int, id: String, lines: [PlanShare.Line]) -> PlanLedger.Entry {
        var plan = TableShare.RemotePlan()
        plan.recordName = "plan-\(id)"
        plan.zoneOwner = "host"
        plan.authorID = "_riley"
        plan.authorName = "Riley Park"
        plan.title = title
        plan.day = PlanDay.string(Self.day(day))
        plan.shoppingID = id
        plan.lines = lines
        return PlanLedger.Entry(plan)
    }

    func testAHousematesNightPutsItsIngredientsOnThisPhonesList() {
        let mine = PlannedMeal(date: Self.day(1), recipe: ragu(), customTitle: "Ragu")
        mine.shoppingID = "mine"
        context.insert(mine)
        // Canonicalised, because that is what the author's phone puts on
        // the wire. A raw "250 g" here would key differently from this
        // phone's own ounces and the two would never have merged, which is
        // precisely the failure this whole change exists to prevent.
        let quarterKilo = GroceryMeasure.canonical(250, "g")
        let theirs = remote(title: "Chilli", day: 2, id: "theirs", lines: [
            PlanShare.Line(name: "Beef mince", normalizedName: "beef mince",
                           unit: quarterKilo.unit, quantity: quarterKilo.quantity,
                           aisle: "Meat & Seafood", isPantryStaple: false)
        ])
        let nights = [
            GroceryListBuilder.SourceNight(id: "mine", title: "Ragu", date: Self.day(1),
                                           lines: PlanShare.groceryLines(for: mine)),
            GroceryListBuilder.SourceNight(id: "theirs", title: "Chilli", date: Self.day(2),
                                           lines: theirs.lines ?? [])
        ]
        let lines = GroceryListBuilder(context: context)
            .aggregate(nights: nights, includePantryStaples: false)
        let beef = lines.first { $0.name == "Beef mince" }
        let expected = GroceryMeasure.canonical(500, "g").quantity + quarterKilo.quantity
        XCTAssertEqual(beef?.quantity ?? 0, expected, accuracy: 0.0001,
                       "both nights' mince is on one line")
        XCTAssertEqual(beef?.sources.count, 2, "and the line still says which dinners it is for")
        XCTAssertEqual(Set(beef?.sources.map(\.title) ?? []), ["Ragu", "Chilli"])
    }

    func testTheKeyAHousematesNightProducesIsTheKeyAMarkTravelsUnder() {
        // The whole reason the ingredients are canonicalised on the
        // author's phone: a mark is keyed on `GroceryMeasure.key`, so the
        // two phones have to arrive at the same one or the mark lands on
        // nothing.
        let meal = PlannedMeal(date: Self.day(1), recipe: ragu(), customTitle: "Ragu")
        context.insert(meal)
        let line = PlanShare.groceryLines(for: meal).first { $0.normalizedName == "beef mince" }
        let overTheWire = TableShare.decodeLines(TableShare.encodeLines([line!])).first!
        XCTAssertEqual(
            GroceryMeasure.key(overTheWire.normalizedName, overTheWire.unit),
            GroceryMeasure.key("beef mince", line!.unit)
        )
    }

    func testANightThisPhoneAlreadyPlannedIsNotCountedTwice() {
        // The ledger never holds this phone's own nights, so the two halves
        // are disjoint by construction. Proven rather than assumed, because
        // a double count would silently double somebody's shopping.
        let mine = PlannedMeal(date: Self.day(1), recipe: ragu(), customTitle: "Ragu")
        mine.shoppingID = "mine"
        context.insert(mine)
        let nights = GroceryListBuilder.nights(
            meals: [mine], from: Self.today, to: Self.day(7), ledger: PlanLedger.shared
        )
        XCTAssertEqual(nights.filter { $0.id == "mine" }.count, 1)
    }
}
