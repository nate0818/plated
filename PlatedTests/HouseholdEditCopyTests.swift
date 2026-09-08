import XCTest
@testable import Plated

/// The sentences a person reads when the household has changed a night they
/// planned. Pure given the identity, so the cook case is testable without an
/// account.
@MainActor
final class HouseholdEditCopyTests: XCTestCase {
    private let me = "_me"

    private func change(
        title: String = "Ragu", cookID: String = "", by: String = "Riley Park"
    ) -> HouseholdEdits.Change {
        HouseholdEdits.Change(
            shoppingID: "n1", recordName: "plan-n1", title: title,
            cookID: cookID, cookName: "", servings: 4,
            day: "2026-09-10", slot: "dinner", by: by, at: .now
        )
    }

    func testBeingPutDownToCookLeads() {
        let line = HouseholdEdits.line(for: change(cookID: me), me: me)
        XCTAssertEqual(line, "Riley put you down to cook Ragu.")
    }

    func testAnOrdinaryChangeNamesTheDish() {
        let line = HouseholdEdits.line(for: change(), me: me)
        XCTAssertEqual(line, "Riley changed this night to Ragu.")
    }

    /// A record written before the editor fields existed names nobody, and a
    /// household is a handful of people: a guessed name is a person in the
    /// room.
    func testANamelessChangeLosesTheNameAndKeepsTheFact() {
        XCTAssertEqual(
            HouseholdEdits.line(for: change(cookID: me, by: ""), me: me),
            "You have been put down to cook Ragu."
        )
        XCTAssertEqual(
            HouseholdEdits.line(for: change(by: ""), me: me),
            "This night was changed to Ragu on another phone."
        )
    }

    /// Somebody else being put down to cook is not "you are cooking".
    func testAnotherPersonsCookIsNotTheCookSentence() {
        let line = HouseholdEdits.line(for: change(cookID: "riley"), me: me)
        XCTAssertEqual(line, "Riley changed this night to Ragu.")
    }

    func testTheContrastIsDroppedWhenTheTitleIsTheSame() {
        XCTAssertNil(HouseholdEdits.contrast(for: change(title: "Tacos"), mineTitle: "Tacos"))
        XCTAssertNil(HouseholdEdits.contrast(for: change(), mineTitle: "   "))
        XCTAssertEqual(
            HouseholdEdits.contrast(for: change(), mineTitle: "Tacos"),
            "Your plan still says Tacos."
        )
    }

    func testTheRowSaysTheConsequenceFirst() {
        XCTAssertEqual(HouseholdEdits.rowLine(for: change(cookID: me), me: me), "Riley put you down to cook")
        XCTAssertEqual(HouseholdEdits.rowLine(for: change(), me: me), "Riley changed this night")
        XCTAssertEqual(HouseholdEdits.rowLine(for: change(by: ""), me: me), "Changed on another phone")
    }
}
