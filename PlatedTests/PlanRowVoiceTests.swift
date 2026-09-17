import XCTest
@testable import Plated

/// Filled Plan who-lines, pinned to the 2026-09-17 copy stamp. Production
/// strings come from `PlanRowVoice` so a test cannot pass by keeping its
/// own copy of the sentence beside the row that draws it.
final class PlanRowVoiceTests: XCTestCase {

    func testCookingOtherAndYou() {
        XCTAssertEqual(
            PlanRowVoice.cooking(isYou: false, firstName: "Alessandra"),
            "Alessandra is cooking"
        )
        XCTAssertEqual(
            PlanRowVoice.cooking(isYou: true, firstName: "Nate"),
            "You're cooking"
        )
    }

    func testPlannedOtherAndYou() {
        XCTAssertEqual(
            PlanRowVoice.planned(isYou: false, firstName: "Alessandra"),
            "Alessandra planned this night"
        )
        XCTAssertEqual(
            PlanRowVoice.planned(isYou: true, firstName: "Nate"),
            "You planned this night"
        )
    }

    func testEatOutOtherAndYou() {
        XCTAssertEqual(
            PlanRowVoice.eatOut(isYou: false, firstName: "Alessandra"),
            "Alessandra: we're eating out"
        )
        XCTAssertEqual(
            PlanRowVoice.eatOut(isYou: true, firstName: "Nate"),
            "You: we're eating out"
        )
    }

    /// Cook assigned (even on a cook-only night) is the cooking sentence,
    /// not planner attribution.
    func testCookAssignedPrefersCooking() {
        XCTAssertEqual(
            PlanRowVoice.whoLine(
                eatingOut: false,
                hasCook: true,
                cookIsYou: false,
                cookFirstName: "Alessandra",
                plannerIsYou: true,
                plannerFirstName: "Nate"
            ),
            "Alessandra is cooking"
        )
        XCTAssertEqual(
            PlanRowVoice.whoLine(
                eatingOut: false,
                hasCook: true,
                cookIsYou: true,
                cookFirstName: "Nate",
                plannerIsYou: true,
                plannerFirstName: "Nate"
            ),
            "You're cooking"
        )
    }

    /// No cook: the planner's attribution sentence, never an eng chip.
    func testNoCookIsPlannedThisNight() {
        XCTAssertEqual(
            PlanRowVoice.whoLine(
                eatingOut: false,
                hasCook: false,
                cookIsYou: false,
                cookFirstName: "",
                plannerIsYou: false,
                plannerFirstName: "Alessandra"
            ),
            "Alessandra planned this night"
        )
        XCTAssertEqual(
            PlanRowVoice.whoLine(
                eatingOut: false,
                hasCook: false,
                cookIsYou: false,
                cookFirstName: "",
                plannerIsYou: true,
                plannerFirstName: "Nate"
            ),
            "You planned this night"
        )
    }

    /// Eat-out wins over a leftover cook, and speaks as that cook when
    /// named; otherwise as the planner. Never reportage.
    func testEatOutWinsAndUsesQuoteStyle() {
        XCTAssertEqual(
            PlanRowVoice.whoLine(
                eatingOut: true,
                hasCook: true,
                cookIsYou: false,
                cookFirstName: "Alessandra",
                plannerIsYou: true,
                plannerFirstName: "Nate"
            ),
            "Alessandra: we're eating out"
        )
        XCTAssertEqual(
            PlanRowVoice.whoLine(
                eatingOut: true,
                hasCook: false,
                cookIsYou: false,
                cookFirstName: "",
                plannerIsYou: true,
                plannerFirstName: "Nate"
            ),
            "You: we're eating out"
        )
        XCTAssertEqual(
            PlanRowVoice.whoLine(
                eatingOut: true,
                hasCook: false,
                cookIsYou: false,
                cookFirstName: "",
                plannerIsYou: false,
                plannerFirstName: "Alessandra"
            ),
            "Alessandra: we're eating out"
        )
    }

    func testEatingOutDetectionNeedsTheTitleAndNoRecipe() {
        XCTAssertTrue(PlanRowVoice.isEatingOut(title: "Eating out", hasRecipe: false))
        XCTAssertTrue(PlanRowVoice.isEatingOut(title: "we're eating out", hasRecipe: false))
        XCTAssertFalse(PlanRowVoice.isEatingOut(title: "Eating out", hasRecipe: true))
        XCTAssertFalse(PlanRowVoice.isEatingOut(title: "Pasta Night", hasRecipe: false))
    }

    /// The stamp's kill list. Each needle is something a filled who-line
    /// must never say; the values are the spec, and the function under
    /// test is the same one the rows call.
    func testWhoLineKillsBanishedCopy() {
        let lines = [
            PlanRowVoice.cooking(isYou: false, firstName: "Alessandra"),
            PlanRowVoice.cooking(isYou: true, firstName: "Nate"),
            PlanRowVoice.planned(isYou: false, firstName: "Alessandra"),
            PlanRowVoice.planned(isYou: true, firstName: "Nate"),
            PlanRowVoice.eatOut(isYou: false, firstName: "Alessandra"),
            PlanRowVoice.eatOut(isYou: true, firstName: "Nate"),
        ]
        let banished = [
            "Alessandra cooks",
            "Nate cooks",
            "You cook",
            "You cooks",
            "said we're eating out",
            "said we're going out",
            "said we are eating",
            "You said",
            "Alessandra said",
            "Assigned",
            "Cook:",
        ]
        for line in lines {
            for needle in banished {
                XCTAssertFalse(
                    line.contains(needle),
                    "who-line \(line.debugDescription) still carries banished \(needle.debugDescription)"
                )
            }
        }
        XCTAssertNotEqual(lines[0], "Alessandra cooks")
        XCTAssertNotEqual(lines[1], "You cook")
        XCTAssertNotEqual(lines[4], "Alessandra said we're eating out")
        XCTAssertNotEqual(lines[5], "You said we're eating out")
        XCTAssertNotEqual(lines[4], "Alessandra said we're going out")
        XCTAssertFalse(lines.contains(where: { $0.contains("going out") }))
    }

    /// First names only: the old full-name cooks line is what overflowed.
    func testActorUsesTheFirstName() {
        XCTAssertEqual(PlanRowVoice.firstName("Alessandra Fitzgerald"), "Alessandra")
        XCTAssertEqual(PlanRowVoice.firstName("Nate"), "Nate")
    }

    func testSpeakerIdentityMatchesTheWhoLinePerson() {
        XCTAssertEqual(
            PlanRowVoice.speakerName(
                eatingOut: false, hasCook: true,
                cookName: "Alessandra Fitzgerald", authorName: "Nate Meadows"
            ),
            "Alessandra Fitzgerald"
        )
        XCTAssertEqual(
            PlanRowVoice.speakerName(
                eatingOut: true, hasCook: false,
                cookName: "", authorName: "Alessandra Fitzgerald"
            ),
            "Alessandra Fitzgerald"
        )
        XCTAssertEqual(
            PlanRowVoice.speakerID(
                eatingOut: false, hasCook: false,
                cookID: "cook", authorID: "author"
            ),
            "author"
        )
    }
}
