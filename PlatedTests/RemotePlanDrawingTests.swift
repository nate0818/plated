import XCTest
import SwiftData
@testable import Plated

/// What the planner SAYS about a household night, held to DESIGN.md's
/// honesty rule: a night that is going, a night whose change has not been
/// sent, and a night the household already has must each read differently,
/// and none of them may claim something that did not happen.
///
/// The sentences are pure functions on purpose. Three of the four answers
/// `PlanShare.write` can give were being set on a sheet that had already
/// dismissed itself, which no screenshot would ever have shown; a rule
/// about words is testable exactly when the words are not buried in a
/// `body`.
@MainActor
final class RemotePlanDrawingTests: XCTestCase {

    private var savedHouseholdOwner: String?

    override func setUp() async throws {
        savedHouseholdOwner = PlanLedger.shared.householdOwner
        PlanLedger.shared.clear()
        PlanShare.forgetEdits()
        PlanLedger.shared.householdOwner = "host"
    }

    override func tearDown() async throws {
        PlanShare.forgetEdits()
        PlanLedger.shared.clear()
        PlanLedger.shared.householdOwner = savedHouseholdOwner
    }

    /// A night off the wire, the way every surface receives one.
    private func remoteNight(title: String = "Tacos", tagline: String = "") -> PlanLedger.Entry {
        var plan = TableShare.RemotePlan()
        plan.recordName = "plan-n1"
        plan.shoppingID = "n1"
        plan.zoneOwner = "host"
        plan.authorID = "_riley"
        plan.authorName = "Riley Park"
        plan.day = PlanDay.string(Calendar.current.startOfDay(for: .now))
        plan.slot = MealSlot.dinner.rawValue
        plan.title = title
        plan.tagline = tagline
        plan.servings = 4
        plan.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        plan.changedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var changes = TableShare.Changes()
        changes.plans = [plan]
        PlanLedger.shared.absorb(changes, me: "_me")
        return PlanLedger.shared.entry("plan-n1")!
    }

    // MARK: The three states, told apart

    func testASettledNightSaysOnlyWhoPlannedIt() {
        let night = remoteNight(tagline: "Kids pick")
        XCTAssertEqual(RemotePlanRow.caption(for: night), "Planned by Riley · Kids pick")
        XCTAssertFalse(night.isGoing)
    }

    func testAChangeThisPhoneHasNotSentSaysSo() {
        let night = remoteNight()
        var edit = PlanShare.Edit(changing: night)
        edit.title = "Ragu"
        let after = PlanLedger.shared.applyLocally(edit)!
        XCTAssertEqual(RemotePlanRow.caption(for: after), "Planned by Riley · Not sent yet")
        XCTAssertFalse(after.isGoing, "a change is not a delete")
    }

    /// The defect this test exists for: the row used to vanish, so an
    /// offline delete left the night standing on every other phone with
    /// nothing anywhere saying so.
    func testANightGoingSaysItIsGoingAndThatTheOthersStillHaveIt() {
        let night = remoteNight(tagline: "Kids pick")
        let after = PlanLedger.shared.applyLocally(PlanShare.Edit(deleting: night))!
        XCTAssertTrue(after.isGoing)
        XCTAssertEqual(RemotePlanRow.caption(for: after), "Coming off the plan · Still on the other phones")
        XCTAssertEqual(
            RemotePlanRow.caption(for: after).contains("Kids pick"), false,
            "the tag line is about a dinner that is coming off, and three clauses truncate at AX sizes"
        )
    }

    func testTheThreeCaptionsAreThreeDifferentSentences() {
        let settled = remoteNight()
        var edit = PlanShare.Edit(changing: settled)
        edit.servings = 6
        let changed = PlanLedger.shared.applyLocally(edit)!
        let going = PlanLedger.shared.applyLocally(PlanShare.Edit(deleting: settled))!
        let captions = [settled, changed, going].map(RemotePlanRow.caption(for:))
        XCTAssertEqual(Set(captions).count, 3, "settled, not sent, and going are three states, not one")
    }

    func testTheSpokenLabelCarriesTheSameStateAsTheCaption() {
        let night = remoteNight()
        let going = PlanLedger.shared.applyLocally(PlanShare.Edit(deleting: night))!
        let spoken = RemotePlanRow.spokenLabel(entry: going, day: "Tonight", cookLine: "Riley is cooking")
        XCTAssertEqual(
            spoken,
            "Tonight, Tacos, Riley is cooking, planned by Riley, you took this night off and it has not reached the other phones yet"
        )
    }

    /// A pending state is quiet, not a failure. Nothing in these sentences
    /// may read as an error, and none of them may carry an em dash.
    func testNoSentenceReadsAsAnErrorOrCarriesAnEmDash() {
        let night = remoteNight()
        let going = PlanLedger.shared.applyLocally(PlanShare.Edit(deleting: night))!
        let sentences = [
            RemotePlanRow.caption(for: going),
            going.pendingSentence ?? "",
            PlanNightSheet.deleteLabel(going: true, deleting: false),
            PlanNightSheet.deleteLabel(going: false, deleting: true),
            PlanNightSheet.sentence(for: .queued("It goes to your household when this phone is back online.")) ?? "",
            PlanNightSheet.sentence(for: .theirs) ?? ""
        ]
        for sentence in sentences {
            XCTAssertFalse(sentence.isEmpty)
            XCTAssertFalse(sentence.contains("—"), "no em dash in anything a person reads: \(sentence)")
            for word in ["error", "failed", "Error", "Failed", "couldn't", "Sorry"] {
                XCTAssertFalse(sentence.contains(word), "a pending state is not a failure: \(sentence)")
            }
        }
    }

    // MARK: The sheet's answer

    /// The defect: the sheet sent and dismissed in the same breath, so
    /// queued, theirs and refused were set on a page nobody was looking at,
    /// and a delete had no row left to carry them either.
    func testOnlyALandedWriteClosesThePage() {
        XCTAssertTrue(PlanNightSheet.closes(.landed(.now)))
        XCTAssertFalse(PlanNightSheet.closes(.queued("Kept on this phone.")))
        XCTAssertFalse(PlanNightSheet.closes(.theirs))
        XCTAssertFalse(PlanNightSheet.closes(.refused("This night is at a household this phone has left.")))
    }

    func testEveryAnswerThatKeepsThePageUpHasSomethingToSay() {
        XCTAssertNil(PlanNightSheet.sentence(for: .landed(.now)), "the page is closing; there is nobody to tell")
        for outcome in [PlanShare.WriteOutcome.queued("Kept on this phone."), .theirs, .refused("Left the household.")] {
            XCTAssertFalse(PlanNightSheet.closes(outcome))
            XCTAssertFalse(
                PlanNightSheet.sentence(for: outcome)?.isEmpty ?? true,
                "an answer that keeps the sheet up is an answer the sheet says out loud"
            )
        }
    }

    func testARefusalIsSaidInTheWordsTheWriteGave() {
        let why = "This night is at a household this phone has left."
        XCTAssertEqual(PlanNightSheet.sentence(for: .refused(why)), why)
    }

    /// The trash is three controls in one, and the off state has to say why
    /// it is off or VoiceOver reads a button that answers nothing.
    func testTheTrashSaysWhichOfItsThreeStatesItIsIn() {
        let labels = [
            PlanNightSheet.deleteLabel(going: false, deleting: false),
            PlanNightSheet.deleteLabel(going: false, deleting: true),
            PlanNightSheet.deleteLabel(going: true, deleting: false)
        ]
        XCTAssertEqual(Set(labels).count, 3)
        XCTAssertEqual(labels[0], "Take this night off the plan")
    }

    // MARK: Settling

    func testANightThatLandsLeavesAndOneThatIsRefusedComesBackSettled() {
        let night = remoteNight()
        let edit = PlanShare.Edit(deleting: night)
        PlanLedger.shared.applyLocally(edit)
        XCTAssertEqual(PlanLedger.shared.entry(night.recordName)?.isGoing, true)

        PlanLedger.shared.settle(edit, .refused("Left the household."))
        let back = PlanLedger.shared.entry(night.recordName)
        XCTAssertEqual(back?.isGoing, false, "a refused delete is a night nobody took off")
        XCTAssertEqual(RemotePlanRow.caption(for: back!), "Planned by Riley")

        PlanLedger.shared.applyLocally(edit)
        PlanLedger.shared.settle(edit, .landed(.now))
        XCTAssertNil(PlanLedger.shared.entry(night.recordName), "now it has really gone, so now the row goes")
    }
}
