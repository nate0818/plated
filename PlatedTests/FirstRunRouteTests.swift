import XCTest
@testable import Plated

final class FirstRunRouteTests: XCTestCase {
    func testNewUserReachesRecipesWithoutProfileContactsOrTour() {
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: false, completedSetup: false, hasInvitation: false), .welcome)
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: true, completedSetup: false, hasInvitation: false), .app(.cookbook))
    }

    func testInvitationWaitsThroughReadinessAndWelcomeThenTakesPriority() {
        XCTAssertEqual(FirstRunRoute.resolve(ready: false, signedIn: false, completedSetup: false, hasInvitation: true), .loading)
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: false, completedSetup: false, hasInvitation: true), .welcome)
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: true, completedSetup: false, hasInvitation: true), .invitation)
    }

    func testReturningHouseholdKeepsItsNormalDestination() {
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: true, completedSetup: true, hasInvitation: false), .app(.week))
        // Returning-user links belong to the shell, not first-run setup.
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: true, completedSetup: true, hasInvitation: true), .app(.week))
    }

    func testRevocationDoesNotResetCompletedSetup() {
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: false, completedSetup: true, hasInvitation: false), .welcome)
        XCTAssertEqual(FirstRunRoute.resolve(ready: true, signedIn: true, completedSetup: true, hasInvitation: false), .app(.week))
    }
}
