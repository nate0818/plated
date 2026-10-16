import XCTest
@testable import Plated

final class CookLedgerTests: XCTestCase {
    func testOlderCookingSessionWithoutTimerPreferencesStillDecodes() throws {
        let data = Data(#"{"startedAt":1791417600,"lastTouched":1791417660,"step":0,"stepCount":3,"timerEndsAt":1791418200,"timerStep":0}"#.utf8)

        let session = try JSONDecoder().decode(CookLedger.Session.self, from: data)

        XCTAssertNil(session.timerDuration)
        XCTAssertNil(session.timerMuted)
    }

    func testTimerDurationAndMutePreferenceSurviveEncoding() throws {
        let data = Data(#"{"startedAt":1791417600,"lastTouched":1791417660,"step":0,"stepCount":3,"timerEndsAt":1791418200,"timerStep":0,"timerDuration":600,"timerMuted":true}"#.utf8)

        let session = try JSONDecoder().decode(CookLedger.Session.self, from: data)
        let roundTrip = try JSONDecoder().decode(CookLedger.Session.self, from: JSONEncoder().encode(session))

        XCTAssertEqual(roundTrip.timerDuration, 600)
        XCTAssertEqual(roundTrip.timerMuted, true)
    }
}
