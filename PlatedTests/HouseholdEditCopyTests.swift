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
        let line = HouseholdEdits.line(for: change(cookID: me), me: me, currentCookID: "")
        XCTAssertEqual(line, "Riley put you down to cook Ragu.")
    }

    func testAnOrdinaryChangeNamesTheDish() {
        let line = HouseholdEdits.line(for: change(), me: me, currentCookID: "")
        XCTAssertEqual(line, "Riley changed this night to Ragu.")
    }

    /// A record written before the editor fields existed names nobody, and a
    /// household is a handful of people: a guessed name is a person in the
    /// room.
    func testANamelessChangeLosesTheNameAndKeepsTheFact() {
        XCTAssertEqual(
            HouseholdEdits.line(for: change(cookID: me, by: ""), me: me, currentCookID: ""),
            "You have been put down to cook Ragu."
        )
        XCTAssertEqual(
            HouseholdEdits.line(for: change(by: ""), me: me, currentCookID: ""),
            "This night was changed to Ragu on another phone."
        )
    }

    /// Somebody else being put down to cook is not "you are cooking".
    func testAnotherPersonsCookIsNotTheCookSentence() {
        let line = HouseholdEdits.line(for: change(cookID: "riley"), me: me, currentCookID: "")
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

    /// The sentence is about a CHANGE. A housemate renaming a dish on a
    /// night the reader was ALREADY cooking is not "Riley put you down to
    /// cook", which claims something Riley did not do.
    func testTheCookSentenceOnlyFiresWhenTheCookIsNew() {
        XCTAssertEqual(
            HouseholdEdits.line(for: change(cookID: me), me: me, currentCookID: me),
            "Riley changed this night to Ragu.",
            "already the cook, so nothing about the cook changed"
        )
        XCTAssertEqual(
            HouseholdEdits.rowLine(for: change(cookID: me), me: me, currentCookID: me),
            "Riley changed this night"
        )
    }

    /// The operand that decides WHICH sentence fires, which thirteen tests
    /// of the sentence itself never touched.
    ///
    /// The record's `cookID` carries whichever spelling the writing phone
    /// had: a member joined through the household share has a
    /// `participantID`, and one this phone knows only through the directory
    /// has a `userRecordName` until the share reconciles. Read the wrong
    /// one and the cook sentence fires when nothing about the cook changed,
    /// or stays silent when somebody has just been put down to cook, and
    /// every test above still passes.
    func testTheCookIdReadsEitherSpellingAndNeitherIsEmpty() {
        let byParticipant = HouseholdMember(name: "Riley Park")
        byParticipant.participantID = "p-riley"
        byParticipant.userRecordName = "u-riley"
        XCTAssertEqual(
            PlanNightSheet.cookID(of: PlannedMeal(cook: byParticipant)), "p-riley",
            "the share's own id wins where there is one"
        )

        let byRecordName = HouseholdMember(name: "Sam Okafor")
        byRecordName.userRecordName = "u-sam"
        XCTAssertEqual(
            PlanNightSheet.cookID(of: PlannedMeal(cook: byRecordName)), "u-sam",
            "a member known only through the directory still answers"
        )

        let unknown = HouseholdMember(name: "Max")
        XCTAssertEqual(PlanNightSheet.cookID(of: PlannedMeal(cook: unknown)), "")
        XCTAssertEqual(PlanNightSheet.cookID(of: PlannedMeal()), "", "no cook is not a cook id")
    }

    func testTheRowSaysTheConsequenceFirst() {
        XCTAssertEqual(HouseholdEdits.rowLine(for: change(cookID: me), me: me, currentCookID: ""), "Riley put you down to cook")
        XCTAssertEqual(HouseholdEdits.rowLine(for: change(), me: me, currentCookID: ""), "Riley changed this night")
        XCTAssertEqual(HouseholdEdits.rowLine(for: change(by: ""), me: me, currentCookID: ""), "Changed on another phone")
    }
}
